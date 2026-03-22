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

@interface TOPagingViewAnimator ()

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

    if (_isAnimating && dir == _turnDirection) {
        _startDistance = _currentDistance;
        _endDistance += _pageWidth;
        _startTime = now;
        return;
    }

    if (_isAnimating) { [self stopAnimation]; }

    _turnDirection = dir;
    _startDistance = 0.0f;
    _currentDistance = 0.0f;
    _endDistance = _pageWidth;
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

    const CFTimeInterval now = CACurrentMediaTime();
    const CGFloat targetDistance = [self _currentAnimatedDistanceAtTime:now];
    const CGFloat delta = targetDistance - _currentDistance;
    _currentDistance = targetDistance;

    CGPoint contentOffset = scrollView.contentOffset;
    contentOffset.x += delta * _turnDirection;
    scrollView.contentOffset = contentOffset;

    if (_currentDistance >= _endDistance - FLT_EPSILON) {
        [self _destroyDisplayLink];
        _isAnimating = NO;
        if (_completionHandler) {
            _completionHandler();
        }
    }
}

#pragma mark - Helpers -

- (CGFloat)_currentAnimatedDistanceAtTime:(CFTimeInterval)time
{
    const CFTimeInterval elapsed = time - _startTime;
    const CGFloat progress = (_duration <= FLT_EPSILON) ? 1.0f : (CGFloat)fmin(elapsed / _duration, 1.0);
    return _startDistance + ((_endDistance - _startDistance) * progress);
}

@end
