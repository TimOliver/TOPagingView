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

#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIGeometry.h>
#import <Foundation/Foundation.h>
#import "TOPagingViewMacros.h"
#import "TOPagingViewTypesPrivate.h"

@class UIScrollView;

NS_ASSUME_NONNULL_BEGIN

/// Drives content offset animations for TOPagingView using CADisplayLink.
///
/// The animator stores absolute `contentOffset.x` values and writes them
/// directly into the scroll view each frame. When TOPagingView recenters the
/// scroll view during page transitions, the animator is rebased by one page
/// segment so the motion remains continuous.
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

/// The direction we're currently turning in.
@property (nonatomic, readonly) UIRectEdge direction;

/// Called when the animation completes naturally (not when stopped mid-way).
@property (nonatomic, copy, nullable) void (^completionHandler)(void);

/// Animates toward the next page in the given direction.
/// @param direction The edge to turn toward (UIRectEdgeLeft or UIRectEdgeRight).
- (void)turnToPageInDirection:(UIRectEdge)direction TOPAGINGVIEW_OBJC_DIRECT;

/// Immediately stops the current animation at its current position.
/// @param didComplete The animation successfully completed so its completion handler should be called.
- (void)stopAnimationWithCompletion:(BOOL)didComplete TOPAGINGVIEW_OBJC_DIRECT;

/// Called when the paging mechanism has performed a transition and all of the pages
/// were offset by one page segment. We pass that segment delta here so the
/// animator can rebase its absolute content offset targets.
- (void)didTransitionWithOffset:(CGFloat)offset TOPAGINGVIEW_OBJC_DIRECT;

/// Called when we've detected we're in animation run and we're about to hit the outer boundary of pages.
/// This method modifies the current velocity so it gracefully decelerates to the boundary instead.
- (void)clampAnimationToOffset:(CGFloat)targetOffset TOPAGINGVIEW_OBJC_DIRECT;

/// Returns a pointer to the animator's live state struct. The pointer's lifetime matches the animator's.
/// Callers may cache it and read fields directly to avoid per-tick ObjC property accessors.
- (const TOPagingViewAnimatorState *)statePointer TOPAGINGVIEW_OBJC_DIRECT NS_RETURNS_INNER_POINTER;

@end

NS_ASSUME_NONNULL_END
