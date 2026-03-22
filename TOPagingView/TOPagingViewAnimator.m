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

// -----------------------------------------------------------------

@interface TOPagingViewAnimator ()

/// The display link driving the frame-by-frame animation.
@property (nonatomic, strong, nullable) CADisplayLink *displayLink;

/// The time at which the current animation cycle started (reset on each tap).
@property (nonatomic, assign) CFTimeInterval startTime;

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

    if (_isAnimating && dir == _turnDirection) {
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
        _startTime = CACurrentMediaTime();
        _isAnimating = YES;
        [self _createDisplayLink];
    }
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

    const CGFloat center = _pageWidth;

    // Linear progress from the last timer reset
    const CFTimeInterval elapsed = CACurrentMediaTime() - _startTime;
    const CGFloat progress = (CGFloat)fmin(elapsed / _duration, 1.0);

    // Interpolate the applied distance from startApplied → totalDistance.
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
    // For skip animations where layout is disabled, no transition fires
    // and this block is simply skipped.
    const CGFloat actualOffset = scrollView.contentOffset.x;
    if (_pageWidth > FLT_EPSILON && fabs(actualOffset - expectedOffset) > _pageWidth * 0.5f) {
        // Transition fired. Snap the offset to exact center, and snap
        // appliedDistance to an integer multiple of pageWidth to
        // eliminate any floating-point drift between page turns.
        _completedPages++;
        _appliedDistance = (CGFloat)_completedPages * _pageWidth;
        scrollView.contentOffset = (CGPoint){center, 0.0f};

        // If more turns are pending, notify the caller so it can
        // fire willTurnToPageOfType: for the next page turn.
        if (_completedPages < _targetPages && _pageTransitionHandler) {
            _pageTransitionHandler();
        }
    }

    // Complete when the duration has elapsed. For page turns, all
    // transitions will have fired by this point. For skip animations,
    // the offset has reached the destination.
    if (progress >= 1.0f) {
        [self _destroyDisplayLink];
        _isAnimating = NO;

        // Snap to center as a final safety net
        if (_pageWidth > FLT_EPSILON) {
            scrollView.contentOffset = (CGPoint){center, 0.0f};
        }

        if (_completionHandler) {
            _completionHandler();
        }
    }
}

@end
