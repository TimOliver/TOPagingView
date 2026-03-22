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

/// Drives fixed content offset animations for TOPagingView using CADisplayLink.
///
/// Each call to `turnToPageInDirection:` animates the scroll view from its
/// current offset to the predetermined edge for that direction.
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

/// Animates to the predetermined page offset in the given direction.
///
/// @param direction The edge to turn toward (UIRectEdgeLeft or UIRectEdgeRight).
- (void)turnToPageInDirection:(UIRectEdge)direction;

/// Immediately stops the current animation at its current position.
- (void)stopAnimation;

@end

NS_ASSUME_NONNULL_END
