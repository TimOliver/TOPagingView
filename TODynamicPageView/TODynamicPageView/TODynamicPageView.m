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

#pragma mark - Page Setup -

- (void)registerPageViewClass:(Class)pageViewClass
{
    NSAssert([pageViewClass isKindOfClass:[UIView class]], @"Only UIView objects may be registered as pages.");
    
    // Fetch the page identifier (or use the default if none were 
    NSString *pageIdentifier = kTODynamicPageViewDefaultIdentifier;
    if ([pageViewClass respondsToSelector:@selector(pageIdentifier)]) {
        pageIdentifier = [pageViewClass pageIdentifier];
    }
}

#pragma mark - Page Management -

- (void)reload
{
    // Remove all currently visible pages from the scroll views
    for (UIView *view in self.scrollView.subviews) { [view removeFromSuperview]; }
    
    // Clean out all of the pages in the queues
    [self.queuedPages removeAllObjects];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    CGPoint offset = scrollView.contentOffset;
    CGSize contentSize = scrollView.contentSize;
    
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context
{
    [self scrollViewDidScroll:self.scrollView];
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
