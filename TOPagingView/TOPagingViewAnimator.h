//
//  TOPagingViewAnimator.h
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

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Drives content offset animations for TOPagingView using CADisplayLink.
///
/// Instead of a pre-canned UIViewPropertyAnimator animation, this class
/// incrementally updates the scroll view's content offset each frame via
/// per-frame deltas. This allows the hosting paging view's scroll handling
/// logic to process page transitions naturally during the animation.
///
/// If multiple animations are requested while one is already in progress,
/// the remaining distance is combined with the new request and the timing
/// restarts, producing smooth aggregation of rapid page turns.
NS_SWIFT_NAME(PagingViewAnimator)
@interface TOPagingViewAnimator : NSObject

/// The scroll view whose content offset will be animated.
@property (nonatomic, weak, nullable) UIScrollView *scrollView;

/// The duration of each animation cycle in seconds (default 0.4).
@property (nonatomic, assign) CFTimeInterval duration;

/// Whether an animation is currently in progress.
@property (nonatomic, readonly) BOOL isAnimating;

/// Called when the animation completes naturally (not when stopped mid-way).
@property (nonatomic, copy, nullable) void (^completionHandler)(void);

/// Starts or extends a content offset animation by the given horizontal distance.
///
/// If called while already animating, the remaining distance is combined
/// with the new distance and the timing resets for a smooth continuation.
///
/// @param distance The horizontal distance to animate in points
///                 (positive = right, negative = left).
- (void)animateDistance:(CGFloat)distance;

/// Immediately stops the current animation at its current position.
- (void)stopAnimation;

@end

NS_ASSUME_NONNULL_END
