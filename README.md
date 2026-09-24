# TOPagingView

An Objective-C paging view for an arbitrary number of horizontal pages. Requires iOS 12 or later. Install with Swift Package Manager or CocoaPods (`pod 'TOPagingView'`). Open `TOPagingView.xcodeproj` to run the example and tests.

The pager keeps three active page slots: previous, current, and next. It rotates these slots as pages turn and keeps reusable page views in per-identifier pools. It does not need the total page count in advance.

## Setup

In a view controller implementing `TOPagingViewDataSource`, configure the pager before adding it to the view hierarchy:

```objc
TOPagingView *const pagingView = [[TOPagingView alloc] initWithFrame:self.view.bounds];
pagingView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
[pagingView registerPageViewClass:UILabel.class];
pagingView.dataSource = self;
[self.view addSubview:pagingView];
self.pagingView = pagingView;
```

The data source returns a configured view for the requested position. This example uses the page's `tag` as its index and assumes the controller owns `currentIndex` and `pageCount` properties:

```objc
- (nullable __kindof UIView<TOPagingViewPage> *)pagingView:(TOPagingView *)pagingView
                                        pageViewForType:(TOPagingViewPageType)type
                                       currentPageView:(nullable UIView<TOPagingViewPage> *)currentPageView {
    NSInteger index = self.currentIndex;
    if (type == TOPagingViewPageTypeNext) {
        index = currentPageView.tag + 1;
    } else if (type == TOPagingViewPageTypePrevious) {
        index = currentPageView.tag - 1;
    }

    if (index < 0 || index >= self.pageCount) {
        return nil;
    }

    UILabel *const page = [pagingView dequeueReusablePageView];
    page.tag = index;
    page.text = [NSString stringWithFormat:@"Page %ld", (long)index + 1];
    page.textAlignment = NSTextAlignmentCenter;
    return (UIView<TOPagingViewPage> *)page;
}
```

The reference page is nil for the initial current-page request, including every full `reload`. For adjacent requests, derive the result from the supplied reference page. If your data source instead uses a controller index, update it in `pagingView:didTurnToPageOfType:` before the next adjacent request.

## Turning and refreshing pages

`turnToNextPageAnimated:` and `turnToPreviousPageAnimated:` follow `pageScrollDirection`; left/right variants use physical screen edges. Each animated tap extends the destination and restarts one duration for the remaining journey. Missing adjacent pages produce a boundary bounce. `skipForwardToNewPageAnimated:` and its backward counterpart request a new current page after you update the data source's state.

Return nil when an adjacent page is unavailable, whether the book has ended or content has not loaded yet. When availability changes, call `fetchAdjacentPagesIfAvailable` on the main thread. To replace already loaded adjacent pages, use `reloadAdjacentPages`. A page arriving during an active bounce does not advance the book automatically; another turn request can use it.

Use the paging view and its data-source/delegate callbacks on the main thread. Keep page creation and configuration lightweight; fetch and decode expensive content outside these callbacks, then publish UI updates on the main thread.

## Reuse and callbacks

`TOPagingViewPage` is optional. Implement `+pageIdentifier` for separate reuse pools, `-uniqueIdentifier` for lookup of an active page, and `-prepareForReuse` to release old content before the pager recycles the view. Implemented identifier methods must return nonnil values. The class identifier must be stable, and an active page's unique identifier must stay unchanged until reclamation.

`pagingView:willTurnToPageOfType:` signals an attempted turn, not a guaranteed page change. `pagingView:didTurnToPageOfType:` reports a committed turn; initial layout and full reload also report the Current type. Adaptive page direction lets the initial page's next page appear on either side until the user commits to a reading direction.

To observe the underlying scroll view, assign `pagingView.scrollViewDelegate`. Keep `pagingView.scrollView.delegate` assigned to the internal proxy. Animated page turns notify `scrollViewDidEndScrollingAnimation:` on natural completion and on drag/resize interruption; reload/removal cancel without that notification.

## Implementation conventions

Internal helpers and actions use `_` prefixes. Framework overrides, protocol callbacks, property accessors, and public APIs retain their declared selectors. Immutable locals use `const` (including constant object pointers), and logical operations are separated by blank lines. C helpers and cached structs keep the scrolling path inexpensive.
