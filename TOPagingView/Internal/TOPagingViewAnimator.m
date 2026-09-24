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
#import <TargetConditionals.h>
#import <UIKit/UIKit.h>

#pragma mark - Constants

static const NSTimeInterval kTOAnimatorDefaultDuration = 0.5;
static const CGFloat kTOAnimatorInitialVelocity = 2.15;

@implementation TOPagingViewAnimator {
    UIViewPropertyAnimator *_propertyAnimator;
    UIView *_animationView;
    CADisplayLink *_displayLink;

    BOOL _nativeCompleted;
    BOOL _immediate;
    CFTimeInterval _lastSampleTime;

    CGFloat _start;
    CGFloat _target;  // Logical destination, unaffected by three-slot recycling.
    CGFloat _origin;  // Translation from logical coordinates to scroll view content offsets.
    CGFloat _lastValue;
    CGFloat _velocity;

    CGFloat _scale;
    CGFloat _animationTimeScale;

    BOOL _originalPagingEnabled;
    NSUInteger _generation;
    TOPagingViewAnimatorState _state;
}

#pragma mark - Object Lifecycle

- (instancetype)init {
    if ((self = [super init])) {
        _duration = kTOAnimatorDefaultDuration;
    }

    return self;
}

- (void)dealloc {
    [_displayLink invalidate];

    if (_propertyAnimator.state == UIViewAnimatingStateActive) {
        [_propertyAnimator stopAnimation:YES];
    }

    [_animationView removeFromSuperview];
}

#pragma mark - Animation State

- (BOOL)isAnimating {
    return _state.isAnimating;
}

- (BOOL)isRubberBanding {
    return _state.isRubberBanding;
}

- (UIRectEdge)direction {
    return _state.direction;
}

- (const TOPagingViewAnimatorState *)_statePointer {
    return &_state;
}

#pragma mark - Page Control

- (void)_turnToPageInDirection:(UIRectEdge)direction {
    UIScrollView *const scrollView = _scrollView;
    NSAssert(_pageWidth > FLT_EPSILON, @"Page width must be positive.");
    if (!scrollView || _pageWidth <= FLT_EPSILON) {
        return;
    }

    const BOOL wasAnimating = _state.isAnimating;
    const BOOL wasBouncing = _state.isRubberBanding;
    const BOOL sameDirection = direction == _state.direction;

    const CGFloat sign = direction == UIRectEdgeRight ? 1 : -1;
    const CGFloat seconds = _duration > FLT_EPSILON ? _duration : kTOAnimatorDefaultDuration;

    _animationTimeScale = 1;
#if TARGET_OS_SIMULATOR
    extern float UIAnimationDragCoefficient(void) __attribute__((weak_import));
    if (UIAnimationDragCoefficient != NULL) {
        _animationTimeScale = fmax(1, UIAnimationDragCoefficient());
    }
#endif

    if (!wasAnimating) {
        _origin = 0;
        _velocity = 0;

        _originalPagingEnabled = scrollView.pagingEnabled;
        scrollView.pagingEnabled = NO;
        _state.isAnimating = YES;

        _scale = fmax(1, fmax(scrollView.window.screen.scale, scrollView.traitCollection.displayScale));
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(_tick:)];

        if (@available(iOS 15.0, *)) {
            _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(80, 120, 120);
        } else {
            _displayLink.preferredFramesPerSecond = 120;
        }

        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }

    _state.direction = direction;

    // Retarget from the displayed position, including pixel rounding, without moving it at tap time.
    const CGFloat start = scrollView.contentOffset.x - _origin;
    CGFloat target;
    CGFloat velocity;

    _state.isRubberBanding = wasBouncing && sameDirection && _rubberBandsAtRest;
    if (_state.isRubberBanding) {
        target = _pageWidth - _origin;
        velocity = _velocity + sign * _pageWidth * kTOAnimatorInitialVelocity / (seconds * _animationTimeScale);

        // A zero-distance UIKit animation cannot carry an impulse. Launch a turn
        // from rest and hand it back to the boundary spring on its first movement.
        if (fabs(target - start) < 0.5 / _scale) {
            _state.isRubberBanding = NO;
            target += sign * _pageWidth;
        }
    } else {
        if (wasAnimating && !wasBouncing && sameDirection) {
            target = _target + sign * _pageWidth;
        } else {
            const CGFloat rest = wasBouncing ? _pageWidth : round(scrollView.contentOffset.x / _pageWidth) * _pageWidth;
            target = rest + sign * _pageWidth - _origin;
        }

        velocity = (target - start) * kTOAnimatorInitialVelocity / (seconds * _animationTimeScale);
    }

    [self _animateFrom:start
                    to:target
              velocity:velocity
              duration:(_duration <= FLT_EPSILON && !_rubberBandsAtRest ? 0 : seconds)];
}

- (void)_stopAnimationWithCompletion:(BOOL)invokeCompletion {
    if (!_state.isAnimating) {
        return;
    }

    _generation++;
    _state.isAnimating = NO;
    _state.isRubberBanding = NO;
    _rubberBandsAtRest = NO;

    [_displayLink invalidate];
    _displayLink = nil;

    if (_propertyAnimator.state == UIViewAnimatingStateActive) {
        [_propertyAnimator stopAnimation:YES];
    }

    _propertyAnimator = nil;
    [_animationView removeFromSuperview];
    _animationView = nil;

    void (^const completion)(void) = _completionHandler;
    _completionHandler = nil;
    _scrollView.pagingEnabled = _originalPagingEnabled;

    if (invokeCompletion && completion) {
        completion();
    }
}

- (void)_didTransitionWithOffset:(CGFloat)offset {
    if (!_state.isAnimating || _state.isRubberBanding) {
        return;
    }

    // Recenter the carousel without restarting or rewriting the native animation.
    _origin += offset;

    if (_immediate) {
        _target = _scrollView.contentOffset.x - _origin;
    }
}

#pragma mark - Native Spring Animation

- (void)_animateFrom:(CGFloat)start
                  to:(CGFloat)target
            velocity:(CGFloat)velocity
            duration:(NSTimeInterval)duration TOPAGINGVIEW_OBJC_DIRECT {
    _generation++;

    if (_propertyAnimator.state == UIViewAnimatingStateActive) {
        [_propertyAnimator stopAnimation:YES];
    }

    _propertyAnimator = nil;

    _start = _lastValue = start;
    _target = target;
    _velocity = velocity;

    _immediate = duration <= FLT_EPSILON;
    _lastSampleTime = CACurrentMediaTime();
    _nativeCompleted = _immediate;

    // A new layer cannot expose the previous animation's presentation position
    // while Core Animation is committing this retarget.
    [_animationView removeFromSuperview];

    UIView *const view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
    view.alpha = 0;
    view.userInteractionEnabled = NO;
    view.accessibilityElementsHidden = YES;
    view.center = CGPointMake(start, 0);

    _animationView = view;
    [_scrollView addSubview:view];

    if (duration <= FLT_EPSILON) {
        return;
    }

    // UIKit expresses initial velocity in animation distances per second.
    const CGFloat span = target - start;
    const CGFloat normalizedVelocity = fabs(span) > FLT_EPSILON ? velocity * _animationTimeScale / span : 0;

    UISpringTimingParameters *const timing =
        [[UISpringTimingParameters alloc] initWithDampingRatio:1 initialVelocity:CGVectorMake(normalizedVelocity, 0)];

    _propertyAnimator = [[UIViewPropertyAnimator alloc] initWithDuration:duration timingParameters:timing];

    [_propertyAnimator addAnimations:^{
        view.center = CGPointMake(target, 0);
    }];

    const NSUInteger generation = _generation;
    __weak typeof(self) const weakSelf = self;

    [_propertyAnimator addCompletion:^(UIViewAnimatingPosition position) {
        typeof(self) const self = weakSelf;

        if (self && self->_generation == generation) {
            self->_nativeCompleted = YES;
        }
    }];

    [_propertyAnimator startAnimation];
}

- (BOOL)_bounceIfNeededAtValue:(CGFloat)value TOPAGINGVIEW_OBJC_DIRECT {
    const CGFloat sign = _state.direction == UIRectEdgeRight ? 1 : -1;
    if (_state.isRubberBanding || !_rubberBandsAtRest || sign * (value + _origin - _pageWidth) <= 0) {
        return NO;
    }

    // Set this before writing the offset so a bounce cannot commit another page.
    _state.isRubberBanding = YES;

    [self _animateFrom:value
                    to:(_pageWidth - _origin)
              velocity:_velocity
              duration:(_duration > FLT_EPSILON ? _duration : kTOAnimatorDefaultDuration)];

    return YES;
}

#pragma mark - Display Link

- (void)_tick:(CADisplayLink *)link {
    UIScrollView *const scrollView = _scrollView;
    if (!scrollView) {
        [self _stopAnimationWithCompletion:NO];
        return;
    }

    const NSUInteger generation = _generation;
    const BOOL finished = _nativeCompleted;

    CALayer *const presentation = _animationView.layer.presentationLayer;
    CGFloat value = finished ? _target : (presentation ? presentation.position.x : _start);

    if (!_state.isRubberBanding) {
        value = _state.direction == UIRectEdgeRight ? fmin(value, _target) : fmax(value, _target);
    }

    // Sample the native motion for a velocity-preserving handoff at a missing page.
    const CFTimeInterval delta = link.timestamp - _lastSampleTime;

    if (delta > 0 && presentation) {
        _velocity = (value - _lastValue) / delta;
    }

    _lastSampleTime = link.timestamp;
    _lastValue = value;

    // Feed long jumps through the carousel a segment at a time, preserving every page commit.
    BOOL reached = NO;

    do {
        const CGFloat physical = value + _origin;
        const CGFloat previous = scrollView.contentOffset.x;
        const CGFloat step = fmax(previous - _pageWidth * 0.5, fmin(previous + _pageWidth * 0.5, physical));
        reached = step == physical;

        if ([self _bounceIfNeededAtValue:(step - _origin)]) {
            scrollView.contentOffset = CGPointMake(round(step * _scale) / _scale, 0);
            return;
        }

        // Intermediate substeps are bookkeeping only. Keep them exact so rounding
        // cannot prevent forward progress with very small or fractional page widths.
        scrollView.contentOffset = CGPointMake(reached && !finished ? round(step * _scale) / _scale : step, 0);

        if (_generation != generation) {
            return;
        }

        if ([self _bounceIfNeededAtValue:(scrollView.contentOffset.x - _origin)]) {
            return;
        }
    } while (!reached);

    if (finished) {
        [self _stopAnimationWithCompletion:YES];
    }
}

@end
