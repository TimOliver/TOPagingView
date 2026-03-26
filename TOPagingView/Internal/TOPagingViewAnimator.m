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

#import "TOPagingViewAnimator.h"
#import "TOPagingViewMacros.h"

#import <QuartzCore/QuartzCore.h>
#import <TargetConditionals.h>

// -----------------------------------------------------------------

/// Default duration for page turn animations.
static const CFTimeInterval kTOAnimatorDefaultDuration = 0.4;

/// Cubic bezier control points for the ease-out curve.
static const CGFloat kTOAnimatorControlPoint1X = 0.3f;
static const CGFloat kTOAnimatorControlPoint1Y = 0.9f;
static const CGFloat kTOAnimatorControlPoint2X = 0.45f;
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

/// Evaluates the slope of the easing curve at a given linear progress.
static inline CGFloat TOPagingViewAnimatorEvaluateEasingSlope(CGFloat t) {
    const CGFloat delta = 0.001f;
    const CGFloat lower = fmax(0.0f, t - delta);
    const CGFloat upper = fmin(1.0f, t + delta);
    const CGFloat range = upper - lower;
    if (range <= FLT_EPSILON) { return 0.0f; }
    return (TOPagingViewAnimatorEvaluateEasing(upper) - TOPagingViewAnimatorEvaluateEasing(lower)) / range;
}

/// Returns the display scale used by the hosting scroll view, or the main screen as a fallback.
static inline CGFloat TOPagingViewAnimatorDisplayScale(UIScrollView *_Nullable scrollView) {
    CGFloat scale = scrollView.window.screen.scale;
    if (scale <= FLT_EPSILON) { scale = scrollView.traitCollection.displayScale; }
    return (scale <= FLT_EPSILON) ? 1.0f : scale;
}

/// Snaps a value to the nearest page boundary only when already within one pixel of that boundary.
static inline CGFloat TOPagingViewAnimatorSnapToPageBoundary(CGFloat value, CGFloat pageWidth, CGFloat scale) {
    if (pageWidth <= FLT_EPSILON) { return value; }

    const CGFloat nearestPageBoundary = round(value / pageWidth) * pageWidth;
    const CGFloat pixelSize = 1.0f / fmax(scale, 1.0f);
    if (fabs(value - nearestPageBoundary) <= pixelSize) { return nearestPageBoundary; }

    return value;
}

/// Rounds a value to the nearest screen pixel for the given display scale.
static inline CGFloat TOPagingViewAnimatorRoundToPixel(CGFloat value, CGFloat scale) { return round(value * scale) / scale; }

/// Returns the active simulator animation drag coefficient when Slow Animations is enabled.
static inline CGFloat TOPagingViewAnimatorAnimationDragCoefficient(void) {
#if TARGET_OS_SIMULATOR
    extern float UIAnimationDragCoefficient(void) __attribute__((weak_import));
    const float dragCoefficient = (UIAnimationDragCoefficient != NULL) ? UIAnimationDragCoefficient() : 1.0f;
    return (dragCoefficient > FLT_EPSILON) ? dragCoefficient : 1.0f;
#else
    return 1.0f;
#endif
}

/// Applies the minimum settle window used when an in-flight turn is cut short.
static inline CFTimeInterval TOPagingViewAnimatorClampSettleDuration(CFTimeInterval duration) { return fmax(0.05, duration); }

// -----------------------------------------------------------------

typedef struct {
    CGFloat displayScale;
    CGFloat pixelSize;
    CGFloat animationDragCoefficient;
} TOPagingViewAnimatorEnvironmentMetrics;

@interface TOPagingViewAnimator ()

/// The display link driving the frame-by-frame animation.
@property (nonatomic, strong, nullable) CADisplayLink *displayLink;

/// The time at which the current animation segment started.
@property (nonatomic, assign) CFTimeInterval startTime;

/// The direction we're turning in.
@property (nonatomic, assign, readwrite) UIRectEdge direction;

/// The duration of the current animation segment.
@property (nonatomic, assign) CFTimeInterval activeDuration;

/// The duration of the current segment after applying any active simulator drag coefficient.
@property (nonatomic, assign) CFTimeInterval activeEffectiveDuration;

/// The direction multiplier (+1 for right, -1 for left).
@property (nonatomic, assign) CGFloat turnDirection;

/// The absolute scroll view content offset when we started.
@property (nonatomic, assign) CGFloat startOffset;

/// The absolute scroll view content offset where this animation should end.
@property (nonatomic, assign) CGFloat endOffset;

/// The original pagingEnabled state before this animator temporarily disabled paging.
@property (nonatomic, assign) BOOL originalPagingEnabled;

/// Cached environment values that stay stable for the life of an animation.
@property (nonatomic, assign) TOPagingViewAnimatorEnvironmentMetrics environmentMetrics;

@end

// -----------------------------------------------------------------

@implementation TOPagingViewAnimator

#pragma mark - Object Lifecycle -

- (instancetype)init {
    self = [super init];
    if (self) {
        _duration = kTOAnimatorDefaultDuration;
        _activeDuration = kTOAnimatorDefaultDuration;
        _environmentMetrics = (TOPagingViewAnimatorEnvironmentMetrics){.displayScale = 1.0f, .pixelSize = 1.0f, .animationDragCoefficient = 1.0f};
        _activeEffectiveDuration = kTOAnimatorDefaultDuration;
    }
    return self;
}

- (void)dealloc {
    [_displayLink invalidate];
}

#pragma mark - Public Methods -

- (void)turnToPageInDirection:(UIRectEdge)direction {
    UIScrollView *const scrollView = _scrollView;
    if (scrollView == nil || _pageWidth <= FLT_EPSILON) { return; }

    [self _updateEnvironmentMetrics];

    const CGFloat dir = (direction == UIRectEdgeRight) ? 1.0f : -1.0f;
    const CFTimeInterval now = CACurrentMediaTime();

    if (_isAnimating && dir == _turnDirection) {
        // Extend the animation one more page in the same direction.
        const CGFloat linearProgress = [self _linearProgressAtReferenceTime:[self _referenceTimeWithFallbackTime:now]];
        const CGFloat progress = TOPagingViewAnimatorEvaluateEasing(linearProgress);
        const CGFloat currentOffset = [self _roundToPixel:[self _presentationOffsetForProgress:progress]];
        const CGFloat endOffset = [self _roundToPixel:(_endOffset + (dir * _pageWidth))];
        [self _configureSegmentWithStartOffset:currentOffset endOffset:endOffset referenceTime:now duration:_duration];
        return;
    }

    // New direction or fresh start: animate from the current position to the nearest
    // page boundary in the requested direction. This naturally handles reversal
    // (tap left while going right snaps back to the page on screen) as well as
    // re-initiating the original direction mid-reversal without drift.
    _direction = direction;
    _turnDirection = dir;
    const CGFloat startOffset = [self _roundToPixel:scrollView.contentOffset.x];
    CGFloat endOffset = (dir > 0.0f) ? ceil(startOffset / _pageWidth + FLT_EPSILON) * _pageWidth
                                     : floor(startOffset / _pageWidth - FLT_EPSILON) * _pageWidth;
    endOffset = [self _roundToPixel:endOffset];
    [self _configureSegmentWithStartOffset:startOffset endOffset:endOffset referenceTime:now duration:_duration];

    if (!_isAnimating) {
        _isAnimating = YES;
        _originalPagingEnabled = scrollView.pagingEnabled;
        scrollView.pagingEnabled = NO;
        [self _createDisplayLink];
    }
}

- (void)stopAnimation {
    if (!_isAnimating) { return; }
    [self _destroyDisplayLink];
    _isAnimating = NO;
    [self _restorePagingState];
}

- (void)clampAnimationToCurrentOffsetInDirection:(UIRectEdge)direction {
    if (!_isAnimating) { return; }

    UIScrollView *const scrollView = _scrollView;
    if (scrollView == nil) { return; }

    const CGFloat dir = (direction == UIRectEdgeRight) ? 1.0f : -1.0f;
    if (_turnDirection != dir) { return; }

    const CGFloat actualOffset = [self _roundToPixel:scrollView.contentOffset.x];
    const CFTimeInterval now = CACurrentMediaTime();
    const CFTimeInterval referenceTime = [self _referenceTimeWithFallbackTime:now];
    const CGFloat linearProgress = [self _linearProgressAtReferenceTime:referenceTime];
    const CGFloat progress = TOPagingViewAnimatorEvaluateEasing(linearProgress);
    const CGFloat easingSlope = TOPagingViewAnimatorEvaluateEasingSlope(linearProgress);
    const CGFloat currentVelocity =
        (_activeEffectiveDuration <= FLT_EPSILON) ? 0.0f : (((_endOffset - _startOffset) * easingSlope) / _activeEffectiveDuration);
    const CGFloat remainingDistance = _pageWidth - actualOffset;

    const CGFloat velocityTowardTarget = currentVelocity * ((remainingDistance >= 0.0f) ? 1.0f : -1.0f);
    if (fabs(remainingDistance) <= _environmentMetrics.pixelSize) {
        [self _configureSegmentWithStartOffset:actualOffset endOffset:_pageWidth referenceTime:referenceTime duration:0.0];
        return;
    }

    const CGFloat remainingProgress = 1.0f - progress;
    if (velocityTowardTarget > FLT_EPSILON && remainingProgress > FLT_EPSILON && easingSlope > FLT_EPSILON) {
        // Preserve the current easing phase so the clamp continues smoothly instead of restarting.
        CGFloat syntheticStartOffset = (actualOffset - (_pageWidth * progress)) / remainingProgress;
        syntheticStartOffset = [self _roundToPixel:syntheticStartOffset];

        const CGFloat totalDistance = _pageWidth - syntheticStartOffset;
        if (fabs(totalDistance) > FLT_EPSILON && ((totalDistance >= 0.0f) == (remainingDistance >= 0.0f))) {
            const CFTimeInterval effectiveSettleDuration = (fabs(totalDistance) * easingSlope) / velocityTowardTarget;
            const CFTimeInterval baseSettleDuration = TOPagingViewAnimatorClampSettleDuration([self _baseDurationForEffectiveDuration:effectiveSettleDuration]);
            const CFTimeInterval adjustedEffectiveDuration = [self _effectiveDurationForDuration:baseSettleDuration];

            [self _configureSegmentWithStartOffset:syntheticStartOffset
                                         endOffset:_pageWidth
                                     referenceTime:(referenceTime - (linearProgress * adjustedEffectiveDuration))
                                          duration:baseSettleDuration];
            return;
        }
    }

    [self _configureSegmentWithStartOffset:actualOffset
                                 endOffset:_pageWidth
                             referenceTime:referenceTime
                                  duration:TOPagingViewAnimatorClampSettleDuration(_duration * 0.45)];
}

- (void)didTransitionWithOffset:(CGFloat)offset {
    if (!_isAnimating) { return; }
    const CGFloat actualOffset = [self _roundToPixel:_scrollView.contentOffset.x];
    const CGFloat linearProgress =
        [self _linearProgressAtReferenceTime:[self _referenceTimeWithFallbackTime:CACurrentMediaTime()]];
    const CGFloat progress = TOPagingViewAnimatorEvaluateEasing(linearProgress);

    _endOffset += offset;
    _endOffset = [self _roundToPixel:_endOffset];
    _endOffset = [self _snapToPageBoundary:_endOffset];

    const CGFloat remainingProgress = 1.0f - progress;
    if (remainingProgress <= FLT_EPSILON) {
        _startOffset = actualOffset;
        _endOffset = actualOffset;
        return;
    }

    _startOffset = (actualOffset - (_endOffset * progress)) / remainingProgress;
    _startOffset = [self _roundToPixel:_startOffset];
    _startOffset = [self _snapToPageBoundary:_startOffset];
}

#pragma mark - Display Link -

- (CFTimeInterval)_referenceTimeWithFallbackTime:(CFTimeInterval)fallbackTime TOPAGINGVIEW_OBJC_DIRECT {
    return (_displayLink != nil) ? _displayLink.targetTimestamp : fallbackTime;
}

- (void)_updateEnvironmentMetrics TOPAGINGVIEW_OBJC_DIRECT {
    const CGFloat displayScale = TOPagingViewAnimatorDisplayScale(_scrollView);
    const CGFloat animationDragCoefficient = TOPagingViewAnimatorAnimationDragCoefficient();
    _environmentMetrics = (TOPagingViewAnimatorEnvironmentMetrics){
        .displayScale = displayScale,
        .pixelSize = 1.0f / fmax(displayScale, 1.0f),
        .animationDragCoefficient = animationDragCoefficient,
    };
}

- (CFTimeInterval)_effectiveDurationForDuration:(CFTimeInterval)duration TOPAGINGVIEW_OBJC_DIRECT {
    return duration * _environmentMetrics.animationDragCoefficient;
}

- (CFTimeInterval)_baseDurationForEffectiveDuration:(CFTimeInterval)effectiveDuration TOPAGINGVIEW_OBJC_DIRECT {
    return effectiveDuration / _environmentMetrics.animationDragCoefficient;
}

- (CGFloat)_linearProgressAtReferenceTime:(CFTimeInterval)referenceTime TOPAGINGVIEW_OBJC_DIRECT {
    return (_activeEffectiveDuration <= FLT_EPSILON) ? 1.0f : (CGFloat)fmin((referenceTime - _startTime) / _activeEffectiveDuration, 1.0);
}

- (CGFloat)_presentationOffsetForProgress:(CGFloat)progress TOPAGINGVIEW_OBJC_DIRECT {
    return _startOffset + ((_endOffset - _startOffset) * progress);
}

- (CGFloat)_roundToPixel:(CGFloat)value TOPAGINGVIEW_OBJC_DIRECT {
    return TOPagingViewAnimatorRoundToPixel(value, _environmentMetrics.displayScale);
}

- (CGFloat)_snapToPageBoundary:(CGFloat)value TOPAGINGVIEW_OBJC_DIRECT {
    return TOPagingViewAnimatorSnapToPageBoundary(value, _pageWidth, _environmentMetrics.displayScale);
}

- (void)_configureSegmentWithStartOffset:(CGFloat)startOffset
                               endOffset:(CGFloat)endOffset
                           referenceTime:(CFTimeInterval)referenceTime
                                duration:(CFTimeInterval)duration TOPAGINGVIEW_OBJC_DIRECT {
    _startOffset = startOffset;
    _endOffset = endOffset;
    _startTime = referenceTime;
    _activeDuration = duration;
    _activeEffectiveDuration = [self _effectiveDurationForDuration:duration];
}

- (void)_restorePagingState TOPAGINGVIEW_OBJC_DIRECT {
    _activeDuration = _duration;
    _activeEffectiveDuration = [self _effectiveDurationForDuration:_duration];
    _scrollView.pagingEnabled = _originalPagingEnabled;
}

- (void)_createDisplayLink TOPAGINGVIEW_OBJC_DIRECT {
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(_displayLinkDidFire:)];
    if (@available(iOS 15.0, *)) {
        _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(80.0, 120.0f, 120.0f);
    } else {
        _displayLink.preferredFramesPerSecond = 120;
    }
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)_destroyDisplayLink TOPAGINGVIEW_OBJC_DIRECT {
    [_displayLink invalidate];
    _displayLink = nil;
}

- (void)_displayLinkDidFire:(CADisplayLink *)displayLink {
    UIScrollView *const scrollView = _scrollView;
    if (scrollView == nil) {
        [self stopAnimation];
        return;
    }

    const CGFloat linearProgress = [self _linearProgressAtReferenceTime:displayLink.targetTimestamp];
    const CGFloat progress = TOPagingViewAnimatorEvaluateEasing(linearProgress);
    CGFloat targetOffset = [self _presentationOffsetForProgress:progress];
    targetOffset = [self _roundToPixel:targetOffset];
    scrollView.contentOffset = (CGPoint){targetOffset, 0.0f};

    if (progress >= 1.0f - FLT_EPSILON && fabs(scrollView.contentOffset.x - _endOffset) <= _environmentMetrics.pixelSize) {
        [self _destroyDisplayLink];
        _isAnimating = NO;
        [self _restorePagingState];
        if (_completionHandler) { _completionHandler(); }
    }
}

@end
