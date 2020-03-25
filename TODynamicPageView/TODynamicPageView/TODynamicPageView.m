//
//  TODynamicPageView.m
//  TODynamicPageViewExample
//
//  Created by Tim Oliver on 2020/03/24.
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

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

/** A dictionary that holds references to any pages with unique identifiers. */
@property (nonatomic, strong) NSMutableDictionary<NSString *, UIView *> *uniqueIdentifierPages;

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
    
    // Lay-out the scroll view.
    // In order to allow spaces between the pages, the scroll
    // view needs to be slightly wider than this container view.
    self.scrollView.frame = CGRectIntegral(CGRectInset(bounds,
                                                       -(_pageSpacing * 0.5f),
                                                       0.0f));
    
    // Layout the page subviews
    [self layoutPageSubviews];
}

- (void)layoutPageSubviews
{
    CGRect bounds = self.bounds;
    
    // Re-size each page view currently in the scroll view
    CGFloat offset = (_pageSpacing * 0.5f);
    for (UIView *pageView in self.visiblePages) {
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

- (void)layoutPages
{
    if (self.dataSource == nil) { return; }
    
    UIScrollView *scrollView = self.scrollView;
    CGSize contentSize = scrollView.contentSize;
    
    // On first run, set up the initial pages layout
    if (self.currentPageView == nil || contentSize.width < FLT_EPSILON) {
        [self performInitialLayout];
        return;
    }
    
    CGRect bounds = self.bounds;
    
    CGFloat halfWidth = bounds.size.width * 0.5f;
    CGPoint offset = scrollView.contentOffset;
    
    // Check if we over-stepped to the next page
    CGFloat nextPageThreshold = CGRectGetMaxX(self.currentPageView.frame)
                                                        - (halfWidth);
    if (offset.x > nextPageThreshold) {
        [self transitionOverToNextPage];
        return;
    }
    
    CGFloat previousPageThreshold = CGRectGetMinX(self.currentPageView.frame)
                                                                - (halfWidth + _pageSpacing);
    if (offset.x < previousPageThreshold) {
        [self transitionOverToPreviousPage];
        return;
    }
}

- (void)transitionOverToNextPage
{
    // Don't bother if we've established there is no next page
    if (!_hasNextPage) { return; }
    
    // Query the data source for the next page, and exit out if we don't
    UIView *nextPage = [self.dataSource dynamicPageView:self
                              nextPageViewAfterPageView:self.nextPageView];
    if (nextPage == nil) {
        _hasNextPage = NO;
        return;
    }
    
}

- (void)transitionOverToPreviousPage
{
    
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
    [self.scrollView addSubview:pageView];
    
    // Add the previous page
    pageView = [self.dataSource dynamicPageView:self
                 previousPageViewBeforePageView:self.currentPageView];
    _hasPreviousPage = (pageView != nil);
    _previousPageView = pageView;
    [self.scrollView addSubview:pageView];
    
    // Update the content size for the scroll view
    [self updateContentSize];
    
    // Layout all of the pages
    [self layoutPageSubviews];
    
    // Set the initial scroll point to the current page
    [self resetContentOffset];
}

- (void)insertPageView:(UIView *)pageView
{
    if (pageView == nil) { return; }
    
    [self.scrollView addSubview:pageView];
    
    // Find the queue this page view was from and remove it
    NSString *pageIdentifier = [self identifierForPageViewClass:pageView.class];
    [(NSMutableSet *)self.queuedPages[pageIdentifier] removeObject:pageView];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context
{
    [self layoutPages];
}

#pragma mark - Accessors -

- (NSArray<UIView *> *)visiblePages
{
    NSMutableArray *visiblePages = [NSMutableArray array];
    if (self.previousPageView) { [visiblePages addObject:self.previousPageView]; }
    if (self.currentPageView) { [visiblePages addObject:self.currentPageView]; }
    if (self.nextPageView) { [visiblePages addObject:self.nextPageView]; }
    return [NSArray arrayWithArray:visiblePages];
}

@end
