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

// MARK: - Constants

/// Default duration for page turn animations.
static const CFTimeInterval kTOAnimatorDefaultDuration = 0.5f;

/// Critically damped rubber-band spring. Closed-form x(t) = exp(-β·t)·(c1 + c2·t)
/// Higher stiffness = snappier; settleThreshold caps the duration once visible motion is sub-pixel.
static const CGFloat kTOAnimatorRubberBandSpringMass            = 1.0f;
static const CGFloat kTOAnimatorRubberBandSpringStiffness       = 250.0f;
static const CGFloat kTOAnimatorRubberBandSpringSettleThreshold = 0.5f;

/// Cubic bezier control points for the ease-out curve.
static const CGFloat kTOAnimatorControlPoint1X = 0.35f;
static const CGFloat kTOAnimatorControlPoint1Y = 0.75f;
static const CGFloat kTOAnimatorControlPoint2X = 0.3f;
static const CGFloat kTOAnimatorControlPoint2Y = 1.0f;

/// Initial dy/dx of the bezier at u=0 — equals (3·CP1Y) / (3·CP1X) = CP1Y/CP1X. Used by the
/// rubber-band impulse path to reproduce the velocity a fresh bezier-from-rest would impart.
static const CGFloat kTOAnimatorBezierInitialSlope = kTOAnimatorControlPoint1Y / kTOAnimatorControlPoint1X;

// MARK: - Helpers

/// Cubic bezier ease-out: solves for u where x(u) = t (Newton), then returns y(u).
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

/// Snaps to the nearest page boundary if within one pixel.
static inline CGFloat TOPagingViewAnimatorSnapToPageBoundary(CGFloat value, CGFloat pageWidth, CGFloat scale) {
    if (pageWidth <= FLT_EPSILON) { return value; }
    const CGFloat nearestPageBoundary = round(value / pageWidth) * pageWidth;
    const CGFloat pixelSize = 1.0f / fmax(scale, 1.0f);
    if (fabs(value - nearestPageBoundary) <= pixelSize) { return nearestPageBoundary; }
    return value;
}

/// Reference time for the current frame: the displayLink's targetTimestamp if available,
/// otherwise wall-clock now.
static inline CFTimeInterval TOPagingViewAnimatorReferenceTime(CADisplayLink *_Nullable displayLink) {
    return (displayLink != nil) ? displayLink.targetTimestamp : CACurrentMediaTime();
}

/// Rounds to the nearest screen pixel for the given display scale.
static inline CGFloat TOPagingViewAnimatorRoundToPixel(CGFloat value, CGFloat scale) {
    NSCAssert(scale > 0, @"Display scale must be positive.");
    return round(value * scale) / scale;
}

/// +1 for right, −1 for left. Centralizes the direction-to-multiplier conversion.
static inline CGFloat TOPagingViewAnimatorDirectionMultiplier(UIRectEdge direction) {
    return (direction == UIRectEdgeRight) ? 1.0f : -1.0f;
}

// MARK: - Timing Parameters

/// 1-D timing source. `valueAtTime:` returns the offset at time t (relative to the parameters'
/// own start). `duration` is the wall-clock window after which the parameters are considered
/// complete and the animator should stop.
@protocol TOPagingViewTimingParameters <NSObject>
@property (nonatomic, readonly) CFTimeInterval duration;
- (CGFloat)valueAtTime:(CFTimeInterval)t;
@end

// -- Bezier ease-out --

@interface TOPagingViewBezierTimingParameters : NSObject <TOPagingViewTimingParameters>
@property (nonatomic, readonly) CGFloat startOffset;
@property (nonatomic, readonly) CGFloat endOffset;
+ (instancetype)timingParametersWithStartOffset:(CGFloat)startOffset
                                       endOffset:(CGFloat)endOffset
                                        duration:(CFTimeInterval)duration TOPAGINGVIEW_OBJC_DIRECT;
/// Wall-clock velocity (pts/sec) at time t — sampled finite-difference of the easing curve.
- (CGFloat)velocityAtTime:(CFTimeInterval)t TOPAGINGVIEW_OBJC_DIRECT;
@end

@implementation TOPagingViewBezierTimingParameters {
    CGFloat _startOffset;
    CGFloat _endOffset;
    CFTimeInterval _duration;
}

// `duration` only comes from the protocol so it needs an explicit synthesize; the other two
// auto-synthesize from their @interface declarations.
@synthesize duration = _duration;

+ (instancetype)timingParametersWithStartOffset:(CGFloat)startOffset
                                       endOffset:(CGFloat)endOffset
                                        duration:(CFTimeInterval)duration {
    TOPagingViewBezierTimingParameters *p = [self new];
    p->_startOffset = startOffset;
    p->_endOffset = endOffset;
    p->_duration = duration;
    return p;
}

- (CGFloat)valueAtTime:(CFTimeInterval)t {
    if (_duration <= FLT_EPSILON) { return _endOffset; }
    const CGFloat linearProgress = (CGFloat)fmin(t / _duration, 1.0);
    return _startOffset + (_endOffset - _startOffset) * TOPagingViewAnimatorEvaluateEasing(linearProgress);
}

- (CGFloat)velocityAtTime:(CFTimeInterval)t {
    if (_duration <= FLT_EPSILON) { return 0.0f; }
    const CGFloat linearProgress = (CGFloat)fmin(t / _duration, 1.0);
    const CGFloat slopeDelta = (CGFloat)1e-3;
    const CGFloat tA = (CGFloat)fmin(1.0, linearProgress + slopeDelta);
    const CGFloat tB = (CGFloat)fmax(0.0, linearProgress - slopeDelta);
    const CGFloat dxSpan = tA - tB;
    if (dxSpan <= FLT_EPSILON) { return 0.0f; }
    const CGFloat dySpan = TOPagingViewAnimatorEvaluateEasing(tA) - TOPagingViewAnimatorEvaluateEasing(tB);
    return (_endOffset - _startOffset) * (dySpan / dxSpan) / (CGFloat)_duration;
}

@end

// -- Critically damped spring --

@interface TOPagingViewSpringTimingParameters : NSObject <TOPagingViewTimingParameters>
+ (instancetype)timingParametersWithRestOffset:(CGFloat)restOffset
                                    displacement:(CGFloat)displacement
                                        velocity:(CGFloat)velocity
                                            mass:(CGFloat)mass
                                       stiffness:(CGFloat)stiffness
                                       threshold:(CGFloat)threshold TOPAGINGVIEW_OBJC_DIRECT;
/// Closed-form velocity at time t: x'(t) = exp(-β·t)·(c2 − β·(c1 + c2·t)).
- (CGFloat)velocityAtTime:(CFTimeInterval)t TOPAGINGVIEW_OBJC_DIRECT;
@end

@implementation TOPagingViewSpringTimingParameters {
    CGFloat _restOffset;
    CGFloat _beta;
    CGFloat _c1;
    CGFloat _c2;
    CFTimeInterval _duration;
}

@synthesize duration = _duration;

+ (instancetype)timingParametersWithRestOffset:(CGFloat)restOffset
                                    displacement:(CGFloat)displacement
                                        velocity:(CGFloat)velocity
                                            mass:(CGFloat)mass
                                       stiffness:(CGFloat)stiffness
                                       threshold:(CGFloat)threshold {
    TOPagingViewSpringTimingParameters *p = [self new];
    const CGFloat beta = (CGFloat)sqrt(stiffness / mass); // critical damping (ζ = 1)
    p->_restOffset = restOffset;
    p->_beta = beta;
    p->_c1 = displacement;
    p->_c2 = velocity + beta * displacement;

    // Settle time: per-component upper bound (max of when each part falls below threshold).
    // Components already under the threshold contribute 0.
    const CFTimeInterval t1 = (fabs(p->_c1) > threshold * 0.5f)
        ? (1.0 / beta) * log(2.0 * fabs(p->_c1) / threshold) : 0.0;
    const CFTimeInterval t2 = (fabs(p->_c2) > (CGFloat)M_E * beta * threshold * 0.25f)
        ? (2.0 / beta) * log(4.0 * fabs(p->_c2) / ((CGFloat)M_E * beta * threshold)) : 0.0;
    p->_duration = fmax(0.0, fmax(t1, t2));
    return p;
}

- (CGFloat)valueAtTime:(CFTimeInterval)t {
    if (t >= _duration) { return _restOffset; }
    return _restOffset + (CGFloat)(exp(-_beta * t) * (_c1 + _c2 * t));
}

- (CGFloat)velocityAtTime:(CFTimeInterval)t {
    if (t >= _duration) { return 0.0f; }
    return (CGFloat)(exp(-_beta * t) * (_c2 - _beta * (_c1 + _c2 * t)));
}

@end

// MARK: - Animator

@implementation TOPagingViewAnimator {
    CADisplayLink *_displayLink;            /// Drives valueAtTime: each frame onto the scroll view.
    CFTimeInterval _activeStartTime;        /// Wall-clock when _activeTiming was installed.
    id<TOPagingViewTimingParameters> _activeTiming; /// Current bezier or spring source.
    BOOL _originalPagingEnabled;            /// Pre-animation pagingEnabled, restored on stop.
    TOPagingViewAnimatorEnvironmentMetrics _environmentMetrics; /// Cached display scale + slow-animation drag coefficient.
    TOPagingViewAnimatorState _state;       /// Live state pointer-readable by the paging view.
}

#pragma mark - Object Lifecycle -

- (instancetype)init {
    self = [super init];
    if (self) {
        _duration = kTOAnimatorDefaultDuration;
        _environmentMetrics = (TOPagingViewAnimatorEnvironmentMetrics){.displayScale = 1.0f, .pixelSize = 1.0f, .animationDragCoefficient = 1.0f};
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

    const CFTimeInterval now = CACurrentMediaTime();
    [self _updateEnvironmentMetrics];
    const CFTimeInterval segmentDuration = _duration * _environmentMetrics.animationDragCoefficient;

    // Same-direction tap during a settling rubber-band: kick the spring with another impulse
    // rather than swapping to a fresh bezier (which would stall a frame on the bezier→spring
    // handoff before any visible movement). Position stays continuous, velocity gets the same
    // boost a fresh bezier-from-rest would impart, so each tap visibly punts the offset
    // further out before the spring pulls it back.
    if (_state.isAnimating && pageDirection == _state.direction && _rubberBandsAtRest
        && [_activeTiming isKindOfClass:[TOPagingViewSpringTimingParameters class]]) {
        TOPagingViewSpringTimingParameters *const oldSpring = (TOPagingViewSpringTimingParameters *)_activeTiming;
        const CFTimeInterval referenceTime = (_displayLink != nil) ? _displayLink.targetTimestamp : now;
        const CFTimeInterval elapsed = referenceTime - _activeStartTime;
        const CGFloat currentValue = [oldSpring valueAtTime:elapsed];
        const CGFloat currentVelocity = [oldSpring velocityAtTime:elapsed];
        // Impulse magnitude matches a fresh bezier-from-rest's initial velocity:
        // span * slopeAtStart / duration, with span = _pageWidth.
        const CGFloat dir = TOPagingViewAnimatorDirectionMultiplier(pageDirection);
        const CGFloat impulse = dir * _pageWidth * kTOAnimatorBezierInitialSlope / (CGFloat)segmentDuration;
        _activeTiming = [TOPagingViewSpringTimingParameters timingParametersWithRestOffset:_pageWidth
                                                                              displacement:(currentValue - _pageWidth)
                                                                                  velocity:(currentVelocity + impulse)
                                                                                      mass:kTOAnimatorRubberBandSpringMass
                                                                                 stiffness:kTOAnimatorRubberBandSpringStiffness
                                                                                 threshold:kTOAnimatorRubberBandSpringSettleThreshold];
        _activeStartTime = referenceTime;
        return;
    }

    // Stacking: same-direction tap mid-flight extends the active bezier by another page. Only
    // valid for normal page chains while the active timing is still a bezier — rubber-band
    // taps go through the impulse branch above instead.
    if (_state.isAnimating && pageDirection == _state.direction && !_rubberBandsAtRest
        && [_activeTiming isKindOfClass:[TOPagingViewBezierTimingParameters class]]) {
        TOPagingViewBezierTimingParameters *const bezier = (TOPagingViewBezierTimingParameters *)_activeTiming;
        const CFTimeInterval referenceTime = (_displayLink != nil) ? _displayLink.targetTimestamp : now;
        const CGFloat dir = TOPagingViewAnimatorDirectionMultiplier(pageDirection);
        const CGFloat currentOffset = TOPagingViewAnimatorRoundToPixel([bezier valueAtTime:(referenceTime - _activeStartTime)],
                                                                       _environmentMetrics.displayScale);
        const CGFloat newEnd = TOPagingViewAnimatorRoundToPixel(bezier.endOffset + dir * _pageWidth, _environmentMetrics.displayScale);
        _activeTiming = [TOPagingViewBezierTimingParameters timingParametersWithStartOffset:currentOffset
                                                                                  endOffset:newEnd
                                                                                   duration:segmentDuration];
        _activeStartTime = now;
        return;
    }

    // Reversal drops any in-flight rubber-band so a back-tap isn't resisted. A same-direction
    // tap during a settling spring keeps the flag armed: the impulse branch above re-energises
    // it without resetting the trajectory.
    if (pageDirection != _state.direction) { _rubberBandsAtRest = NO; }
    _state.direction = pageDirection;

    // Target the page boundary one full page past where natural decel would settle: round
    // startOffset to the nearest boundary (its decel rest), then advance one page in tap dir.
    // This way a tap mid-decel always adds a full page beyond what the swipe would have done.
    const CGFloat startOffset = TOPagingViewAnimatorRoundToPixel(scrollView.contentOffset.x, _environmentMetrics.displayScale);
    const CGFloat nearestRest = round(startOffset / _pageWidth) * _pageWidth;
    CGFloat endOffset = nearestRest + TOPagingViewAnimatorDirectionMultiplier(pageDirection) * _pageWidth;
    endOffset = TOPagingViewAnimatorRoundToPixel(endOffset, _environmentMetrics.displayScale);
    _activeTiming = [TOPagingViewBezierTimingParameters timingParametersWithStartOffset:startOffset
                                                                              endOffset:endOffset
                                                                               duration:segmentDuration];
    _activeStartTime = now;

    if (!_state.isAnimating) {
        _state.isAnimating = YES;
        _originalPagingEnabled = scrollView.pagingEnabled;
        scrollView.pagingEnabled = NO;
        [self _createDisplayLink];
    }
}

- (void)stopAnimationWithCompletion:(BOOL)didComplete {
    if (!_state.isAnimating) { return; }
    [_displayLink invalidate];
    _displayLink = nil;
    _state.isAnimating = NO;
    _rubberBandsAtRest = NO;
    _activeTiming = nil;
    _scrollView.pagingEnabled = _originalPagingEnabled;
    if (didComplete && _completionHandler) { _completionHandler(); }
    _completionHandler = nil;
}

- (void)didTransitionWithOffset:(CGFloat)offset {
    if (!_state.isAnimating) { return; }
    if (![_activeTiming isKindOfClass:[TOPagingViewBezierTimingParameters class]]) { return; }

    // Slot rotation shifted everything by `offset`; rebase the bezier so the visible position
    // stays continuous through the page transition.
    TOPagingViewBezierTimingParameters *const bezier = (TOPagingViewBezierTimingParameters *)_activeTiming;
    const CGFloat actualOffset = TOPagingViewAnimatorRoundToPixel(_scrollView.contentOffset.x, _environmentMetrics.displayScale);
    const CFTimeInterval t = TOPagingViewAnimatorReferenceTime(_displayLink) - _activeStartTime;
    const CGFloat span = bezier.endOffset - bezier.startOffset;
    const CGFloat progress = (fabs(span) > FLT_EPSILON) ? ([bezier valueAtTime:t] - bezier.startOffset) / span : 1.0f;

    CGFloat newEnd = TOPagingViewAnimatorRoundToPixel(bezier.endOffset + offset, _environmentMetrics.displayScale);
    newEnd = TOPagingViewAnimatorSnapToPageBoundary(newEnd, _pageWidth, _environmentMetrics.displayScale);

    CGFloat newStart;
    const CGFloat remainingProgress = 1.0f - progress;
    if (remainingProgress <= FLT_EPSILON) {
        newStart = actualOffset;
        newEnd = actualOffset;
    } else {
        newStart = (actualOffset - (newEnd * progress)) / remainingProgress;
        newStart = TOPagingViewAnimatorRoundToPixel(newStart, _environmentMetrics.displayScale);
        newStart = TOPagingViewAnimatorSnapToPageBoundary(newStart, _pageWidth, _environmentMetrics.displayScale);
    }

    // Replace the bezier with the rebased version; preserve _activeStartTime so progress is
    // continuous across the transition.
    _activeTiming = [TOPagingViewBezierTimingParameters timingParametersWithStartOffset:newStart
                                                                              endOffset:newEnd
                                                                               duration:bezier.duration];
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
    if (scrollView == nil) { [self stopAnimationWithCompletion:NO]; return; }

    const CFTimeInterval now = displayLink.targetTimestamp;
    const CFTimeInterval t = now - _activeStartTime;
    const CGFloat value = [_activeTiming valueAtTime:t];

    // First tick the bezier crosses the rest boundary in rubber-band mode, swap to the spring.
    if ([self _handOffBezierToSpringIfCrossingBoundaryAtValue:value time:now]) { return; }

    scrollView.contentOffset = (CGPoint){TOPagingViewAnimatorRoundToPixel(value, _environmentMetrics.displayScale), 0.0f};
    if (t >= _activeTiming.duration) { [self stopAnimationWithCompletion:YES]; }
}

#pragma mark - Rubber-band Spring -

/// If the active bezier has just carried the offset past the rest boundary, replace it with a
/// spring whose v0 matches the bezier's instantaneous velocity. Returns YES if the swap fired.
/// Assumes the rest position is `_pageWidth` (the middle slot), which is true for every site
/// that arms `rubberBandsAtRest` today — the flag is only set when an adjacent-page fetch
/// returns nil while the current page is centered.
- (BOOL)_handOffBezierToSpringIfCrossingBoundaryAtValue:(CGFloat)value time:(CFTimeInterval)now TOPAGINGVIEW_OBJC_DIRECT {
    if (!_rubberBandsAtRest) { return NO; }
    if (![_activeTiming isKindOfClass:[TOPagingViewBezierTimingParameters class]]) { return NO; }
    if (TOPagingViewAnimatorDirectionMultiplier(_state.direction) * (value - _pageWidth) <= 0.0f) { return NO; }

    TOPagingViewBezierTimingParameters *const bezier = (TOPagingViewBezierTimingParameters *)_activeTiming;
    const CGFloat velocity = [bezier velocityAtTime:(now - _activeStartTime)];
    _activeTiming = [TOPagingViewSpringTimingParameters timingParametersWithRestOffset:_pageWidth
                                                                          displacement:(value - _pageWidth)
                                                                              velocity:velocity
                                                                                  mass:kTOAnimatorRubberBandSpringMass
                                                                             stiffness:kTOAnimatorRubberBandSpringStiffness
                                                                             threshold:kTOAnimatorRubberBandSpringSettleThreshold];
    _activeStartTime = now;
    _scrollView.contentOffset = (CGPoint){TOPagingViewAnimatorRoundToPixel(value, _environmentMetrics.displayScale), 0.0f};
    return YES;
}

#pragma mark - Environment -

- (void)_updateEnvironmentMetrics TOPAGINGVIEW_OBJC_DIRECT {
    // Display scale (eg @2x = 2.0, @3x = 3.0). pixelSize is the reciprocal.
    const CGFloat displayScale = ({
        CGFloat scale = _scrollView.window.screen.scale;
        if (scale <= FLT_EPSILON) { scale = _scrollView.traitCollection.displayScale; }
        (scale <= FLT_EPSILON) ? 1.0f : scale;
    });

    // 'Slow Animations' coefficient on the simulator; 1.0 on device.
    const CGFloat animationDragCoefficient = ({
        #if TARGET_OS_SIMULATOR
            extern float UIAnimationDragCoefficient(void) __attribute__((weak_import));
            const float dragCoefficient = (UIAnimationDragCoefficient != NULL) ? UIAnimationDragCoefficient() : 1.0f;
            (dragCoefficient > FLT_EPSILON) ? dragCoefficient : 1.0f;
        #else
            1.0f;
        #endif
    });

    _environmentMetrics = (TOPagingViewAnimatorEnvironmentMetrics){
        .displayScale = displayScale,
        .pixelSize = 1.0f / fmax(displayScale, 1.0f),
        .animationDragCoefficient = animationDragCoefficient,
    };
}

@end
