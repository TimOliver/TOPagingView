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

/// Once the easing duration has elapsed, keep nudging by a tiny amount until
/// the paging view commits the final threshold crossing.
static const CGFloat kTOAnimatorCommitNudge = 1.0f;

// -----------------------------------------------------------------

@interface TOPagingViewAnimator ()

/// The display link driving the frame-by-frame animation.
@property (nonatomic, strong, nullable) CADisplayLink *displayLink;

/// The time at which the current animation cycle started (reset on each tap).
@property (nonatomic, assign) CFTimeInterval startTime;

/// YES when running a skip animation that does not trigger page transitions.
@property (nonatomic, assign) BOOL isOneShotAnimation;

// -- Page turn state --

/// The total number of page turns to animate through.
@property (nonatomic, assign) NSInteger targetPages;

/// The number of page boundaries crossed so far (transitions fired).
@property (nonatomic, assign) NSInteger completedPages;

/// The direction multiplier (+1 for right, -1 for left).
@property (nonatomic, assign) CGFloat turnDirection;

/// The total distance to animate (targetPages * pageWidth). Always positive.
@property (nonatomic, assign) CGFloat totalDistance;

/// How much distance has been applied to the scroll view so far. Always positive.
/// Snapped to an exact integer multiple of pageWidth after each transition.
@property (nonatomic, assign) CGFloat appliedDistance;

/// The value of appliedDistance when the easing timer was last reset.
/// Used as the interpolation start point so the animation continues
/// smoothly from wherever the offset currently is.
@property (nonatomic, assign) CGFloat startApplied;

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
        // Already animating in the same direction. Add another page
        // and restart the timer so the animation covers from the
        // current position to the new target in a fresh duration.
        _targetPages++;
        _totalDistance = (CGFloat)_targetPages * _pageWidth;
        _startApplied = _appliedDistance;
        _startTime = CACurrentMediaTime();
    } else {
        // Fresh page turn animation (or direction change)
        if (_isAnimating) { [self stopAnimation]; }

        _targetPages = 1;
        _completedPages = 0;
        _turnDirection = dir;
        _totalDistance = _pageWidth;
        _appliedDistance = 0.0f;
        _startApplied = 0.0f;
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
    _isOneShotAnimation = NO;
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

    // Linear progress from the last timer reset
    const CFTimeInterval elapsed = CACurrentMediaTime() - _startTime;
    const CGFloat progress = (CGFloat)fmin(elapsed / _duration, 1.0);

    // Interpolate the applied distance from startApplied -> totalDistance.
    // This gives us the total cumulative delta that should have been
    // output by this point in the animation.
    const CGFloat targetApplied = _startApplied + (_totalDistance - _startApplied) * progress;
    const CGFloat delta = targetApplied - _appliedDistance;
    _appliedDistance = targetApplied;

    // Apply the delta to the scroll view in the turn direction.
    // Setting contentOffset synchronously triggers scrollViewDidScroll,
    // which may fire a page transition that adjusts the offset.
    CGPoint offset = scrollView.contentOffset;
    const CGFloat expectedOffset = offset.x + delta * _turnDirection;
    offset.x = expectedOffset;
    scrollView.contentOffset = offset;

    // Check if a page transition fired (offset jumped by ~pageWidth).
    // For one-shot skip animations, this logic is bypassed entirely.
    const CGFloat actualOffset = scrollView.contentOffset.x;
    if (_pageWidth > FLT_EPSILON && fabs(actualOffset - expectedOffset) > _pageWidth * 0.5f) {
        // Transition fired. Snap the offset to exact center, and snap
        // appliedDistance to an exact integer multiple of pageWidth.
        // This keeps the logical animation state in sync with the
        // paging view after it recenters the scroll view.
        _completedPages++;
        _appliedDistance = (CGFloat)_completedPages * _pageWidth;
        scrollView.contentOffset = (CGPoint){center, 0.0f};

        // If more turns are still queued, notify the caller so it can
        // prepare for the next turn at the correct point in the sequence.
        if (_completedPages < _targetPages && _pageTransitionHandler) {
            _pageTransitionHandler();
        }
    }

    // If the easing duration elapsed exactly on the page boundary, the
    // paging view may still need one more tick of movement before it
    // commits the transition. Keep nudging until that happens.
    if (progress >= 1.0f && _completedPages < _targetPages) {
        CGPoint nudgedOffset = scrollView.contentOffset;
        const CGFloat expectedNudgedOffset = nudgedOffset.x + (kTOAnimatorCommitNudge * _turnDirection);
        nudgedOffset.x = expectedNudgedOffset;
        scrollView.contentOffset = nudgedOffset;

        const CGFloat actualNudgedOffset = scrollView.contentOffset.x;
        if (_pageWidth > FLT_EPSILON && fabs(actualNudgedOffset - expectedNudgedOffset) > _pageWidth * 0.5f) {
            _completedPages++;
            _appliedDistance = (CGFloat)_completedPages * _pageWidth;
            scrollView.contentOffset = (CGPoint){center, 0.0f};

            if (_completedPages < _targetPages && _pageTransitionHandler) {
                _pageTransitionHandler();
            }
        }
    }

    // Complete once all requested page boundaries have fired.
    if (_completedPages >= _targetPages) {
        [self _destroyDisplayLink];
        _isAnimating = NO;
        _isOneShotAnimation = NO;
        scrollView.contentOffset = (CGPoint){center, 0.0f};
        if (_completionHandler) {
            _completionHandler();
        }
    }
}

#pragma mark - One-Shot Animation -

- (void)_updateOneShotAnimation:(UIScrollView *)scrollView
{
    const CFTimeInterval elapsed = CACurrentMediaTime() - _startTime;
    const CGFloat progress = (CGFloat)fmin(elapsed / _duration, 1.0);

    const CGFloat currentOffset = _offsetStartX + (_offsetDistance * progress);
    scrollView.contentOffset = (CGPoint){currentOffset, 0.0f};

    if (progress >= 1.0f) {
        [self _destroyDisplayLink];
        _isAnimating = NO;
        _isOneShotAnimation = NO;
        if (_completionHandler) {
            _completionHandler();
        }
    }
}

@end
