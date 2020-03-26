//
//  TODynamicPageView.m
//
//  Copyright 2018-2020 Timothy Oliver. All rights reserved.
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

#import "TODynamicPageView.h"

/** For pages that don't specify an identifier, this string will be used. */
static NSString * const kTODynamicPageViewDefaultIdentifier = @"TODynamicPageView.DefaultPageIdentifier";

@interface TODynamicPageView ()

/** The scroll view managed by this container */
@property (nonatomic, strong, readwrite) UIScrollView *scrollView;

/** A collection of all of the page view objects that were once used, and are pending re-use. */
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableSet *> *queuedPages;

/** A collection of all of the registered page classes, saved against their identifiers. */
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSValue *> *registeredPageViewClasses;

/** The views that are all currently in the scroll view, in specific order. */
@property (nonatomic, weak, readwrite) UIView *currentPageView;
@property (nonatomic, weak, readwrite) UIView *nextPageView;
@property (nonatomic, weak, readwrite) UIView *previousPageView;

/** Once checked, if a next/previous page isn't forth-coming, hold a flag so we don't pummel the data source. */
@property (nonatomic, assign) BOOL hasNextPage;
@property (nonatomic, assign) BOOL hasPreviousPage;

/** Disable automatic layout when manually laying out content. */
@property (nonatomic ,assign) BOOL disableLayout;

/** A dictionary that holds references to any pages with unique identifiers. */
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIView *> *uniqueIdentifierPages;

/** The absolute size of each segment of the scroll view as it is paging.*/
@property (nonatomic, readonly) CGFloat scrollViewPageWidth;

/** A convenience accessor for checking if we are reversed. */
@property (nonatomic, readonly) BOOL isDirectionReversed;

@end

@implementation TODynamicPageView

#pragma mark - Object Creation -

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
    
    // Configure the main properties of this view
    //self.clipsToBounds = YES; // The scroll view intentionally overlaps, so this view MUST clip.
    self.backgroundColor = [UIColor clearColor];
    
    // Create and configure the scroll view
    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    [self configureScrollView];
    [self addSubview:self.scrollView];
}

- (void)configureScrollView
{
    UIScrollView *scrollView = self.scrollView;
    
    // Set the scroll behaviour to snap between pages
    scrollView.pagingEnabled = YES;
    
    // Disable auto status bar insetting
    scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    
    // Never show the indicators
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.showsVerticalScrollIndicator = NO;
    
    // Register an observer we can use to hook when the scroll view is
    // moving in order to leave the delegate free
    [scrollView addObserver:self forKeyPath:@"contentOffset" options:0 context:nil];
}

#pragma mark - View Lifecycle -

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    CGRect bounds = self.bounds;
    
    // Disable the observer while we update the scroll view
    self.disableLayout = YES;
    
    // Lay-out the scroll view.
    // In order to allow spaces between the pages, the scroll
    // view needs to be slightly wider than this container view.
    self.scrollView.frame = CGRectIntegral(CGRectInset(bounds,
                                                       -(_pageSpacing * 0.5f),
                                                       0.0f));
    
    // In case the width changed, re-set the content size and offset to match
    CGFloat oldContentWidth = self.scrollView.contentSize.width;
    CGFloat oldOffset = self.scrollView.contentOffset.x;
    
    // Update the content size of the scroll view
    CGFloat contentWidth = self.visiblePages.count * self.scrollViewPageWidth;
    self.scrollView.contentSize = (CGSize){contentWidth, bounds.size.height };
    
    // Update the content offset to match the amount that the width changed
    CGFloat contentOffset = oldOffset * (contentWidth / oldContentWidth);
    self.scrollView.contentOffset = (CGPoint){contentOffset, 0.0f};
    
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
    if (self.pageScrollDirection == TODynamicPageViewDirectionRightToLeft) {
        visiblePages = [[visiblePages reverseObjectEnumerator] allObjects];
    }
    
    // Re-size each page view currently in the scroll view
    CGFloat offset = (_pageSpacing * 0.5f);
    for (UIView *pageView in visiblePages) {
        // Center each page view in each scroll content slot
        CGRect frame = pageView.frame;
        frame.origin.x = offset;
        frame.size = bounds.size;
        pageView.frame = frame;
        
        offset += bounds.size.width + _pageSpacing;
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
    contentSize.width = (contentSize.width + _pageSpacing) * self.visiblePages.count;
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
    NSAssert([pageViewClass isSubclassOfClass:[UIView class]], @"Only UIView objects may be registered as pages.");
    
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

- (__kindof UIView *)dequeueReusablePageView
{
    return [self dequeueReusablePageViewForIdentifier:nil];
}

- (__kindof UIView *)dequeueReusablePageViewForIdentifier:(NSString *)identifier
{
    if (identifier.length == 0) { identifier = kTODynamicPageViewDefaultIdentifier; }
    
    // Fetch the set for this page type, and lazily create if it doesn't exist
    NSMutableSet *enqueuedPages = self.queuedPages[identifier];
    if (enqueuedPages == nil) {
        enqueuedPages = [NSMutableSet set];
        self.queuedPages[identifier] = enqueuedPages;
    }
    
    // Attempt to fetch a previous page from it
    UIView *pageView = enqueuedPages.anyObject;
    
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
    NSString *pageIdentifier = kTODynamicPageViewDefaultIdentifier;
    if ([pageViewClass respondsToSelector:@selector(pageIdentifier)]) {
        pageIdentifier = [pageViewClass pageIdentifier];
    }
    
    return pageIdentifier;
}

#pragma mark - Page Management -

- (void)reload
{
    if (self.dataSource == nil) { return; }
    
    // Remove all currently visible pages from the scroll views
    for (UIView *view in self.scrollView.subviews) { [view removeFromSuperview]; }
    
    // Reset the content size of the scroll view content
    self.scrollView.contentSize = CGSizeZero;
    
    // Clean out all of the pages in the queues
    [self.queuedPages removeAllObjects];
    
    // Perform the initial layout of pages
    [self layoutPages];
}

- (void)insertPageView:(UIView *)pageView
{
    if (pageView == nil) { return; }
    
    // Add the view to the scroll view
    [self.scrollView addSubview:pageView];
    
    // If it has a unique identifier, store it so we can refer to it easily
    if ([pageView respondsToSelector:@selector(uniqueIdentifier)]) {
        NSString *uniqueIdentifier = [(id)pageView uniqueIdentifier];
        
        // Lazily create the dictionary as needed
        if (self.uniqueIdentifierPages == nil) {
            self.uniqueIdentifierPages = [NSMutableDictionary dictionary];
        }
        
        // Add to the dictionary
        self.uniqueIdentifierPages[uniqueIdentifier] = pageView;
    }
    
    // Remove it from the pool of recycled pages
    NSString *pageIdentifier = [self identifierForPageViewClass:pageView.class];
    [self.queuedPages[pageIdentifier] removeObject:pageView];
}

- (void)reclaimPageView:(UIView *)pageView
{
    if (pageView == nil) { return; }
    
    // Re-add it to the recycled pages pool
    NSString *pageIdentifier = [self identifierForPageViewClass:pageView.class];
    [self.queuedPages[pageIdentifier] addObject:pageView];
    
    // If the page has a unique identifier, remove it from the dictionary
    if ([pageView respondsToSelector:@selector(uniqueIdentifier)]) {
        [self.uniqueIdentifierPages removeObjectForKey:[(id)pageView uniqueIdentifier]];
    }
    
    // If the class supports the clean up method, clean it up now
    if ([pageView respondsToSelector:@selector(prepareForReuse)]) {
        [(id)pageView prepareForReuse];
    }
    
    // Pull it out of the scroll view
    [pageView removeFromSuperview];
}

- (void)layoutPages
{
    if (self.dataSource == nil || self.disableLayout) { return; }
    
    UIScrollView *scrollView = self.scrollView;
    CGSize contentSize = scrollView.contentSize;
    
    // On first run, set up the initial pages layout
    if (self.currentPageView == nil || contentSize.width < FLT_EPSILON) {
        [self performInitialLayout];
        return;
    }
    
    BOOL isReversed = self.isDirectionReversed;
    CGPoint offset = scrollView.contentOffset;
    CGFloat segmentWidth = self.scrollViewPageWidth;
    
    // Configure two blocks we can dynamically call depending on direction
    void (^goToNextPageBlock)(void) = ^{
        [self transitionOverToNextPage];
        self.hasPreviousPage = YES;
    };
    
    void (^goToPreviousPageBlock)(void) = ^{
        [self transitionOverToPreviousPage];
        self.hasNextPage = YES;
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

- (void)performInitialLayout
{
    // Set these back to true for now, since we'll perform the check in here
    _hasNextPage = YES;
    _hasPreviousPage = YES;
    
    // Add the initial page
    UIView *pageView = [self.dataSource initialPageViewForDynamicPageView:self];
    if (pageView == nil) { return; }
    [self insertPageView:pageView];
    self.currentPageView = pageView;
    
    // Add the next page
    pageView = [self.dataSource dynamicPageView:self
                      nextPageViewAfterPageView:self.currentPageView];
    _hasNextPage = (pageView != nil);
    _nextPageView = pageView;
    [self insertPageView:pageView];
    
    // Add the previous page
    pageView = [self.dataSource dynamicPageView:self
                 previousPageViewBeforePageView:self.currentPageView];
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
    self.disableLayout = YES;
}

- (void)transitionOverToNextPage
{
    // Don't start churning if we already confirmed there is no page after this.
    if (!_hasNextPage) { return; }
    
    // Query the data source for the next page, and exit out if there is no more page data
    UIView *nextPage = [self.dataSource dynamicPageView:self
                              nextPageViewAfterPageView:self.nextPageView];
    if (nextPage == nil) {
        _hasNextPage = NO;
        return;
    }
    
    // Insert the new page object
    [self insertPageView:nextPage];
    
    // Shift all of the content over to make room for the new page
    nextPage.frame = self.nextPageView.frame;
    self.nextPageView.frame = self.currentPageView.frame;
    self.currentPageView.frame = self.previousPageView.frame;
    
    // Remove the previous view
    [self reclaimPageView:self.previousPageView];
    
    // Update all of the references
    self.previousPageView = self.currentPageView;
    self.currentPageView = self.nextPageView;
    self.nextPageView = nextPage;
    
    // Move the scroll view back one segment
    CGPoint contentOffset = self.scrollView.contentOffset;
    if (self.isDirectionReversed) { contentOffset.x += self.scrollViewPageWidth; }
    else { contentOffset.x -= self.scrollViewPageWidth; }
    self.scrollView.contentOffset = contentOffset;
}

- (void)transitionOverToPreviousPage
{
    // Don't start churning if we already confirmed there is no page before this.
    if (!_hasPreviousPage) { return; }
    
    // Query the data source for the previous page, and exit out if there is no more page data
    UIView *previousPage = [self.dataSource dynamicPageView:self
                             previousPageViewBeforePageView:self.previousPageView];
    if (previousPage == nil) {
        _hasPreviousPage = NO;
        return;
    }
    
    // Insert the new page object
    [self insertPageView:previousPage];
    
    // Shift all of the content over to make room for the new page
    previousPage.frame = self.previousPageView.frame;
    self.previousPageView.frame = self.currentPageView.frame;
    self.currentPageView.frame = self.nextPageView.frame;
    
    // Remove the next view that has been moved out
    [self reclaimPageView:self.nextPageView];
    
    // Update all of the references
    self.nextPageView = self.currentPageView;
    self.currentPageView = self.previousPageView;
    self.previousPageView = previousPage;
    
    // Move the scroll view forward one segment
    CGPoint contentOffset = self.scrollView.contentOffset;
    if (self.isDirectionReversed) { contentOffset.x -= self.scrollViewPageWidth; }
    else { contentOffset.x += self.scrollViewPageWidth; }
    self.scrollView.contentOffset = contentOffset;
}

- (void)rearrangePagesForScrollDirection:(TODynamicPageViewDirection)direction
{
    // Left is for Eastern type layouts
    BOOL leftDirection = (direction == TODynamicPageViewDirectionRightToLeft);
    
    CGFloat segmentWidth = self.scrollViewPageWidth;
    CGFloat halfSegment = segmentWidth * 0.5f;
    CGFloat contentWidth = self.scrollView.contentSize.width;
    CGFloat halfSpacing = self.pageSpacing * 0.5f;
    
    // Move the next page to the left if direction is left, or vice versa
    if (self.nextPageView) {
        CGRect frame = self.nextPageView.frame;
        if (leftDirection) { frame.origin.x = halfSpacing; }
        else { frame.origin.x = (contentWidth - segmentWidth) + halfSpacing; }
        self.nextPageView.frame = frame;
    }
    
    // Move the previous page to the right if direction is left, or vice versa
    if (self.previousPageView) {
        CGRect frame = self.previousPageView.frame;
        if (leftDirection) { frame.origin.x = (contentWidth - segmentWidth) + halfSpacing; }
        else { frame.origin.x = halfSpacing; }
        self.previousPageView.frame = frame;
    }
    
    // Move the current page to be adjacent to whichever view is visible
    CGRect frame = self.currentPageView.frame;
    if (self.nextPageView) {
        CGRect nextFrame = self.nextPageView.frame;
        if (leftDirection) { frame.origin.x = segmentWidth + halfSpacing; }
        else { frame.origin.x = CGRectGetMinX(nextFrame) - segmentWidth; }
    }
    else if (self.previousPageView) {
        CGRect previousFrame = self.previousPageView.frame;
        if (leftDirection) { frame.origin.x = CGRectGetMinX(previousFrame) - segmentWidth; }
        else { frame.origin.x = segmentWidth + halfSpacing; }
    }
    self.currentPageView.frame = frame;
    
    // Flip the current scroll position, based off the middle of the scrolling region
    CGFloat contentMiddle = contentWidth * 0.5f;
    CGFloat contentOffset = self.scrollView.contentOffset.x + (segmentWidth * 0.5f);
    CGFloat distance = contentOffset - contentMiddle;
    
    CGPoint newOffset = self.scrollView.contentOffset;
    newOffset.x = (contentMiddle - distance) - halfSegment;
    self.scrollView.contentOffset = newOffset;
}

#pragma mark - External Page Control -

- (void)turnToPageAtContentXOffset:(CGFloat)offset animated:(BOOL)animated
{
    if (animated == NO) {
        self.disableLayout = NO;
        self.scrollView.contentOffset = (CGPoint){offset, 0.0f};
        return;
    }
    
    // If we're already in an animation, cancel it out
    // and reset all of the content as if the animation completed
    if (self.scrollView.layer.animationKeys.count) {
        [self.scrollView.layer removeAllAnimations];
        self.disableLayout = NO;
        [self layoutPages];
    }
    
    // Disable layout during this animation as we're controlling the whole stack
    self.disableLayout = YES;

    // Perform the animation
    [UIView animateWithDuration:0.45f
                          delay:0.0f
         usingSpringWithDamping:1.0f
          initialSpringVelocity:2.5f
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        self.scrollView.contentOffset = (CGPoint){offset, 0.0f};
    } completion:^(BOOL finished) {
        // If we canceled this animation,
        // disregard since we'll manually restore after
        if (!finished) { return; }
        self.disableLayout = NO;
        [self layoutPages];
    }];
}

- (void)turnToLeftPageAnimated:(BOOL)animated
{
    if (self.isDirectionReversed && !self.hasNextPage) { return; }
    [self turnToPageAtContentXOffset:0.0f animated:animated];
}

- (void)turnToRightPageAnimated:(BOOL)animated
{
    if (!self.isDirectionReversed && !self.hasNextPage) { return; }
    [self turnToPageAtContentXOffset:self.scrollView.contentSize.width - self.scrollViewPageWidth
                            animated:animated];
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

- (void)setPageScrollDirection:(TODynamicPageViewDirection)pageScrollDirection
{
    if (_pageScrollDirection == pageScrollDirection) { return; }
    _pageScrollDirection = pageScrollDirection;
    [self rearrangePagesForScrollDirection:_pageScrollDirection];
}

- (BOOL)isDirectionReversed
{
    return (self.pageScrollDirection == TODynamicPageViewDirectionRightToLeft);
}

@end
