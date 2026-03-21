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
static const CFTimeInterval kTOAnimatorDefaultDuration = 0.4;

/// Cubic bezier control points for the ease-out curve.
static const CGFloat kTOAnimatorControlPoint1X = 0.3f;
static const CGFloat kTOAnimatorControlPoint1Y = 0.9f;
static const CGFloat kTOAnimatorControlPoint2X = 0.45f;
static const CGFloat kTOAnimatorControlPoint2Y = 1.0f;

// -----------------------------------------------------------------

/// Evaluates a cubic bezier easing curve for the given linear time progress.
/// Uses Newton-Raphson iteration to find the parametric value, then
/// evaluates the y-component for the eased output.
/// @param t Linear time progress from 0.0 to 1.0.
/// @return Eased progress from 0.0 to 1.0.
static inline CGFloat TOPagingViewAnimatorEvaluateEasing(CGFloat t) {
    // Use Newton-Raphson to solve for the parameter u where x(u) = t
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

    // Evaluate y(u) to get the eased value
    const CGFloat oneMinusU = 1.0f - u;
    return 3.0f * oneMinusU * oneMinusU * u * kTOAnimatorControlPoint1Y
         + 3.0f * oneMinusU * u * u * kTOAnimatorControlPoint2Y
         + u * u * u;
}

// -----------------------------------------------------------------

@interface TOPagingViewAnimator ()

/// The display link driving the frame-by-frame animation.
@property (nonatomic, strong, nullable) CADisplayLink *displayLink;

/// The time at which the current easing cycle started.
@property (nonatomic, assign) CFTimeInterval startTime;

/// YES when running a one-shot offset animation (skip), NO for page turns.
@property (nonatomic, assign) BOOL isOneShotAnimation;

// -- Page turn state --

/// The total number of page turns requested during this animation.
@property (nonatomic, assign) NSInteger targetTurns;

/// The number of page turns fully completed (transitions fired).
@property (nonatomic, assign) NSInteger completedTurns;

/// The direction of the animation (+1 for right, -1 for left).
@property (nonatomic, assign) CGFloat turnDirection;

/// The fractional turn progress (0–1 within the current page) at the
/// moment the easing timer was last reset. Used to avoid visual jumps
/// when aggregating new page turns mid-animation.
@property (nonatomic, assign) CGFloat turnFractionAtReset;

// -- One-shot offset state --

/// The starting content offset X for a one-shot animation.
@property (nonatomic, assign) CGFloat offsetStartX;

/// The total distance for a one-shot animation.
@property (nonatomic, assign) CGFloat offsetDistance;

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
    const CGFloat dir = (direction == UIRectEdgeRight) ? 1.0f : -1.0f;

    if (_isAnimating && !_isOneShotAnimation && dir == _turnDirection) {
        // Already animating page turns in the same direction.
        // Capture the current visual position so the easing
        // continues smoothly after the timer resets.
        const CFTimeInterval elapsed = CACurrentMediaTime() - _startTime;
        const CGFloat progress = (CGFloat)fmin(elapsed / _duration, 1.0);
        const CGFloat easedProgress = TOPagingViewAnimatorEvaluateEasing(progress);
        const NSInteger remainingTurns = _targetTurns - _completedTurns;
        const CGFloat currentFraction = _turnFractionAtReset
                                      + easedProgress * ((CGFloat)remainingTurns - _turnFractionAtReset);
        _turnFractionAtReset = fmin(currentFraction, 1.0f);

        // Queue one more turn and restart the easing timer
        _targetTurns++;
        _startTime = CACurrentMediaTime();
    } else {
        // Fresh page turn animation (or direction change)
        if (_isAnimating) { [self stopAnimation]; }

        _targetTurns = 1;
        _completedTurns = 0;
        _turnDirection = dir;
        _turnFractionAtReset = 0.0f;
        _isOneShotAnimation = NO;
        _startTime = CACurrentMediaTime();
        _isAnimating = YES;
        [self _createDisplayLink];
    }
}

- (void)animateOffset:(CGFloat)distance
{
    if (_isAnimating) { [self stopAnimation]; }

    _offsetStartX = _scrollView.contentOffset.x;
    _offsetDistance = distance;
    _isOneShotAnimation = YES;
    _startTime = CACurrentMediaTime();
    _isAnimating = YES;
    [self _createDisplayLink];
}

- (void)stopAnimation
{
    if (!_isAnimating) { return; }
    [self _destroyDisplayLink];
    _isAnimating = NO;
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

    if (_isOneShotAnimation) {
        [self _updateOneShotAnimation:scrollView];
    } else {
        [self _updatePageTurnAnimation:scrollView];
    }
}

#pragma mark - Page Turn Animation -

- (void)_updatePageTurnAnimation:(UIScrollView *)scrollView
{
    const CGFloat center = _pageWidth;

    // Calculate the current easing progress
    const CFTimeInterval elapsed = CACurrentMediaTime() - _startTime;
    const CGFloat progress = (CGFloat)fmin(elapsed / _duration, 1.0);
    const CGFloat easedProgress = TOPagingViewAnimatorEvaluateEasing(progress);

    // The easing covers all remaining turns in one sweep.
    // It interpolates from turnFractionAtReset (the visual position when
    // the timer last reset) through the total remaining turns.
    const NSInteger remainingTurns = _targetTurns - _completedTurns;
    const CGFloat totalFraction = _turnFractionAtReset
                                + easedProgress * ((CGFloat)remainingTurns - _turnFractionAtReset);

    // Clamp to one page width — the offset can only reach the edge of
    // the current page slot. The transition handles the rest.
    const CGFloat currentTurnFraction = fmin(totalFraction, 1.0f);

    // Compute the desired offset: center + fraction * pageWidth * direction
    const CGFloat desiredOffset = center + currentTurnFraction * _pageWidth * _turnDirection;
    scrollView.contentOffset = (CGPoint){desiredOffset, 0.0f};

    // Check if a page transition fired (offset was adjusted by ~pageWidth)
    const CGFloat actualOffset = scrollView.contentOffset.x;
    if (fabs(actualOffset - desiredOffset) > _pageWidth * 0.5f) {
        // Transition fired. Snap to exact center and advance the counter.
        _completedTurns++;
        _turnFractionAtReset = 0.0f;
        scrollView.contentOffset = (CGPoint){center, 0.0f};
    }

    // Complete the animation once all queued turns are done
    if (_completedTurns >= _targetTurns) {
        [self _destroyDisplayLink];
        _isAnimating = NO;
        scrollView.contentOffset = (CGPoint){center, 0.0f};
        if (_completionHandler) {
            _completionHandler();
        }
    }
}

#pragma mark - One-Shot Offset Animation -

- (void)_updateOneShotAnimation:(UIScrollView *)scrollView
{
    const CFTimeInterval elapsed = CACurrentMediaTime() - _startTime;
    const CGFloat progress = (CGFloat)fmin(elapsed / _duration, 1.0);
    const CGFloat easedProgress = TOPagingViewAnimatorEvaluateEasing(progress);

    // Interpolate from start to destination
    const CGFloat currentOffset = _offsetStartX + _offsetDistance * easedProgress;
    scrollView.contentOffset = (CGPoint){currentOffset, 0.0f};

    // Complete when the easing finishes
    if (progress >= 1.0f) {
        [self _destroyDisplayLink];
        _isAnimating = NO;
        if (_completionHandler) {
            _completionHandler();
        }
    }
}

@end
