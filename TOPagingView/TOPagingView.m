//
//  TOPagingView.m
//
//  Copyright 2018-2023 Timothy Oliver. All rights reserved.
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

/// Mark methods as being statically called to increase performance
#define TOPAGINGVIEW_OBJC_DIRECT __attribute__((objc_direct))

// -----------------------------------------------------------------

/// For pages that don't specify an identifier, this string will be used.
static NSString *const kTOPagingViewDefaultIdentifier = @"TOPagingView.DefaultPageIdentifier";

/// There are always 3 slots, with content insetting used to block pages on either side.
static const CGFloat kTOPagingViewPageSlotCount = 3.0f;

/// The amount of padding along the edge of the screen shown when the "no incoming page" animation plays
static const CGFloat kTOPagingViewBumperWidthCompact = 48.0f;
static const CGFloat kTOPagingViewBumperWidthRegular = 96.0f;

/// The timing parameters when playing a precanned transition animation.
static const CFTimeInterval kTOPagingViewAnimationDuration = 0.4f;
static const CGPoint kTOPagingViewAnimationControlPoint1 = (CGPoint){0.3f, 0.9f};
static const CGPoint kTOPagingViewAnimationControlPoint2 = (CGPoint){0.45f, 1.0f};
static const NSInteger kTOPagingViewAnimationOptions = (UIViewAnimationOptionAllowUserInteraction);

// -----------------------------------------------------------------

/// A struct to cache which methods the current delegate implements. */
typedef struct {
    unsigned int delegateWillTurnToPage:1;
    unsigned int delegateDidTurnToPage:1;
    unsigned int delegateDidChangeToPageDirection:1;
} TOPagingViewDelegateFlags;

// -----------------------------------------------------------------

/// A struct to cache which methods each page view class implements.
typedef struct {
    unsigned int protocolPageIdentifier:1;
    unsigned int protocolUniqueIdentifier:1;
    unsigned int protocolPrepareForReuse:1;
    unsigned int protocolIsInitialPage:1;
    unsigned int protocolSetPageDirection:1;
} TOPageViewProtocolFlags;

@interface TOPageViewProtocolCache : NSObject
@property (nonatomic, assign) TOPageViewProtocolFlags flags;
@end

@implementation TOPageViewProtocolCache
@end

// -----------------------------------------------------------------
// Convenience functions for easier mapping Objective-C and C constructs

/// Convert an Objective-C class pointer into an NSValue that can be stored in a dictionary
static inline NSValue *TOPagingViewValueForClass(Class *class) {
    return [NSValue valueWithBytes:class objCType:@encode(Class)];
}

/// Convert an Objective-C class that was encoded to NSValue back out again
static inline Class TOPagingViewClassForValue(NSValue *value) {
    Class class; [value getValue:&class]; return class;
}

// -----------------------------------------------------------------

@interface TOPagingView ()

/// The scroll view managed by this container.
@property (nonatomic, strong, readwrite) UIScrollView *scrollView;

/// A collection of all of the page view objects that were once used, and are pending re-use.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableSet *> *queuedPages;

/// A collection of all of the registered page classes, saved against their identifiers.
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *registeredPageViewClasses;

/// The views that are all currently in the scroll view, in specific order.
@property (nonatomic, weak, readwrite) UIView<TOPagingViewPage> *currentPageView;
@property (nonatomic, weak, readwrite) UIView<TOPagingViewPage> *nextPageView;
@property (nonatomic, weak, readwrite) UIView<TOPagingViewPage> *previousPageView;

/// Flags to ensure the data source isn't thrashed if it doesn't return a page the first time.
@property (nonatomic, assign) BOOL hasNextPage;
@property (nonatomic, assign) BOOL hasPreviousPage;

/// Struct to cache the state of the delegate for performance.
@property (nonatomic, assign) TOPagingViewDelegateFlags delegateFlags;

/// Struct to cache the protocol state of each type of page view class used in this session.
@property (nonatomic, strong) NSMutableDictionary<NSString *, TOPageViewProtocolCache *> *pageViewProtocolFlags;

/// Disable automatic layout when manually laying out content.
@property (nonatomic, assign) BOOL disableLayout;

/// A dictionary that holds references to any pages with unique identifiers.
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIView *> *uniqueIdentifierPages;

/// State tracking for when a user is dragging their finger on screen.
@property (nonatomic, assign) CGFloat draggingOrigin;
@property (nonatomic, assign) TOPagingViewPageType draggingDirectionType;

/// State tracking for handling offloading view configuration to another run-loop tick
@property (nonatomic, assign) BOOL needsNextPage;
@property (nonatomic, assign) BOOL needsPreviousPage;

/// The animator used to play smooth transitions when turning pages
@property (nonatomic, strong) UIViewPropertyAnimator *pageViewAnimator;

@end

// -----------------------------------------------------------------

@implementation TOPagingView

#pragma mark - Object Creation -

- (instancetype)init
{
    self = [super init];
    if (self) { [self _setUp]; }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) { [self _setUp]; }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) { [self _setUp]; }
    return self;
}

- (void)_setUp TOPAGINGVIEW_OBJC_DIRECT
{
    // Set default values
    _pageSpacing = 40.0f;
    _queuedPages = [NSMutableDictionary dictionary];
    _pageViewProtocolFlags = [NSMutableDictionary dictionary];
    memset(&_delegateFlags, 0, sizeof(TOPagingViewDelegateFlags));

    // Configure the main properties of this view
    self.clipsToBounds = YES; // The scroll view intentionally overlaps, so this view MUST clip.
    self.backgroundColor = [UIColor clearColor];
    
    // Create and configure the scroll view
    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    [self _configureScrollView];
    [self addSubview:_scrollView];

    // Configure the page view animator
    UICubicTimingParameters *const cubicTiming = [[UICubicTimingParameters alloc] initWithControlPoint1:kTOPagingViewAnimationControlPoint1
                                                                                    controlPoint2:kTOPagingViewAnimationControlPoint2];
    _pageViewAnimator = [[UIViewPropertyAnimator alloc] initWithDuration:kTOPagingViewAnimationDuration
                                                        timingParameters:cubicTiming];
}

- (void)_configureScrollView TOPAGINGVIEW_OBJC_DIRECT
{
    UIScrollView *const scrollView = _scrollView;
    
    // Set the frame of the scrollview now so we can start
    // calculating the inset
    scrollView.frame = TOPagingViewScrollViewFrame(self);
    
    // Set the scroll behaviour to snap between pages
    scrollView.pagingEnabled = YES;

    // Disable auto status bar insetting
    if (@available(iOS 11.0, *)) {
        scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    
    // Never show the indicators
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.showsVerticalScrollIndicator = NO;
    
    // Register an observer to capture when the scroll view scrolls.
    // Doing it this way lets us leave the delegate available for external objects to use.
    [scrollView addObserver:self forKeyPath:@"contentOffset" options:0 context:(__bridge void *)self];

    // Enable scrolling by clicking and dragging with the mouse
    // The only way to do this is via a private API. FB10593893 was filed to request this property is made public.
    if (@available(iOS 14.0, *)) {
        NSArray *const selectorComponents = @[@"_", @"set", @"SupportsPointerDragScrolling:"];
        SEL selector = NSSelectorFromString([selectorComponents componentsJoinedByString:@""]);
        if ([scrollView respondsToSelector:selector]) {
            [scrollView performSelector:selector withObject:@(YES) afterDelay:0];
        }
    }
}

- (void)dealloc
{
    // Make sure to remove the observer before we deallocate otherwise it can potentially cause a crash.
    [_scrollView removeObserver:self forKeyPath:@"contentOffset"];
}

#pragma mark - View Lifecycle -

- (void)setFrame:(CGRect)frame {
    const CGRect oldFrame = self.frame;
    [super setFrame:frame];
    if (!CGRectEqualToRect(frame, oldFrame)) {
        [self layoutContent];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self layoutContent];
}

- (void)layoutContent
{
    // If need be, request new next/previous pages
    [self _requestPendingPages];

    UIScrollView *const scrollView = _scrollView;
    const CGRect newScrollViewFrame = TOPagingViewScrollViewFrame(self);

    // We don't need to perform any new sizing calculations unless the frame changed enough to warrant
    // also changing the content size
    if (CGSizeEqualToSize(_scrollView.frame.size, newScrollViewFrame.size)) {
        return;
    }

    // Disable the observer while we update the scroll view
    _disableLayout = YES;
    
    // In case the width is changing, re-set the content size and offset to match
    const CGFloat oldContentWidth = scrollView.contentSize.width;
    const CGFloat oldOffsetMid    = scrollView.contentOffset.x + (scrollView.frame.size.width * 0.5f);
    
    // Layout the scroll view.
    // In order to allow spaces between the pages, the scroll view needs to be
    // slightly wider than this container view.
    scrollView.frame = newScrollViewFrame;
    
    // Update the content size of the scroll view
    [self _updateContentSize];

    // Update the content offset to match the amount that the width changed
    // (Only do this if there actually was an old content width, otherwise we might get a NaN error)
    if (oldContentWidth > FLT_EPSILON) {
        const CGFloat newOffsetMid = oldOffsetMid * (scrollView.contentSize.width / oldContentWidth);
        const CGFloat contentOffset = newOffsetMid - (scrollView.frame.size.width * 0.5f);
        scrollView.contentOffset = (CGPoint){contentOffset, 0.0f};
    }
    
    // Re-enable the observer
    _disableLayout = NO;

    // Layout the page subviews
    _nextPageView.frame = TOPagingViewNextPageFrame(self);
    _currentPageView.frame = TOPagingViewCurrentPageFrame(self);
    _previousPageView.frame = TOPagingViewPreviousPageFrame(self);
}

- (void)didMoveToSuperview
{
    [super didMoveToSuperview];
    [self reload];
}

#pragma mark - Scroll View Management -

- (void)_updateContentSize TOPAGINGVIEW_OBJC_DIRECT
{
    // With the three pages set, calculate the scrolling content size
    CGSize contentSize = self.bounds.size;
    contentSize.width = TOPagingViewScrollViewPageWidth(self) * kTOPagingViewPageSlotCount;
    _scrollView.contentSize = contentSize;
}

- (void)_resetContentOffset TOPAGINGVIEW_OBJC_DIRECT
{
    if (_currentPageView == nil) { return; }
    
    // Reset the scroll view offset to the current page view
    CGPoint offset = CGPointZero;
    offset.x = CGRectGetMinX(_currentPageView.frame);
    offset.x -= (_pageSpacing * 0.5f);
    _scrollView.contentOffset = offset;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context
{
    if ((__bridge id)context != self) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    } else if (!_disableLayout) {
        TOPagingViewLayoutPages(self);
    }
}

- (void)_layoutPages TOPAGINGVIEW_OBJC_DIRECT
{
    // Since `TOPagingViewLayoutPages` is inlined, the only call to it should be
    // in the KVO callback method. For all other calls (That don't require frame-tick precision),
    // we can proxy through this method to call it.
    [self observeValueForKeyPath:nil ofObject:nil change:nil context:(__bridge void *)self];
}

#pragma mark - Page Setup -

- (void)registerPageViewClass:(Class)pageViewClass
{
    NSAssert([pageViewClass isSubclassOfClass:[UIView class]],
             @"Only UIView objects may be registered as pages.");

    // Cache the protocol methods this class implements to save checking each time
    TOPagingViewCachedProtocolFlagsForPageViewClass(self, pageViewClass);

    // Fetch the page identifier (or use the default if none were 
    const NSString *pageIdentifier = TOPagingViewIdentifierForPageViewClass(self, pageViewClass);
    
    // Lazily make the store for the first time
    if (_registeredPageViewClasses == nil) {
        _registeredPageViewClasses = [NSMutableDictionary dictionary];
    }
    
    // Encode the class as an NSValue and store to the dictionary
    _registeredPageViewClasses[pageIdentifier] = TOPagingViewValueForClass(&pageViewClass);
}

- (__kindof UIView<TOPagingViewPage> *)dequeueReusablePageView
{
    return [self dequeueReusablePageViewForIdentifier:nil];
}

- (__kindof UIView<TOPagingViewPage> *)dequeueReusablePageViewForIdentifier:(NSString *)identifier
{
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
        if (!CGSizeEqualToSize(pageView.frame.size, self.bounds.size)) {
            pageView.frame = self.bounds;
        }
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

static inline NSString *TOPagingViewIdentifierForPageViewClass(TOPagingView *view, Class pageViewClass)
{
    TOPageViewProtocolFlags flags = TOPagingViewCachedProtocolFlagsForPageViewClass(view, pageViewClass);
    if (flags.protocolPageIdentifier) {
        return [pageViewClass pageIdentifier];
    } else {
        return kTOPagingViewDefaultIdentifier;
    }
}

static inline BOOL TOPagingViewIsInitialPageForPageView(TOPagingView *view, UIView<TOPagingViewPage> *pageView)
{
    if (pageView == nil) { return NO; }
    TOPageViewProtocolFlags flags = TOPagingViewCachedProtocolFlagsForPageViewClass(view, pageView.class);
    return flags.protocolIsInitialPage ? [pageView isInitialPage] : NO;
}

static inline void TOPagingViewSetPageDirectionForPageView(TOPagingView *view, TOPagingViewDirection direction, UIView<TOPagingViewPage> *pageView)
{
    if (pageView == nil) { return; }
    TOPageViewProtocolFlags flags = TOPagingViewCachedProtocolFlagsForPageViewClass(view, pageView.class);
    if (flags.protocolSetPageDirection) { [pageView setPageDirection:direction]; }
}

static inline TOPageViewProtocolFlags TOPagingViewCachedProtocolFlagsForPageViewClass(TOPagingView *view, Class class)
{
    // Skip if we already captured the protocols from this class
    TOPageViewProtocolCache *cache = view->_pageViewProtocolFlags[NSStringFromClass(class)];
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

    // Store in the dictionary
    cache = [TOPageViewProtocolCache new];
    cache.flags = flags;
    view->_pageViewProtocolFlags[NSStringFromClass(class)] = cache;

    // Return the flags
    return flags;
}

#pragma mark - External Page Control -

- (void)reload
{
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
    TOPagingViewPerformBlockWithoutLayout(self, ^{
        self->_scrollView.contentSize = CGSizeZero;
    });

    // Perform a fresh layout
    [self _layoutPages];
}

- (void)reloadAdjacentPages {
    // Reclaim the previous and next pages
    TOPagingViewReclaimPageView(self, _nextPageView);
    TOPagingViewReclaimPageView(self, _previousPageView);

    _nextPageView = nil;
    _previousPageView = nil;

    _hasNextPage = YES;
    _hasPreviousPage = YES;

    [self _fetchNewNextPage];
    if (!_isDynamicPageDirectionEnabled || !TOPagingViewIsInitialPageForPageView(self, _currentPageView)) {
        [self _fetchNewPreviousPage];
    } else {
        _hasPreviousPage = _hasNextPage;
    }
}

- (void)fetchAdjacentPagesIfAvailable
{
    if (_dataSource == nil) { return; }
    
    // If there currently isn't a previous page, check again to see if there is one now.
    if (!_hasPreviousPage) {
        UIView<TOPagingViewPage> *previousPage = [_dataSource pagingView:self
                                                         pageViewForType:TOPagingViewPageTypePrevious
                                                         currentPageView:_currentPageView];
        // Add the page view to the hierarchy
        if (previousPage) {
            TOPagingViewInsertPageView(self, previousPage);
            previousPage.frame = TOPagingViewPreviousPageFrame(self);
            _previousPageView = previousPage;
            _hasPreviousPage = YES;
        }
    }
    
    // If there currently isn't a next page, check again
    if (!_hasNextPage) {
        UIView<TOPagingViewPage> *nextPage = [_dataSource pagingView:self
                                                     pageViewForType:TOPagingViewPageTypeNext
                                                     currentPageView:_currentPageView];
        // Add the page view to the hierarchy
        if (nextPage) {
            TOPagingViewInsertPageView(self, nextPage);
            nextPage.frame = TOPagingViewNextPageFrame(self);
            _nextPageView = nextPage;
            _hasNextPage = YES;
        }
    }

    // If we're on the initial page, set the previous page state to match whatever the next state is
    if (_isDynamicPageDirectionEnabled && TOPagingViewIsInitialPageForPageView(self, _currentPageView)) {
        _hasPreviousPage = _hasNextPage;
    }

    [self _layoutPages];
}

- (void)turnToNextPageAnimated:(BOOL)animated
{
    if (TOPagingViewIsDirectionReversed(self)) {
        [self turnToLeftPageAnimated:animated];
    } else {
        [self turnToRightPageAnimated:animated];
    }
}

- (void)turnToPreviousPageAnimated:(BOOL)animated
{
    if (TOPagingViewIsDirectionReversed(self)) {
        [self turnToRightPageAnimated:animated];
    } else {
        [self turnToLeftPageAnimated:animated];
    }
}

- (void)turnToLeftPageAnimated:(BOOL)animated
{
    const BOOL isDirectionReversed = TOPagingViewIsDirectionReversed(self);
    const BOOL hasLeftPage = (isDirectionReversed && _hasNextPage) ||
                             (!isDirectionReversed && _hasPreviousPage);

    // Play a bouncy animation if there's no incoming page
    if (!hasLeftPage) {
        if (!animated) { return; }
        [self _playBounceAnimationInDirection:TOPagingViewDirectionRightToLeft];
        return;
    }

    // Turn to the left side page
    [self _turnToPageInDirection:UIRectEdgeLeft animated:animated];
}

- (void)turnToRightPageAnimated:(BOOL)animated
{
    const BOOL isDirectionReversed = TOPagingViewIsDirectionReversed(self);
    const BOOL hasRightPage = (isDirectionReversed && _hasPreviousPage) ||
                                (!isDirectionReversed && _hasNextPage);

    // Play a bouncy animation if there's no incoming page
    if (!hasRightPage) {
        if (!animated) { return; }
        [self _playBounceAnimationInDirection:TOPagingViewDirectionLeftToRight];
        return;
    }

    // Turn to the right side page
    [self _turnToPageInDirection:UIRectEdgeRight animated:animated];
}

- (void)skipForwardToNewPageAnimated:(BOOL)animated
{
    UIRectEdge direction = TOPagingViewIsDirectionReversed(self) ? UIRectEdgeLeft : UIRectEdgeRight;
    [self _skipToNewPageInDirection:direction animated:animated];
}

- (void)skipBackwardToNewPageAnimated:(BOOL)animated
{
    UIRectEdge direction = TOPagingViewIsDirectionReversed(self) ? UIRectEdgeRight : UIRectEdgeLeft;
    [self _skipToNewPageInDirection:direction animated:animated];
}

#pragma mark - Page Layout & Management -

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

    // When dynamic paging is enabled, we swap the on-screen 'next' page to either
    // side of the initial page as the user swipes left and right
    if (view->_isDynamicPageDirectionEnabled 
        && TOPagingViewIsInitialPageForPageView(view, view->_currentPageView)) {
        TOPagingViewHandleDynamicPageDirectionLayout(view);
    }

    // Check the offset of the scroll view, and when it passes over
    // the mid point between two pages, perform the page transition
    TOPagingViewHandlePageTransitions(view);

    // Observe user interaction for triggering certain delegate callbacks
    TOPagingViewUpdateDragInteractions(view);

    // When the page offset crosses either the left or right threshold,
    // check if a page is ready or not and enable insetting at that point to
    // avoid any hitchy motion
    TOPagingViewUpdateEnabledPages(view);
}

static inline void TOPagingViewPerformInitialLayout(TOPagingView *view)
{
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
    view->_currentPageView.frame = TOPagingViewCurrentPageFrame(view);

    // Add the next & previous pages
    [view _fetchNewNextPage];

    // When dynamic page detection is enabled, skip fetching the previous page, and assume we have one if we have
    // a next page available.
    if (!view->_isDynamicPageDirectionEnabled || !TOPagingViewIsInitialPageForPageView(view, view->_currentPageView)) {
        [view _fetchNewPreviousPage];
    } else {
        view->_hasPreviousPage = view->_hasNextPage;
    }

    // Disable the observer while we manually place all elements
    view->_disableLayout = YES;

    // Update the content size for the scroll view
    [view _updateContentSize];

    // Set the initial scroll point to the current page
    [view _resetContentOffset];

    // Re-enable the observer
    view->_disableLayout = NO;

    // Send a delegate event stating we've completed transitioning to the initial page
    if (view->_delegateFlags.delegateDidTurnToPage) {
        [view->_delegate pagingView:view didTurnToPageOfType:TOPagingViewPageTypeCurrent];
    }
}

static inline void TOPagingViewPerformBlockWithoutLayout(TOPagingView *view, void (^block)(void))
{
    view->_disableLayout = YES;
    if (block) { block(); }
    view->_disableLayout = NO;
}

static inline void TOPagingViewHandleDynamicPageDirectionLayout(TOPagingView *view)
{
    const CGPoint offset = view->_scrollView.contentOffset;
    const CGFloat segmentWidth = TOPagingViewScrollViewPageWidth(view);
    const UIView<TOPagingViewPage> *nextPage = view->_nextPageView;
    const CGFloat xPosition = CGRectGetMinX(view->_nextPageView.frame);

    // Check when the page starts moving in a certain direction and update the 'next'
    // page to match if it hasn't already been updated.
    if (offset.x < segmentWidth - FLT_EPSILON && xPosition > segmentWidth) {
        TOPagingViewSetPageDirectionForPageView(view, TOPagingViewDirectionRightToLeft, view->_nextPageView);
        nextPage.frame = TOPagingViewLeftPageFrame(view);
    } else if (offset.x > segmentWidth + FLT_EPSILON && xPosition < segmentWidth) {
        TOPagingViewSetPageDirectionForPageView(view, TOPagingViewDirectionLeftToRight, view->_nextPageView);
        nextPage.frame = TOPagingViewRightPageFrame(view);
    }

    // If we've sufficiently committed to this direction, update the hosting paging view's direction
    BOOL needsDelegateUpdate = NO;
    if (offset.x <= FLT_EPSILON 
        && view->_pageScrollDirection == TOPagingViewDirectionLeftToRight) { // Scrolled all the way to the left
        view->_pageScrollDirection = TOPagingViewDirectionRightToLeft;
        needsDelegateUpdate = YES;
    } else if (offset.x >= (segmentWidth * 2.0f) - FLT_EPSILON 
               && view->_pageScrollDirection == TOPagingViewDirectionRightToLeft) { // Scrolled all the way to the right
        view->_pageScrollDirection = TOPagingViewDirectionLeftToRight;
        needsDelegateUpdate = YES;
    }

    if (needsDelegateUpdate && view->_delegateFlags.delegateDidChangeToPageDirection) {
        [view->_delegate pagingView:view didChangeToPageDirection:view->_pageScrollDirection];
    }
}

static inline void TOPagingViewHandlePageTransitions(TOPagingView *view)
{
    const BOOL isReversed = (view->_pageScrollDirection == TOPagingViewDirectionRightToLeft);
    const CGPoint offset = view->_scrollView.contentOffset;
    const CGFloat segmentWidth = TOPagingViewScrollViewPageWidth(view);
    const CGSize contentSize = view->_scrollView.contentSize;

    // Check if we went over the right-hand threshold to start transitioning the pages
    if ((!isReversed && offset.x >= (contentSize.width - segmentWidth))
        || (isReversed && offset.x <= FLT_EPSILON)) {
        TOPagingViewTransitionOverToNextPage(view);
    } else if ((isReversed && offset.x >= (contentSize.width - segmentWidth))
               || (!isReversed && offset.x <= FLT_EPSILON)) { // Check if we're over the left threshold
        TOPagingViewTransitionOverToPreviousPage(view);
    }
}

static inline void TOPagingViewUpdateDragInteractions(TOPagingView *view)
{
    // Exit out if we don't actually use the delegate
    if (view->_delegateFlags.delegateWillTurnToPage == NO) { return; }

    // If we're not being dragged, reset the state
    if (view->_scrollView.isTracking == NO) {
        view->_draggingDirectionType = TOPagingViewPageTypeCurrent;
        view->_draggingOrigin = -CGFLOAT_MAX;
        return;
    }

    // If we just started dragging, capture the current offset and exit
    if (view->_draggingOrigin <= -CGFLOAT_MAX + FLT_EPSILON) {
        view->_draggingOrigin = view->_scrollView.contentOffset.x;
        return;
    }

    // Check the direction of the next step
    const CGFloat offset = view->_scrollView.contentOffset.x;
    const BOOL isDetectingDirection = (view->_isDynamicPageDirectionEnabled
                                       && TOPagingViewIsInitialPageForPageView(view, view->_currentPageView));
    const BOOL isReversed = (view->_pageScrollDirection == TOPagingViewDirectionRightToLeft);
    TOPagingViewPageType directionType;

    //If we're detecting the direction, it will be 'next' regardless
    if (isDetectingDirection) {
        directionType = TOPagingViewPageTypeNext;
    } else if (offset < view->_draggingOrigin - FLT_EPSILON) { // We dragged to the right
        directionType = isReversed ? TOPagingViewPageTypeNext : TOPagingViewPageTypePrevious;
    } else if (offset > view->_draggingOrigin + FLT_EPSILON) { // We dragged to the left
        directionType = isReversed ? TOPagingViewPageTypePrevious : TOPagingViewPageTypeNext;
    } else { return; }

    // If this is a new direction than before, inform the delegate, and then save to avoid repeating
    if (directionType != view->_draggingDirectionType) {
        // Offload this delegate call to another run-loop to avoid any heavy operations as the data source
        [view->_delegate pagingView:view willTurnToPageOfType:directionType];
        view->_draggingDirectionType = directionType;
    }

    // Update with the new offset
    view->_draggingOrigin = offset;
}

static inline void TOPagingViewUpdateEnabledPages(TOPagingView *view)
{
    const CGPoint offset = view->_scrollView.contentOffset;
    const CGFloat segmentWidth = TOPagingViewScrollViewPageWidth(view);
    const BOOL isReversed = (view->_pageScrollDirection == TOPagingViewDirectionRightToLeft);

    // Check the offset and disable the adjancent slot if we've gone over the threshold
    BOOL isEnabled = NO;
    UIRectEdge edge = UIRectEdgeNone;
    if (offset.x < segmentWidth) { // Check the left page slot
        isEnabled = isReversed ? view->_hasNextPage : view->_hasPreviousPage;
        edge = UIRectEdgeLeft;
    } else if (offset.x > segmentWidth) { // Check the right slot
        isEnabled = isReversed ? view->_hasPreviousPage : view->_hasNextPage;
        edge = UIRectEdgeRight;
    }

    // If we matched and edge, update its state
    if (edge != UIRectEdgeNone) {
        TOPagingViewSetPageSlotEnabled(view, isEnabled, edge);
    }
}

static inline void TOPagingViewSetPageSlotEnabled(TOPagingView *view, BOOL enabled, UIRectEdge edge)
{
    // Fetch the segment width. It will be used for either value
    const CGFloat segmentWidth = TOPagingViewScrollViewPageWidth(view);

    // Get the current insets of the scroll view
    UIEdgeInsets insets = view->_scrollView.contentInset;

    // Exit out if we don't need to set the state already
    const BOOL isLeft = (edge == UIRectEdgeLeft);
    CGFloat inset = isLeft ? insets.left : insets.right;
    if (enabled && inset == segmentWidth) { return; }
    else if (!enabled && inset == -segmentWidth) { return; }

    // When the slot is enabled, expand the scrollable region an
    // extra slot, so that it won't bump against the edge of the
    // scroll region when scrolling rapidly.
    // Otherwise, inset it a whole slot to disable it completely.
    CGFloat value = enabled ? segmentWidth : -segmentWidth;

    // Capture the content offset since changing the inset will change it
    CGPoint contentOffset = view->_scrollView.contentOffset;

    // Set the target inset value
    if (isLeft) { insets.left = value; }
    else { insets.right = value; }

    // Set the inset and then restore the offset
    view->_disableLayout = YES;
    view->_scrollView.contentInset = insets;
    view->_scrollView.contentOffset = contentOffset;
    view->_disableLayout = NO;
}

#pragma mark - Animated Transitions -

- (void)_turnToPageInDirection:(UIRectEdge)direction animated:(BOOL)animated TOPAGINGVIEW_OBJC_DIRECT
{
    // Determine the direction to animate towards
    CGFloat offset = 0.0f;
    if (direction == UIRectEdgeRight) {
        offset = _scrollView.contentSize.width - TOPagingViewScrollViewPageWidth(self);
    }

    UIScrollView *const scrollView = _scrollView;

    // Determine the direction we're heading for the delegate
    const BOOL isLeftDirection = (offset < FLT_EPSILON);
    const BOOL isDirectionReversed = TOPagingViewIsDirectionReversed(self);
    const BOOL isDetectingDirection = _isDynamicPageDirectionEnabled
                                        && TOPagingViewIsInitialPageForPageView(self, _currentPageView);
    const BOOL isPreviousPage = !isDetectingDirection && ((!isDirectionReversed && isLeftDirection) ||
                                                          (isDirectionReversed && !isLeftDirection));

    // Send a delegate event stating the page is about to turn
    if (_delegateFlags.delegateWillTurnToPage) {
        TOPagingViewPageType type = (isPreviousPage ? TOPagingViewPageTypePrevious : TOPagingViewPageTypeNext);
        [_delegate pagingView:self willTurnToPageOfType:type];
    }

    // If we're not animating, re-enable layout,
    // and then set the offset to the target
    if (animated == NO) {
        scrollView.contentOffset = (CGPoint){offset, 0.0f};
        return;
    }

    // If the scroll view delegate was set, define this block we can use when the animations completes.
    // (Whether it succeeded, or got canceled)
    __weak __typeof(self) weakSelf = self;
    void (^scrollDidEndDelegateBlock)(void) = ^{
        __strong __typeof(self) strongSelf = weakSelf;
        if (strongSelf == nil) { return; }
        id<UIScrollViewDelegate> scrollViewDelegate = strongSelf->_scrollView.delegate;
        if (scrollViewDelegate) {
            if ([scrollViewDelegate respondsToSelector:@selector(scrollViewDidEndScrollingAnimation:)]) {
                [scrollViewDelegate scrollViewDidEndScrollingAnimation:strongSelf->_scrollView];
            }
        }
    };

    // If the scroll view is decelerating from a swipe, cancel it.
    if (scrollView.isDecelerating) {
        [scrollView setContentOffset:scrollView.contentOffset animated:NO];
    }

    // If we're already in an animation, we can't queue up a new animation
    // before the old one completes, otherwise we'll overshoot the pages and cause visual glitching.
    // (There might be a better way to implement this down the line)
    if (scrollView.layer.animationKeys.count) {
        // If we're already in an animation that is moving towards the last a page
        // with no page coming after it, cancel out to let the animation completely fluidly.
        if ((isPreviousPage && !_hasPreviousPage) || (!isPreviousPage && !_hasNextPage)) {
            return;
        }

        // Cancel the current animation
        [scrollView.layer removeAllAnimations];

        // Trigger the completed delegate
        scrollDidEndDelegateBlock();

        // Re-enable layout so when we change the content offset, we'll reset all of the pages
        _disableLayout = NO;
    }

    // Move the scroll view to the target offset, which will trigger a layout.
    // This will update all of the page views, and trigger the delegate with the right state
    scrollView.contentOffset = (CGPoint){offset, 0.0f};

    // Disable layout during this animation as we'll manually control layout here
    _disableLayout = YES;

    // The scroll view will now be centered, so lets capture this destination
    const CGPoint destOffset = scrollView.contentOffset;

    // Move the scroll view back to where it should be so we can perform the animation
    if (offset < FLT_EPSILON) {
        scrollView.contentOffset = (CGPoint){TOPagingViewScrollViewPageWidth(self) * 2.0f, 0.0f};
    } else {
        scrollView.contentOffset = (CGPoint){0.0f, 0.0f};
    }

    // Define animation parameters
    id animationBlock = ^{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }
        strongSelf->_scrollView.contentOffset = destOffset;
    };

    id completionBlock = ^(UIViewAnimatingPosition finalPosition) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }

        // Re-enable automatic layout
        strongSelf->_disableLayout = NO;

        // Perform a sanity layout just in case
        // (But in most cases, this should be a no-op)
        [strongSelf _layoutPages];

        // Trigger the animation completed delgate
        scrollDidEndDelegateBlock();
    };

    // Perform a very tight transition animation to the next page
    [_pageViewAnimator addAnimations:animationBlock];
    [_pageViewAnimator addCompletion:completionBlock];
    [_pageViewAnimator startAnimation];
}

- (void)_skipToNewPageInDirection:(UIRectEdge)direction animated:(BOOL)animated TOPAGINGVIEW_OBJC_DIRECT
{
    // Disable the layout since we'll handle everything beyond this point
    _disableLayout = YES;

    // If the scroll view is decelerating from a swipe, cancel it.
    if (_scrollView.isDecelerating) {
        [_scrollView setContentOffset:_scrollView.contentOffset animated:NO];
    }

    // If we're already in an animation, cancel it and reset the position
    if (_scrollView.layer.animationKeys.count > 0) {
        [_scrollView.layer removeAllAnimations];
    }

    // Reclaim the next and previous pages since these will always need to be regenerated
    TOPagingViewReclaimPageView(self, _nextPageView);
    TOPagingViewReclaimPageView(self, _previousPageView);

    // Request the new page view that will become the new current page after this completes
    UIView<TOPagingViewPage> *newPageView = [_dataSource pagingView:self
                                                    pageViewForType:TOPagingViewPageTypeCurrent
                                                    currentPageView:_currentPageView];

    // Set the destination point regardless of animation to them middle
    CGPoint destinationPoint = (CGPoint){TOPagingViewScrollViewPageWidth(self), 0.0f}; // Destination is always the middle

    // Zero out the adjacent pages and set the
    // next/previous flags to ensure we'll query for new pages
    _nextPageView = nil;
    _previousPageView = nil;
    _hasNextPage = NO;
    _hasPreviousPage = NO;

    // If we're not animating, we can rearrange everything statically and cancel out here
    if (!animated) {
        // Reclaim the current page since we'll swap over to the newly requested one
        TOPagingViewReclaimPageView(self, _currentPageView);

        // Insert the new current page view
        _currentPageView = newPageView;
        _currentPageView.frame = TOPagingViewCurrentPageFrame(self);
        TOPagingViewInsertPageView(self, _currentPageView);

        // Re-enable layout to trigger a check for the next pages
        _disableLayout = NO;

        // Re-set the offset to the middle
        _scrollView.contentOffset = destinationPoint;

        // Trigger requesting replacement adjacent pages
        [self fetchAdjacentPagesIfAvailable];

        return;
    }

    // Set the scroll view offset to adjacent the middle to animate
    _scrollView.contentOffset = (direction == UIRectEdgeLeft) ? (CGPoint){TOPagingViewScrollViewPageWidth(self) * 2.0f, 0.0f} : CGPointZero;

    // Put the current view in the same slot so we can animate to the new one
    _currentPageView.frame = (direction == UIRectEdgeLeft) ? TOPagingViewRightPageFrame(self) : TOPagingViewLeftPageFrame(self);

    // Make the old current page the previous page so we can keep track of it across animations
    _previousPageView = _currentPageView;

    // Put the new view in the center point and promote it to new current
    _currentPageView = newPageView;
    _currentPageView.frame = TOPagingViewCurrentPageFrame(self);
    TOPagingViewInsertPageView(self, _currentPageView);

    // Define the animation block, making sure not to cause any retain cycles
    __weak __typeof(self) weakSelf = self;
    id animationBlock = ^{
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }
        strongSelf->_scrollView.contentOffset = destinationPoint;
    };

    // Define the completion block
    id completionBlock = ^(UIViewAnimatingPosition finalPosition) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) { return; }

        // Remove the previous page
        TOPagingViewReclaimPageView(self, self->_previousPageView);
        strongSelf->_previousPageView = nil;

        // Re-enable layout
        strongSelf->_disableLayout = NO;

        // Trigger requesting replacement adjacent pages
        [strongSelf fetchAdjacentPagesIfAvailable];

        // If the scroll view delegate was set, tell it the animation completed
        id<UIScrollViewDelegate> scrollViewDelegate = strongSelf->_scrollView.delegate;
        if (scrollViewDelegate) {
            if ([scrollViewDelegate respondsToSelector:@selector(scrollViewDidEndScrollingAnimation:)]) {
                [scrollViewDelegate scrollViewDidEndScrollingAnimation:strongSelf->_scrollView];
            }
        }
    };

    // Perform a very tight transition animation to the target page
    [_pageViewAnimator addAnimations:animationBlock];
    [_pageViewAnimator addCompletion:completionBlock];
    [_pageViewAnimator startAnimation];
}

- (nullable __kindof UIView *)pageViewForUniqueIdentifier:(NSString *)identifier
{
    return _uniqueIdentifierPages[identifier];
}

#pragma mark - Page View Recycling -

static void TOPagingViewInsertPageView(TOPagingView *view, UIView<TOPagingViewPage> *pageView)
{
    if (pageView == nil) { return; }

    // Add the view to the scroll view
    if (pageView.superview == nil) { [view->_scrollView addSubview:pageView]; }
    pageView.hidden = NO;

    // Cache the page's protocol methods if it hasn't been done yet
    TOPageViewProtocolFlags flags = TOPagingViewCachedProtocolFlagsForPageViewClass(view, pageView.class);

    // If it has a unique identifier, store it so we can refer to it easily
    if (flags.protocolUniqueIdentifier) {
        NSString *uniqueIdentifier = [(id)pageView uniqueIdentifier];

        // Lazily create the dictionary as needed
        if (view->_uniqueIdentifierPages == nil) {
            view->_uniqueIdentifierPages = [NSMutableDictionary dictionary];
        }

        // Add to the dictionary
        view->_uniqueIdentifierPages[uniqueIdentifier] = pageView;
    }

    // If the page view supports it, inform the delegate of the current page direction
    if (flags.protocolSetPageDirection) {
        [pageView setPageDirection:view->_pageScrollDirection];
    }

    // Remove it from the pool of recycled pages
    NSString *pageIdentifier = TOPagingViewIdentifierForPageViewClass(view, pageView.class);
    [view->_queuedPages[pageIdentifier] removeObject:pageView];
}

static void TOPagingViewReclaimPageView(TOPagingView *view, UIView *pageView)
{
    if (pageView == nil) { return; }

    // Skip internal UIScrollView views
    if ([NSStringFromClass([pageView class]) characterAtIndex:0] == '_') {
        return;
    }

    // Fetch the protocol flags for this class
    TOPageViewProtocolFlags flags = TOPagingViewCachedProtocolFlagsForPageViewClass(view, pageView.class);

    // If the page has a unique identifier, remove it from the dictionary
    if (flags.protocolUniqueIdentifier) {
        [view->_uniqueIdentifierPages removeObjectForKey:[(id)pageView uniqueIdentifier]];
    }

    // If the class supports the clean up method, clean it up now
    if (flags.protocolPrepareForReuse) {
        [(id)pageView prepareForReuse];
    }

    // Hide the view (Don't remove because that is a heavier operation)
    pageView.hidden = YES;

    // Re-add it to the recycled pages pool
    NSString *pageIdentifier = TOPagingViewIdentifierForPageViewClass(view, pageView.class);
    [view->_queuedPages[pageIdentifier] addObject:pageView];
}

#pragma mark - Page Transitions -

static inline void TOPagingViewTransitionOverToNextPage(TOPagingView *view)
{
    // Don't start churning if we already confirmed there is no page after this.
    if (!view->_hasNextPage) { return; }

    // If we moved over to the threshold of the next page,
    // re-enable the previous page
    if (!view->_hasPreviousPage) {
        view->_hasPreviousPage = YES;
    }

    view->_disableLayout = YES;

    // Reclaim the previous view
    TOPagingViewReclaimPageView(view, view->_previousPageView);

    // Update all of the references by pushing each view back
    view->_previousPageView = view->_currentPageView;
    view->_currentPageView = view->_nextPageView;
    view->_nextPageView = nil;

    // Update the frames of the pages
    view->_currentPageView.frame = TOPagingViewCurrentPageFrame(view);
    view->_previousPageView.frame = TOPagingViewPreviousPageFrame(view);

    // Inform the delegate we have comitted to a transition so we can update state for the next page
    if (view->_delegateFlags.delegateDidTurnToPage) {
        [view->_delegate pagingView:view didTurnToPageOfType:TOPagingViewPageTypeNext];
    }

    // Offload the heavy work to a new run-loop cyle so we don't overload the current one
    view->_needsNextPage = YES;
    [view setNeedsLayout];

    // Move the scroll view back one segment
    CGPoint contentOffset = view->_scrollView.contentOffset;
    const CGFloat scrollViewPageWidth = TOPagingViewScrollViewPageWidth(view);
    const BOOL isDirectionReversed = (view->_pageScrollDirection == TOPagingViewDirectionRightToLeft);
    if (isDirectionReversed) { contentOffset.x += scrollViewPageWidth; }
    else { contentOffset.x -= scrollViewPageWidth; }
    TOPagingViewPerformBlockWithoutLayout(view, ^{
        view->_scrollView.contentOffset = contentOffset;
    });

    // If we're dragging, reset the state
    if (view->_scrollView.isDragging) {
        view->_draggingOrigin = -CGFLOAT_MAX;
    }

    view->_disableLayout = NO;
}

static inline void TOPagingViewTransitionOverToPreviousPage(TOPagingView *view)
{
    // Don't start churning if we already confirmed there is no page before this.
    if (!view->_hasPreviousPage) { return; }

    // If we confirmed we moved away from the next page, re-enable
    // so we can query again next time
    if (!view->_hasNextPage) {
        view->_hasNextPage = YES;
    }

    view->_disableLayout = YES;

    // Reclaim the next view
    TOPagingViewReclaimPageView(view, view->_nextPageView);

    // Update all of the references by pushing each view forward
    view->_nextPageView = view->_currentPageView;
    view->_currentPageView = view->_previousPageView;
    view->_previousPageView = nil;

    // Update the frames of the pages
    view->_currentPageView.frame = TOPagingViewCurrentPageFrame(view);
    view->_nextPageView.frame = TOPagingViewNextPageFrame(view);

    // Inform the delegate we have just committed to a transition so we can update state for the previous page
    if (view->_delegateFlags.delegateDidTurnToPage) {
        [view->_delegate pagingView:view didTurnToPageOfType:TOPagingViewPageTypePrevious];
    }

    // Offload the heavy work to a new run-loop cyle so we don't overload the current one
    view->_needsPreviousPage = YES;
    [view setNeedsLayout];

    // Move the scroll view forward one segment
    CGPoint contentOffset = view->_scrollView.contentOffset;
    const CGFloat scrollViewPageWidth = TOPagingViewScrollViewPageWidth(view);
    const BOOL isDirectionReversed = (view->_pageScrollDirection == TOPagingViewDirectionRightToLeft);
    if (isDirectionReversed) { contentOffset.x -= TOPagingViewScrollViewPageWidth(view); }
    else { contentOffset.x += scrollViewPageWidth; }
    TOPagingViewPerformBlockWithoutLayout(view, ^{
        view->_scrollView.contentOffset = contentOffset;
    });

    // If we're dragging, reset the state
    if (view->_scrollView.isDragging) {
        view->_draggingOrigin = -CGFLOAT_MAX;
    }

    view->_disableLayout = NO;
}

- (void)_fetchNewNextPage TOPAGINGVIEW_OBJC_DIRECT
{
    // Query the data source for the next page
    UIView<TOPagingViewPage> *nextPage = [_dataSource pagingView:self
                                                 pageViewForType:TOPagingViewPageTypeNext
                                                 currentPageView:_nextPageView];

    if (nextPage) {
        // Insert the new page object and update its position (Will fall through if nil)
        TOPagingViewInsertPageView(self, nextPage);
        _nextPageView = nextPage;
        _nextPageView.frame = TOPagingViewNextPageFrame(self);
    }

    // If the next page ended up being nil,
    // set a flag to prevent churning, and inset the scroll inset
    _hasNextPage = (nextPage != nil);
}

- (void)_fetchNewPreviousPage TOPAGINGVIEW_OBJC_DIRECT
{
    // Query the data source for the previous page, and exit out if there is no more page data
    UIView<TOPagingViewPage> *previousPage = [_dataSource pagingView:self
                                                     pageViewForType:TOPagingViewPageTypePrevious
                                                     currentPageView:_previousPageView];

    if (previousPage) {
        // Insert the new page object and set its position (Will fall through if nil)
        TOPagingViewInsertPageView(self, previousPage);
        _previousPageView = previousPage;
        _previousPageView.frame = TOPagingViewPreviousPageFrame(self);
    }

    // If the previous page ended up being nil, set a flag so we don't check again until we need to
    _hasPreviousPage = (previousPage != nil);
}

- (void)_rearrangePagesForScrollDirection:(TOPagingViewDirection)direction TOPAGINGVIEW_OBJC_DIRECT
{
    // Left is for Eastern type layouts
    const BOOL leftDirection = (direction == TOPagingViewDirectionRightToLeft);
    
    const CGFloat segmentWidth = TOPagingViewScrollViewPageWidth(self);
    const CGFloat contentWidth = _scrollView.contentSize.width;
    const CGFloat halfSpacing = self.pageSpacing * 0.5f;
    const CGFloat rightOffset = (contentWidth - segmentWidth) + halfSpacing;

    // Move the next page to the left if direction is left, or vice versa
    if (_nextPageView) {
        CGRect frame = _nextPageView.frame;
        if (leftDirection) { frame.origin.x = halfSpacing; }
        else { frame.origin.x = rightOffset; }
        _nextPageView.frame = frame;
    }
    
    // Move the previous page to the right if direction is left, or vice versa
    if (_previousPageView) {
        CGRect frame = _previousPageView.frame;
        if (leftDirection) { frame.origin.x = rightOffset; }
        else { frame.origin.x = halfSpacing; }
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
    TOPagingViewPerformBlockWithoutLayout(self, ^{
        self->_scrollView.contentInset = insets;
    });
}

- (void)_playBounceAnimationInDirection:(TOPagingViewDirection)direction TOPAGINGVIEW_OBJC_DIRECT
{
    const CGFloat offsetModifier = (direction == TOPagingViewDirectionLeftToRight) ? 1.0f : -1.0f;
    const BOOL isCompactSizeClass = self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact;
    const CGFloat bumperPadding = (isCompactSizeClass ? kTOPagingViewBumperWidthCompact :
                                                        kTOPagingViewBumperWidthRegular) * offsetModifier;

    // Set the origin and bumper margins
    const CGPoint origin = (CGPoint){TOPagingViewScrollViewPageWidth(self), 0.0f};
    const CGPoint bumperOffset = (CGPoint){origin.x + bumperPadding, 0.0f};

    // Disable layout while this is occurring
    _disableLayout = YES;

    // Animation block when pulling back to the original state
    void (^popAnimationBlock)(void) = ^{
        [self->_scrollView setContentOffset:origin animated:NO];
    };

    // Completion block that cleans everything up at the end of the animation
    void (^popAnimationCompletionBlock)(BOOL) = ^(BOOL success) {
        self->_disableLayout = NO;
    };

    // Initial block that starts the animation chain
    void (^pullAnimationBlock)(void) = ^{
        [self->_scrollView setContentOffset:bumperOffset animated:NO];
    };

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

- (void)_requestPendingPages TOPAGINGVIEW_OBJC_DIRECT
{
    // Don't continue if neither pages are pending
    if (!_needsNextPage && !_needsPreviousPage) { return; }

    // Request a new next page
    if (_needsNextPage) {
        // We shouldn't be in a state where a next page is already set,
        // but re-use it if we do
        if (_nextPageView != nil) {
            TOPagingViewInsertPageView(self, _nextPageView);
        } else {
            [self _fetchNewNextPage];
        }

        // Reset the state
        _needsNextPage = NO;

        // If we also have a previous page, offload that to another tick
        if (_needsPreviousPage) {
            [self setNeedsLayout];
            return;
        }
    }

    // If we have dynamic page detection, and we're on the origin page,
    // don't request a previous page since we're re-using just the next page.
    if (_isDynamicPageDirectionEnabled && TOPagingViewIsInitialPageForPageView(self, _currentPageView)) {
        _needsPreviousPage = NO;
        return;
    }

    // Request a new previous page
    if (_needsPreviousPage) {
        // We shouldn't be in a state where a previous page is already set,
        // but re-use it if we do
        if (_previousPageView != nil) {
            TOPagingViewInsertPageView(self, _previousPageView);
        } else {
            [self _fetchNewPreviousPage];
        }

        // Reset the state
        _needsPreviousPage = NO;

        // If we also have a next page, offload that to another tick
        if (_needsNextPage) {
            [self setNeedsLayout];
            return;
        }
    }
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

#pragma mark - Public Accessors -

- (void)setDataSource:(id<TOPagingViewDataSource>)dataSource
{
    if (dataSource == _dataSource) { return; }
    _dataSource = dataSource;
    if (self.superview) { [self reload]; }
}

- (void)setDelegate:(id<TOPagingViewDelegate>)delegate
{
    if (delegate == _delegate) { return; }
    _delegate = delegate;
    _delegateFlags.delegateWillTurnToPage = [_delegate
                                             respondsToSelector:@selector(pagingView:willTurnToPageOfType:)];
    _delegateFlags.delegateDidTurnToPage = [_delegate
                                            respondsToSelector:@selector(pagingView:didTurnToPageOfType:)];
    _delegateFlags.delegateDidChangeToPageDirection = [_delegate
                                                       respondsToSelector:@selector(pagingView:didChangeToPageDirection:)];
}

- (nullable NSSet<__kindof UIView<TOPagingViewPage> *> *)visiblePageViews
{
    NSMutableSet *visiblePages = [NSMutableSet set];
    if (_previousPageView) { [visiblePages addObject:_previousPageView]; }
    if (_currentPageView) { [visiblePages addObject:_currentPageView]; }
    if (_nextPageView) { [visiblePages addObject:_nextPageView]; }
    if (visiblePages.count == 0) { return nil; }
    return [NSSet setWithSet:visiblePages];
}

- (void)setPageScrollDirection:(TOPagingViewDirection)pageScrollDirection
{
    if (_pageScrollDirection == pageScrollDirection) { return; }
    _pageScrollDirection = pageScrollDirection;
    [self _rearrangePagesForScrollDirection:_pageScrollDirection];
}

- (void)setIsDynamicPageDirectionEnabled:(BOOL)isDynamicPageDirectionEnabled {
    if (_isDynamicPageDirectionEnabled == isDynamicPageDirectionEnabled) { return; }
    _isDynamicPageDirectionEnabled = isDynamicPageDirectionEnabled;
    [self reload];
}

#pragma mark - Layout Calculation Helpers -

static inline CGFloat TOPagingViewScrollViewPageWidth(TOPagingView *view)
{
    return view.bounds.size.width + view->_pageSpacing;
}

static inline BOOL TOPagingViewIsDirectionReversed(TOPagingView *view)
{
    return (view->_pageScrollDirection == TOPagingViewDirectionRightToLeft);
}

static inline CGRect TOPagingViewScrollViewFrame(TOPagingView *view)
{
    const CGRect frame = CGRectInset(view.bounds, -(view->_pageSpacing * 0.5f), 0.0f);
    return CGRectIntegral(frame);
}

static inline CGRect TOPagingViewCurrentPageFrame(TOPagingView *view)
{
    // Current page is always in the middle slot
    return CGRectMake(TOPagingViewScrollViewPageWidth(view) + (view->_pageSpacing * 0.5f),
                      view.bounds.origin.y,
                      view.bounds.size.width,
                      view.bounds.size.height);
}

static inline CGRect TOPagingViewNextPageFrame(TOPagingView *view)
{
    // Next frame is on the right side when non-reversed,
    // and on the right side when reversed
    return TOPagingViewIsDirectionReversed(view) ?
            TOPagingViewLeftPageFrame(view) : TOPagingViewRightPageFrame(view);
}

static inline CGRect TOPagingViewPreviousPageFrame(TOPagingView *view)
{
    // Previous frame is on the left side when non-reversed,
    // and on the right side when reversed
    return TOPagingViewIsDirectionReversed(view) ?
            TOPagingViewRightPageFrame(view) : TOPagingViewLeftPageFrame(view);
}

static inline CGRect TOPagingViewLeftPageFrame(TOPagingView *view)
{
    return CGRectOffset(view.bounds, (view->_pageSpacing * 0.5f), 0.0f);
}

static inline CGRect TOPagingViewRightPageFrame(TOPagingView *view)
{
    return CGRectOffset(view.bounds, (TOPagingViewScrollViewPageWidth(view) * 2.0f) + (view->_pageSpacing * 0.5f), 0.0f);
}

@end
