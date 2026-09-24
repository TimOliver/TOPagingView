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
/// sqrt(stiffness / mass) for the fixed spring (stiffness 500, mass 1).
static const CGFloat kTOAnimatorRubberBandSpringDecay           = 22.360679774997898;
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
    // A newly created display link has no frame timestamp yet. Retiming a burst
    // against zero would make its very first frame look like the animation's end.
    const CFTimeInterval targetTimestamp = displayLink.targetTimestamp;
    return targetTimestamp > 0.0 ? targetTimestamp : CACurrentMediaTime();
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

// MARK: - Inline Timing State

typedef struct {
    CGFloat startOffset;
    CGFloat endOffset;
    CFTimeInterval duration;
} TOPagingViewBezierTiming;

typedef struct {
    CGFloat restOffset;
    CGFloat displacement;
    CGFloat velocityTerm;
    CFTimeInterval duration;
} TOPagingViewSpringTiming;

static inline CGFloat TOPagingViewBezierValue(TOPagingViewBezierTiming timing, CFTimeInterval t) {
    if (timing.duration <= FLT_EPSILON) { return timing.endOffset; }
    const CGFloat progress = (CGFloat)fmin(t / timing.duration, 1.0);
    return timing.startOffset + (timing.endOffset - timing.startOffset) * TOPagingViewAnimatorEvaluateEasing(progress);
}

static inline CGFloat TOPagingViewBezierVelocity(TOPagingViewBezierTiming timing, CFTimeInterval t) {
    if (timing.duration <= FLT_EPSILON) { return 0.0f; }
    const CGFloat linearProgress = (CGFloat)fmin(t / timing.duration, 1.0);
    const CGFloat slopeDelta = (CGFloat)1e-3;
    const CGFloat tA = (CGFloat)fmin(1.0, linearProgress + slopeDelta);
    const CGFloat tB = (CGFloat)fmax(0.0, linearProgress - slopeDelta);
    const CGFloat dxSpan = tA - tB;
    if (dxSpan <= FLT_EPSILON) { return 0.0f; }
    const CGFloat dySpan = TOPagingViewAnimatorEvaluateEasing(tA) - TOPagingViewAnimatorEvaluateEasing(tB);
    return (timing.endOffset - timing.startOffset) * (dySpan / dxSpan) / (CGFloat)timing.duration;
}

static inline CGFloat TOPagingViewSpringValue(TOPagingViewSpringTiming timing, CFTimeInterval t) {
    if (t >= timing.duration) { return timing.restOffset; }
    return timing.restOffset + (CGFloat)(exp(-kTOAnimatorRubberBandSpringDecay * t)
                                        * (timing.displacement + timing.velocityTerm * t));
}

static inline CGFloat TOPagingViewSpringVelocity(TOPagingViewSpringTiming timing, CFTimeInterval t) {
    if (t >= timing.duration) { return 0.0f; }
    const CGFloat beta = kTOAnimatorRubberBandSpringDecay;
    return (CGFloat)(exp(-beta * t) * (timing.velocityTerm - beta * (timing.displacement + timing.velocityTerm * t)));
}

// MARK: - Animator

@implementation TOPagingViewAnimator {
    CADisplayLink *_displayLink;
    CFTimeInterval _activeStartTime;
    TOPagingViewBezierTiming _bezierTiming;
    TOPagingViewSpringTiming _springTiming; /// Used only while _state.isRubberBanding is YES.
    BOOL _originalPagingEnabled;            /// Pre-animation pagingEnabled, restored on stop.
    TOPagingViewAnimatorEnvironmentMetrics _environmentMetrics; /// Cached display scale + slow-animation drag coefficient.
    TOPagingViewAnimatorState _state;       /// Live state pointer-readable by the paging view.
}

#pragma mark - Object Lifecycle -

- (instancetype)init {
    self = [super init];
    if (self) {
        _duration = kTOAnimatorDefaultDuration;
        _environmentMetrics = (TOPagingViewAnimatorEnvironmentMetrics){.displayScale = 1.0f, .animationDragCoefficient = 1.0f};
    }
    return self;
}

- (void)dealloc {
    [_displayLink invalidate];
}

- (BOOL)isAnimating { return _state.isAnimating; }
- (BOOL)isRubberBanding { return _state.isRubberBanding; }
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
    if (_state.isRubberBanding && pageDirection == _state.direction && _rubberBandsAtRest) {
        const CFTimeInterval referenceTime = TOPagingViewAnimatorReferenceTime(_displayLink);
        const CFTimeInterval elapsed = referenceTime - _activeStartTime;
        const CGFloat currentValue = TOPagingViewSpringValue(_springTiming, elapsed);
        const CGFloat currentVelocity = TOPagingViewSpringVelocity(_springTiming, elapsed);
        // Impulse magnitude matches a fresh bezier-from-rest's initial velocity:
        // span * slopeAtStart / duration, with span = _pageWidth.
        const CGFloat dir = TOPagingViewAnimatorDirectionMultiplier(pageDirection);
        const CFTimeInterval impulseDuration = segmentDuration > FLT_EPSILON ? segmentDuration : kTOAnimatorDefaultDuration;
        const CGFloat impulse = dir * _pageWidth * kTOAnimatorBezierInitialSlope / (CGFloat)impulseDuration;
        [self _startRubberBandWithDisplacement:(currentValue - _pageWidth)
                                    velocity:(currentVelocity + impulse)
                                        time:referenceTime];
        return;
    }

    // Stacking: same-direction tap mid-flight extends the active bezier by another page.
    // Applies whether or not the rubber-band is armed — for the rubber-band-armed case it
    // preserves the bezier's accumulated forward velocity across the boundary so a tap that
    // arrives just as the page transitions in doesn't reset to a single-page span and visibly
    // drop the velocity before the spring handoff takes over.
    if (_state.isAnimating && !_state.isRubberBanding && pageDirection == _state.direction) {
        const CFTimeInterval referenceTime = TOPagingViewAnimatorReferenceTime(_displayLink);
        const CGFloat dir = TOPagingViewAnimatorDirectionMultiplier(pageDirection);
        const CGFloat currentValue = TOPagingViewBezierValue(_bezierTiming, referenceTime - _activeStartTime);
        const CGFloat currentOffset = TOPagingViewAnimatorRoundToPixel(currentValue, _environmentMetrics.displayScale);
        // Extend the page boundary, not the already pixel-rounded target. Otherwise
        // fractional page widths accumulate rounding error across a rapid tap burst.
        const CGFloat targetPage = round(_bezierTiming.endOffset / _pageWidth) + dir;
        const CGFloat newEnd = TOPagingViewAnimatorRoundToPixel(targetPage * _pageWidth, _environmentMetrics.displayScale);
        _bezierTiming = (TOPagingViewBezierTiming){currentOffset, newEnd, segmentDuration};
        _activeStartTime = referenceTime;
        return;
    }

    // The caller supplies availability for the requested direction, including reversals.
    // A tap toward a newly available page replaces a settling spring with a normal turn.
    const BOOL wasRubberBanding = _state.isRubberBanding;
    _state.isRubberBanding = NO;
    _state.direction = pageDirection;

    // Target the page boundary one full page past where natural decel would settle: round
    // startOffset to the nearest boundary (its decel rest), then advance one page in tap dir.
    // This way a tap mid-decel always adds a full page beyond what the swipe would have done.
    const CGFloat startOffset = TOPagingViewAnimatorRoundToPixel(scrollView.contentOffset.x, _environmentMetrics.displayScale);
    // A bounce always belongs to the middle slot, even after several large impulses.
    const CGFloat nearestRest = wasRubberBanding ? _pageWidth : round(startOffset / _pageWidth) * _pageWidth;
    CGFloat endOffset = nearestRest + TOPagingViewAnimatorDirectionMultiplier(pageDirection) * _pageWidth;
    endOffset = TOPagingViewAnimatorRoundToPixel(endOffset, _environmentMetrics.displayScale);
    _bezierTiming = (TOPagingViewBezierTiming){startOffset, endOffset, segmentDuration};
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
    _state.isRubberBanding = NO;
    _rubberBandsAtRest = NO;
    _scrollView.pagingEnabled = _originalPagingEnabled;
    if (didComplete && _completionHandler) { _completionHandler(); }
    _completionHandler = nil;
}

- (void)didTransitionWithOffset:(CGFloat)offset {
    if (!_state.isAnimating || _state.isRubberBanding) { return; }

    // Slot rotation shifted everything by `offset`; rebase the bezier so the visible position
    // stays continuous through the page transition.
    const TOPagingViewBezierTiming bezier = _bezierTiming;
    const CGFloat actualOffset = TOPagingViewAnimatorRoundToPixel(_scrollView.contentOffset.x, _environmentMetrics.displayScale);
    const CFTimeInterval t = TOPagingViewAnimatorReferenceTime(_displayLink) - _activeStartTime;
    const CGFloat span = bezier.endOffset - bezier.startOffset;
    const CGFloat progress = (fabs(span) > FLT_EPSILON) ? (TOPagingViewBezierValue(bezier, t) - bezier.startOffset) / span : 1.0f;

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

    // Rebase in place; preserve _activeStartTime so progress is continuous.
    _bezierTiming = (TOPagingViewBezierTiming){newStart, newEnd, bezier.duration};
}

#pragma mark - Display Link -

- (void)_createDisplayLink TOPAGINGVIEW_OBJC_DIRECT {
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(_displayLinkDidFire:)];
    if (@available(iOS 15.0, *)) {
        _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(80.0f, 120.0f, 120.0f);
    }
    // Coverage runs on iOS 15+, so don't count the legacy OS branch in instrumented builds.
#if !defined(__LLVM_INSTR_PROFILE_GENERATE)
    else {
        _displayLink.preferredFramesPerSecond = 120;
    }
#endif
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)_displayLinkDidFire:(CADisplayLink *)displayLink {
    UIScrollView *const scrollView = _scrollView;
    if (scrollView == nil) { [self stopAnimationWithCompletion:NO]; return; }

    const CFTimeInterval now = displayLink.targetTimestamp;
    const CFTimeInterval t = now - _activeStartTime;
    const CGFloat value = _state.isRubberBanding ? TOPagingViewSpringValue(_springTiming, t)
                                               : TOPagingViewBezierValue(_bezierTiming, t);

    // First tick the bezier crosses the rest boundary in rubber-band mode, swap to the spring.
    if ([self _handOffBezierToSpringIfCrossingBoundaryAtValue:value time:now]) { return; }

    scrollView.contentOffset = (CGPoint){TOPagingViewAnimatorRoundToPixel(value, _environmentMetrics.displayScale), 0.0f};
    // Writing the offset can synchronously rebase the animation through the scroll delegate.
    const CFTimeInterval duration = _state.isRubberBanding ? _springTiming.duration : _bezierTiming.duration;
    if (t >= duration) { [self stopAnimationWithCompletion:YES]; }
}

#pragma mark - Rubber-band Spring -

/// If the active bezier has just carried the offset past the rest boundary, replace it with a
/// spring whose v0 matches the bezier's instantaneous velocity. Returns YES if the swap fired.
/// The rest position is `_pageWidth` (the middle slot). The paging view arms this only
/// when a tap or an adjacent-page fetch encounters a missing page in the turn's direction.
- (BOOL)_handOffBezierToSpringIfCrossingBoundaryAtValue:(CGFloat)value time:(CFTimeInterval)now TOPAGINGVIEW_OBJC_DIRECT {
    if (!_rubberBandsAtRest || _state.isRubberBanding) { return NO; }
    if (TOPagingViewAnimatorDirectionMultiplier(_state.direction) * (value - _pageWidth) <= 0.0f) { return NO; }

    const CGFloat velocity = TOPagingViewBezierVelocity(_bezierTiming, now - _activeStartTime);
    [self _startRubberBandWithDisplacement:(value - _pageWidth) velocity:velocity time:now];
    _scrollView.contentOffset = (CGPoint){TOPagingViewAnimatorRoundToPixel(value, _environmentMetrics.displayScale), 0.0f};
    return YES;
}

/// Both an edge crossing and another tap restart the same fixed spring from its current motion.
- (void)_startRubberBandWithDisplacement:(CGFloat)displacement
                              velocity:(CGFloat)velocity
                                  time:(CFTimeInterval)time TOPAGINGVIEW_OBJC_DIRECT {
    const CGFloat beta = kTOAnimatorRubberBandSpringDecay;
    const CGFloat threshold = kTOAnimatorRubberBandSpringSettleThreshold;
    const CGFloat velocityTerm = velocity + beta * displacement;

    // Bound each decaying component so even a large burst settles before we snap to rest.
    const CFTimeInterval t1 = (fabs(displacement) > threshold * 0.5f)
        ? (1.0 / beta) * log(2.0 * fabs(displacement) / threshold) : 0.0;
    const CFTimeInterval t2 = (fabs(velocityTerm) > (CGFloat)M_E * beta * threshold * 0.25f)
        ? (2.0 / beta) * log(4.0 * fabs(velocityTerm) / ((CGFloat)M_E * beta * threshold)) : 0.0;
    _springTiming = (TOPagingViewSpringTiming){_pageWidth, displacement, velocityTerm, fmax(t1, t2)};
    _activeStartTime = time;
    _state.isRubberBanding = YES;
}

#pragma mark - Environment -

- (void)_updateEnvironmentMetrics TOPAGINGVIEW_OBJC_DIRECT {
    // Display scale (eg @2x = 2.0, @3x = 3.0).
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
        .animationDragCoefficient = animationDragCoefficient,
    };
}

@end
