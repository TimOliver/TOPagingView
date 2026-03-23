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
#import <QuartzCore/QuartzCore.h>

// -----------------------------------------------------------------

/// Default duration for page turn animations.
static const CFTimeInterval kTOAnimatorDefaultDuration = 1.4;

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
        const CGFloat x = 3.0f * oneMinusU * oneMinusU * u * kTOAnimatorControlPoint1X
                        + 3.0f * oneMinusU * u * u * kTOAnimatorControlPoint2X
                        + u * u * u
                        - t;
        const CGFloat dx = 3.0f * oneMinusU * oneMinusU * kTOAnimatorControlPoint1X
                         + 6.0f * oneMinusU * u * (kTOAnimatorControlPoint2X - kTOAnimatorControlPoint1X)
                         + 3.0f * u * u * (1.0f - kTOAnimatorControlPoint2X);
        if (fabs(dx) < 1e-6f) { break; }
        u -= x / dx;
    }
    u = fmax(0.0f, fmin(1.0f, u));
    const CGFloat oneMinusU = 1.0f - u;
    return 3.0f * oneMinusU * oneMinusU * u * kTOAnimatorControlPoint1Y
         + 3.0f * oneMinusU * u * u * kTOAnimatorControlPoint2Y
         + u * u * u;
}

/// Returns the display scale used by the hosting scroll view, or the main screen as a fallback.
static inline CGFloat TOPagingViewAnimatorDisplayScale(UIScrollView * _Nullable scrollView) {
    CGFloat scale = scrollView.window.screen.scale;
    if (scale <= FLT_EPSILON) {
        scale = scrollView.traitCollection.displayScale;
    }
    return (scale <= FLT_EPSILON) ? 1.0f : scale;
}

/// Snaps a value to the nearest page boundary only when already within one pixel of that boundary.
static inline CGFloat TOPagingViewAnimatorSnapToPageBoundary(CGFloat value, CGFloat pageWidth, CGFloat scale) {
    if (pageWidth <= FLT_EPSILON) { return value; }

    const CGFloat nearestPageBoundary = round(value / pageWidth) * pageWidth;
    const CGFloat pixelSize = 1.0f / fmax(scale, 1.0f);
    if (fabs(value - nearestPageBoundary) <= pixelSize) {
        return nearestPageBoundary;
    }

    return value;
}

/// Clamps extremely small values to zero using a one-pixel tolerance.
static inline CGFloat TOPagingViewAnimatorClampNearZero(CGFloat value, CGFloat scale) {
    const CGFloat pixelSize = 1.0f / fmax(scale, 1.0f);
    return (fabs(value) <= pixelSize) ? 0.0f : value;
}

/// The maximum distance that can be safely consumed in one frame without
/// risking the pager jumping across multiple page boundaries before it can
/// process the next scroll event.
static inline CGFloat TOPagingViewAnimatorMaximumFrameDelta(CGFloat pageWidth, CGFloat scale) {
    const CGFloat pixelSize = 1.0f / fmax(scale, 1.0f);
    return fmax(pageWidth - pixelSize, 0.0f);
}

// -----------------------------------------------------------------

@interface TOPagingViewAnimator () {
    CGFloat _currentOffset;
}

/// The display link driving the frame-by-frame animation.
@property (nonatomic, strong, nullable) CADisplayLink *displayLink;

/// The time at which the current animation cycle started (reset on each tap).
@property (nonatomic, assign) CFTimeInterval startTime;

/// The direction multiplier (+1 for right, -1 for left).
@property (nonatomic, assign) CGFloat turnDirection;

/// The animated distance at the start of the current easing cycle.
@property (nonatomic, assign) CGFloat startDistance;

/// The total target distance for the current animation sequence.
@property (nonatomic, assign) CGFloat endDistance;

/// The amount of distance already applied to the scroll view.
@property (nonatomic, assign) CGFloat currentDistance;

@end

// -----------------------------------------------------------------

@implementation TOPagingViewAnimator

#pragma mark - Object Lifecycle -

- (instancetype)init
{
    self = [super init];
    if (self) {
        _duration = kTOAnimatorDefaultDuration;
    }
    return self;
}

- (void)dealloc
{
    [_displayLink invalidate];
}

#pragma mark - Public Methods -

- (void)turnToPageInDirection:(UIRectEdge)direction
{
    UIScrollView *const scrollView = _scrollView;
    if (scrollView == nil || _pageWidth <= FLT_EPSILON) { return; }

    const CGFloat dir = (direction == UIRectEdgeRight) ? 1.0f : -1.0f;
    const CFTimeInterval now = CACurrentMediaTime();
    const CGFloat scale = TOPagingViewAnimatorDisplayScale(scrollView);

    if (_isAnimating && dir == _turnDirection) {
        _startDistance = _currentDistance;
        _endDistance += _pageWidth;
        _endDistance = TOPagingViewAnimatorSnapToPageBoundary(_endDistance, _pageWidth, scale);
        _startTime = now;
        return;
    }

    if (_isAnimating) { [self stopAnimation]; }

    _currentOffset = _scrollView.contentOffset.x;
    _turnDirection = dir;

    // If we're starting mid-page (e.g. from a swipe), target the remaining
    // distance to the nearest page-turn boundary in this direction.
    const CGFloat boundaryOffset = _pageWidth + (_pageWidth * dir);
    const CGFloat remainingDistance = (boundaryOffset - _currentOffset) * dir;
    _startDistance = 0.0f;
    _currentDistance = 0.0f;
    _endDistance = TOPagingViewAnimatorClampNearZero(fmax(remainingDistance, 0.0f), scale);

    _startTime = now;
    _isAnimating = YES;
    [self _createDisplayLink];
}

- (void)stopAnimation
{
    if (!_isAnimating) { return; }
    [self _destroyDisplayLink];
    _isAnimating = NO;
}

- (void)didTransition
{
    UIScrollView *const scrollView = _scrollView;
    if (!_isAnimating || scrollView == nil || _pageWidth <= FLT_EPSILON) { return; }

    const CGFloat scale = TOPagingViewAnimatorDisplayScale(scrollView);

    // Re-base the logical distances whenever TOPagingView recenters the
    // scroll view so that any overshoot is preserved, but stale page widths
    // don't keep accumulating in the remaining target distance.
    _currentOffset = scrollView.contentOffset.x;
    _startDistance -= _pageWidth;
    _currentDistance -= _pageWidth;
    _endDistance -= _pageWidth;

    _startDistance = TOPagingViewAnimatorSnapToPageBoundary(_startDistance, _pageWidth, scale);
    _currentDistance = TOPagingViewAnimatorSnapToPageBoundary(_currentDistance, _pageWidth, scale);
    _endDistance = TOPagingViewAnimatorSnapToPageBoundary(_endDistance, _pageWidth, scale);

    _currentDistance = TOPagingViewAnimatorClampNearZero(_currentDistance, scale);
    _endDistance = TOPagingViewAnimatorClampNearZero(_endDistance, scale);

    if (_endDistance < _currentDistance) {
        _endDistance = _currentDistance;
    }

    // Restart the easing cycle from the rebased position so the next frame
    // doesn't evaluate the old progress value against the new bounds.
    _startDistance = _currentDistance;
    _startTime = CACurrentMediaTime();
}

#pragma mark - Display Link -

- (void)_createDisplayLink
{
    _displayLink = [CADisplayLink displayLinkWithTarget:self
                                              selector:@selector(_displayLinkDidFire:)];
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop]
                       forMode:NSRunLoopCommonModes];
}

- (void)_destroyDisplayLink
{
    [_displayLink invalidate];
    _displayLink = nil;
}

- (void)_displayLinkDidFire:(CADisplayLink *)displayLink
{
    UIScrollView *const scrollView = _scrollView;
    if (scrollView == nil) {
        [self stopAnimation];
        return;
    }

    const CFTimeInterval elapsed = CACurrentMediaTime() - _startTime;
    const CGFloat linearProgress = (_duration <= FLT_EPSILON) ? 1.0f : (CGFloat)fmin(elapsed / _duration, 1.0);
    const CGFloat progress = TOPagingViewAnimatorEvaluateEasing(linearProgress);
    const CGFloat targetDistance = _startDistance + ((_endDistance - _startDistance) * progress);
    CGFloat delta = targetDistance - _currentDistance;
    const CGFloat maxDelta = TOPagingViewAnimatorMaximumFrameDelta(_pageWidth,
                                                                   TOPagingViewAnimatorDisplayScale(scrollView));
    if (delta > maxDelta) {
        delta = maxDelta;
    } else if (delta < -maxDelta) {
        delta = -maxDelta;
    }
    _currentDistance += delta;

    // Track the offset at full precision to avoid sub-pixel rounding
    // losses from reading back contentOffset each frame.
    if (progress < 1.0f - FLT_EPSILON) {
        _currentOffset += delta * _turnDirection;
    } else if (progress >= 1.0f && (_currentOffset < (_pageWidth * 0.5f) || _currentOffset > (_pageWidth * 1.5f))) {
        // In the off chance the progression finishes, but we didn't hit the end threshold,
        _currentOffset = _pageWidth + (_pageWidth * _turnDirection);
    }
    scrollView.contentOffset = (CGPoint){_currentOffset, 0.0f};

    // Once the scroll view goes over its boundary, it performs the transition and jumps
    // back to the middle. This can happen in the final few ticks, so we'll use a fuzzy check here to stay in sync.
    if (fabs(_currentOffset - scrollView.contentOffset.x) > (_pageWidth * 0.5f)) {
        _currentOffset = _scrollView.contentOffset.x;
    }

    if (_currentDistance >= _endDistance - FLT_EPSILON) {
        [self _destroyDisplayLink];
        _isAnimating = NO;
        if (_completionHandler) {
            _completionHandler();
        }
    }
}

@end
