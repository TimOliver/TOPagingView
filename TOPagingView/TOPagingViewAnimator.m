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

/// Converts an absolute content offset into a logical offset relative to the middle slot.
static inline CGFloat TOPagingViewAnimatorLogicalOffset(CGFloat contentOffset, CGFloat pageWidth, CGFloat scale) {
    const CGFloat logicalOffset = TOPagingViewAnimatorRoundToPixel(contentOffset - pageWidth, scale);
    return TOPagingViewAnimatorClampNearZero(logicalOffset, scale);
}

/// Converts a logical offset relative to the middle slot back into an absolute content offset.
static inline CGFloat TOPagingViewAnimatorAbsoluteOffset(CGFloat logicalOffset, CGFloat pageWidth, CGFloat scale) {
    return TOPagingViewAnimatorRoundToPixel(pageWidth + logicalOffset, scale);
}

// -----------------------------------------------------------------

@interface TOPagingViewAnimator ()

/// The display link driving the frame-by-frame animation.
@property (nonatomic, strong, nullable) CADisplayLink *displayLink;

/// The time at which the current animation cycle started (reset on each tap).
@property (nonatomic, assign) CFTimeInterval startTime;

/// The direction multiplier (+1 for right, -1 for left).
@property (nonatomic, assign) CGFloat turnDirection;

/// The logical offset from the middle slot when we started.
@property (nonatomic, assign) CGFloat startOffset;

/// The logical offset from the middle slot where this animation should end.
@property (nonatomic, assign) CGFloat endOffset;

/// The original pagingEnabled state before this animator temporarily disabled paging.
@property (nonatomic, assign) BOOL originalPagingEnabled;

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
    const CGFloat scale = TOPagingViewAnimatorDisplayScale(scrollView);
    const CFTimeInterval now = CACurrentMediaTime();

    if (_isAnimating && dir == _turnDirection) {
        // Extend the animation one more page in the same direction.
        const CFTimeInterval elapsed = (_displayLink != nil) ? (_displayLink.targetTimestamp - _startTime)
                                                             : (now - _startTime);
        const CGFloat linearProgress = (_duration <= FLT_EPSILON) ? 1.0f : (CGFloat)fmin(elapsed / _duration, 1.0);
        const CGFloat progress = TOPagingViewAnimatorEvaluateEasing(linearProgress);
        _startOffset = TOPagingViewAnimatorRoundToPixel(_startOffset + ((_endOffset - _startOffset) * progress), scale);
        _startOffset = TOPagingViewAnimatorClampNearZero(_startOffset, scale);
        _endOffset = TOPagingViewAnimatorRoundToPixel(_endOffset + (dir * _pageWidth), scale);
        _endOffset = TOPagingViewAnimatorClampNearZero(_endOffset, scale);
        _startTime = now;
        return;
    }

    // New direction or fresh start: animate from the current position to the nearest
    // page boundary in the requested direction. This naturally handles reversal
    // (tap left while going right snaps back to the page on screen) as well as
    // re-initiating the original direction mid-reversal without drift.
    _turnDirection = dir;
    _startOffset = TOPagingViewAnimatorLogicalOffset(scrollView.contentOffset.x, _pageWidth, scale);
    _endOffset = (dir > 0.0f)
        ? ceil(_startOffset / _pageWidth + FLT_EPSILON) * _pageWidth
        : floor(_startOffset / _pageWidth - FLT_EPSILON) * _pageWidth;
    _endOffset = TOPagingViewAnimatorRoundToPixel(_endOffset, scale);
    _endOffset = TOPagingViewAnimatorClampNearZero(_endOffset, scale);
    _startTime = now;

    if (!_isAnimating) {
        _isAnimating = YES;
        _originalPagingEnabled = scrollView.pagingEnabled;
        scrollView.pagingEnabled = NO;
        [self _createDisplayLink];
    }
}

- (void)stopAnimation
{
    if (!_isAnimating) { return; }
    [self _destroyDisplayLink];
    _isAnimating = NO;
    _scrollView.pagingEnabled = _originalPagingEnabled;
}

- (BOOL)hasRunwayInDirection:(UIRectEdge)direction {
    UIScrollView *scrollView = _scrollView;
    if (scrollView == nil || _pageWidth <= FLT_EPSILON) { return NO; }

    const CGFloat scale = TOPagingViewAnimatorDisplayScale(scrollView);
    const CGFloat pixelSize = 1.0f / fmax(scale, 1.0f);
    const CGFloat offset = scrollView.contentOffset.x;
    const CGFloat maxOffset = scrollView.contentSize.width - CGRectGetWidth(scrollView.bounds);

    if (direction == UIRectEdgeRight) {
        return offset < maxOffset - pixelSize;
    } else {
        return offset > pixelSize;
    }
}

- (void)stopAnimationInDirection:(UIRectEdge)direction {
    const CGFloat dir = (direction == UIRectEdgeRight) ? 1.0f : -1.0f;
    UIScrollView *const scrollView = _scrollView;
    if (!scrollView || !_isAnimating || _turnDirection != dir) { return; }

    // Capture the current velocity before stopping.
    const CFTimeInterval elapsed = (_displayLink != nil) ? (_displayLink.targetTimestamp - _startTime)
                                                         : (CACurrentMediaTime() - _startTime);
    const CGFloat linearProgress = (_duration <= FLT_EPSILON) ? 1.0f : (CGFloat)fmin(elapsed / _duration, 1.0);
    const CGFloat dp = 0.001f;
    const CGFloat easingNow = TOPagingViewAnimatorEvaluateEasing(linearProgress);
    const CGFloat easingNext = TOPagingViewAnimatorEvaluateEasing(fmin(linearProgress + dp, 1.0f));
    const CGFloat easingSlope = (easingNext - easingNow) / dp;
    _velocity = (_endOffset - _startOffset) * easingSlope / (CGFloat)_duration;

    [self stopAnimation];

    [UIView animateWithDuration:0.25f delay:0.0 usingSpringWithDamping:1.0 initialSpringVelocity:_velocity / 65.0f
                        options:0 animations:^{
        scrollView.contentOffset = (CGPoint){scrollView.contentOffset.x + (65.0f * dir), 0.0f};
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.4f delay:0.0 usingSpringWithDamping:1.0 initialSpringVelocity:1.0f
                            options:0 animations:^{
            scrollView.contentOffset = (CGPoint){self->_pageWidth, 0.0f};
        } completion:nil];
    }];
}

- (void)didTransitionWithOffset:(CGFloat)offset {
    if (!_isAnimating) { return; }
    const CGFloat scale = TOPagingViewAnimatorDisplayScale(_scrollView);
    const CGFloat actualOffset = TOPagingViewAnimatorLogicalOffset(_scrollView.contentOffset.x, _pageWidth, scale);
    const CFTimeInterval elapsed = (_displayLink != nil) ? (_displayLink.targetTimestamp - _startTime)
                                                         : (CACurrentMediaTime() - _startTime);
    const CGFloat linearProgress = (_duration <= FLT_EPSILON) ? 1.0f : (CGFloat)fmin(elapsed / _duration, 1.0);
    const CGFloat progress = TOPagingViewAnimatorEvaluateEasing(linearProgress);

    _endOffset += offset;
    if (_pageWidth > FLT_EPSILON) {
        // Keep the logical destination on an exact page multiple even if the
        // scroll view crossed the threshold at a slightly rounded offset.
        _endOffset = round(_endOffset / _pageWidth) * _pageWidth;
    }
    _endOffset = TOPagingViewAnimatorRoundToPixel(_endOffset, scale);
    _endOffset = TOPagingViewAnimatorClampNearZero(_endOffset, scale);

    const CGFloat remainingProgress = 1.0f - progress;
    if (remainingProgress <= FLT_EPSILON) {
        _startOffset = actualOffset;
        _endOffset = actualOffset;
        return;
    }

    _startOffset = (actualOffset - (_endOffset * progress)) / remainingProgress;
    _startOffset = TOPagingViewAnimatorRoundToPixel(_startOffset, scale);
    _startOffset = TOPagingViewAnimatorSnapToPageBoundary(_startOffset, _pageWidth, scale);
    _startOffset = TOPagingViewAnimatorClampNearZero(_startOffset, scale);
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

    const CFTimeInterval elapsed = displayLink.targetTimestamp - _startTime;
    const CGFloat linearProgress = (_duration <= FLT_EPSILON) ? 1.0f : (CGFloat)fmin(elapsed / _duration, 1.0);
    const CGFloat progress = TOPagingViewAnimatorEvaluateEasing(linearProgress);
    CGFloat targetOffset = _startOffset + ((_endOffset - _startOffset) * progress);
    scrollView.contentOffset = (CGPoint){TOPagingViewAnimatorAbsoluteOffset(targetOffset, _pageWidth, TOPagingViewAnimatorDisplayScale(scrollView)), 0.0f};
    
    const CGFloat pixelSize = 1.0f / TOPagingViewAnimatorDisplayScale(scrollView);
    if (progress >= 1.0f - FLT_EPSILON
        && fabs(TOPagingViewAnimatorLogicalOffset(scrollView.contentOffset.x, _pageWidth, TOPagingViewAnimatorDisplayScale(scrollView)) - _endOffset) <= pixelSize) {
        [self _destroyDisplayLink];
        _isAnimating = NO;
        _scrollView.pagingEnabled = _originalPagingEnabled;
        if (_completionHandler) {
            _completionHandler();
        }
    }
}

@end
