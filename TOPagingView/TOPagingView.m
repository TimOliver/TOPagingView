//
//  TOPagingView.m
//
//  Copyright 2018-2022 Timothy Oliver. All rights reserved.
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

// -----------------------------------------------------------------

/** For pages that don't specify an identifier, this string will be used. */
static NSString * const kTOPagingViewDefaultIdentifier = @"TOPagingView.DefaultPageIdentifier";

/** There are always 3 slots, with content insetting used to block pages on either side. */
static CGFloat const kTOPagingViewPageSlotCount = 3.0f;

/** The amount of padding along the edge of the screen shown when the "no incoming page" animation plays */
static CGFloat const kTOPagingViewBumperWidthCompact = 48.0f;
static CGFloat const kTOPagingViewBumperWidthRegular = 96.0f;

// -----------------------------------------------------------------

typedef struct {
    unsigned int delegateWillTurnToPage:1;
    unsigned int delegateDidTurnToPage:1;
} TOPagingViewDelegateFlags;

// -----------------------------------------------------------------

@interface TOPagingView ()

/** The scroll view managed by this container */
@property (nonatomic, strong, readwrite) UIScrollView *scrollView;

/** A collection of all of the page view objects that were once used, and are pending re-use. */
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableSet *> *queuedPages;

/** A collection of all of the registered page classes, saved against their identifiers. */
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *registeredPageViewClasses;

/** The views that are all currently in the scroll view, in specific order. */
@property (nonatomic, weak, readwrite) UIView<TOPagingViewPage> *currentPageView;
@property (nonatomic, weak, readwrite) UIView<TOPagingViewPage> *nextPageView;
@property (nonatomic, weak, readwrite) UIView<TOPagingViewPage> *previousPageView;

/** The logical frame for the scroll view given the current bounds */
@property (nonatomic, readonly) CGRect scrollViewFrame;

/** The logical frame values for laying out each of the frames. */
@property (nonatomic, readonly) CGRect currentPageViewFrame;
@property (nonatomic, readonly) CGRect nextPageViewFrame;
@property (nonatomic, readonly) CGRect previousPageViewFrame;

/** Flags to ensure the data source isn't thrashed if it doesn't return a page */
@property (nonatomic, assign) BOOL hasNextPage;
@property (nonatomic, assign) BOOL hasPreviousPage;

/** Struct to cache the state of the delegate for performance */
@property (nonatomic, assign) TOPagingViewDelegateFlags delegateFlags;

/** Disable automatic layout when manually laying out content. */
@property (nonatomic, assign) BOOL disableLayout;

/** A dictionary that holds references to any pages with unique identifiers. */
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIView *> *uniqueIdentifierPages;

/** State tracking for when a user is dragging their finger on screen */
@property (nonatomic, assign) CGFloat draggingOrigin;
@property (nonatomic, assign) TOPagingViewPageType draggingDirectionType;

/** The absolute size of each segment of the scroll view as it is paging.*/
@property (nonatomic, direct, readonly) CGFloat scrollViewPageWidth;

/** A convenience accessor for checking if we are reversed. */
@property (nonatomic, direct, readonly) BOOL isDirectionReversed;

/** Mark all methods called per-frame as direct calls
 (ie, they are called directly, instead of via objc_msgSend)
 to reduce per-frame overhead as much as possible.  */
- (void)layoutPages __attribute__((objc_direct));
- (void)performInitialLayout __attribute__((objc_direct));
- (void)handlePageTransitions __attribute__((objc_direct));
- (void)updateEnabledPages __attribute__((objc_direct));
- (void)updateDragInteraction __attribute__((objc_direct));
- (void)transitionOverToNextPage __attribute__((objc_direct));
- (void)transitionOverToPreviousPage __attribute__((objc_direct));
- (void)insertPageView:(UIView *)pageView __attribute__((objc_direct));
- (void)reclaimPageView:(UIView *)pageView __attribute__((objc_direct));
- (void)setPageSlotEnabled:(BOOL)enabled isLeft:(BOOL)isLeft  __attribute__((objc_direct));

@end

// -----------------------------------------------------------------

@implementation TOPagingView

#pragma mark - Object Creation -

- (instancetype)init
{
    self = [super init];
    if (self) { [self setUp]; }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) { [self setUp]; }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) { [self setUp]; }
    return self;
}

- (void)setUp
{
    // Set default values
    _pageSpacing = 40.0f;
    _queuedPages = [NSMutableDictionary dictionary];
    memset(&_delegateFlags, 0, sizeof(TOPagingViewDelegateFlags));

    // Configure the main properties of this view
    self.clipsToBounds = YES; // The scroll view intentionally overlaps, so this view MUST clip.
    self.backgroundColor = [UIColor clearColor];
    
    // Create and configure the scroll view
    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    [self configureScrollView];
    [self addSubview:self.scrollView];
}

- (void)configureScrollView
{
    UIScrollView *scrollView = self.scrollView;
    
    // Set the frame of the scrollview now so we can start
    // calculating the inset
    scrollView.frame = self.scrollViewFrame;
    
    // Set the scroll behaviour to snap between pages
    scrollView.pagingEnabled = YES;

    // Disable auto status bar insetting
    if (@available(iOS 11.0, *)) {
        scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    
    // Never show the indicators
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.showsVerticalScrollIndicator = NO;
    
    // Register an observer we can use to hook when the scroll view is
    // moving in order to leave the delegate free
    [scrollView addObserver:self forKeyPath:@"contentOffset" options:0 context:nil];
}

- (void)dealloc
{
    // Make sure to remove the observer before we deallocate this object, or else it can cause crashes.
    [self.scrollView removeObserver:self forKeyPath:@"contentOffset"];
}

#pragma mark - View Lifecycle -

- (void)layoutSubviews
{
    [super layoutSubviews];

    UIScrollView *scrollView = self.scrollView;
    
    // Disable the observer while we update the scroll view
    self.disableLayout = YES;
    
    // In case the width is changing, re-set the content size and offset to match
    CGFloat oldContentWidth = scrollView.contentSize.width;
    CGFloat oldOffsetMid    = scrollView.contentOffset.x + (scrollView.frame.size.width * 0.5f);
    
    // Lay-out the scroll view.
    // In order to allow spaces between the pages, the scroll
    // view needs to be slightly wider than this container view.
    scrollView.frame = self.scrollViewFrame;
    
    // Update the content size of the scroll view
    [self updateContentSize];
    
    // Update the content offset to match the amount that the width changed
    // (Only do this if there actually was an old content width, otherwise we might get a NaN error)
    if (oldContentWidth > FLT_EPSILON) {
        CGFloat newOffsetMid = oldOffsetMid * (scrollView.contentSize.width / oldContentWidth);
        CGFloat contentOffset = newOffsetMid - (scrollView.frame.size.width * 0.5f);
        scrollView.contentOffset = (CGPoint){contentOffset, 0.0f};
    }

    // Re-enable the observer
    self.disableLayout = NO;
    
    // Layout the page subviews
    [self layoutPageSubviews];
}

- (void)layoutPageSubviews
{
    CGRect bounds = self.bounds;
    
    // Flip the array if we have reversed the page direction
    NSArray *visiblePages = self.visiblePages;
    if (self.pageScrollDirection == TOPagingViewDirectionRightToLeft) {
        visiblePages = [[visiblePages reverseObjectEnumerator] allObjects];
    }

    // Set the origin to account for the scroll view padding
    CGFloat offset = (_pageSpacing * 0.5f);
    CGFloat width = bounds.size.width + _pageSpacing;

    // If the first page is the center page (eg, the previous/next page is nil),
    // skip ahead one offset slot
    if (visiblePages.firstObject == _currentPageView) {
        offset += width;
    }

    // Re-size each page view currently in the scroll view
    for (UIView *pageView in visiblePages) {
        // Center each page view in each scroll content slot
        CGRect frame = pageView.frame;
        frame.origin.x = offset;
        frame.size = bounds.size;
        pageView.frame = frame;

        // Apply the offset for the next page
        offset += width;
    }
}

- (void)didMoveToSuperview
{
    [super didMoveToSuperview];
    [self reload];
}

#pragma mark - Scroll View Management -

- (void)updateContentSize
{
    // With the up-to-three pages set, calculate the scrolling content size
    CGSize contentSize = self.bounds.size;
    contentSize.width = self.scrollViewPageWidth * kTOPagingViewPageSlotCount;
    self.scrollView.contentSize = contentSize;
}

- (void)resetContentOffset
{
    if (self.currentPageView == nil) { return; }
    
    // Reset the scroll view offset to the current page view
    CGPoint offset = CGPointZero;
    offset.x = CGRectGetMinX(self.currentPageView.frame);
    offset.x -= (_pageSpacing * 0.5f);
    self.scrollView.contentOffset = offset;
}

#pragma mark - Page Setup -

- (void)registerPageViewClass:(Class)pageViewClass
{
    NSAssert([pageViewClass isSubclassOfClass:[UIView class]],
             @"Only UIView objects may be registered as pages.");
    
    // Fetch the page identifier (or use the default if none were 
    NSString *pageIdentifier = [self identifierForPageViewClass:pageViewClass];
    
    // Lazily make the store for the first time
    if (self.registeredPageViewClasses == nil) {
        self.registeredPageViewClasses = [NSMutableDictionary dictionary];
    }
    
    // Encode the class as an NSValue and store to the dictionary
    NSValue *encodedClass = [NSValue valueWithBytes:&pageViewClass objCType:@encode(Class)];
    self.registeredPageViewClasses[pageIdentifier] = encodedClass;
}

- (__kindof UIView<TOPagingViewPage> *)dequeueReusablePageView
{
    return [self dequeueReusablePageViewForIdentifier:nil];
}

- (__kindof UIView<TOPagingViewPage> *)dequeueReusablePageViewForIdentifier:(NSString *)identifier
{
    if (identifier.length == 0) { identifier = kTOPagingViewDefaultIdentifier; }
    
    // Fetch the set for this page type, and lazily create if it doesn't exist
    NSMutableSet *enqueuedPages = self.queuedPages[identifier];
    if (enqueuedPages == nil) {
        enqueuedPages = [NSMutableSet set];
        self.queuedPages[identifier] = enqueuedPages;
    }
    
    // Attempt to fetch a previous page from it
    UIView<TOPagingViewPage> *pageView = enqueuedPages.anyObject;
    
    // If a page was found, set its bounds, and return it
    if (pageView) {
        pageView.frame = self.bounds;
        return pageView;
    }
    
    // If we have a class for this one, create a new instance and return
    NSValue *pageClassValue = self.registeredPageViewClasses[identifier];
    if (pageClassValue) {
        Class pageClass;
        [pageClassValue getValue:&pageClass];
        pageView = [[pageClass alloc] initWithFrame:self.bounds];
        [enqueuedPages addObject:pageView];
        return pageView;
    }
    
    return nil;
}

- (NSString *)identifierForPageViewClass:(Class)pageViewClass
{
    NSString *pageIdentifier = kTOPagingViewDefaultIdentifier;
    if ([pageViewClass respondsToSelector:@selector(pageIdentifier)]) {
        pageIdentifier = [pageViewClass pageIdentifier];
    }
    
    return pageIdentifier;
}

#pragma mark - Page Management -

- (void)reload
{
    // Exit out if we're not ready to display any content yet
    if (self.dataSource == nil || self.superview == nil) { return; }
    
    // Remove all currently visible pages from the scroll views
    for (UIView *view in self.visiblePages) { [self reclaimPageView:view]; }

    // Reset all of the active page references
    self.currentPageView = nil;
    self.previousPageView = nil;
    self.nextPageView = nil;

    // Reset the content size of the scroll view content
    self.scrollView.contentSize = CGSizeZero;
    
    // Clean out all of the pages in the queues
    [self.queuedPages removeAllObjects];
    
    // Perform the initial layout of pages
    [self layoutPages];
}

- (void)setNeedsPageUpdate
{
    if (self.dataSource == nil) { return; }
    
    // If there currently isn't a previous page, check if there is one now
    if (!_hasPreviousPage) {
        UIView *previousPage = [self.dataSource pagingView:self
                                           pageViewForType:TOPagingViewPageTypePrevious
                                           currentPageView:self.currentPageView];
        // Add the page view to the hierarchy
        if (previousPage) {
            [self insertPageView:previousPage];
            previousPage.frame = self.previousPageViewFrame;
            _hasPreviousPage = YES;
        }
    }
    
    // If there currently isn't a next page, check if there is one now
    if (!_hasNextPage) {
        UIView *nextPage = [self.dataSource pagingView:self
                                       pageViewForType:TOPagingViewPageTypeNext
                                       currentPageView:self.currentPageView];
        // Add the page view to the hierarchy
        if (nextPage) {
            [self insertPageView:nextPage];
            nextPage.frame = self.nextPageViewFrame;
            _hasNextPage = YES;
        }
    }
}

- (void)insertPageView:(UIView *)pageView
{
    if (pageView == nil) { return; }
    
    // Add the view to the scroll view
    if (pageView.superview == nil) {
        [_scrollView addSubview:pageView];
    } else {
        pageView.hidden = NO;
    }
    
    // If it has a unique identifier, store it so we can refer to it easily
    if ([pageView respondsToSelector:@selector(uniqueIdentifier)]) {
        NSString *uniqueIdentifier = [(id)pageView uniqueIdentifier];
        
        // Lazily create the dictionary as needed
        if (_uniqueIdentifierPages == nil) {
            _uniqueIdentifierPages = [NSMutableDictionary dictionary];
        }
        
        // Add to the dictionary
        _uniqueIdentifierPages[uniqueIdentifier] = pageView;
    }
    
    // Remove it from the pool of recycled pages
    NSString *pageIdentifier = [self identifierForPageViewClass:pageView.class];
    [_queuedPages[pageIdentifier] removeObject:pageView];
}

- (void)reclaimPageView:(UIView *)pageView
{
    if (pageView == nil) { return; }

    // Leave in the hierarchy, but hide from view
    pageView.hidden = YES;

    // If the page has a unique identifier, remove it from the dictionary
    if ([pageView respondsToSelector:@selector(uniqueIdentifier)]) {
        [_uniqueIdentifierPages removeObjectForKey:[(id)pageView uniqueIdentifier]];
    }

    // If the class supports the clean up method, clean it up now
    if ([pageView respondsToSelector:@selector(prepareForReuse)]) {
        [(id)pageView prepareForReuse];
    }

    // Re-add it to the recycled pages pool
    NSString *pageIdentifier = [self identifierForPageViewClass:pageView.class];
    [_queuedPages[pageIdentifier] addObject:pageView];
}

- (void)layoutPages
{
    // Only perform this overhead when we are in the appropriate state,
    // and we're not being disabled by an active animation.
    if (_dataSource == nil || _disableLayout) { return; }

    UIScrollView *scrollView = _scrollView;
    CGSize contentSize = scrollView.contentSize;

    // Observe user interaction for triggering certain delegate callbacks
    [self updateDragInteraction];

    // On first run, set up the initial pages layout
    if (_currentPageView == nil || contentSize.width < FLT_EPSILON) {
        [self performInitialLayout];
        return;
    }

    // Check the offset of the scroll view, and when it passes over
    // the mid point between two pages, perform the page transition
    [self handlePageTransitions];

    // When the page offset crosses either the left or right threshold,
    // check if a page is ready or not and enable insetting at that point to
    // avoid any hitchy motion
    [self updateEnabledPages];
}

- (void)handlePageTransitions
{
    BOOL isReversed = self.isDirectionReversed;
    CGPoint offset = _scrollView.contentOffset;
    CGFloat segmentWidth = self.scrollViewPageWidth;
    CGSize contentSize = _scrollView.contentSize;

    // Configure two blocks we can dynamically call depending on direction
    void (^goToNextPageBlock)(void) = ^{
        [self transitionOverToNextPage];
    };

    void (^goToPreviousPageBlock)(void) = ^{
        [self transitionOverToPreviousPage];
    };

    // Check if we over-stepped to the next page
    CGFloat rightPageThreshold = contentSize.width - (segmentWidth * 1.5f);
    if (offset.x > rightPageThreshold) {
        if (isReversed) { goToPreviousPageBlock(); }
        else { goToNextPageBlock(); }
        return;
    }

    CGFloat leftPageThreshold = segmentWidth * 0.5f;
    if (offset.x < leftPageThreshold) {
        if (isReversed) { goToNextPageBlock(); }
        else { goToPreviousPageBlock(); }
        return;
    }
}

- (void)updateEnabledPages
{
    CGPoint offset = _scrollView.contentOffset;
    CGFloat segmentWidth = self.scrollViewPageWidth;
    BOOL isReversed = (self.pageScrollDirection == TOPagingViewDirectionRightToLeft);

    // Check the offset and disable the adjance slot if we've gone over the threshold
    // Check the left page slot
    if (offset.x < segmentWidth) {
        BOOL isEnabled = isReversed ? self.hasNextPage : self.hasPreviousPage;
        [self setPageSlotEnabled:isEnabled isLeft:YES];
    }

    // Check the right slot
    if (offset.x > segmentWidth * 2.0f) {
        BOOL isEnabled = isReversed ? self.hasPreviousPage : self.hasNextPage;
        [self setPageSlotEnabled:isEnabled isLeft:NO];
    }
}

- (void)updateDragInteraction
{
    // Exit out if we don't actually use the delegate
    if (_delegateFlags.delegateWillTurnToPage == NO) { return; }

    // If we're not being dragged, reset the state
    if (_scrollView.isTracking == NO) {
        self.draggingOrigin = -CGFLOAT_MAX;
        self.draggingDirectionType = TOPagingViewPageTypeInitial;
        return;
    }

    // If we just started dragging, capture the current offset and exit
    if (_draggingOrigin <= -CGFLOAT_MAX + FLT_EPSILON) {
        _draggingOrigin = _scrollView.contentOffset.x;
        return;
    }

    // Check the direction of the next step
    CGFloat offset = _scrollView.contentOffset.x;
    BOOL isReversed = self.isDirectionReversed;
    TOPagingViewPageType directionType = TOPagingViewPageTypeInitial;

    // We dragged to the right
    if (offset < _draggingOrigin - FLT_EPSILON) {
        directionType = isReversed ? TOPagingViewPageTypeNext : TOPagingViewPageTypePrevious;
    } else if (offset > _draggingOrigin + FLT_EPSILON) { // We dragged to the left
        directionType = isReversed ? TOPagingViewPageTypePrevious : TOPagingViewPageTypeNext;
    } else { return; }

    // If this is a new direction than before, inform the delegate, and then save to avoid repeating
    if (directionType != _draggingDirectionType) {
        [_delegate pagingView:self willTurnToPageOfType:directionType];
        _draggingDirectionType = directionType;
    }

    // Update with the new offset
    _draggingOrigin = offset;
}

- (void)performInitialLayout
{
    // Set these back to true for now, since we'll perform the check in here
    _hasNextPage = YES;
    _hasPreviousPage = YES;

    // Send a delegate event stating we're about to transition to the initial page
    if (_delegateFlags.delegateWillTurnToPage) {
        [self.delegate pagingView:self willTurnToPageOfType:TOPagingViewPageTypeInitial];
    }

    // Add the initial page
    UIView<TOPagingViewPage> *pageView = [self.dataSource pagingView:self
                                                     pageViewForType:TOPagingViewPageTypeInitial
                                                     currentPageView:nil];
    if (pageView == nil) { return; }
    [self insertPageView:pageView];
    self.currentPageView = pageView;
    
    // Add the next page
    pageView = [self.dataSource pagingView:self
                           pageViewForType:TOPagingViewPageTypeNext
                           currentPageView:self.currentPageView];
    _hasNextPage = (pageView != nil);
    _nextPageView = pageView;
    [self insertPageView:pageView];
    
    // Add the previous page
    pageView = [self.dataSource pagingView:self
                           pageViewForType:TOPagingViewPageTypePrevious
                           currentPageView:self.currentPageView];
    _hasPreviousPage = (pageView != nil);
    _previousPageView = pageView;
    [self insertPageView:pageView];
    
    // Disable the observer while we manually place all elements
    self.disableLayout = YES;
    
    // Update the content size for the scroll view
    [self updateContentSize];
    
    // Layout all of the pages
    [self layoutPageSubviews];
    
    // Set the initial scroll point to the current page
    [self resetContentOffset];
    
    // Re-enable the observer
    self.disableLayout = NO;

    // Send a delegate event stating we've completed transitioning to the initial page
    if (_delegateFlags.delegateDidTurnToPage) {
        [self.delegate pagingView:self didTurnToPageOfType:TOPagingViewPageTypeInitial];
    }
}

- (void)transitionOverToNextPage
{
    // If we moved over to the threshold of the next page,
    // re-enable the previous page
    if (!self.hasPreviousPage) {
        self.hasPreviousPage = YES;
    }
    
    // Don't start churning if we already confirmed there is no page after this.
    if (!_hasNextPage) { return; }

    // Reclaim the previous view
    [self reclaimPageView:self.previousPageView];

    // Update all of the references by pushing each view back
    self.previousPageView = self.currentPageView;
    self.currentPageView = self.nextPageView;

    // Update the frames of the pages
    self.currentPageView.frame = self.currentPageViewFrame;
    self.previousPageView.frame = self.previousPageViewFrame;

    // Inform the delegate we have comitted to a transition so we can update state for the next page
    if (_delegateFlags.delegateDidTurnToPage) {
        [self.delegate pagingView:self didTurnToPageOfType:TOPagingViewPageTypeNext];
    }

    // Query the data source for the next page
    UIView<TOPagingViewPage> *nextPage = [self.dataSource pagingView:self
                                                     pageViewForType:TOPagingViewPageTypeNext
                                                     currentPageView:self.nextPageView];
    
    // Insert the new page object and update its position (Will fall through if nil)
    [self insertPageView:nextPage];
    self.nextPageView = nextPage;
    self.nextPageView.frame = self.nextPageViewFrame;

    // If the next page ended up being nil,
    // set a flag to prevent churning, and inset the scroll inset
    if (nextPage == nil) {
        _hasNextPage = NO;
    }

    // Move the scroll view back one segment
    CGPoint contentOffset = self.scrollView.contentOffset;
    if (self.isDirectionReversed) { contentOffset.x += self.scrollViewPageWidth; }
    else { contentOffset.x -= self.scrollViewPageWidth; }
    [self performWithoutLayout:^{
        self.scrollView.contentOffset = contentOffset;
    }];

    // If we're dragging, reset the state
    if (self.scrollView.isDragging) {
        self.draggingOrigin = -CGFLOAT_MAX;
        self.draggingDirectionType = TOPagingViewPageTypeInitial;
    }
}

- (void)transitionOverToPreviousPage
{
    // If we confirmed we moved away from the next page, re-enable
    // so we can query again next time
    if (!self.hasNextPage) {
        self.hasNextPage = YES;
    }
        
    // Don't start churning if we already confirmed there is no page before this.
    if (!_hasPreviousPage) { return; }

    // Reclaim the next view
    [self reclaimPageView:self.nextPageView];

    // Update all of the references by pushing each view forward
    self.nextPageView = self.currentPageView;
    self.currentPageView = self.previousPageView;

    // Update the frames of the pages
    self.currentPageView.frame = self.currentPageViewFrame;
    self.nextPageView.frame = self.nextPageViewFrame;

    // Inform the delegate we have just committed to a transition so we can update state for the previous page
    if (_delegateFlags.delegateDidTurnToPage) {
        [self.delegate pagingView:self didTurnToPageOfType:TOPagingViewPageTypePrevious];
    }

    // Query the data source for the previous page, and exit out if there is no more page data
    UIView<TOPagingViewPage> *previousPage = [self.dataSource pagingView:self
                                                         pageViewForType:TOPagingViewPageTypePrevious
                                                         currentPageView:self.previousPageView];
    
    // Insert the new page object and set its position (Will fall through if nil)
    [self insertPageView:previousPage];
    self.previousPageView = previousPage;
    self.previousPageView.frame = self.previousPageViewFrame;

    // If the previous page ended up being nil,
    // set a flag to prevent churning, and inset the scroll inset
    if (previousPage == nil) {
        _hasPreviousPage = NO;
    }

    // Move the scroll view forward one segment
    CGPoint contentOffset = self.scrollView.contentOffset;
    if (self.isDirectionReversed) { contentOffset.x -= self.scrollViewPageWidth; }
    else { contentOffset.x += self.scrollViewPageWidth; }
    [self performWithoutLayout:^{
        self.scrollView.contentOffset = contentOffset;
    }];

    // If we're dragging, reset the state
    if (self.scrollView.isDragging) {
        self.draggingOrigin = -CGFLOAT_MAX;
        self.draggingDirectionType = TOPagingViewPageTypeInitial;
    }
}

- (void)rearrangePagesForScrollDirection:(TOPagingViewDirection)direction
{
    // Left is for Eastern type layouts
    BOOL leftDirection = (direction == TOPagingViewDirectionRightToLeft);
    
    CGFloat segmentWidth = self.scrollViewPageWidth;
    CGFloat contentWidth = self.scrollView.contentSize.width;
    CGFloat halfSpacing = self.pageSpacing * 0.5f;
    CGFloat rightOffset = (contentWidth - segmentWidth) + halfSpacing;
    
    // Move the next page to the left if direction is left, or vice versa
    if (self.nextPageView) {
        CGRect frame = self.nextPageView.frame;
        if (leftDirection) { frame.origin.x = halfSpacing; }
        else { frame.origin.x = rightOffset; }
        self.nextPageView.frame = frame;
    }
    
    // Move the previous page to the right if direction is left, or vice versa
    if (self.previousPageView) {
        CGRect frame = self.previousPageView.frame;
        if (leftDirection) { frame.origin.x = rightOffset; }
        else { frame.origin.x = halfSpacing; }
        self.previousPageView.frame = frame;
    }
    
    // Flip the content insets if we were potentially at the end of the scroll view
    UIEdgeInsets insets = self.scrollView.contentInset;
    CGFloat leftInset = insets.left;
    insets.left = insets.right;
    insets.right = leftInset;
    [self performWithoutLayout:^{
        self.scrollView.contentInset = insets;
    }];
}

- (void)setPageSlotEnabled:(BOOL)enabled isLeft:(BOOL)isLeft
{
    // Get the current insets of the scroll view
    UIEdgeInsets insets = _scrollView.contentInset;

    // Exit out if we don't need to set the state already
    CGFloat inset = isLeft ? insets.left : insets.right;
    if (enabled && inset >= -FLT_EPSILON) { return; }
    else if (!enabled && inset < -FLT_EPSILON) { return; }

    // Work out what the value should be
    CGFloat value = enabled ? 0.0f : -self.scrollViewPageWidth;
    
    // Capture the content offset since changing the inset will change it
    CGPoint contentOffset = self.scrollView.contentOffset;

    // Set the target inset value
    if (isLeft) { insets.left = value; }
    else { insets.right = value; }
    
    // Set the inset and then restore the offset
    [self performWithoutLayout:^{
        self.scrollView.contentInset = insets;
        self.scrollView.contentOffset = contentOffset;
    }];
}

#pragma mark - External Page Control -

- (void)turnToPageAtContentXOffset:(CGFloat)offset
                          animated:(BOOL)animated
{
    [self turnToPageAtContentXOffset:offset animated:animated completionHandler:nil];
}

- (void)turnToPageAtContentXOffset:(CGFloat)offset
                          animated:(BOOL)animated
                 completionHandler:(void (^)(BOOL))completionHandler
{
    UIScrollView *scrollView = self.scrollView;

    // Determine the direction we're heading for the delegate
    BOOL isLeftDirection = (offset < FLT_EPSILON);
    BOOL isPreviousPage = ((!self.isDirectionReversed && isLeftDirection) ||
                           (self.isDirectionReversed && !isLeftDirection));

    // Send a delegate event stating the page is about to turn
    if (_delegateFlags.delegateWillTurnToPage) {
        TOPagingViewPageType type = (isPreviousPage ? TOPagingViewPageTypePrevious : TOPagingViewPageTypeNext);
        [_delegate pagingView:self willTurnToPageOfType:type];
    }

    // If we're not animating, re-enable layout,
    // and then set the offset to the target
    if (animated == NO) {
        scrollView.contentOffset = (CGPoint){offset, 0.0f};
        if (completionHandler) { completionHandler(YES); }
        return;
    }
    
    // If we're already in an animation, we can't queue up a new animation
    // before the old one completes, otherwise we'll overshoot the pages and cause visual glitching.
    // (There might be a better way to implement this down the line)
    if (scrollView.layer.animationKeys.count) {
        // If we're already in an animation that is moving towards the last a page
        // with no page coming after it, cancel out to let the animation completely fluidly.
        if ((isPreviousPage && !_hasPreviousPage) || (!isPreviousPage && !_hasNextPage)) {
            completionHandler(NO);
            return;
        }

        // Cancel the current animation, and force a layout to reset the state of all the pages
        [scrollView.layer removeAllAnimations];
        self.disableLayout = NO;
        [self layoutPages];
    }

    // Move the scroll view to the target offset, which will trigger a layout.
    // This will update all of the page views, and trigger the delegate with the right state
    scrollView.contentOffset = (CGPoint){offset, 0.0f};

    // Disable layout during this animation as we'll manually control layout here
    self.disableLayout = YES;

    // The scroll view will now be centered, so lets capture this destination
    CGPoint destOffset = scrollView.contentOffset;

    // Move the scroll view back to where it should be so we can perform the animation
    if (offset < FLT_EPSILON) {
        scrollView.contentOffset = (CGPoint){self.scrollViewPageWidth * 2.0f, 0.0f};
    } else {
        scrollView.contentOffset = (CGPoint){0.0f, 0.0f};
    }

    // Perform the animation
    [UIView animateWithDuration:0.4f
                          delay:0.0f
         usingSpringWithDamping:1.0f
          initialSpringVelocity:1.0f
                        options:(UIViewAnimationOptionAllowUserInteraction|UIViewAnimationOptionCurveEaseOut)
                     animations:^{
        scrollView.contentOffset = destOffset;
    } completion:^(BOOL finished) {
        // Re-enable automatic layout
        self.disableLayout = NO;

        // Perform a sanity layout just in case
        // (But in most cases, this should be a no-op)
        [self layoutPages];

        // Perform the completion handler if available
        if (completionHandler) { completionHandler(YES); }
    }];
}

- (void)turnToLeftPageAnimated:(BOOL)animated
{
    BOOL hasLeftPage = (self.isDirectionReversed && self.hasNextPage) ||
                        (!self.isDirectionReversed && self.hasPreviousPage);

    // Play a bouncy animation if there's no incoming page
    if (!hasLeftPage) {
        if (!animated) { return; }
        [self playBounceAnimationInDirection:TOPagingViewDirectionRightToLeft];
        return;
    }

    [self turnToPageAtContentXOffset:0.0f animated:animated];
}

- (void)turnToRightPageAnimated:(BOOL)animated
{
    BOOL hasRightPage = (self.isDirectionReversed && self.hasPreviousPage) ||
                        (!self.isDirectionReversed && self.hasNextPage);

    // Play a bouncy animation if there's no incoming page
    if (!hasRightPage) {
        if (!animated) { return; }
        [self playBounceAnimationInDirection:TOPagingViewDirectionLeftToRight];
        return;
    }

    [self turnToPageAtContentXOffset:self.scrollView.contentSize.width - self.scrollViewPageWidth
                            animated:animated];
}

- (void)skipAheadToNewPageAnimated:(BOOL)animated
{
    // Work out the direction we'll scroll in
    CGFloat offset = 0.0f;
    if (!self.isDirectionReversed) { offset = self.scrollViewPageWidth * 2.0f; }
    
    // Remove the page that this page will be replacing
    [self reclaimPageView:self.nextPageView];
    
    // Get the new page
    self.nextPageView = [_dataSource pagingView:self
                                pageViewForType:TOPagingViewPageTypeNext
                                currentPageView:self.currentPageView];
    
    // Add it to the scroll view
    [self insertPageView:self.nextPageView];
    
    // Set its frame to its placement
    self.nextPageView.frame = self.nextPageViewFrame;
    
    // Set the offset to trigger the appropriate layout
    [self turnToPageAtContentXOffset:offset animated:animated completionHandler:^(BOOL success) {
        if (success == NO) { return; }

        // When finished, replace the page we just came from
        [self reclaimPageView:self.previousPageView];

        self.previousPageView = [self->_dataSource pagingView:self
                                              pageViewForType:TOPagingViewPageTypePrevious
                                              currentPageView:self.currentPageView];

        [self insertPageView:self.previousPageView];

        self.previousPageView.frame = self.previousPageViewFrame;
    }];
}

- (void)skipBehindToNewPageAnimated:(BOOL)animated
{
    // Work out the direction we'll scroll in
    CGFloat offset = 0.0f;
    if (self.isDirectionReversed) { offset = self.scrollViewPageWidth * 2.0f; }
    
    // Remove the page that this page will be replacing
    [self reclaimPageView:self.previousPageView];
    
    // Get the new page
    self.previousPageView = [_dataSource pagingView:self
                                    pageViewForType:TOPagingViewPageTypePrevious
                                    currentPageView:self.currentPageView];
    
    // Add it to the scroll view
    [self insertPageView:self.previousPageView];
    
    // Set its frame to its placement
    self.previousPageView.frame = self.previousPageViewFrame;

    // Set the offset to trigger the appropriate layout
    [self turnToPageAtContentXOffset:offset animated:animated completionHandler:^(BOOL success) {
        if (success == NO) { return; }

        // When finished, replace the page we just came from
        [self reclaimPageView:self.nextPageView];

        self.nextPageView = [self->_dataSource pagingView:self
                                          pageViewForType:TOPagingViewPageTypePrevious
                                          currentPageView:self.currentPageView];

        [self insertPageView:self.nextPageView];

        self.nextPageView.frame = self.nextPageViewFrame;
    }];
}

- (void)playBounceAnimationInDirection:(TOPagingViewDirection)direction
{
    const CGFloat offsetModifier = (direction == TOPagingViewDirectionLeftToRight) ? 1.0f : -1.0f;
    const BOOL isCompactSizeClass = self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact;
    const CGFloat bumperPadding = (isCompactSizeClass ? kTOPagingViewBumperWidthCompact : kTOPagingViewBumperWidthRegular) * offsetModifier;

    // Set the origin and bumper margins
    CGPoint origin = (CGPoint){self.scrollViewPageWidth, 0.0f};
    CGPoint bumperOffset = (CGPoint){origin.x + bumperPadding, 0.0f};

    // Disable layout while this is occurring
    self.disableLayout = YES;

    // Animation block when pulling back to the original state
    void (^popAnimationBlock)(void) = ^{
        [self.scrollView setContentOffset:origin animated:NO];
    };

    // Completion block that cleans everything up at the end of the animation
    void (^popAnimationCompletionBlock)(BOOL) = ^(BOOL success) {
        self.disableLayout = NO;
    };

    // Initial block that starts the animation chain
    void (^pullAnimationBlock)(void) = ^{
        [self.scrollView setContentOffset:bumperOffset animated:NO];
    };

    // Completion block after the initial pull back is started
    void (^pullAnimationCompletionBlock)(BOOL) = ^(BOOL success) {
        // Play a very wobbly spring back animation snapping back into place
        [UIView animateWithDuration:0.4f
                              delay:0.0f
             usingSpringWithDamping:0.3f
              initialSpringVelocity:0.1f
                            options:UIViewAnimationOptionAllowUserInteraction
                         animations:popAnimationBlock
                         completion:popAnimationCompletionBlock];
    };

    // Kickstart the animation chain.
    // Play a very quick rubber-banding slide out to the bumper padding
    [UIView animateWithDuration:0.1f
                          delay:0.0f
         usingSpringWithDamping:1.0f
          initialSpringVelocity:2.5f
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:pullAnimationBlock
                     completion:pullAnimationCompletionBlock];
}

#pragma mark - Keyboard Control -

- (BOOL)canBecomeFirstResponder { return YES; }

- (NSArray<UIKeyCommand *> *)keyCommands
{
    SEL selector = @selector(arrowKeyPressed:);
    UIKeyCommand *leftArrowCommand = [UIKeyCommand keyCommandWithInput:UIKeyInputLeftArrow
                                                         modifierFlags:0
                                                                action:selector];

    UIKeyCommand *rightArrowCommand = [UIKeyCommand keyCommandWithInput:UIKeyInputRightArrow
                                                          modifierFlags:0
                                                                 action:selector];

    if (@available(iOS 15.0, *)) {
        leftArrowCommand.wantsPriorityOverSystemBehavior = YES;
        rightArrowCommand.wantsPriorityOverSystemBehavior = YES;
    }

    return @[leftArrowCommand, rightArrowCommand];
}

- (void)arrowKeyPressed:(UIKeyCommand *)command
{
    if ([command.input isEqualToString:UIKeyInputLeftArrow]) {
        [self turnToLeftPageAnimated:YES];
    }
    else if ([command.input isEqualToString:UIKeyInputRightArrow]) {
        [self turnToRightPageAnimated:YES];
    }
}

#pragma mark - Scroll View Observing -

- (void)performWithoutLayout:(void (^)(void))block
{
    self.disableLayout = YES;
    if (block) { block(); }
    self.disableLayout = NO;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context
{
    [self layoutPages];
}

#pragma mark - Accessors -

- (nullable __kindof UIView *)pageViewForUniqueIdentifier:(NSString *)identifier
{
    return self.uniqueIdentifierPages[identifier];
}

- (NSArray<UIView *> *)visiblePages
{
    NSMutableArray *visiblePages = [NSMutableArray array];
    if (self.previousPageView) { [visiblePages addObject:self.previousPageView]; }
    if (self.currentPageView) { [visiblePages addObject:self.currentPageView]; }
    if (self.nextPageView) { [visiblePages addObject:self.nextPageView]; }
    return [NSArray arrayWithArray:visiblePages];
}

- (CGFloat)scrollViewPageWidth
{
    return self.bounds.size.width + _pageSpacing;
}

- (void)setPageScrollDirection:(TOPagingViewDirection)pageScrollDirection
{
    if (_pageScrollDirection == pageScrollDirection) { return; }
    _pageScrollDirection = pageScrollDirection;
    [self rearrangePagesForScrollDirection:_pageScrollDirection];
}

- (BOOL)isDirectionReversed
{
    return (self.pageScrollDirection == TOPagingViewDirectionRightToLeft);
}

- (CGRect)scrollViewFrame
{
    CGRect frame = CGRectInset(self.bounds, -(_pageSpacing * 0.5f), 0.0f);
    return CGRectIntegral(frame);
}

- (CGRect)currentPageViewFrame
{
    // Current page is always in the middle slot
    CGRect frame = self.bounds;
    frame.origin.x = self.scrollViewPageWidth + (_pageSpacing * 0.5f);
    return frame;
}

- (CGRect)nextPageViewFrame
{
    // Next frame is on the right side when non-reversed,
    // and on the right side when reversed
    CGRect frame = self.bounds;
    if (!self.isDirectionReversed) {
        frame.origin.x = (self.scrollViewPageWidth * 2.0f);
    }
    frame.origin.x += (_pageSpacing * 0.5f);
    return frame;
}

- (CGRect)previousPageViewFrame
{
    // Previous frame is on the left side when non-reversed,
    // and on the right side when reversed
    CGRect frame = self.bounds;
    if (self.isDirectionReversed) {
        frame.origin.x = (self.scrollViewPageWidth * 2.0f);
    }
    frame.origin.x += (_pageSpacing * 0.5f);
    return frame;
}

- (void)setDataSource:(id<TOPagingViewDataSource>)dataSource
{
    if (dataSource == _dataSource) { return; }
    _dataSource = dataSource;
    [self reload];
}

- (void)setDelegate:(id<TOPagingViewDelegate>)delegate
{
    if (delegate == _delegate) { return; }
    _delegate = delegate;

    _delegateFlags.delegateWillTurnToPage = [_delegate
                                             respondsToSelector:@selector(pagingView:willTurnToPageOfType:)];
    _delegateFlags.delegateDidTurnToPage = [_delegate
                                            respondsToSelector:@selector(pagingView:didTurnToPageOfType:)];
}

@end
