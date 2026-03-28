//
//  TOPagingViewAnimator.m
//
//  Copyright 2018-2026 Timothy Oliver. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
//  OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
//  IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#import <UIKit/UIScreen.h>
#import <UIKit/UIScrollView.h>
#import <UIKit/UIWindow.h>
#import <QuartzCore/QuartzCore.h>
#import <TargetConditionals.h>

#import "TOPagingViewAnimator.h"
#import "TOPagingViewTypes.h"
#import "TOPagingViewTypesPrivate.h"	

// -----------------------------------------------------------------

/// Default duration for page turn animations.
static const CFTimeInterval kTOAnimatorDefaultDuration = 0.5f;

/// Default fraction of a full turn duration to use when clamping to a nearer target.
static const CGFloat kTOAnimatorClampDurationFactor = 0.45f;

/// Cubic bezier control points for the ease-out curve.
static const CGFloat kTOAnimatorControlPoint1X = 0.3f;
static const CGFloat kTOAnimatorControlPoint1Y = 0.75f;
static const CGFloat kTOAnimatorControlPoint2X = 0.3f;
static const CGFloat kTOAnimatorControlPoint2Y = 1.0f;

// -----------------------------------------------------------------

/// Evaluates a cubic bezier easing curve for the given linear time progress.
/// @param t Linear time progress from 0.0 to 1.0.
/// @return Eased progress from 0.0 to 1.0.
static inline CGFloat TOPagingViewAnimatorEvaluateEasing(CGFloat t) {
    CGFloat u = t;
    for (int i = 0; i < 8; i++) {
        const CGFloat oneMinusU = 1.0f - u;
        const CGFloat x = 3.0f * oneMinusU * oneMinusU * u * kTOAnimatorControlPoint1X +
                          3.0f * oneMinusU * u * u * kTOAnimatorControlPoint2X + u * u * u - t;
        const CGFloat dx = 3.0f * oneMinusU * oneMinusU * kTOAnimatorControlPoint1X +
                           6.0f * oneMinusU * u * (kTOAnimatorControlPoint2X - kTOAnimatorControlPoint1X) +
                           3.0f * u * u * (1.0f - kTOAnimatorControlPoint2X);
        if (fabs(dx) < 1e-6f) { break; }
        u -= x / dx;
    }
    u = fmax(0.0f, fmin(1.0f, u));
    const CGFloat oneMinusU = 1.0f - u;
    return 3.0f * oneMinusU * oneMinusU * u * kTOAnimatorControlPoint1Y + 3.0f * oneMinusU * u * u * kTOAnimatorControlPoint2Y +
           u * u * u;
}

/// Returns the easing curve's normalized velocity multiplier at a given linear progress.
///
/// This is the first derivative of the eased progress with respect to linear time progress.
/// A value of 1.0 means the curve is moving linearly at that instant, values above 1.0
/// are moving faster than linear, and values near 0.0 indicate the curve is flattening out.
///
/// We approximate the derivative numerically by sampling just before and after `t`.
/// That is accurate enough for animation velocity matching, and keeps the math simple.
static inline CGFloat TOPagingViewAnimatorEvaluateEasingVelocityMultiplier(CGFloat t) {
    const CGFloat delta = 0.001f;
    const CGFloat lower = fmax(0.0f, t - delta);
    const CGFloat upper = fmin(1.0f, t + delta);
    const CGFloat range = upper - lower;
    if (range <= FLT_EPSILON) { return 0.0f; }
    return (TOPagingViewAnimatorEvaluateEasing(upper) - TOPagingViewAnimatorEvaluateEasing(lower)) / range;
}

/// Snaps a value to the nearest page boundary only when already within one pixel of that boundary.
static inline CGFloat TOPagingViewAnimatorSnapToPageBoundary(CGFloat value, CGFloat pageWidth, CGFloat scale) {
    if (pageWidth <= FLT_EPSILON) { return value; }
    const CGFloat nearestPageBoundary = round(value / pageWidth) * pageWidth;
    const CGFloat pixelSize = 1.0f / fmax(scale, 1.0f);
    if (fabs(value - nearestPageBoundary) <= pixelSize) { return nearestPageBoundary; }
    return value;
}

/// Fetches the reference time of the current animation, derived from the CADisplayLink's time if available, or CACurrentMediaTime otherwise.
static inline CFTimeInterval TOPagingViewAnimatorReferenceTime(CADisplayLink *_Nullable displayLink) {
    return (displayLink != nil) ? displayLink.targetTimestamp : CACurrentMediaTime();
}

/// Rounds a value to the nearest screen pixel for the given display scale.
static inline CGFloat TOPagingViewAnimatorRoundToPixel(CGFloat value, CGFloat scale) {
    return round(value * scale) / scale;
}

/// Applies the minimum settle window used when an in-flight turn is cut short.
static inline CFTimeInterval TOPagingViewAnimatorClampSettleDuration(CFTimeInterval duration) {
    return fmax(0.05, duration);
}

@implementation TOPagingViewAnimator {
    CADisplayLink *_displayLink;            /// The display link driving the frame-by-frame animation.
    CFTimeInterval _startTime;              /// The time at which the current animation segment started.
    UIRectEdge _direction;                  /// The direction we're turning in.
    CFTimeInterval _activeEffectiveDuration; /// The duration of the current segment after applying any active simulator drag coefficient.
    CGFloat _directionMultiplier;           /// The direction multiplier (+1 for right, -1 for left).
    CGFloat _startOffset;                   /// The absolute scroll view content offset when we started.
    CGFloat _endOffset;                     /// The absolute scroll view content offset where this animation should end.
    BOOL _originalPagingEnabled;            /// The original pagingEnabled state before this animator temporarily disabled paging.
    TOPagingViewAnimatorEnvironmentMetrics _environmentMetrics; /// Cached environment values that stay stable for the life of an animation.
}

@synthesize direction = _direction;

#pragma mark - Object Lifecycle -

- (instancetype)init {
    self = [super init];
    if (self) {
        _duration = kTOAnimatorDefaultDuration;
        _environmentMetrics = (TOPagingViewAnimatorEnvironmentMetrics){.displayScale = 1.0f, .pixelSize = 1.0f, .animationDragCoefficient = 1.0f};
        _activeEffectiveDuration = kTOAnimatorDefaultDuration;
    }
    return self;
}

- (void)dealloc {
    [_displayLink invalidate];
}

#pragma mark - Public Methods -

- (void)turnToPageInDirection:(UIRectEdge)pageDirection {
    UIScrollView *const scrollView = _scrollView;
    if (scrollView == nil || _pageWidth <= FLT_EPSILON) { return; }

    const CGFloat dir = (pageDirection == UIRectEdgeRight) ? 1.0f : -1.0f;
    const CFTimeInterval now = CACurrentMediaTime();
    const CFTimeInterval referenceTime = (_displayLink != nil) ? _displayLink.targetTimestamp : now;
    
    // Cache all of the device metrics that won't change in this animation run.
    [self _updateEnvironmentMetrics];

    // If we were already animating, and another turn event comes through, stack it.
    if (_isAnimating && dir == _directionMultiplier) {
        const CGFloat linearProgress = [self _linearProgressAtReferenceTime:referenceTime];
        const CGFloat progress = TOPagingViewAnimatorEvaluateEasing(linearProgress);
        const CGFloat currentOffset =
            TOPagingViewAnimatorRoundToPixel(_startOffset + ((_endOffset - _startOffset) * progress), _environmentMetrics.displayScale);
        const CGFloat endOffset = TOPagingViewAnimatorRoundToPixel(_endOffset + (dir * _pageWidth), _environmentMetrics.displayScale);
        [self _configureSegmentWithStartOffset:currentOffset endOffset:endOffset referenceTime:now duration:_duration];
        return;
    }

    // New direction or fresh start: animate from the current position to the nearest
    // page boundary in the requested direction. This naturally handles reversal
    // (tap left while going right snaps back to the page on screen) as well as
    // re-initiating the original direction mid-reversal without drift.
    _direction = pageDirection;
    _directionMultiplier = dir;
    const CGFloat startOffset = TOPagingViewAnimatorRoundToPixel(scrollView.contentOffset.x, _environmentMetrics.displayScale);
    CGFloat endOffset = (dir > 0.0f) ? ceil(startOffset / _pageWidth + FLT_EPSILON) * _pageWidth
                                     : floor(startOffset / _pageWidth - FLT_EPSILON) * _pageWidth;
    endOffset = TOPagingViewAnimatorRoundToPixel(endOffset, _environmentMetrics.displayScale);
    [self _configureSegmentWithStartOffset:startOffset endOffset:endOffset referenceTime:now duration:_duration];

    // If we weren't already in an animation loop, start the display link.
    // We also need to disable paging, otherwise our offset code ends up fighting
    // another display link, internal to UIScrollView that is managing the paging state.
    if (!_isAnimating) {
        _isAnimating = YES;
        _originalPagingEnabled = scrollView.pagingEnabled;
        scrollView.pagingEnabled = NO;
        [self _createDisplayLink];
    }
}

- (void)stopAnimationWithCompletion:(BOOL)didComplete {
    if (!_isAnimating) { return; }
    // Cancel the display link.
    // The scroll view will stop at whatever offset it is now.
    [_displayLink invalidate];
    _displayLink = nil;
    _isAnimating = NO;
    _scrollView.pagingEnabled = _originalPagingEnabled;
    if (didComplete && _completionHandler) { _completionHandler(); }
    _completionHandler = nil;
}

- (void)clampAnimationToOffset:(CGFloat)targetOffset {
    if (!_isAnimating) { return; }

    const CFTimeInterval referenceTime = TOPagingViewAnimatorReferenceTime(_displayLink);
    const CGFloat linearProgress = [self _linearProgressAtReferenceTime:referenceTime];
    const CGFloat progress = TOPagingViewAnimatorEvaluateEasing(linearProgress);

    // Sample the active segment at its current presentation position so the clamp begins
    // exactly where the in-flight animation visually is, not at the last whole-frame offset.
    const CGFloat currentOffset = TOPagingViewAnimatorRoundToPixel(_startOffset + ((_endOffset - _startOffset) * progress),
                                                                   _environmentMetrics.displayScale);
    const CGFloat clampedTargetOffset = TOPagingViewAnimatorRoundToPixel(targetOffset, _environmentMetrics.displayScale);
    const CGFloat remainingDistance = clampedTargetOffset - currentOffset;

    // If we're already effectively at the requested target, collapse the segment immediately.
    if (fabs(remainingDistance) <= _environmentMetrics.pixelSize) {
        [self _configureSegmentWithStartOffset:currentOffset endOffset:clampedTargetOffset referenceTime:referenceTime duration:0.0];
        return;
    }

    // Recover the current instantaneous velocity from the active easing curve.
    // `TOPagingViewAnimatorEvaluateEasingVelocityMultiplier` returns the normalized
    // derivative of the curve at the current progress, so multiplying by the segment
    // distance and dividing by the effective duration yields points per second.
    const CGFloat easingVelocityMultiplier = TOPagingViewAnimatorEvaluateEasingVelocityMultiplier(linearProgress);
    const CGFloat currentVelocity = (_activeEffectiveDuration <= FLT_EPSILON) ?
                                        0.0f : (((_endOffset - _startOffset) * easingVelocityMultiplier) / _activeEffectiveDuration);
    const CGFloat velocityTowardTarget = currentVelocity * ((remainingDistance >= 0.0f) ? 1.0f : -1.0f);

    // Fall back to a short settle segment when we can't infer a better duration.
    CFTimeInterval settleDuration = TOPagingViewAnimatorClampSettleDuration(_duration * kTOAnimatorClampDurationFactor);
    if (velocityTowardTarget > FLT_EPSILON) {
        // Start a fresh ease-out segment that initially moves at the same velocity as the
        // current segment. We do that by solving for a duration whose t=0 derivative
        // matches the captured velocity toward the new target.
        const CGFloat initialVelocityMultiplier = TOPagingViewAnimatorEvaluateEasingVelocityMultiplier(0.0f);
        if (initialVelocityMultiplier > FLT_EPSILON) {
            const CFTimeInterval effectiveSettleDuration = (fabs(remainingDistance) * initialVelocityMultiplier) / velocityTowardTarget;
            settleDuration = TOPagingViewAnimatorClampSettleDuration(effectiveSettleDuration / _environmentMetrics.animationDragCoefficient);
        }
    }

    // Otherwise commit to the full, new segment animation
    [self _configureSegmentWithStartOffset:currentOffset
                                 endOffset:clampedTargetOffset
                             referenceTime:referenceTime
                                  duration:settleDuration];
}

- (void)didTransitionWithOffset:(CGFloat)offset {
    if (!_isAnimating) { return; }
    
    // When the paging view performs its transition, which ostensibly just moves all embedded pages either forward or back
    // by one slot, it is also necessary to apply the same slot distance to our animation start and end positions.
    const CGFloat actualOffset = TOPagingViewAnimatorRoundToPixel(_scrollView.contentOffset.x, _environmentMetrics.displayScale);
    const CFTimeInterval referenceTime = TOPagingViewAnimatorReferenceTime(_displayLink);
    const CGFloat linearProgress = [self _linearProgressAtReferenceTime:referenceTime];
    const CGFloat progress = TOPagingViewAnimatorEvaluateEasing(linearProgress);

    _endOffset += offset;
    _endOffset = TOPagingViewAnimatorRoundToPixel(_endOffset, _environmentMetrics.displayScale);
    _endOffset = TOPagingViewAnimatorSnapToPageBoundary(_endOffset, _pageWidth, _environmentMetrics.displayScale);

    // If we were effectively at the end already, let's just exit out.
    const CGFloat remainingProgress = 1.0f - progress;
    if (remainingProgress <= FLT_EPSILON) {
        _startOffset = actualOffset;
        _endOffset = actualOffset;
        return;
    }

    _startOffset = (actualOffset - (_endOffset * progress)) / remainingProgress;
    _startOffset = TOPagingViewAnimatorRoundToPixel(_startOffset, _environmentMetrics.displayScale);
    _startOffset = TOPagingViewAnimatorSnapToPageBoundary(_startOffset, _pageWidth, _environmentMetrics.displayScale);
}

#pragma mark - Animation State -

- (void)_updateEnvironmentMetrics TOPAGINGVIEW_OBJC_DIRECT {
    // Capture device metrics that may change between animations but are stable
    // enough to cache for the duration of one.
    
    // Capture the physical display scale of the screen (eg 2x = 0.5, 3x = 0.33333)
    const CGFloat displayScale = ({
        CGFloat scale = _scrollView.window.screen.scale;
        if (scale <= FLT_EPSILON) { scale = _scrollView.traitCollection.displayScale; }
        (scale <= FLT_EPSILON) ? 1.0f : scale;
    });
    
    // When on the simulator, and 'Slow Animations' is enabled, add that coefficient to our animation speed.
    const CGFloat animationDragCoefficient = ({
        #if TARGET_OS_SIMULATOR
            extern float UIAnimationDragCoefficient(void) __attribute__((weak_import));
            const float dragCoefficient = (UIAnimationDragCoefficient != NULL) ? UIAnimationDragCoefficient() : 1.0f;
            (dragCoefficient > FLT_EPSILON) ? dragCoefficient : 1.0f;
        #else
            1.0f;
        #endif
    });
    
    // Apply the metrics. These will be regenerated on each new animation run.
    _environmentMetrics = (TOPagingViewAnimatorEnvironmentMetrics){
        .displayScale = displayScale,
        .pixelSize = 1.0f / fmax(displayScale, 1.0f),
        .animationDragCoefficient = animationDragCoefficient,
    };
}

- (CGFloat)_linearProgressAtReferenceTime:(CFTimeInterval)referenceTime TOPAGINGVIEW_OBJC_DIRECT {
    return (_activeEffectiveDuration <= FLT_EPSILON) ? 1.0f : (CGFloat)fmin((referenceTime - _startTime) / _activeEffectiveDuration, 1.0);
}

- (void)_configureSegmentWithStartOffset:(CGFloat)startOffset
                               endOffset:(CGFloat)endOffset
                           referenceTime:(CFTimeInterval)referenceTime
                                duration:(CFTimeInterval)duration TOPAGINGVIEW_OBJC_DIRECT {
    _startOffset = startOffset;
    _endOffset = endOffset;
    _startTime = referenceTime;
    _activeEffectiveDuration = duration * _environmentMetrics.animationDragCoefficient;
}

#pragma mark - Display Link -

- (void)_createDisplayLink TOPAGINGVIEW_OBJC_DIRECT {
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(_displayLinkDidFire:)];
    if (@available(iOS 15.0, *)) {
        _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(80.0f, 120.0f, 120.0f);
    } else {
        _displayLink.preferredFramesPerSecond = 120;
    }
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)_displayLinkDidFire:(CADisplayLink *)displayLink {
    UIScrollView *const scrollView = _scrollView;
    if (scrollView == nil) {
        [self stopAnimationWithCompletion:NO];
        return;
    }

    const CGFloat linearProgress = [self _linearProgressAtReferenceTime:displayLink.targetTimestamp];
    const CGFloat progress = TOPagingViewAnimatorEvaluateEasing(linearProgress);
    CGFloat targetOffset = _startOffset + ((_endOffset - _startOffset) * progress);
    targetOffset = TOPagingViewAnimatorRoundToPixel(targetOffset, _environmentMetrics.displayScale);
    scrollView.contentOffset = (CGPoint){targetOffset, 0.0f};

    if (progress >= 1.0f - FLT_EPSILON && fabs(scrollView.contentOffset.x - _endOffset) <= _environmentMetrics.pixelSize) {
        [self stopAnimationWithCompletion:YES];
    }
}

@end
