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

// -----------------------------------------------------------------

@interface TOPagingViewAnimator () {
    CGFloat _delta;
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
    _delta = 0.0;
    _currentOffset = _scrollView.contentOffset.x;
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

    const CFTimeInterval elapsed = CACurrentMediaTime() - _startTime;
    const CGFloat linearProgress = (_duration <= FLT_EPSILON) ? 1.0f : (CGFloat)fmin(elapsed / _duration, 1.0);
    const CGFloat progress = TOPagingViewAnimatorEvaluateEasing(linearProgress);
    const CGFloat targetDistance = _startDistance + ((_endDistance - _startDistance) * progress);
    const CGFloat delta = targetDistance - _currentDistance;
    _currentDistance = targetDistance;

    // Track the offset at full precision to avoid sub-pixel rounding
    // losses from reading back contentOffset each frame.
    _currentOffset += delta * _turnDirection;
    scrollView.contentOffset = (CGPoint){_currentOffset, 0.0f};

    NSLog(@"delta: %f totalDelta: %f linearProgress: %f progress: %f current: %f, scrolloffset: %f",
          delta, _delta, linearProgress, progress, _currentOffset, _scrollView.contentOffset.x);

    // When the offset crosses a page boundary, wrap it back to center.
    // This keeps our tracked offset in sync with the scroll view's
    // transition logic which resets the offset after a page turn.
    const CGFloat rightEdge = _pageWidth * 2.0f;
    if (rightEdge - _currentOffset < 0.5f ||
        _currentOffset < 0.5f + FLT_EPSILON) {
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
