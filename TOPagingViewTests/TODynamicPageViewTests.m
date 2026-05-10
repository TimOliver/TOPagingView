//
//  TOPagingViewTests.m
//  TOPagingViewTests
//
//  Created by Tim Oliver on 2020/03/23.
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <objc/runtime.h>

#import "TOPagingView.h"

#pragma mark - Test Page View

@interface TOUnitTestPageView : UIView <TOPagingViewPage>
@property (nonatomic, assign) NSInteger pageNumber;
@property (nonatomic, assign) BOOL prepareForReuseCalled;
@property (nonatomic, assign) NSInteger prepareForReuseCount;
@property (nonatomic, assign) BOOL initialPage;
@property (nonatomic, assign) TOPagingViewDirection pageDirection;
@property (nonatomic, assign) BOOL pageDirectionWasSet;
@end

@implementation TOUnitTestPageView

- (void)prepareForReuse {
    _prepareForReuseCalled = YES;
    _prepareForReuseCount++;
}

+ (NSString *)pageIdentifier {
    return @"TOUnitTestPageView";
}

- (NSString *)uniqueIdentifier {
    return [NSString stringWithFormat:@"page-%@", @(_pageNumber)];
}

- (BOOL)isInitialPage {
    return _initialPage;
}

- (void)setPageDirection:(TOPagingViewDirection)pageDirection {
    _pageDirection = pageDirection;
    _pageDirectionWasSet = YES;
}

@end

#pragma mark - Test Data Source

@interface TOUnitTestDataSource : NSObject <TOPagingViewDataSource>
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, assign) NSInteger minIndex;
@property (nonatomic, assign) NSInteger maxIndex;
@property (nonatomic, assign) NSInteger dataSourceCallCount;
@property (nonatomic, assign) BOOL usesDequeue;
@property (nonatomic, assign) BOOL returnsNilForCurrentPage;
@property (nonatomic, assign) BOOL returnsCurrentPageForCurrentRequest;
@property (nonatomic, assign) NSInteger reusedPageDequeueCount;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *requestedPageTypes;
@end

@implementation TOUnitTestDataSource

- (instancetype)init {
    self = [super init];
    if (self) {
        _minIndex = NSIntegerMin;
        _maxIndex = NSIntegerMax;
        _usesDequeue = YES;
        _requestedPageTypes = [NSMutableArray array];
    }
    return self;
}

- (nullable UIView<TOPagingViewPage> *)pagingView:(TOPagingView *)pagingView
                                   pageViewForType:(TOPagingViewPageType)type
                                  currentPageView:(nullable TOUnitTestPageView *)currentPageView {
    _dataSourceCallCount++;
    [_requestedPageTypes addObject:@(type)];

    if (type == TOPagingViewPageTypeCurrent && _returnsNilForCurrentPage) { return nil; }
    if (type == TOPagingViewPageTypeCurrent && _returnsCurrentPageForCurrentRequest) { return currentPageView; }

    const NSInteger referenceIndex = currentPageView ? currentPageView.pageNumber : _currentIndex;
    NSInteger index;
    switch (type) {
    case TOPagingViewPageTypeCurrent:
        index = _currentIndex;
        break;
    case TOPagingViewPageTypeNext:
        index = referenceIndex + 1;
        if (index > _maxIndex) { return nil; }
        break;
    case TOPagingViewPageTypePrevious:
        index = referenceIndex - 1;
        if (index < _minIndex) { return nil; }
        break;
    }

    TOUnitTestPageView *pageView = nil;
    if (_usesDequeue) {
        pageView = [pagingView dequeueReusablePageViewForIdentifier:@"TOUnitTestPageView"];
        if (pageView.prepareForReuseCount > 0) { _reusedPageDequeueCount++; }
    }
    if (pageView == nil) { pageView = [[TOUnitTestPageView alloc] initWithFrame:CGRectZero]; }
    pageView.pageNumber = index;
    pageView.initialPage = (type == TOPagingViewPageTypeCurrent && index == 0);
    pageView.pageDirectionWasSet = NO;
    return pageView;
}

@end

#pragma mark - Test Delegate

@interface TOUnitTestDelegate : NSObject <TOPagingViewDelegate>
@property (nonatomic, assign) NSInteger willTurnCallCount;
@property (nonatomic, assign) NSInteger didTurnCallCount;
@property (nonatomic, assign) TOPagingViewPageType lastDidTurnType;
@property (nonatomic, assign) NSInteger directionChangeCallCount;
@property (nonatomic, assign) TOPagingViewDirection lastDirection;
@end

@implementation TOUnitTestDelegate

- (void)pagingView:(TOPagingView *)pagingView willTurnToPageOfType:(TOPagingViewPageType)type {
    _willTurnCallCount++;
}

- (void)pagingView:(TOPagingView *)pagingView didTurnToPageOfType:(TOPagingViewPageType)type {
    _didTurnCallCount++;
    _lastDidTurnType = type;
}

- (void)pagingView:(TOPagingView *)pagingView didChangeToPageDirection:(TOPagingViewDirection)direction {
    _directionChangeCallCount++;
    _lastDirection = direction;
}

@end

#pragma mark - Test Helpers

static UIView *TOCreatePrivateScrollViewSubview(void) {
    static Class privateSubviewClass;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        privateSubviewClass = objc_getClass("_TOPrivateScrollViewSubview");
        if (privateSubviewClass == Nil) {
            privateSubviewClass = objc_allocateClassPair(UIView.class, "_TOPrivateScrollViewSubview", 0);
            objc_registerClassPair(privateSubviewClass);
        }
    });
    return [[privateSubviewClass alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
}

static TOUnitTestPageView *TOTestPageView(UIView<TOPagingViewPage> *pageView) {
    return (TOUnitTestPageView *)pageView;
}

#pragma mark - Tests

@interface TOPagingViewTests : XCTestCase
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) TOPagingView *pagingView;
@property (nonatomic, strong) TOUnitTestDataSource *dataSource;
@property (nonatomic, strong) TOUnitTestDelegate *testDelegate;
@end

@implementation TOPagingViewTests

- (void)installPagingViewWithDataSource:(TOUnitTestDataSource *)dataSource
                              configure:(void (^ _Nullable)(TOPagingView *pagingView))configure {
    [_pagingView removeFromSuperview];

    _dataSource = dataSource;
    _testDelegate = [[TOUnitTestDelegate alloc] init];
    _pagingView = [[TOPagingView alloc] initWithFrame:_window.bounds];
    _pagingView.delegate = _testDelegate;
    [_pagingView registerPageViewClass:TOUnitTestPageView.class];
    if (configure) { configure(_pagingView); }
    _pagingView.dataSource = _dataSource;
    [_window addSubview:_pagingView];
    [_pagingView layoutIfNeeded];
}

- (void)setUp {
    [super setUp];
    _window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 375, 812)];
    [self installPagingViewWithDataSource:[[TOUnitTestDataSource alloc] init] configure:nil];
}

- (void)tearDown {
    [_pagingView removeFromSuperview];
    _pagingView = nil;
    _dataSource = nil;
    _testDelegate = nil;
    _window = nil;
    [super tearDown];
}

#pragma mark - Initialization

- (void)testInitialPageIsLoaded {
    XCTAssertNotNil(self.pagingView.currentPageView, @"Current page should be loaded after layout");
}

- (void)testInitialPageIsCorrectIndex {
    TOUnitTestPageView *current = TOTestPageView(self.pagingView.currentPageView);
    XCTAssertEqual(current.pageNumber, 0, @"Initial page should be index 0");
}

- (void)testAdjacentPagesLoadedOnInit {
    XCTAssertNotNil(self.pagingView.nextPageView, @"Next page should be loaded");
    XCTAssertNotNil(self.pagingView.previousPageView, @"Previous page should be loaded");
    XCTAssertEqual(TOTestPageView(self.pagingView.nextPageView).pageNumber, 1);
    XCTAssertEqual(TOTestPageView(self.pagingView.previousPageView).pageNumber, -1);
}

- (void)testDefaultPageSpacing {
    XCTAssertEqual(self.pagingView.pageSpacing, 40.0f, @"Default page spacing should be 40");
}

- (void)testDefaultScrollDirection {
    XCTAssertEqual(self.pagingView.pageScrollDirection, TOPagingViewDirectionLeftToRight);
}

#pragma mark - Page Registration and Recycling

- (void)testDequeueReturnsRegisteredClass {
    UIView<TOPagingViewPage> *page = [self.pagingView dequeueReusablePageViewForIdentifier:@"TOUnitTestPageView"];
    XCTAssertTrue([page isKindOfClass:TOUnitTestPageView.class]);
}

- (void)testDequeueDefaultReturnsNilWithoutRegistration {
    TOPagingView *fresh = [[TOPagingView alloc] initWithFrame:CGRectMake(0, 0, 375, 812)];
    UIView<TOPagingViewPage> *page = [fresh dequeueReusablePageView];
    XCTAssertNil(page, @"Dequeue without registration should return nil");
}

#pragma mark - Visible Pages

- (void)testVisiblePageViewsReturnsAllThreePages {
    NSSet *visible = [self.pagingView visiblePageViews];
    XCTAssertEqual(visible.count, 3u, @"Should have 3 visible pages");
    XCTAssertTrue([visible containsObject:self.pagingView.currentPageView]);
    XCTAssertTrue([visible containsObject:self.pagingView.nextPageView]);
    XCTAssertTrue([visible containsObject:self.pagingView.previousPageView]);
}

- (void)testPageViewForUniqueIdentifierReturnsVisiblePage {
    TOUnitTestPageView *current = TOTestPageView(self.pagingView.currentPageView);
    TOUnitTestPageView *next = TOTestPageView(self.pagingView.nextPageView);

    XCTAssertEqual([self.pagingView pageViewForUniqueIdentifier:current.uniqueIdentifier], current);
    XCTAssertEqual([self.pagingView pageViewForUniqueIdentifier:next.uniqueIdentifier], next);
    XCTAssertNil([self.pagingView pageViewForUniqueIdentifier:@"missing"]);
}

#pragma mark - Edge Boundaries

- (void)testNoPreviousPageAtMinBoundary {
    _dataSource.minIndex = 0;
    _dataSource.currentIndex = 0;
    [self.pagingView reload];
    [self.pagingView layoutIfNeeded];

    XCTAssertNotNil(self.pagingView.currentPageView);
    XCTAssertNotNil(self.pagingView.nextPageView);
    XCTAssertNil(self.pagingView.previousPageView, @"No previous page at min boundary");
}

- (void)testNoNextPageAtMaxBoundary {
    _dataSource.maxIndex = 0;
    _dataSource.currentIndex = 0;
    [self.pagingView reload];
    [self.pagingView layoutIfNeeded];

    XCTAssertNotNil(self.pagingView.currentPageView);
    XCTAssertNil(self.pagingView.nextPageView, @"No next page at max boundary");
    XCTAssertNotNil(self.pagingView.previousPageView);
}

#pragma mark - Non-animated Page Turns

- (void)testTurnToNextPageNonAnimated {
    [self.pagingView turnToNextPageAnimated:NO];
    [self.pagingView layoutIfNeeded];

    XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageNumber, 1);
    XCTAssertEqual(TOTestPageView(self.pagingView.previousPageView).pageNumber, 0);
    XCTAssertEqual(TOTestPageView(self.pagingView.nextPageView).pageNumber, 2);
    XCTAssertEqual(_testDelegate.lastDidTurnType, TOPagingViewPageTypeNext);
}

- (void)testTurnToPreviousPageNonAnimated {
    [self.pagingView turnToPreviousPageAnimated:NO];
    [self.pagingView layoutIfNeeded];

    XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageNumber, -1);
    XCTAssertEqual(TOTestPageView(self.pagingView.previousPageView).pageNumber, -2);
    XCTAssertEqual(TOTestPageView(self.pagingView.nextPageView).pageNumber, 0);
    XCTAssertEqual(_testDelegate.lastDidTurnType, TOPagingViewPageTypePrevious);
}

- (void)testTurnToLeftAndRightPageNonAnimated {
    [self.pagingView turnToLeftPageAnimated:NO];
    [self.pagingView layoutIfNeeded];
    XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageNumber, -1);

    [self.pagingView turnToRightPageAnimated:NO];
    [self.pagingView layoutIfNeeded];
    XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageNumber, 0);
}

#pragma mark - Delegate Callbacks

- (void)testDelegateReceivesInitialDidTurn {
    // setUp already triggered initial layout which fires didTurnToPage for initial
    XCTAssertGreaterThanOrEqual(_testDelegate.didTurnCallCount, 1u, @"Delegate should receive initial didTurn");
}

- (void)testWillTurnCalledOnPageTurn {
    NSInteger countBefore = _testDelegate.willTurnCallCount;
    [self.pagingView turnToNextPageAnimated:NO];
    XCTAssertGreaterThan(_testDelegate.willTurnCallCount, countBefore, @"willTurn should fire on page turn");
}

#pragma mark - Reload

- (void)testReloadClearsAndRecreatesPages {
    [self.pagingView reload];
    [self.pagingView layoutIfNeeded];

    XCTAssertNotNil(self.pagingView.currentPageView);
    XCTAssertNotNil(self.pagingView.nextPageView);
    XCTAssertNotNil(self.pagingView.previousPageView);
    XCTAssertEqualWithAccuracy(self.pagingView.scrollView.contentInset.left, 0.0, 0.001);
    XCTAssertEqualWithAccuracy(self.pagingView.scrollView.contentInset.right, 0.0, 0.001);
}

- (void)testReloadAdjacentKeepsCurrentPage {
    UIView *currentBefore = self.pagingView.currentPageView;
    [self.pagingView reloadAdjacentPages];
    [self.pagingView layoutIfNeeded];

    XCTAssertEqual(self.pagingView.currentPageView, currentBefore, @"Current page should be unchanged");
}

- (void)testReloadAdjacentPagesNoOpsWithoutDataSource {
    self.pagingView.dataSource = nil;
    [self.pagingView reloadAdjacentPages];

    XCTAssertNil(self.pagingView.currentPageView);
    XCTAssertNil(self.pagingView.nextPageView);
    XCTAssertNil(self.pagingView.previousPageView);
}

- (void)testReloadAdjacentPagesNoOpsWithoutCurrentPage {
    TOPagingView *pagingView = [[TOPagingView alloc] initWithFrame:self.window.bounds];
    TOUnitTestDataSource *dataSource = [[TOUnitTestDataSource alloc] init];
    [pagingView registerPageViewClass:TOUnitTestPageView.class];
    pagingView.dataSource = dataSource;

    [pagingView reloadAdjacentPages];

    XCTAssertEqual(dataSource.dataSourceCallCount, 0);
    XCTAssertNil(pagingView.currentPageView);
}

- (void)testReloadDoesNotRemovePrivateScrollViewSubviews {
    UIView *privateSubview = TOCreatePrivateScrollViewSubview();
    [self.pagingView.scrollView addSubview:privateSubview];

    [self.pagingView reload];

    XCTAssertEqual(privateSubview.superview, self.pagingView.scrollView);
}

#pragma mark - Scroll Direction

- (void)testSetScrollDirectionRTL {
    self.pagingView.pageScrollDirection = TOPagingViewDirectionRightToLeft;
    XCTAssertEqual(self.pagingView.pageScrollDirection, TOPagingViewDirectionRightToLeft);
    // Pages should still be loaded
    XCTAssertNotNil(self.pagingView.currentPageView);
    XCTAssertNotNil(self.pagingView.nextPageView);
    XCTAssertNotNil(self.pagingView.previousPageView);
    XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageDirection, TOPagingViewDirectionRightToLeft);
    XCTAssertEqual(TOTestPageView(self.pagingView.nextPageView).pageDirection, TOPagingViewDirectionRightToLeft);
    XCTAssertEqual(TOTestPageView(self.pagingView.previousPageView).pageDirection, TOPagingViewDirectionRightToLeft);
}

- (void)testTurnToNextAndPreviousRespectRightToLeftDirection {
    self.pagingView.pageScrollDirection = TOPagingViewDirectionRightToLeft;

    [self.pagingView turnToNextPageAnimated:NO];
    [self.pagingView layoutIfNeeded];
    XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageNumber, 1);

    [self.pagingView turnToPreviousPageAnimated:NO];
    [self.pagingView layoutIfNeeded];
    XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageNumber, 0);
}

#pragma mark - Page Spacing

- (void)testCustomPageSpacing {
    self.pagingView.pageSpacing = 20.0f;
    XCTAssertEqual(self.pagingView.pageSpacing, 20.0f);
}

- (void)testFractionalPageSpacingUsesScrollViewPagingWidth {
    self.pagingView.pageSpacing = 21.5f;
    [self.pagingView layoutIfNeeded];

    const CGFloat pageWidth = self.pagingView.bounds.size.width + self.pagingView.pageSpacing;
    XCTAssertEqualWithAccuracy(self.pagingView.scrollView.bounds.size.width, pageWidth, 0.001);
    XCTAssertEqualWithAccuracy(self.pagingView.scrollView.contentSize.width, pageWidth * 3.0f, 0.001);
    XCTAssertEqualWithAccuracy(self.pagingView.scrollView.contentOffset.x, pageWidth, 0.001);
}

#pragma mark - Async Page Availability

- (void)testFetchAdjacentPagesClearsDisabledRightInsetWhenNextPageAppears {
    _dataSource.maxIndex = 0;
    [self.pagingView reload];
    [self.pagingView layoutIfNeeded];

    const CGFloat pageWidth = self.pagingView.scrollView.bounds.size.width;
    self.pagingView.scrollView.contentOffset = CGPointMake(pageWidth + 1.0f, 0.0f);
    XCTAssertLessThan(self.pagingView.scrollView.contentInset.right, 0.0f);
    self.pagingView.scrollView.contentOffset = CGPointMake(pageWidth, 0.0f);

    _dataSource.maxIndex = 1;
    [self.pagingView fetchAdjacentPagesIfAvailable];

    XCTAssertNotNil(self.pagingView.nextPageView);
    XCTAssertEqualWithAccuracy(self.pagingView.scrollView.contentInset.right, 0.0f, 0.001);
}

- (void)testFetchAdjacentPagesClearsDisabledLeftInsetWhenPreviousPageAppears {
    _dataSource.minIndex = 0;
    [self.pagingView reload];
    [self.pagingView layoutIfNeeded];

    const CGFloat pageWidth = self.pagingView.scrollView.bounds.size.width;
    self.pagingView.scrollView.contentOffset = CGPointMake(pageWidth - 1.0f, 0.0f);
    XCTAssertLessThan(self.pagingView.scrollView.contentInset.left, 0.0f);
    self.pagingView.scrollView.contentOffset = CGPointMake(pageWidth, 0.0f);

    _dataSource.minIndex = -1;
    [self.pagingView fetchAdjacentPagesIfAvailable];

    XCTAssertNotNil(self.pagingView.previousPageView);
    XCTAssertEqualWithAccuracy(self.pagingView.scrollView.contentInset.left, 0.0f, 0.001);
}

#pragma mark - Adaptive Page Direction

- (void)testAdaptiveInitialLayoutRequestsOnlyCurrentAndNextPages {
    TOUnitTestDataSource *dataSource = [[TOUnitTestDataSource alloc] init];
    [self installPagingViewWithDataSource:dataSource configure:^(TOPagingView *pagingView) {
        pagingView.isAdaptivePageDirectionEnabled = YES;
    }];

    XCTAssertEqualObjects(dataSource.requestedPageTypes, (@[@(TOPagingViewPageTypeCurrent), @(TOPagingViewPageTypeNext)]));
    XCTAssertNotNil(self.pagingView.currentPageView);
    XCTAssertNotNil(self.pagingView.nextPageView);
    XCTAssertNil(self.pagingView.previousPageView);
}

#pragma mark - Page Reuse

- (void)testManuallyCreatedPagesAreReusableAfterReclaim {
    TOUnitTestDataSource *dataSource = [[TOUnitTestDataSource alloc] init];
    dataSource.usesDequeue = NO;
    [self installPagingViewWithDataSource:dataSource configure:nil];

    TOUnitTestPageView *previousPage = TOTestPageView(self.pagingView.previousPageView);
    dataSource.usesDequeue = YES;

    [self.pagingView turnToNextPageAnimated:NO];
    [self.pagingView layoutIfNeeded];

    XCTAssertEqual(self.pagingView.nextPageView, previousPage);
    XCTAssertEqual(TOTestPageView(self.pagingView.nextPageView).pageNumber, 2);
    XCTAssertGreaterThan(previousPage.prepareForReuseCount, 0);
    XCTAssertGreaterThan(dataSource.reusedPageDequeueCount, 0);
}

#pragma mark - Page Skipping

- (void)testSkipForwardToNilCurrentPageNoOps {
    UIView *currentPage = self.pagingView.currentPageView;
    UIView *nextPage = self.pagingView.nextPageView;
    UIView *previousPage = self.pagingView.previousPageView;
    _dataSource.returnsNilForCurrentPage = YES;

    [self.pagingView skipForwardToNewPageAnimated:NO];

    XCTAssertEqual(self.pagingView.currentPageView, currentPage);
    XCTAssertEqual(self.pagingView.nextPageView, nextPage);
    XCTAssertEqual(self.pagingView.previousPageView, previousPage);
}

- (void)testSkipForwardToSameCurrentPageNoOps {
    UIView *currentPage = self.pagingView.currentPageView;
    UIView *nextPage = self.pagingView.nextPageView;
    UIView *previousPage = self.pagingView.previousPageView;
    _dataSource.returnsCurrentPageForCurrentRequest = YES;

    [self.pagingView skipForwardToNewPageAnimated:NO];

    XCTAssertEqual(self.pagingView.currentPageView, currentPage);
    XCTAssertEqual(self.pagingView.nextPageView, nextPage);
    XCTAssertEqual(self.pagingView.previousPageView, previousPage);
}

- (void)testSkipForwardToNewPageReplacesCurrentAndRefreshesAdjacentPages {
    _dataSource.currentIndex = 42;

    [self.pagingView skipForwardToNewPageAnimated:NO];
    [self.pagingView layoutIfNeeded];

    XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageNumber, 42);
    XCTAssertEqual(TOTestPageView(self.pagingView.previousPageView).pageNumber, 41);
    XCTAssertEqual(TOTestPageView(self.pagingView.nextPageView).pageNumber, 43);
}

#pragma mark - Nil Data Source

- (void)testNilDataSourceShowsNoPages {
    self.pagingView.dataSource = nil;
    [self.pagingView reload];
    [self.pagingView layoutIfNeeded];

    XCTAssertNil(self.pagingView.currentPageView);
    XCTAssertNil(self.pagingView.nextPageView);
    XCTAssertNil(self.pagingView.previousPageView);
}

- (void)testVisiblePageViewsNilWhenEmpty {
    self.pagingView.dataSource = nil;
    [self.pagingView reload];
    [self.pagingView layoutIfNeeded];

    XCTAssertNil([self.pagingView visiblePageViews]);
}

@end
