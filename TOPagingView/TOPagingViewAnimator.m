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

/// The direction multiplier (+1 for right, -1 for left).
@property (nonatomic, assign) CGFloat turnDirection;

/// The total distance to animate. Always positive.
/// Incremented by pageWidth on each call to turnToPageInDirection:.
@property (nonatomic, assign) CGFloat totalDistance;

/// How much distance has been applied to the scroll view so far. Always positive.
/// Snapped to the nearest multiple of pageWidth after each transition.
@property (nonatomic, assign) CGFloat appliedDistance;

/// The value of appliedDistance when the timer was last reset.
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
        // Already animating in the same direction.
        // Add one more page width of distance and restart the timer.
        _totalDistance += _pageWidth;
    } else {
        // Fresh animation (or direction change)
        if (_isAnimating) { [self stopAnimation]; }

        _turnDirection = dir;
        _totalDistance = _pageWidth;
        _isAnimating = YES;
        [self _createDisplayLink];
    }

    _startApplied = 0.0;
    _appliedDistance = 0.0f;
    _startTime = CACurrentMediaTime();
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

    // Interpolate from startApplied → totalDistance
    const CGFloat targetApplied = _startApplied + (_totalDistance - _startApplied) * progress;
    const CGFloat delta = targetApplied - _appliedDistance;
    _appliedDistance = targetApplied;

    // Apply the delta to the scroll view in the turn direction
    CGPoint offset = scrollView.contentOffset;
    const CGFloat expectedOffset = offset.x + delta * _turnDirection;
    offset.x = expectedOffset;
    scrollView.contentOffset = offset;

    // Check if a page transition fired (offset jumped by ~pageWidth)
//    const CGFloat actualOffset = scrollView.contentOffset.x;
//    if (_pageWidth > FLT_EPSILON && fabs(actualOffset - expectedOffset) > _pageWidth * 0.5f) {
//        // Transition fired. Snap appliedDistance to the nearest page
//        // boundary to eliminate floating-point drift, and snap the
//        // offset to exact center.
//        _appliedDistance = round(_appliedDistance / _pageWidth) * _pageWidth;
//        scrollView.contentOffset = (CGPoint){center, 0.0f};
//
//        // If there's still distance remaining, notify the caller
//        // so it can fire willTurnToPageOfType: for the next page.
//        if (_appliedDistance < _totalDistance && _pageTransitionHandler) {
//            _pageTransitionHandler();
//        }
//    }

    // Complete when the duration has elapsed
    if (progress >= 1.0f) {
        [self _destroyDisplayLink];
        _isAnimating = NO;

//        if (_pageWidth > FLT_EPSILON) {
//            scrollView.contentOffset = (CGPoint){center, 0.0f};
//        }

        if (_completionHandler) {
            _completionHandler();
        }
    }
}

@end
