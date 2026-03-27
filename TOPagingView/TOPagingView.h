//
//  TOPagingView.h
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

#import <UIKit/UIView.h>

#import "TOPagingViewTypes.h"
#import "TOPagingViewPage.h"

NS_ASSUME_NONNULL_BEGIN

@class TOPagingView;
@class UIScrollView;
@protocol UIScrollViewDelegate;

/// Supplies page views to the paging view on demand as the user moves through the sequence.
/// Return configured page views relative to the current page, or `nil` to indicate
/// that the sequence ends in that direction.
NS_SWIFT_NAME(PagingViewDataSource)
@protocol TOPagingViewDataSource <NSObject>

@required

/// Called when the paging view is requesting a new page view in the current sequence in either direction.
/// Use this method to dequeue, or create a new page view that will be displayed in the paging view.
/// Return nil when there are no more pages available for the requested type relative to the supplied reference page.
/// In that case, the paging view will treat the supplied reference page as the end of the sequence in that direction
/// and settle the scroll view there.
/// @param pagingView The paging view requesting the new page view.
/// @param type The type of page to be displayed in its relation to the current page.
/// @param currentPageView The current page view on screen. Use this to determine which page should come before or after it.
/// This will be nil only on the very first load, before any pages have been displayed.
/// @return The newly dequeued and configured page. At any point, if it's determined that there are no more pages, return nil instead.
- (nullable __kindof UIView<TOPagingViewPage> *)pagingView:(TOPagingView *)pagingView
                                           pageViewForType:(TOPagingViewPageType)type
                                          currentPageView:(UIView<TOPagingViewPage> *_Nullable)currentPageView;

@end

/// Receives lifecycle events about page turns and page-direction changes.
/// Use this to preload content, update external state, or respond when a page turn commits.
NS_SWIFT_NAME(PagingViewDataDelegate)
@protocol TOPagingViewDelegate <NSObject>

@optional

/// Called when a transition has started moving in a direction (eg, the user has
/// started swiping in a direction, or an animation is about to start) that can potentially
/// end in a page transition. Use this to start preloading content in that direction.
/// @param pagingView The calling paging view instance.
/// @param type The type of page that was turned to, whether the next or previous one.
- (void)pagingView:(TOPagingView *)pagingView willTurnToPageOfType:(TOPagingViewPageType)type;

/// Called when a page turn has crossed the turning threshold and a new page has become the current one.
/// Use this to update any state around the paging view used to control the current page.
/// @param pagingView The calling paging view instance.
/// @param type The type of page that was turned to (This can include initial after a reload).
- (void)pagingView:(TOPagingView *)pagingView didTurnToPageOfType:(TOPagingViewPageType)type;

/// Called when adaptive page direction is enabled, and the user just swiped off the initial page in either
/// direction, effectively committing to a new page direction. Use this to update any UI or persist the new direction.
/// @param pagingView The calling paging view instance.
/// @param direction The new direction in which the pages are flowing.
- (void)pagingView:(TOPagingView *)pagingView didChangeToPageDirection:(TOPagingViewDirection)direction;

@end

/// A view that presents content as discrete horizontal scrolling pages.
/// The interface has been designed so any arbitrary number of pages may be
/// displayed without knowing the final number up front.
NS_SWIFT_NAME(PagingView)
@interface TOPagingView : UIView

/// The internal scroll view wrapped by this view that controls the scrolling content.
@property (nonatomic, strong, readonly) UIScrollView *scrollView;

/// The delegate for the internal scroll view. Use this property instead of setting
/// scrollView.delegate directly, as the paging view uses the delegate internally.
@property (nonatomic, weak, nullable) id<UIScrollViewDelegate> scrollViewDelegate;

/// The object responsible for creating and configuring page views for this paging view.
/// The pager consults this object whenever it needs the current page or an adjacent page.
@property (nonatomic, weak, nullable) id<TOPagingViewDataSource> dataSource;

/// The object notified as turns begin, commit, or when adaptive direction changes.
/// Use this for side effects and external state updates rather than for supplying page views.
@property (nonatomic, weak, nullable) id<TOPagingViewDelegate> delegate;

/// Width of the spacing between pages in points (default value of 40).
@property (nonatomic, assign) CGFloat pageSpacing;

/// The ascending layout direction of the page views in the scroll view.
@property (nonatomic, assign) TOPagingViewDirection pageScrollDirection;

/// Allows users to intuitively start scrolling in either direction,
/// with `pageScrollDirection` automatically updating to match.
@property (nonatomic, assign) BOOL isAdaptivePageDirectionEnabled;

/// The currently visible primary page view on screen.
@property (nonatomic, weak, readonly, nullable) UIView<TOPagingViewPage> *currentPageView;

/// The next page after the currently visible page on the screen.
@property (nonatomic, weak, readonly, nullable) UIView<TOPagingViewPage> *nextPageView;

/// The previous page before the currently visible page on the screen.
@property (nonatomic, weak, readonly, nullable) UIView<TOPagingViewPage> *previousPageView;

/// Registers a page view class that can be automatically instantiated as needed.
/// If the class overrides `pageIdentifier`, new instances may automatically be created
/// when needed. Any classes that do not override that property will become the default
/// page class.
- (void)registerPageViewClass:(Class)pageViewClass;

/// Reload the view from scratch, including tearing down and recreating all page views
- (void)reload;

/// Tears down and recreates just the previous and next page views from scratch, leaving the current one as-is.
- (void)reloadAdjacentPages;

/// Loads the previous and/or next page views only if they're not already loaded.
/// Useful for when the data source has updated with new page data.
- (void)fetchAdjacentPagesIfAvailable;

/// Returns a page view from the default queue of pages, ready for re-use.
- (nullable __kindof UIView<TOPagingViewPage> *)dequeueReusablePageView;

/// Returns a page view from the specific queue matching the provided identifier string.
/// - Parameter identifier: The identifier of the specific page type to be returned. Generates a new instance if no more spares in
/// the queue exist
- (nullable __kindof UIView<TOPagingViewPage> *)dequeueReusablePageViewForIdentifier:(nullable NSString *)identifier
    NS_SWIFT_NAME(dequeueReusablePageView(for:));

/// Returns all of the currently visible pages as an un-ordered set
- (nullable NSSet<__kindof UIView<TOPagingViewPage> *> *)visiblePageViews;

/// Returns the visible page view for the supplied unique identifier, or nil otherwise.
/// - Parameter identifier: The identifier of the specific page view to retrieve.
- (nullable __kindof UIView<TOPagingViewPage> *)pageViewForUniqueIdentifier:(NSString *)identifier
    NS_SWIFT_NAME(uniquePageView(for:));

/// Advance one page forward in ascending order (which will be left or right depending on direction)
/// - Parameter animated: Whether the transition is animated, or updates instantly
- (void)turnToNextPageAnimated:(BOOL)animated;

/// Advance one page backward in descending order (which will be left or right depending on direction)
/// - Parameter animated: Whether the transition is animated, or updates instantly
- (void)turnToPreviousPageAnimated:(BOOL)animated;

/// Advance one page to the left (Regardless of current scroll direction)
/// - Parameter animated: Whether the transition is animated, or updates instantly
- (void)turnToLeftPageAnimated:(BOOL)animated;

/// Advance one page to the right (Regardless of current scroll direction)
/// - Parameter animated: Whether the transition is animated, or updates instantly
- (void)turnToRightPageAnimated:(BOOL)animated;

/// Skips ahead to an arbitrary new page view.
/// The data source must be updated to the new state before calling this.
/// - Parameter animated: Whether the transition is animated, or updates instantly
- (void)skipForwardToNewPageAnimated:(BOOL)animated;

/// Skips backwards to an arbitrary new page view.
/// The data source must be updated to the new state before calling this.
/// - Parameter animated: Whether the transition is animated, or updates instantly
- (void)skipBackwardToNewPageAnimated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
