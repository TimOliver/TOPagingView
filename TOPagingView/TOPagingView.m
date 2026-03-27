//
//  TOPagingView.m
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

#import "TOPagingView.h"

#import <objc/runtime.h>

#import "TOPagingViewAnimator.h"
#import "TOPagingViewConstants.h"
#import "TOPagingViewMacros.h"
#import "TOPageViewProtocolCache.h"
#import "TOPagingViewTypes.h"
#import "TOPagingViewUtilities.h"
#import "TOScrollViewDelegateProxy.h"

@implementation TOPagingView {
    /// The scroll view managed by this container.
    UIScrollView *_scrollView;

    /// Dictionaries managing the pool of available pages and page classes.
    NSMutableDictionary<NSString *, NSMutableSet *> *_queuedPages;          // pageIdentifier - available reusable pages
    NSMutableDictionary<NSString *, UIView *> *_uniqueIdentifierPages;      // uniqueIdentifier - specific page on demand
    NSMutableDictionary<NSString *, NSValue *> *_registeredPageViewClasses;

    /// Struct to cache the protocol state of each type of page view class used in this session.
    /// Uses NSMapTable with pointer keys to avoid NSStringFromClass allocations on lookup.
    NSMapTable<Class, TOPageViewProtocolCache *> *_pageViewProtocolFlags;
    
    /// The views that are all currently in the scroll view, in specific order.
    UIView<TOPagingViewPage> * __weak _currentPageView;
    UIView<TOPagingViewPage> * __weak _nextPageView;
    UIView<TOPagingViewPage> * __weak _previousPageView;

    /// Flags tracking the current state of layout
    BOOL _disableLayout;     // Pause all layout logic temporarily for fine-grained modifications.
    BOOL _hasNextPage;       // Skip checking for an incoming next page once we've successfully dequeued one.
    BOOL _hasPreviousPage;   // Skip checking for an outgoing previous page once we've successfully dequeued one.
    BOOL _needsNextPage;     // Defers loading the next page until the next view layout pass to spread the work across run loops
    BOOL _needsPreviousPage; // Defers loading the previous page until the next view layout pass to spread the work across run loops

    /// Structs that cache long-lived state about the paging view
    TOPagingViewDelegateFlags _delegateFlags;        // Which methods the current delegate implements
    TOPagingViewLayoutMetrics _layoutMetrics;        // Layout metrics about the paging view that only change on frame change.
    TOPagingViewDraggingState _dragInteractionState; // Tracking the user's dragging behavior to detect when to alert of a sudden direction change
    
    /// Additional modularized components of the paging view
    TOPagingViewAnimator *_pageAnimator;                 // A real-time animator that plays an interruptible page-turning animation
    TOScrollViewDelegateProxy *_scrollViewDelegateProxy; // A proxy object that allows forwarding all UIScrollViewDelegate events to an external object
}

@synthesize scrollView = _scrollView;
@synthesize previousPageView = _previousPageView;
@synthesize currentPageView = _currentPageView;
@synthesize nextPageView = _nextPageView;

#pragma mark - Object Creation

- (instancetype)init {
    self = [super init];
    if (self) { [self _setUp]; }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) { [self _setUp]; }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) { [self _setUp]; }
    return self;
}

#pragma mark - Setup

- (void)_setUp TOPAGINGVIEW_OBJC_DIRECT {
    // Set default values
    _pageSpacing = 40.0f;
    _queuedPages = [NSMutableDictionary dictionary];
    _pageViewProtocolFlags = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsOpaqueMemory | NSPointerFunctionsOpaquePersonality
                                                   valueOptions:NSPointerFunctionsStrongMemory];
    memset(&_delegateFlags, 0, sizeof(TOPagingViewDelegateFlags));
    _dragInteractionState = TOPagingViewDraggingStateReset();

    // Configure the main properties of this view
    self.clipsToBounds = YES;  // The scroll view intentionally overlaps, so this view MUST clip.
    self.backgroundColor = [UIColor clearColor];

    // Create and configure the scroll view delegate proxy
    _scrollViewDelegateProxy = [[TOScrollViewDelegateProxy alloc] init];
    _scrollViewDelegateProxy.pagingView = self;

    // Create and configure the scroll view
    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    [self _updateCachedLayoutMetrics];
    [self _configureScrollView];
    [self addSubview:_scrollView];

    // Configure the page view animator
    _pageAnimator = [[TOPagingViewAnimator alloc] init];
    _pageAnimator.scrollView = _scrollView;
}

- (void)_configureScrollView TOPAGINGVIEW_OBJC_DIRECT {
    UIScrollView *const scrollView = _scrollView;
    scrollView.frame = _layoutMetrics.scrollViewFrame;
    scrollView.pagingEnabled = YES;
    scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.showsVerticalScrollIndicator = NO;

    // Set our delegate proxy as the scroll view's delegate.
    // The proxy forwards calls to an external delegate while also handling internal scroll tracking.
    scrollView.delegate = _scrollViewDelegateProxy;

    // Enable scrolling by clicking and dragging with the mouse
    // The only way to do this is via a private API. FB10593893 was filed to request this property is made public.
    if (@available(iOS 14.0, *)) {
        NSArray *const selectorComponents = @[@"_", @"set", @"SupportsPointerDragScrolling:"];
        SEL selector = NSSelectorFromString([selectorComponents componentsJoinedByString:@""]);
        if ([scrollView respondsToSelector:selector]) { [scrollView performSelector:selector withObject:@(YES) afterDelay:0]; }
    }
}

#pragma mark - View Lifecycle


- (void)layoutSubviews {
    [super layoutSubviews];
    [self layoutContent];
}

- (void)layoutContent TOPAGINGVIEW_OBJC_DIRECT {
    // Refresh the latest page and layout state
    [self _requestPendingPages];
    [self _updateCachedLayoutMetrics];

    // Skip performing a new layout pass if the scroll view size didn't actually change.
    UIScrollView *const scrollView = _scrollView;
    const CGRect newScrollViewFrame = _layoutMetrics.scrollViewFrame;
    if (CGSizeEqualToSize(_scrollView.frame.size, newScrollViewFrame.size)) { return; }
    
    // If we changed size mid-pageturn animation, reset back to the center
    BOOL wasAnimating = NO;
    if (_pageAnimator.isAnimating) {
        [_pageAnimator stopAnimationWithCompletion:YES];
        wasAnimating = YES;
    }
    
    // Disable the observer since this code will be tweaking all of the scroll view
    _disableLayout = YES;
    {
        // Capture the old content width and x offset so we can apply it to the new size
        const CGFloat oldContentWidth = scrollView.contentSize.width;
        const CGFloat oldOffsetMid = scrollView.contentOffset.x + (scrollView.frame.size.width * 0.5f);

        // Update the scroll view to the new size
        scrollView.frame = newScrollViewFrame;
        [self _updateContentSize];
        
        // Update the content offset to match the amount that the width changed
        // (Only do this if there actually was an old content width, otherwise we might get a NaN error)
        if (!wasAnimating && oldContentWidth > FLT_EPSILON) {
            const CGFloat newOffsetMid = oldOffsetMid * (scrollView.contentSize.width / oldContentWidth);
            const CGFloat contentOffset = newOffsetMid - (scrollView.frame.size.width * 0.5f);
            scrollView.contentOffset = (CGPoint){contentOffset, 0.0f};
        } else if (wasAnimating) {
            scrollView.contentOffset = (CGPoint){_layoutMetrics.pageWidth, 0.0f};
        }
    }
    _disableLayout = NO;

    // Layout the page subviews
    _nextPageView.frame = _layoutMetrics.nextPageFrame;
    _currentPageView.frame = _layoutMetrics.currentPageFrame;
    _previousPageView.frame = _layoutMetrics.previousPageFrame;
}

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    [self reload];
}

#pragma mark - Scroll View Management

- (void)_updateCachedLayoutMetrics TOPAGINGVIEW_OBJC_DIRECT {
    const CGRect bounds = self.bounds;
    const CGFloat halfPageSpacing = _pageSpacing * 0.5f;
    const CGFloat pageWidth = bounds.size.width + _pageSpacing;

    _layoutMetrics.halfPageSpacing = halfPageSpacing;
    _layoutMetrics.pageWidth = pageWidth;
    _layoutMetrics.scrollViewFrame = CGRectIntegral(CGRectInset(bounds, -halfPageSpacing, 0.0f));
    _layoutMetrics.leftPageFrame = CGRectOffset(bounds, halfPageSpacing, 0.0f);
    _layoutMetrics.rightPageFrame = CGRectOffset(bounds, (pageWidth * 2.0f) + halfPageSpacing, 0.0f);
    _layoutMetrics.currentPageFrame = CGRectMake(pageWidth + halfPageSpacing, bounds.origin.y, bounds.size.width, bounds.size.height);

    if (TOPagingViewIsDirectionReversed(_pageScrollDirection)) {
        _layoutMetrics.nextPageFrame = _layoutMetrics.leftPageFrame;
        _layoutMetrics.previousPageFrame = _layoutMetrics.rightPageFrame;
    } else {
        _layoutMetrics.nextPageFrame = _layoutMetrics.rightPageFrame;
        _layoutMetrics.previousPageFrame = _layoutMetrics.leftPageFrame;
    }
}

- (void)_updateContentSize TOPAGINGVIEW_OBJC_DIRECT {
    // With the three pages set, calculate the scrolling content size
    CGSize contentSize = self.bounds.size;
    contentSize.width = _layoutMetrics.pageWidth * kTOPagingViewPageSlotCount;
    _scrollView.contentSize = contentSize;
}

- (void)_resetContentOffset TOPAGINGVIEW_OBJC_DIRECT {
    if (_currentPageView == nil) { return; }

    // Reset the scroll view offset to the current page view
    CGPoint offset = CGPointZero;
    offset.x = CGRectGetMinX(_currentPageView.frame);
    offset.x -= (_pageSpacing * 0.5f);
    _scrollView.contentOffset = offset;
}

/// Called by the scroll view delegate proxy when the user begins dragging.
- (void)_scrollViewWillBeginDragging TOPAGINGVIEW_OBJC_DIRECT {
    if (_pageAnimator.isAnimating) {
        [_pageAnimator stopAnimationWithCompletion:YES];
    }
}

/// Perform a layout pass for the pages
- (void)_layoutPages TOPAGINGVIEW_OBJC_DIRECT {
    if (_disableLayout) { return; }
    TOPagingViewLayoutPages(self);
}

/// External hook for the scroll view proxy to forward scroll events to us
void TOPagingViewHandleScrollViewDidScroll(TOPagingView *pagingView) {
    [pagingView _layoutPages];
}

/// External hook for the scroll view proxy to forward scroll events to us
void TOPagingViewHandleScrollViewWillBeginDragging(TOPagingView *pagingView) {
    [pagingView _scrollViewWillBeginDragging];
}

#pragma mark - Page Setup

- (void)registerPageViewClass:(Class)pageViewClass {
    NSAssert([pageViewClass isSubclassOfClass:[UIView class]], @"Only UIView objects may be registered as pages.");

    // Cache the protocol methods this class implements to save checking each time
    TOPagingViewCachedProtocolFlagsForPageViewClass(self, pageViewClass);

    // Fetch the page identifier (or use the default if none were provided).
    const NSString *pageIdentifier = TOPagingViewIdentifierForPageViewClass(self, pageViewClass);

    // Lazily make the store for the first time
    if (_registeredPageViewClasses == nil) { _registeredPageViewClasses = [NSMutableDictionary dictionary]; }

    // Encode the class as an NSValue and store to the dictionary
    _registeredPageViewClasses[pageIdentifier] = TOPagingViewValueForClass(&pageViewClass);
}

- (__kindof UIView<TOPagingViewPage> *)dequeueReusablePageView {
    return [self dequeueReusablePageViewForIdentifier:nil];
}

- (__kindof UIView<TOPagingViewPage> *)dequeueReusablePageViewForIdentifier:(NSString *)identifier {
    if (identifier.length == 0) { identifier = kTOPagingViewDefaultIdentifier; }

    // Fetch the set for this page type, and lazily create if it doesn't exist
    NSMutableSet *enqueuedPages = _queuedPages[identifier];
    if (enqueuedPages == nil) {
        enqueuedPages = [NSMutableSet set];
        _queuedPages[identifier] = enqueuedPages;
    }

    // Attempt to fetch a previous page from it
    UIView<TOPagingViewPage> *pageView = enqueuedPages.anyObject;

    // If a page was found, set its bounds, and return it
    if (pageView) {
        if (!CGSizeEqualToSize(pageView.frame.size, self.bounds.size)) { pageView.frame = self.bounds; }
        return pageView;
    }

    // If we have a class for this one, create a new instance and return
    NSValue *pageClassValue = _registeredPageViewClasses[identifier];
    if (pageClassValue) {
        Class pageClass = TOPagingViewClassForValue(pageClassValue);
        pageView = [[pageClass alloc] initWithFrame:self.bounds];
        [enqueuedPages addObject:pageView];
        return pageView;
    }

    return nil;
}

static inline NSString *TOPagingViewIdentifierForPageViewClass(TOPagingView *view, Class pageViewClass) {
    // If the page class supports the pageIdentifier protocol, return it, otherwise use the default string
    TOPageViewProtocolFlags flags = TOPagingViewCachedProtocolFlagsForPageViewClass(view, pageViewClass);
    if (flags.protocolPageIdentifier) { return [pageViewClass pageIdentifier]; }
    return kTOPagingViewDefaultIdentifier;
}

static inline BOOL TOPagingViewIsInitialPageForPageView(TOPagingView *view, UIView<TOPagingViewPage> *pageView) {
    // Verify the protocol supports 'isInitialPage' and call it if it does
    if (pageView == nil) { return NO; }
    TOPageViewProtocolFlags flags = TOPagingViewCachedProtocolFlagsForPageViewClass(view, pageView.class);
    return flags.protocolIsInitialPage ? [pageView isInitialPage] : NO;
}

static inline void TOPagingViewSetPageDirectionForPageView(TOPagingView *view, TOPagingViewDirection direction, UIView<TOPagingViewPage> *pageView) {
    // Check the page view supports the page direction protocol and set it if it does
    if (pageView == nil) { return; }
    TOPageViewProtocolFlags flags = TOPagingViewCachedProtocolFlagsForPageViewClass(view, pageView.class);
    if (flags.protocolSetPageDirection) { [pageView setPageDirection:direction]; }
}

static inline TOPageViewProtocolFlags TOPagingViewCachedProtocolFlagsForPageViewClass(TOPagingView *view, Class class) {
    // Skip if we already captured the protocols from this class (pointer-based lookup, no allocation)
    TOPageViewProtocolCache *cache = [view->_pageViewProtocolFlags objectForKey:class];
    if (cache != nil) { return cache.flags; }

    // Create a new instance of the struct and prepare its memory
    TOPageViewProtocolFlags flags;
    memset(&flags, 0, sizeof(TOPageViewProtocolFlags));

    // Capture the protocol methods this class implements
    flags.protocolPageIdentifier = [class respondsToSelector:@selector(pageIdentifier)];
    flags.protocolUniqueIdentifier = [class instancesRespondToSelector:@selector(uniqueIdentifier)];
    flags.protocolPrepareForReuse = [class instancesRespondToSelector:@selector(prepareForReuse)];
    flags.protocolIsInitialPage = [class instancesRespondToSelector:@selector(isInitialPage)];
    flags.protocolSetPageDirection = [class instancesRespondToSelector:@selector(setPageDirection:)];

    // Store in the map table (pointer-based key, no allocation)
    cache = [TOPageViewProtocolCache new];
    cache.flags = flags;
    [view->_pageViewProtocolFlags setObject:cache forKey:class];

    // Return the flags
    return flags;
}

#pragma mark - External Page Control

- (void)reload {
    // Remove all currently visible pages from the scroll views
    for (UIView *view in _scrollView.subviews) {
        TOPagingViewReclaimPageView(self, view);
        [view removeFromSuperview];
    }

    // Reset all of the active page references
    _currentPageView = nil;
    _previousPageView = nil;
    _nextPageView = nil;

    // Clean out all of the pages in the queues
    [_queuedPages removeAllObjects];

    // Reset the content size of the scroll view content
    _disableLayout = YES;
    {
        _scrollView.contentSize = CGSizeZero;
    }
    _disableLayout = NO;

    // Perform a fresh layout
    [self _layoutPages];
}

- (void)reloadAdjacentPages {
    // Reclaim the previous and next pages
    TOPagingViewReclaimPageView(self, _nextPageView);     _nextPageView = nil;
    TOPagingViewReclaimPageView(self, _previousPageView); _previousPageView = nil;

    // Set the flags to yes to ensure the following flow isn't blocked
    _hasNextPage = YES;
    _hasPreviousPage = YES;

    // Fetch the next and previous pages
    [self _fetchNewNextPage];
    if (!_isAdaptivePageDirectionEnabled || !TOPagingViewIsInitialPageForPageView(self, _currentPageView)) {
        [self _fetchNewPreviousPage];
    } else {
        _hasPreviousPage = _hasNextPage;
    }
}

- (nullable UIView<TOPagingViewPage> *)_fetchAdjacentPageForType:(TOPagingViewPageType)pageType
                                                currentPageView:(nullable UIView<TOPagingViewPage> *)currentPageView
                                           clampAnimatorIfMissing:(BOOL)clampAnimatorIfMissing TOPAGINGVIEW_OBJC_DIRECT {
    // Fetch a new page from the data source
    UIView<TOPagingViewPage> *pageView = [_dataSource pagingView:self
                                                 pageViewForType:pageType
                                                currentPageView:currentPageView];
    
    // Set up our new page as the incoming 'next' page
    if (pageType == TOPagingViewPageTypeNext) {
        // If non-nil, insert into the scroll view
        if (pageView) {
            TOPagingViewInsertPageView(self, pageView);
            _nextPageView = pageView;
            _nextPageView.frame = _layoutMetrics.nextPageFrame;
        } else if (clampAnimatorIfMissing) {
            // If 'next' was nil while we were animating, cancel the animation
            [_pageAnimator clampAnimationToOffset:_layoutMetrics.pageWidth];
        }
        _hasNextPage = (pageView != nil);
        return pageView;
    }

    // Set up our new page as the incoming 'previous' page
    if (pageType == TOPagingViewPageTypePrevious) {
        // If non-nil, insert into the scroll view
        if (pageView) {
            TOPagingViewInsertPageView(self, pageView);
            _previousPageView = pageView;
            _previousPageView.frame = _layoutMetrics.previousPageFrame;
        } else if (clampAnimatorIfMissing) {
            [_pageAnimator clampAnimationToOffset:_layoutMetrics.pageWidth];
        }
        _hasPreviousPage = (pageView != nil);
        return pageView;
    }
    
    return nil;
}

- (void)fetchAdjacentPagesIfAvailable {
    if (_dataSource == nil) { return; }

    // If there currently isn't a previous page, check again to see if there is one now.
    if (!_hasPreviousPage) {
        [self _fetchAdjacentPageForType:TOPagingViewPageTypePrevious currentPageView:_currentPageView clampAnimatorIfMissing:NO];
    }

    // If there currently isn't a next page, check again
    if (!_hasNextPage) {
        [self _fetchAdjacentPageForType:TOPagingViewPageTypeNext currentPageView:_currentPageView clampAnimatorIfMissing:NO];
    }

    // If we're on the initial page, set the previous page state to match whatever the next state is
    if (_isAdaptivePageDirectionEnabled && TOPagingViewIsInitialPageForPageView(self, _currentPageView)) {
        _hasPreviousPage = _hasNextPage;
    }

    // Perform a layout pass to ensure the new pages are correctly positioned
    [self _layoutPages];
}

- (void)turnToNextPageAnimated:(BOOL)animated {
    // Map what 'next' means towards the current ascending direction
    if (TOPagingViewIsDirectionReversed(_pageScrollDirection)) {
        [self turnToLeftPageAnimated:animated];
    } else {
        [self turnToRightPageAnimated:animated];
    }
}

- (void)turnToPreviousPageAnimated:(BOOL)animated {
    // Map what 'previous' means towards the current descending direction
    if (TOPagingViewIsDirectionReversed(_pageScrollDirection)) {
        [self turnToRightPageAnimated:animated];
    } else {
        [self turnToLeftPageAnimated:animated];
    }
}

- (void)turnToLeftPageAnimated:(BOOL)animated {
    const CGFloat offset = _scrollView.contentOffset.x;
    const CGFloat pageWidth = _layoutMetrics.pageWidth;
    const BOOL isAnimating = _pageAnimator.isAnimating;
    const BOOL isAnimatingLeft = isAnimating && _pageAnimator.direction == UIRectEdgeLeft;
    const BOOL isDirectionReversed = TOPagingViewIsDirectionReversed(_pageScrollDirection);
    const BOOL hasLeftPage = (isDirectionReversed && _hasNextPage) || (!isDirectionReversed && _hasPreviousPage);

    // Play a bouncy animation if there's no page available on that side and
    // the scroll view isn't already settling from a user-driven swipe.
    if (!hasLeftPage && (offset <= pageWidth + FLT_EPSILON || isAnimatingLeft)) {
        if (!animated || isAnimating) { return; }
        [self _playBounceAnimationInDirection:UIRectEdgeLeft];
        return;
    }

    // Turn to the left side page
    [self _turnToPageInDirection:UIRectEdgeLeft animated:animated];
}

- (void)turnToRightPageAnimated:(BOOL)animated {
    const CGFloat offset = _scrollView.contentOffset.x;
    const CGFloat pageWidth = _layoutMetrics.pageWidth;
    const BOOL isAnimating = _pageAnimator.isAnimating;
    const BOOL isAnimatingRight = isAnimating && _pageAnimator.direction == UIRectEdgeRight;
    const BOOL isDirectionReversed = TOPagingViewIsDirectionReversed(_pageScrollDirection);
    const BOOL hasRightPage = (isDirectionReversed && _hasPreviousPage) || (!isDirectionReversed && _hasNextPage);

    // If we're partially at the last page and animating in, skip turning again to let it bottom out.
    // Otherwise, we've hit the edge, so play a 'bounce' visual cue to make it clear there's no more pages.
    if (!hasRightPage && (offset >= pageWidth - FLT_EPSILON || isAnimatingRight)) {
        if (!animated || isAnimating) { return; }
        [self _playBounceAnimationInDirection:UIRectEdgeRight];
        return;
    }

    [self _turnToPageInDirection:UIRectEdgeRight animated:animated];
}

- (void)skipForwardToNewPageAnimated:(BOOL)animated {
    UIRectEdge direction = TOPagingViewIsDirectionReversed(_pageScrollDirection) ? UIRectEdgeLeft : UIRectEdgeRight;
    [self _skipToNewPageInDirection:direction animated:animated];
}

- (void)skipBackwardToNewPageAnimated:(BOOL)animated {
    UIRectEdge direction = TOPagingViewIsDirectionReversed(_pageScrollDirection) ? UIRectEdgeRight : UIRectEdgeLeft;
    [self _skipToNewPageInDirection:direction animated:animated];
}

#pragma mark - Page Layout & Management

static inline void TOPagingViewLayoutPages(TOPagingView *view) {
    // Only perform this overhead when we are in the appropriate state,
    // and we're not being disabled by an active animation.
    if (view->_dataSource == nil || view->_disableLayout) { return; }

    const CGSize contentSize = view->_scrollView.contentSize;

    // On first run, set up the initial pages layout
    if (view->_currentPageView == nil || contentSize.width < FLT_EPSILON) {
        TOPagingViewPerformInitialLayout(view);
        return;
    }

    const TOPagingViewScrollMetrics metrics = {
        .offsetX = view->_scrollView.contentOffset.x,
        .segmentWidth = view->_layoutMetrics.pageWidth,
        .contentWidth = contentSize.width,
        .isReversed = TOPagingViewIsDirectionReversed(view->_pageScrollDirection),
    };

    // When adaptive paging is enabled, we swap the on-screen 'next' page to either
    // side of the initial page as the user swipes left and right
    if (view->_isAdaptivePageDirectionEnabled && TOPagingViewIsInitialPageForPageView(view, view->_currentPageView)) {
        TOPagingViewHandleAdaptivePageDirectionLayout(view, metrics);
    }

    // Check the offset of the scroll view, and when it passes over
    // the mid point between two pages, perform the page transition
    TOPagingViewHandlePageTransitions(view, metrics);

    // Observe user interaction for triggering certain delegate callbacks
    TOPagingViewUpdateDragInteractions(view, metrics);

    // When the page offset crosses either the left or right threshold,
    // check if a page is ready or not and enable insetting at that point to
    // avoid any hitchy motion
    TOPagingViewUpdateEnabledPages(view, metrics);
}

static inline void TOPagingViewPerformInitialLayout(TOPagingView *view) {
    // Set these back to true for now, since we'll perform the check in here
    view->_hasNextPage = YES;
    view->_hasPreviousPage = YES;

    // Send a delegate event stating we're about to transition to the initial page
    if (view->_delegateFlags.delegateWillTurnToPage) {
        [view->_delegate pagingView:view willTurnToPageOfType:TOPagingViewPageTypeCurrent];
    }

    // Add the initial page
    UIView<TOPagingViewPage> *pageView = [view->_dataSource pagingView:view
                                                       pageViewForType:TOPagingViewPageTypeCurrent
                                                     currentPageView:nil];
    if (pageView == nil) { return; }
    view->_currentPageView = pageView;
    TOPagingViewInsertPageView(view, pageView);
    view->_currentPageView.frame = view->_layoutMetrics.currentPageFrame;
    
    // Fetch next and previous pages. If we're on the initial page when adaptive direction is enabled, skip previous for now.
    [view _fetchNewNextPage];
    if (!view->_isAdaptivePageDirectionEnabled || !TOPagingViewIsInitialPageForPageView(view, view->_currentPageView)) {
        [view _fetchNewPreviousPage];
    } else {
        view->_hasPreviousPage = view->_hasNextPage;
    }

    // Update the initial content size and rest position
    view->_disableLayout = YES;
    {
        [view _updateContentSize];
        [view _resetContentOffset];
    }
    view->_disableLayout = NO;

    // Send a delegate event stating we've completed transitioning to the initial page
    if (view->_delegateFlags.delegateDidTurnToPage) {
        [view->_delegate pagingView:view didTurnToPageOfType:TOPagingViewPageTypeCurrent];
    }
}

static inline void TOPagingViewHandleAdaptivePageDirectionLayout(TOPagingView *view, TOPagingViewScrollMetrics metrics) {
    UIView<TOPagingViewPage> * const nextPage = view->_nextPageView;
    const CGFloat xPosition = CGRectGetMinX(view->_nextPageView.frame);
    const CGFloat offsetX = metrics.offsetX;
    const CGFloat segmentWidth = metrics.segmentWidth;

    // Check when the page starts moving in a certain direction and update the 'next' page to match if it hasn't already been updated.
    if (offsetX < segmentWidth - FLT_EPSILON && xPosition > segmentWidth) {
        TOPagingViewSetPageDirectionForPageView(view, TOPagingViewDirectionRightToLeft, view->_nextPageView);
        nextPage.frame = view->_layoutMetrics.leftPageFrame;
    } else if (offsetX > segmentWidth + FLT_EPSILON && xPosition < segmentWidth) {
        TOPagingViewSetPageDirectionForPageView(view, TOPagingViewDirectionLeftToRight, view->_nextPageView);
        nextPage.frame = view->_layoutMetrics.rightPageFrame;
    }

    // If we've sufficiently committed to this direction, update the hosting paging view's direction
    BOOL needsDelegateUpdate = NO;
    if (offsetX <= FLT_EPSILON && view->_pageScrollDirection == TOPagingViewDirectionLeftToRight) {
        // Scrolled all the way to the left
        view->_pageScrollDirection = TOPagingViewDirectionRightToLeft;
        needsDelegateUpdate = YES;
    } else if (offsetX >= (segmentWidth * 2.0f) - FLT_EPSILON && view->_pageScrollDirection == TOPagingViewDirectionRightToLeft) {
        // Scrolled all the way to the right
        view->_pageScrollDirection = TOPagingViewDirectionLeftToRight;
        needsDelegateUpdate = YES;
    }

    // Inform the delegate we committed to a page direction change
    if (needsDelegateUpdate && view->_delegateFlags.delegateDidChangeToPageDirection) {
        [view->_delegate pagingView:view didChangeToPageDirection:view->_pageScrollDirection];
    }

    // Refresh the layout metrics just in case any layout state changed from this
    if (needsDelegateUpdate) { [view _updateCachedLayoutMetrics]; }
}

static inline void TOPagingViewHandlePageTransitions(TOPagingView *view, TOPagingViewScrollMetrics metrics) {
    const UIRectEdge direction = view->_pageAnimator.direction;
    const BOOL isAnimating = view->_pageAnimator.isAnimating;
    const BOOL isAnimatingRight = isAnimating && direction == UIRectEdgeRight;
    const BOOL isAnimatingLeft = isAnimating && direction == UIRectEdgeLeft;

    // By default, we only perform transitions when a new page has fully landed on screen.
    // This defers heavier layout work until there is no visible motion.
    //
    // When the page animator is active, transition as soon as movement commits away from
    // the middle slot so the internal page bookkeeping stays ahead of rapid animation.
    const CGFloat rightHandThreshold = isAnimatingRight ? metrics.segmentWidth + 1.0f : metrics.contentWidth - metrics.segmentWidth;
    const CGFloat leftHandThreshold = isAnimatingLeft ? metrics.segmentWidth - 1.0f : FLT_EPSILON;

    // Check if we went over the right-hand threshold to start transitioning the pages
    if ((!metrics.isReversed && metrics.offsetX >= rightHandThreshold) ||
        (metrics.isReversed && metrics.offsetX <= leftHandThreshold)) {
        TOPagingViewTransitionOverToNextPage(view);
    } else if ((metrics.isReversed && metrics.offsetX >= rightHandThreshold) ||
               (!metrics.isReversed && metrics.offsetX <= leftHandThreshold)) {
        // Check if we're over the left threshold
        TOPagingViewTransitionOverToPreviousPage(view);
    }
}

static inline void TOPagingViewUpdateDragInteractions(TOPagingView *view, TOPagingViewScrollMetrics metrics) {
    // Exit out if we don't actually use the delegate
    if (view->_delegateFlags.delegateWillTurnToPage == NO) { return; }

    // If we're not being dragged, reset the state
    if (view->_scrollView.isTracking == NO) {
        view->_dragInteractionState = TOPagingViewDraggingStateReset();
        return;
    }

    // If we just started dragging, capture the current offset and exit
    if (view->_dragInteractionState.origin <= -CGFLOAT_MAX + FLT_EPSILON) {
        view->_dragInteractionState.origin = metrics.offsetX;
        return;
    }

    // Check the direction of the next step
    const BOOL isDetectingDirection = (view->_isAdaptivePageDirectionEnabled &&
                                       TOPagingViewIsInitialPageForPageView(view, view->_currentPageView));

    // If we're detecting the direction, it will be 'next' regardless.
    TOPagingViewPageType directionType;
    if (isDetectingDirection) {
        directionType = TOPagingViewPageTypeNext;
    } else if (metrics.offsetX < view->_dragInteractionState.origin - FLT_EPSILON) {  // We dragged to the right
        directionType = metrics.isReversed ? TOPagingViewPageTypeNext : TOPagingViewPageTypePrevious;
    } else if (metrics.offsetX > view->_dragInteractionState.origin + FLT_EPSILON) {  // We dragged to the left
        directionType = metrics.isReversed ? TOPagingViewPageTypePrevious : TOPagingViewPageTypeNext;
    } else {
        return;
    }

    // If this is a new direction than before, inform the delegate, and then save to avoid repeating
    if (directionType != view->_dragInteractionState.directionType) {
        [view->_delegate pagingView:view willTurnToPageOfType:directionType];
        view->_dragInteractionState.directionType = directionType;
    }

    // Update with the new offset
    view->_dragInteractionState.origin = metrics.offsetX;
}

static inline void TOPagingViewUpdateEnabledPages(TOPagingView *view, TOPagingViewScrollMetrics metrics) {
    // Check the offset and disable the adjacent slot if we've gone over the threshold.
    BOOL isEnabled = NO;
    UIRectEdge edge = UIRectEdgeNone;
    if (metrics.offsetX < metrics.segmentWidth) {  // Check the left page slot
        isEnabled = metrics.isReversed ? view->_hasNextPage : view->_hasPreviousPage;
        edge = UIRectEdgeLeft;
    } else if (metrics.offsetX > metrics.segmentWidth) {  // Check the right slot
        isEnabled = metrics.isReversed ? view->_hasPreviousPage : view->_hasNextPage;
        edge = UIRectEdgeRight;
    }

    // If we matched an edge, update its state.
    if (edge == UIRectEdgeNone) { return; }
    TOPagingViewSetPageSlotEnabled(view, isEnabled, edge, metrics.segmentWidth);
}

static inline void TOPagingViewSetPageSlotEnabled(TOPagingView *view, BOOL enabled, UIRectEdge edge, CGFloat segmentWidth) {
    UIEdgeInsets insets = view->_scrollView.contentInset;

    // Exit out if we don't need to set the state already
    const BOOL isLeft = (edge == UIRectEdgeLeft);
    const CGFloat inset = isLeft ? insets.left : insets.right;
    if (enabled && inset == segmentWidth) {
        return;
    } else if (!enabled && inset == -segmentWidth) {
        return;
    }

    // When the slot is enabled, expand the scrollable region by an extra slot
    // so it won't bump against the edge of the scroll region when scrolling rapidly.
    // Otherwise, inset it a whole slot to disable it completely.
    const CGFloat value = enabled ? segmentWidth : -segmentWidth;
    const CGPoint contentOffset = view->_scrollView.contentOffset;
    if (isLeft) {
        insets.left = value;
    } else {
        insets.right = value;
    }

    // Set the inset and then restore the offset
    view->_disableLayout = YES;
    {
        view->_scrollView.contentInset = insets;
        view->_scrollView.contentOffset = contentOffset;
    }
    view->_disableLayout = NO;
}

#pragma mark - Animated Transitions

- (void)_turnToPageInDirection:(UIRectEdge)direction animated:(BOOL)animated TOPAGINGVIEW_OBJC_DIRECT {
    const BOOL isLeftDirection = (direction == UIRectEdgeLeft);
    const BOOL isDirectionReversed = TOPagingViewIsDirectionReversed(_pageScrollDirection);
    const BOOL isDetectingDirection = _isAdaptivePageDirectionEnabled && TOPagingViewIsInitialPageForPageView(self, _currentPageView);
    const BOOL isPreviousPage = !isDetectingDirection && ((!isDirectionReversed && isLeftDirection) || (isDirectionReversed && !isLeftDirection));

    // Fire the willTurn delegate for each requested animated turn.
    const TOPagingViewPageType type = (isPreviousPage ? TOPagingViewPageTypePrevious : TOPagingViewPageTypeNext);
    if (_delegateFlags.delegateWillTurnToPage) { [_delegate pagingView:self willTurnToPageOfType:type]; }

    UIScrollView *const scrollView = _scrollView;
    
    // If we're not animating, set the offset to the target directly
    if (animated == NO) {
        CGFloat targetOffset = 0.0f;
        if (direction == UIRectEdgeRight) { targetOffset = scrollView.contentSize.width - _layoutMetrics.pageWidth; }
        scrollView.contentOffset = (CGPoint){targetOffset, 0.0f};
        return;
    }

    // If the scroll view is decelerating from a swipe, cancel it.
    if (scrollView.isDecelerating) { [scrollView setContentOffset:scrollView.contentOffset animated:NO]; }

    // Set up the completion handler to notify the external scroll view delegate
    __weak __typeof(self) weakSelf = self;
    _pageAnimator.completionHandler = ^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) { return; }
        id<UIScrollViewDelegate> scrollViewDelegate = strongSelf->_scrollViewDelegateProxy.externalDelegate;
        if ([scrollViewDelegate respondsToSelector:@selector(scrollViewDidEndScrollingAnimation:)]) {
            [scrollViewDelegate scrollViewDidEndScrollingAnimation:strongSelf->_scrollView];
        }
    };

    // Animate the page turn via CADisplayLink by directly driving the scroll view content offset.
    _pageAnimator.pageWidth = _layoutMetrics.pageWidth;
    [_pageAnimator turnToPageInDirection:direction];
}

- (void)_skipToNewPageInDirection:(UIRectEdge)direction animated:(BOOL)animated TOPAGINGVIEW_OBJC_DIRECT {
    // Stop any ongoing animations
    [_pageAnimator stopAnimationWithCompletion:NO];

    // Disable the layout since we'll handle everything beyond this point
    _disableLayout = YES;

    // If the scroll view is decelerating from a swipe, cancel it.
    if (_scrollView.isDecelerating) {
        [_scrollView setContentOffset:_scrollView.contentOffset animated:NO];
    }

    // Reclaim the next and previous pages since these will always need to be regenerated
    TOPagingViewReclaimPageView(self, _nextPageView);
    TOPagingViewReclaimPageView(self, _previousPageView);

    // Request the new page view that will become the new current page after this completes
    UIView<TOPagingViewPage> *newPageView = [_dataSource pagingView:self
                                                    pageViewForType:TOPagingViewPageTypeCurrent
                                                  currentPageView:_currentPageView];

    // Zero out the adjacent pages and set the
    // next/previous flags to ensure we'll query for new pages
    _nextPageView = nil; _hasNextPage = NO;
    _previousPageView = nil; _hasPreviousPage = NO;

    // If we're not animating, we can rearrange everything statically and cancel out here
    if (!animated) {
        // Reclaim the current page and instantly swap to the new one.
        TOPagingViewReclaimPageView(self, _currentPageView);
        _currentPageView = newPageView;
        _currentPageView.frame = _layoutMetrics.currentPageFrame;
        TOPagingViewInsertPageView(self, _currentPageView);

        // Re-enable layout and then trigger a pass to set up the adjacent pages
        _disableLayout = NO;
        _scrollView.contentOffset = (CGPoint){_layoutMetrics.pageWidth, 0.0f};
        [self fetchAdjacentPagesIfAvailable];

        return;
    }

    // Set the scroll view offset to either side slot, depending on direction, so we can animate to current page in the center
    _scrollView.contentOffset = (direction == UIRectEdgeLeft) ? (CGPoint){_layoutMetrics.pageWidth * 2.0f, 0.0f} : CGPointZero;
    _currentPageView.frame = (direction == UIRectEdgeLeft) ? _layoutMetrics.rightPageFrame : _layoutMetrics.leftPageFrame;
    _previousPageView = _currentPageView;

    // Put the new view in the center point and promote it to new current
    _currentPageView = newPageView;
    _currentPageView.frame = _layoutMetrics.currentPageFrame;
    TOPagingViewInsertPageView(self, _currentPageView);

    // Set up the completion handler
    __weak __typeof(self) weakSelf = self;
    void (^completionBlock)(BOOL) = ^(BOOL finished) {
        __strong __typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { return; }

        // Remove the previous page, now that we're done with it
        TOPagingViewReclaimPageView(strongSelf, strongSelf->_previousPageView);
        strongSelf->_previousPageView = nil;
        
        // Re-enable layout and refresh adjacent pages
        strongSelf->_disableLayout = NO;
        [strongSelf fetchAdjacentPagesIfAvailable];

        // If the scroll view delegate was set, tell it the animation completed
        id<UIScrollViewDelegate> scrollViewDelegate = strongSelf->_scrollViewDelegateProxy.externalDelegate;
        if ([scrollViewDelegate respondsToSelector:@selector(scrollViewDidEndScrollingAnimation:)]) {
            [scrollViewDelegate scrollViewDidEndScrollingAnimation:strongSelf->_scrollView];
        }
    };

    // Animate the scroll view back to the center slot with a standard view animation.
    const CGPoint centerOffset = (CGPoint){_layoutMetrics.pageWidth, 0.0f};
    [UIView animateWithDuration:_pageAnimator.duration
                          delay:0.0f
                        options:kTOPagingViewAnimationOptions
                     animations:^{ [self->_scrollView setContentOffset:centerOffset animated:NO]; }
                     completion:completionBlock];
}

- (nullable __kindof UIView *)pageViewForUniqueIdentifier:(NSString *)identifier {
    return _uniqueIdentifierPages[identifier];
}

#pragma mark - Page View Recycling

static void TOPagingViewInsertPageView(TOPagingView *view, UIView<TOPagingViewPage> *pageView) {
    if (pageView == nil) { return; }

    // Add the view to the scroll view
    if (pageView.superview == nil) { [view->_scrollView addSubview:pageView]; }
    pageView.hidden = NO;

    // Cache the page's protocol methods if it hasn't been done yet
    TOPageViewProtocolFlags flags = TOPagingViewCachedProtocolFlagsForPageViewClass(view, pageView.class);

    // If it implements the unique identifier protocol, capture the identifier and store it in our dictionary
    if (flags.protocolUniqueIdentifier) {
        NSString *uniqueIdentifier = [(id)pageView uniqueIdentifier];
        if (view->_uniqueIdentifierPages == nil) { view->_uniqueIdentifierPages = [NSMutableDictionary dictionary]; }
        view->_uniqueIdentifierPages[uniqueIdentifier] = pageView;
    }

    // If the page view supports it, inform the delegate of the current page direction
    if (flags.protocolSetPageDirection) { [pageView setPageDirection:view->_pageScrollDirection]; }

    // Remove it from the pool of recycled pages
    NSString *pageIdentifier = TOPagingViewIdentifierForPageViewClass(view, pageView.class);
    [view->_queuedPages[pageIdentifier] removeObject:pageView];
}

static void TOPagingViewReclaimPageView(TOPagingView *view, UIView *pageView) {
    if (pageView == nil) { return; }

    // Skip internal UIScrollView views (use class_getName to avoid NSString allocation)
    if (class_getName([pageView class])[0] == '_') { return; }

    // Fetch the protocol flags for this class and make any appropriate calls now
    TOPageViewProtocolFlags flags = TOPagingViewCachedProtocolFlagsForPageViewClass(view, pageView.class);
    if (flags.protocolUniqueIdentifier) { [view->_uniqueIdentifierPages removeObjectForKey:[(id)pageView uniqueIdentifier]]; }
    if (flags.protocolPrepareForReuse) { [(id)pageView prepareForReuse]; }

    // Hide the view and remove from the superview. (This might become a performance bottleneck down the line)
    pageView.hidden = YES;
    [pageView removeFromSuperview];

    // Re-add it to the recycled pages pool
    NSString *pageIdentifier = TOPagingViewIdentifierForPageViewClass(view, pageView.class);
    [view->_queuedPages[pageIdentifier] addObject:pageView];
}

#pragma mark - Page Transitions

static inline void TOPagingViewTransitionOverToNextPage(TOPagingView *view) {
    // If there's no next page, exit out now, to avoid calling this on each frame tick
    if (!view->_hasNextPage) { return; }
    
    // If we didn't have a previous page before, we will after this transaction
    if (!view->_hasPreviousPage) { view->_hasPreviousPage = YES; }

    view->_disableLayout = YES;
    {
        // Reclaim the previous view
        TOPagingViewReclaimPageView(view, view->_previousPageView);
        
        // Update all of the references by pushing each view back
        view->_previousPageView = view->_currentPageView;
        view->_currentPageView = view->_nextPageView;
        view->_nextPageView = nil;
        
        // Update the frames of the pages
        view->_currentPageView.frame = view->_layoutMetrics.currentPageFrame;
        view->_previousPageView.frame = view->_layoutMetrics.previousPageFrame;
        
        // Inform the delegate we have committed to a transition so we can update state for the next page.
        if (view->_delegateFlags.delegateDidTurnToPage) {
            [view->_delegate pagingView:view didTurnToPageOfType:TOPagingViewPageTypeNext];
        }
        
        // Offload the heavy work to a new run-loop cycle so we don't overload the current one.
        view->_needsNextPage = YES;
        [view setNeedsLayout];
        
        // Move the scroll view back one segment
        const BOOL isDirectionReversed = (view->_pageScrollDirection == TOPagingViewDirectionRightToLeft);
        const CGFloat previousOffsetX = view->_scrollView.contentOffset.x;
        const CGFloat scrollViewPageWidth = view->_layoutMetrics.pageWidth;
        const CGFloat offset = scrollViewPageWidth * (isDirectionReversed ? 1.0f : -1.0f);
        CGPoint contentOffset = view->_scrollView.contentOffset;
        contentOffset.x += offset;
        view->_scrollView.contentOffset = contentOffset;
        [view->_pageAnimator didTransitionWithOffset:(contentOffset.x - previousOffsetX)];
        
        // If we're dragging, reset the state
        if (view->_scrollView.isDragging) { view->_dragInteractionState.origin = -CGFLOAT_MAX; }
    }
    view->_disableLayout = NO;
}

static inline void TOPagingViewTransitionOverToPreviousPage(TOPagingView *view) {
    // If there's no previous page, exit out now, to avoid calling this on each frame tick
    if (!view->_hasPreviousPage) { return; }
    
    // If we didn't have a next page before, we will after this transaction
    if (!view->_hasNextPage) { view->_hasNextPage = YES; }
    
    view->_disableLayout = YES;
    {
        // Reclaim the next view
        TOPagingViewReclaimPageView(view, view->_nextPageView);
        
        // Update all of the references by pushing each view forward
        view->_nextPageView = view->_currentPageView;
        view->_currentPageView = view->_previousPageView;
        view->_previousPageView = nil;
        
        // Update the frames of the pages
        view->_currentPageView.frame = view->_layoutMetrics.currentPageFrame;
        view->_nextPageView.frame = view->_layoutMetrics.nextPageFrame;
        
        // Inform the delegate we have just committed to a transition so we can update state for the previous page.
        if (view->_delegateFlags.delegateDidTurnToPage) {
            [view->_delegate pagingView:view didTurnToPageOfType:TOPagingViewPageTypePrevious];
        }
        
        // Offload the heavy work to a new run-loop cycle so we don't overload the current one.
        view->_needsPreviousPage = YES;
        [view setNeedsLayout];
        
        // Move the scroll view forward one segment
        const BOOL isDirectionReversed = (view->_pageScrollDirection == TOPagingViewDirectionRightToLeft);
        const CGFloat previousOffsetX = view->_scrollView.contentOffset.x;
        const CGFloat scrollViewPageWidth = view->_layoutMetrics.pageWidth;
        const CGFloat offset = scrollViewPageWidth * (isDirectionReversed ? -1.0f : 1.0f);
        CGPoint contentOffset = view->_scrollView.contentOffset;
        contentOffset.x += offset;
        view->_scrollView.contentOffset = contentOffset;
        [view->_pageAnimator didTransitionWithOffset:(contentOffset.x - previousOffsetX)];
        
        // If we're dragging, reset the state
        if (view->_scrollView.isDragging) { view->_dragInteractionState.origin = -CGFLOAT_MAX; }
    }
    view->_disableLayout = NO;
}

- (void)_fetchNewNextPage TOPAGINGVIEW_OBJC_DIRECT {
    [self _fetchAdjacentPageForType:TOPagingViewPageTypeNext currentPageView:_currentPageView clampAnimatorIfMissing:YES];
}

- (void)_fetchNewPreviousPage TOPAGINGVIEW_OBJC_DIRECT {
    [self _fetchAdjacentPageForType:TOPagingViewPageTypePrevious currentPageView:_currentPageView clampAnimatorIfMissing:YES];
}

- (void)_rearrangePagesForScrollDirection:(TOPagingViewDirection)direction TOPAGINGVIEW_OBJC_DIRECT {
    const BOOL leftDirection = (direction == TOPagingViewDirectionRightToLeft);
    const CGFloat segmentWidth = _layoutMetrics.pageWidth;
    const CGFloat contentWidth = _scrollView.contentSize.width;
    const CGFloat halfSpacing = self.pageSpacing * 0.5f;
    const CGFloat rightOffset = (contentWidth - segmentWidth) + halfSpacing;

    // Move the next page to the left if direction is left, or vice versa
    if (_nextPageView) {
        CGRect frame = _nextPageView.frame;
        frame.origin.x = leftDirection ? halfSpacing : rightOffset;
        _nextPageView.frame = frame;
    }

    // Move the previous page to the right if direction is left, or vice versa
    if (_previousPageView) {
        CGRect frame = _previousPageView.frame;
        frame.origin.x = leftDirection ? rightOffset : halfSpacing;
        _previousPageView.frame = frame;
    }

    // Inform all of the pages that the direction changed, so they can re-arrange their subviews as needed
    TOPagingViewSetPageDirectionForPageView(self, direction, _currentPageView);
    TOPagingViewSetPageDirectionForPageView(self, direction, _nextPageView);
    TOPagingViewSetPageDirectionForPageView(self, direction, _previousPageView);

    // Flip the content insets if we were potentially at the end of the scroll view
    UIEdgeInsets insets = _scrollView.contentInset;
    CGFloat leftInset = insets.left;
    insets.left = insets.right;
    insets.right = leftInset;
    _disableLayout = YES;
    _scrollView.contentInset = insets;
    _disableLayout = NO;
}

- (void)_requestPendingPages TOPAGINGVIEW_OBJC_DIRECT {
    // Don't continue if neither pages are pending
    if (!_needsNextPage && !_needsPreviousPage) { return; }

    // Request a new next page if we're still pending
    if (_needsNextPage) {
        // Re-position the next page if we already have one, or otherwise fetch a new one
        _nextPageView != nil ? TOPagingViewInsertPageView(self, _nextPageView) : [self _fetchNewNextPage];
        _needsNextPage = NO;

        // If we also still need to fetch a previous page, defer that to the next layout pass
        if (_needsPreviousPage) {
            [self setNeedsLayout];
            return;
        }
    }

    // If we have adaptive page detection, and we're on the origin page,
    // don't request a previous page since we're just showing the next page on either edge right now.
    if (_isAdaptivePageDirectionEnabled && TOPagingViewIsInitialPageForPageView(self, _currentPageView)) {
        _needsPreviousPage = NO;
        return;
    }

    // Request a new previous page if we're still pending
    if (_needsPreviousPage) {
        // Re-position the previous page if we already have one, or otherwise fetch a new one
        _previousPageView != nil ? TOPagingViewInsertPageView(self, _previousPageView) : [self _fetchNewPreviousPage];
        _needsPreviousPage = NO;

        // If we also still need to fetch a next page, defer that to the next layout pass
        if (_needsNextPage) { [self setNeedsLayout]; }
    }
}

- (void)_playBounceAnimationInDirection:(UIRectEdge)direction TOPAGINGVIEW_OBJC_DIRECT {
    const BOOL isCompactSizeClass = self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact;
    const CGFloat offsetModifier = (direction == UIRectEdgeLeft) ? -1.0f : 1.0f;
    const CGFloat bumperPadding = (isCompactSizeClass ? kTOPagingViewBumperWidthCompact : kTOPagingViewBumperWidthRegular) * offsetModifier;
    const CGPoint origin = (CGPoint){_layoutMetrics.pageWidth, 0.0f};
    const CGPoint bumperOffset = (CGPoint){origin.x + bumperPadding, 0.0f};

    // Set the various animation blocks so we pull to the side, and then snap back to the middle
    void (^pullAnimationBlock)(void) = ^{ [self->_scrollView setContentOffset:bumperOffset animated:NO]; };
    void (^popAnimationBlock)(void) = ^{ [self->_scrollView setContentOffset:origin animated:NO]; };
    void (^popAnimationCompletionBlock)(BOOL) = ^(BOOL success) { self->_disableLayout = NO; };
    
    // Completion block after the initial pull back is started
    void (^pullAnimationCompletionBlock)(BOOL) = ^(BOOL success) {
        // Play a very wobbly spring back animation snapping back into place
        [UIView animateWithDuration:0.4f
                              delay:0.0f
             usingSpringWithDamping:0.3f
              initialSpringVelocity:0.1f
                            options:kTOPagingViewAnimationOptions
                         animations:popAnimationBlock
                         completion:popAnimationCompletionBlock];
    };

    // Disable layout since the animation will manage everything
    _disableLayout = YES;
    
    // Kickstart the animation chain.
    // Play a very quick rubber-banding slide out to the bumper padding
    [UIView animateWithDuration:0.1f
                          delay:0.0f
         usingSpringWithDamping:1.0f
          initialSpringVelocity:2.5f
                        options:kTOPagingViewAnimationOptions
                     animations:pullAnimationBlock
                     completion:pullAnimationCompletionBlock];
}

#pragma mark - Public Accessors

- (void)setDataSource:(id<TOPagingViewDataSource>)dataSource {
    if (dataSource == _dataSource) { return; }
    _dataSource = dataSource;
    if (self.superview) { [self reload]; }
}

- (void)setDelegate:(id<TOPagingViewDelegate>)delegate {
    if (delegate == _delegate) { return; }
    _delegate = delegate;
    _delegateFlags.delegateWillTurnToPage = [_delegate respondsToSelector:@selector(pagingView:willTurnToPageOfType:)];
    _delegateFlags.delegateDidTurnToPage = [_delegate respondsToSelector:@selector(pagingView:didTurnToPageOfType:)];
    _delegateFlags.delegateDidChangeToPageDirection = [_delegate respondsToSelector:@selector(pagingView:didChangeToPageDirection:)];
}

- (nullable NSSet<__kindof UIView<TOPagingViewPage> *> *)visiblePageViews {
    NSMutableSet *visiblePages = [NSMutableSet set];
    if (_previousPageView) { [visiblePages addObject:_previousPageView]; }
    if (_currentPageView) { [visiblePages addObject:_currentPageView]; }
    if (_nextPageView) { [visiblePages addObject:_nextPageView]; }
    if (visiblePages.count == 0) { return nil; }
    return [visiblePages copy];
}

- (void)setPageScrollDirection:(TOPagingViewDirection)pageScrollDirection {
    if (_pageScrollDirection == pageScrollDirection) { return; }
    _pageScrollDirection = pageScrollDirection;
    [self _updateCachedLayoutMetrics];
    [self _rearrangePagesForScrollDirection:_pageScrollDirection];
}

- (void)setPageSpacing:(CGFloat)pageSpacing {
    if (fabs(_pageSpacing - pageSpacing) <= FLT_EPSILON) { return; }
    _pageSpacing = pageSpacing;
    [self _updateCachedLayoutMetrics];
    [self layoutContent];
}

- (void)setIsAdaptivePageDirectionEnabled:(BOOL)isAdaptivePageDirectionEnabled {
    if (_isAdaptivePageDirectionEnabled == isAdaptivePageDirectionEnabled) { return; }
    _isAdaptivePageDirectionEnabled = isAdaptivePageDirectionEnabled;
    [self reload];
}

- (void)setScrollViewDelegate:(id<UIScrollViewDelegate>)scrollViewDelegate {
    _scrollViewDelegateProxy.externalDelegate = scrollViewDelegate;
}

- (id<UIScrollViewDelegate>)scrollViewDelegate {
    return _scrollViewDelegateProxy.externalDelegate;
}

@end
