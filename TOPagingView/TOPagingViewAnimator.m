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

/// The starting content offset X for the current animation.
@property (nonatomic, assign) CGFloat startOffsetX;

/// The destination content offset X for the current animation.
@property (nonatomic, assign) CGFloat targetOffsetX;

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
    if (scrollView == nil) { return; }

    if (_isAnimating) { [self stopAnimation]; }

    _startOffsetX = scrollView.contentOffset.x;
    _targetOffsetX = (direction == UIRectEdgeRight) ? (_pageWidth * 2.0f) : 0.0f;
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

    const CFTimeInterval elapsed = CACurrentMediaTime() - _startTime;
    const CGFloat progress = (CGFloat)fmin(elapsed / _duration, 1.0);
    const CGFloat currentOffset = _startOffsetX + ((_targetOffsetX - _startOffsetX) * progress);
    scrollView.contentOffset = (CGPoint){currentOffset, 0.0f};

    if (progress >= 1.0f) {
        [self _destroyDisplayLink];
        _isAnimating = NO;
        if (_completionHandler) {
            _completionHandler();
        }
    }
}

@end
