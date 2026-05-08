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

/// Critically damped spring that takes over from the bezier the moment the offset crosses the
/// rest boundary in rubber-band mode. Picks up the bezier's velocity as v0; the spring's natural
/// motion then carries the offset past the boundary, peaks, and decays back to rest as one
/// continuous solution. Modeled on https://github.com/super-ultra/ScrollMechanics
/// (SpringTimingParameters.swift): for damping ratio 1, x(t) = exp(-β·t)·(c1 + c2·t), where
/// β = damping/(2·mass), c1 = displacement, c2 = velocity + β·displacement.
///
/// Higher stiffness = faster oscillation (shorter overshoot peak time, shorter overall settle).
/// `settleThreshold` is the visible-position threshold below which the spring is considered
/// finished — sub-pixel motion isn't perceptible, so we stop ticking past that.
static const CGFloat kTOAnimatorRubberBandSpringMass         = 1.0f;
static const CGFloat kTOAnimatorRubberBandSpringStiffness    = 300.0f;
static const CGFloat kTOAnimatorRubberBandSpringDampingRatio = 1.0f;
static const CGFloat kTOAnimatorRubberBandSpringSettleThreshold = 0.5f;

/// Cubic bezier control points for the ease-out curve.
static const CGFloat kTOAnimatorControlPoint1X = 0.35f;
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
    NSCAssert(scale > 0, @"Display scale must be positive.");
    return round(value * scale) / scale;
}

@implementation TOPagingViewAnimator {
    CADisplayLink *_displayLink;            /// The display link driving the frame-by-frame animation.
    CFTimeInterval _startTime;              /// The time at which the current animation segment started.
    CFTimeInterval _activeEffectiveDuration; /// The duration of the current segment after applying any active simulator drag coefficient.
    CGFloat _directionMultiplier;           /// The direction multiplier (+1 for right, -1 for left).
    CGFloat _startOffset;                   /// The absolute scroll view content offset when we started.
    CGFloat _endOffset;                     /// The absolute scroll view content offset where this animation should end.
    BOOL _originalPagingEnabled;            /// The original pagingEnabled state before this animator temporarily disabled paging.

    /// Spring physics state — armed when the bezier crosses the rubber-band boundary, drives
    /// contentOffset until the analytical settle duration elapses.
    BOOL _isInSpringSettle;
    CFTimeInterval _springStartTime;
    CFTimeInterval _springDuration;
    CGFloat _springBeta;                    /// damping / (2·mass) — exponential decay rate.
    CGFloat _springC1;                      /// = initial displacement past the rest boundary.
    CGFloat _springC2;                      /// = initial velocity + β·displacement (per the closed-form solution).

    TOPagingViewAnimatorEnvironmentMetrics _environmentMetrics; /// Cached environment values that stay stable for the life of an animation.
    TOPagingViewAnimatorState _state;       /// Live state exposed via -statePointer so the paging view can read it without msg sends.
}

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

@dynamic isAnimating, direction;

- (BOOL)isAnimating { return _state.isAnimating; }
- (UIRectEdge)direction { return _state.direction; }
- (const TOPagingViewAnimatorState *)statePointer { return &_state; }

#pragma mark - Public Methods -

- (void)turnToPageInDirection:(UIRectEdge)pageDirection {
    UIScrollView *const scrollView = _scrollView;
    NSAssert(_pageWidth > FLT_EPSILON, @"Page width must be set and positive before starting an animation.");
    if (scrollView == nil || _pageWidth <= FLT_EPSILON) { return; }

    const CGFloat dir = (pageDirection == UIRectEdgeRight) ? 1.0f : -1.0f;

    // While the rubber-band sequence is in flight, discard further turns in the same direction —
    // the user has exhausted travel that way and must wait for the snap-back to settle. A turn
    // in the opposite direction is allowed and will cancel the snap-back below.
    if (_rubberBandsAtRest && dir == _directionMultiplier) { return; }

    const CFTimeInterval now = CACurrentMediaTime();
    const CFTimeInterval referenceTime = (_displayLink != nil) ? _displayLink.targetTimestamp : now;
    
    // Cache all of the device metrics that won't change in this animation run.
    [self _updateEnvironmentMetrics];

    // If we were already animating, and another turn event comes through, stack it.
    if (_state.isAnimating && dir == _directionMultiplier) {
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
    _state.direction = pageDirection;
    _directionMultiplier = dir;
    // Direction change discards any rubber-band state from the previous direction. The spring
    // phase, if any, just stops being driven — the bezier branch takes over from this tick.
    _rubberBandsAtRest = NO;
    _isInSpringSettle = NO;
    const CGFloat startOffset = TOPagingViewAnimatorRoundToPixel(scrollView.contentOffset.x, _environmentMetrics.displayScale);
    CGFloat endOffset = (dir > 0.0f) ? ceil(startOffset / _pageWidth + FLT_EPSILON) * _pageWidth
                                     : floor(startOffset / _pageWidth - FLT_EPSILON) * _pageWidth;
    endOffset = TOPagingViewAnimatorRoundToPixel(endOffset, _environmentMetrics.displayScale);
    [self _configureSegmentWithStartOffset:startOffset endOffset:endOffset referenceTime:now duration:_duration];

    // If we weren't already in an animation loop, start the display link.
    // We also need to disable paging, otherwise our offset code ends up fighting
    // another display link, internal to UIScrollView that is managing the paging state.
    if (!_state.isAnimating) {
        _state.isAnimating = YES;
        _originalPagingEnabled = scrollView.pagingEnabled;
        scrollView.pagingEnabled = NO;
        [self _createDisplayLink];
    }
}

- (void)stopAnimationWithCompletion:(BOOL)didComplete {
    if (!_state.isAnimating) { return; }
    // Cancel the display link.
    // The scroll view will stop at whatever offset it is now.
    [_displayLink invalidate];
    _displayLink = nil;
    _state.isAnimating = NO;
    _rubberBandsAtRest = NO;
    _isInSpringSettle = NO;
    _scrollView.pagingEnabled = _originalPagingEnabled;
    if (didComplete && _completionHandler) { _completionHandler(); }
    _completionHandler = nil;
}

- (void)didTransitionWithOffset:(CGFloat)offset {
    if (!_state.isAnimating) { return; }
    
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
    
    // Capture the physical display scale of the screen (eg @2x = 2.0, @3x = 3.0).
    // `pixelSize` is derived below as its reciprocal.
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

    // Spring phase: closed-form critical-damped oscillator drives contentOffset until it settles
    // at the rest boundary. x(t) = exp(-β·t)·(c1 + c2·t) gives the signed displacement past the
    // boundary in the direction of motion; absolute offset = pageWidth + sign · x.
    if (_isInSpringSettle) {
        const CFTimeInterval t = displayLink.targetTimestamp - _springStartTime;
        if (t >= _springDuration) {
            scrollView.contentOffset = (CGPoint){_pageWidth, 0.0f};
            _isInSpringSettle = NO;
            [self stopAnimationWithCompletion:YES];
            return;
        }
        const CGFloat x = (CGFloat)(exp(-_springBeta * t) * (_springC1 + _springC2 * t));
        const CGFloat absoluteOffset = TOPagingViewAnimatorRoundToPixel(_pageWidth + _directionMultiplier * x,
                                                                         _environmentMetrics.displayScale);
        scrollView.contentOffset = (CGPoint){absoluteOffset, 0.0f};
        return;
    }

    const CGFloat linearProgress = [self _linearProgressAtReferenceTime:displayLink.targetTimestamp];
    const CGFloat progress = TOPagingViewAnimatorEvaluateEasing(linearProgress);
    CGFloat targetOffset = _startOffset + ((_endOffset - _startOffset) * progress);
    targetOffset = TOPagingViewAnimatorRoundToPixel(targetOffset, _environmentMetrics.displayScale);
    NSCAssert(isfinite(targetOffset), @"Animation target offset must be a finite number, got %f.", targetOffset);

    // Rubber-band hand-off: when the bezier first carries the offset past the rest boundary in
    // rubber-band mode, recover its instantaneous velocity and pass it as v0 to a critically
    // damped spring. The spring then takes over — its natural motion handles the overshoot peak
    // and the snap-back as one continuous solution, matching SpringTimingParameters' approach.
    if (_rubberBandsAtRest) {
        const CGFloat overshoot = _directionMultiplier * (targetOffset - _pageWidth);
        if (overshoot > 0.0f) {
            CGFloat absVelocity = 0.0f;
            if (_activeEffectiveDuration > FLT_EPSILON) {
                const CGFloat slopeDelta = (CGFloat)1e-3;
                const CGFloat tA = (CGFloat)fmin(1.0, linearProgress + slopeDelta);
                const CGFloat tB = (CGFloat)fmax(0.0, linearProgress - slopeDelta);
                const CGFloat dxSpan = tA - tB;
                if (dxSpan > FLT_EPSILON) {
                    const CGFloat dySpan = TOPagingViewAnimatorEvaluateEasing(tA) - TOPagingViewAnimatorEvaluateEasing(tB);
                    const CGFloat slope = dySpan / dxSpan;
                    absVelocity = (_endOffset - _startOffset) * slope / (CGFloat)_activeEffectiveDuration;
                }
            }
            const CGFloat signedVelocityIntoVoid = _directionMultiplier * absVelocity;
            [self _startRubberBandSpringFromDisplacement:overshoot
                                                velocity:signedVelocityIntoVoid
                                                  atTime:displayLink.targetTimestamp];
            // Apply this tick's spring value (which equals overshoot at t=0) so position is
            // continuous through the hand-off; subsequent ticks fall into the spring branch.
            const CGFloat absoluteOffset = TOPagingViewAnimatorRoundToPixel(_pageWidth + _directionMultiplier * overshoot,
                                                                             _environmentMetrics.displayScale);
            scrollView.contentOffset = (CGPoint){absoluteOffset, 0.0f};
            return;
        }
    }

    scrollView.contentOffset = (CGPoint){targetOffset, 0.0f};

    // Natural-end for the regular bezier path. The rubber-band path can't reach here because
    // it always exits via the spring hand-off above before the bezier completes.
    if (progress >= 1.0f - FLT_EPSILON && fabs(scrollView.contentOffset.x - _endOffset) <= _environmentMetrics.pixelSize) {
        [self stopAnimationWithCompletion:YES];
    }
}

- (void)_startRubberBandSpringFromDisplacement:(CGFloat)x0
                                        velocity:(CGFloat)v0
                                          atTime:(CFTimeInterval)now TOPAGINGVIEW_OBJC_DIRECT {
    // Critical damping: damping = 2·dampingRatio·sqrt(mass·stiffness), β = damping / (2·mass).
    // For the closed-form solution x(t) = exp(-β·t)·(c1 + c2·t), c1 is the initial displacement
    // and c2 is initialVelocity + β·displacement. v0 here is signed in the direction of motion,
    // so positive means "still moving away from the rest position" — the spring then naturally
    // continues past, peaks, and decays back toward 0.
    const CGFloat damping = 2.0f * kTOAnimatorRubberBandSpringDampingRatio
                                 * sqrt(kTOAnimatorRubberBandSpringMass * kTOAnimatorRubberBandSpringStiffness);
    const CGFloat beta = damping / (2.0f * kTOAnimatorRubberBandSpringMass);

    _springBeta = beta;
    _springC1 = x0;
    _springC2 = v0 + beta * x0;
    _springStartTime = now;

    // Analytical settle duration (per ScrollMechanics' SpringTimingParameters): max of the times
    // each component falls below the visible-motion threshold. If a component is already below
    // the threshold (negative log argument) treat its contribution as zero.
    const CGFloat threshold = kTOAnimatorRubberBandSpringSettleThreshold;
    CFTimeInterval t1 = 0.0;
    if (fabs(_springC1) > threshold * 0.5f) {
        t1 = (1.0 / beta) * log(2.0 * fabs(_springC1) / threshold);
    }
    CFTimeInterval t2 = 0.0;
    const CGFloat c2_lower_bound = (CGFloat)(M_E) * beta * threshold * 0.25f;
    if (fabs(_springC2) > c2_lower_bound) {
        t2 = (2.0 / beta) * log(4.0 * fabs(_springC2) / ((CGFloat)(M_E) * beta * threshold));
    }
    _springDuration = fmax(0.0, fmax(t1, t2));
    _isInSpringSettle = YES;
}

@end
