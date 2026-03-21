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
/// Supports two modes of animation:
///
/// **Page turns** (`turnToPageInDirection:`) drive the offset from center toward
/// the page edge each frame, letting the paging view's scroll handling fire
/// transitions naturally. Multiple calls aggregate — each call adds one more
/// page turn to the queue and restarts the easing timer from the current position.
///
/// **Offset animations** (`animateOffset:`) perform a simple one-shot slide
/// of the content offset by a fixed distance, used for skip animations where
/// the page layout is managed externally.
NS_SWIFT_NAME(PagingViewAnimator)
@interface TOPagingViewAnimator : NSObject

/// The scroll view whose content offset will be animated.
@property (nonatomic, weak, nullable) UIScrollView *scrollView;

/// The width of one page segment in the scroll view (view width + page spacing).
/// Must be set before calling `turnToPageInDirection:`.
@property (nonatomic, assign) CGFloat pageWidth;

/// The duration of each animation cycle in seconds (default 0.4).
@property (nonatomic, assign) CFTimeInterval duration;

/// Whether an animation is currently in progress.
@property (nonatomic, readonly) BOOL isAnimating;

/// Called when the animation completes naturally (not when stopped mid-way).
@property (nonatomic, copy, nullable) void (^completionHandler)(void);

/// Queues a page turn animation in the given direction.
///
/// The animator determines the destination offset from the current scroll position,
/// the page width, and the number of page turns already queued. If called while
/// already animating in the same direction, the turn count increments and the
/// easing timer restarts from the current visual position.
///
/// @param direction The edge to turn toward (UIRectEdgeLeft or UIRectEdgeRight).
- (void)turnToPageInDirection:(UIRectEdge)direction;

/// Performs a one-shot content offset animation by the given distance.
///
/// Unlike `turnToPageInDirection:`, this does not track page transitions
/// or support aggregation. Used for skip animations where the caller
/// manages page layout and disables automatic layout during the animation.
///
/// @param distance The horizontal distance to animate in points
///                 (positive = right, negative = left).
- (void)animateOffset:(CGFloat)distance;

/// Immediately stops the current animation at its current position.
- (void)stopAnimation;

@end

NS_ASSUME_NONNULL_END
