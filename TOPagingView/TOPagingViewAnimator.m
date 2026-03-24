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

/// Rounds a value to the nearest screen pixel for the given display scale.
static inline CGFloat TOPagingViewAnimatorRoundToPixel(CGFloat value, CGFloat scale) {
    return round(value * scale) / scale;
}

// -----------------------------------------------------------------

@interface TOPagingViewAnimator ()

/// The display link driving the frame-by-frame animation.
@property (nonatomic, strong, nullable) CADisplayLink *displayLink;

/// The time at which the current animation cycle started (reset on each tap).
@property (nonatomic, assign) CFTimeInterval startTime;

/// The direction multiplier (+1 for right, -1 for left).
@property (nonatomic, assign) CGFloat turnDirection;

/// The offset value when we started.
@property (nonatomic, assign) CGFloat startOffset;

/// The total target distance. This gets shrunk as we transition over boundaries.
@property (nonatomic, assign) CGFloat endOffset;

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
    const CGFloat centerOffset = _pageWidth;
    const CGFloat distanceFromCenter = scrollView.contentOffset.x - centerOffset;
    const CGFloat pixelSize = 1.0f / fmax(scale, 1.0f);

    if (_isAnimating && dir == _turnDirection) {
        _endOffset += _pageWidth;
        _endOffset = TOPagingViewAnimatorSnapToPageBoundary(_endOffset, _pageWidth, scale);
        _startOffset = scrollView.contentOffset.x;
        _startTime = now;
        return;
    }

    if (_isAnimating && fabs(distanceFromCenter) > pixelSize) {
        _turnDirection = (distanceFromCenter > 0.0f) ? -1.0f : 1.0f;
        _startOffset = scrollView.contentOffset.x;
        _endOffset = centerOffset;
        _startTime = now;
        return;
    }

    if (_isAnimating) { [self stopAnimation]; }

    _turnDirection = dir;
    _startOffset = scrollView.contentOffset.x;
    _endOffset = _pageWidth + (_pageWidth * dir);

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

- (void)didTransitionWithOffset:(CGFloat)offset {
    if (!_isAnimating) { return; }
    _startOffset += offset;
    _endOffset += offset;
}

#pragma mark - Display Link -

- (void)_createDisplayLink
{
    _displayLink = [CADisplayLink displayLinkWithTarget:self
                                              selector:@selector(_displayLinkDidFire:)];
    if (@available(iOS 15.0, *)) {
        _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(80.0, 120.0f, 120.0f);
    } else {
        _displayLink.preferredFramesPerSecond = 120;
    }
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
    const CGFloat targetOffset = _startOffset + ((_endOffset - _startOffset) * progress);
    scrollView.contentOffset = (CGPoint){targetOffset, 0.0f};

    if (progress >= 1.0f - FLT_EPSILON) {
        [self _destroyDisplayLink];
        _isAnimating = NO;
        if (_completionHandler) {
            _completionHandler();
        }
    }
}

@end
