//
//  TOPagingViewTests.m
//  TOPagingViewTests
//
//  Created by Tim Oliver on 2020/03/23.
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "TOPagingView.h"
#import "TOUnitTestDataSource.h"
#import "TOUnitTestDelegate.h"
#import "TOUnitTestHelpers.h"

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
    const CGFloat pixelTolerance = 1.0f / fmax(self.pagingView.window.screen.scale, 1.0f);
    XCTAssertEqualWithAccuracy(self.pagingView.scrollView.bounds.size.width, pageWidth, 0.001);
    XCTAssertEqualWithAccuracy(self.pagingView.scrollView.contentSize.width, pageWidth * 3.0f, 0.001);
    XCTAssertEqualWithAccuracy(self.pagingView.scrollView.contentOffset.x, pageWidth, pixelTolerance);
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
