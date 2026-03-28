//
//  TOPagingViewTests.m
//  TOPagingViewTests
//
//  Created by Tim Oliver on 2020/03/23.
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "TOPagingView.h"

#pragma mark - Test Page View

@interface TOUnitTestPageView : UIView <TOPagingViewPage>
@property (nonatomic, assign) NSInteger pageNumber;
@property (nonatomic, assign) BOOL prepareForReuseCalled;
@end

@implementation TOUnitTestPageView

- (void)prepareForReuse {
    _prepareForReuseCalled = YES;
}

+ (NSString *)pageIdentifier {
    return @"TOUnitTestPageView";
}

@end

#pragma mark - Test Data Source

@interface TOUnitTestDataSource : NSObject <TOPagingViewDataSource>
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, assign) NSInteger minIndex;
@property (nonatomic, assign) NSInteger maxIndex;
@property (nonatomic, assign) NSInteger dataSourceCallCount;
@end

@implementation TOUnitTestDataSource

- (instancetype)init {
    self = [super init];
    if (self) {
        _minIndex = NSIntegerMin;
        _maxIndex = NSIntegerMax;
    }
    return self;
}

- (nullable UIView<TOPagingViewPage> *)pagingView:(TOPagingView *)pagingView
                                   pageViewForType:(TOPagingViewPageType)type
                                  currentPageView:(TOUnitTestPageView *)currentPageView {
    _dataSourceCallCount++;

    NSInteger index;
    switch (type) {
    case TOPagingViewPageTypeCurrent:
        index = _currentIndex;
        break;
    case TOPagingViewPageTypeNext:
        index = _currentIndex + 1;
        if (index > _maxIndex) { return nil; }
        break;
    case TOPagingViewPageTypePrevious:
        index = _currentIndex - 1;
        if (index < _minIndex) { return nil; }
        break;
    }

    TOUnitTestPageView *pageView = [pagingView dequeueReusablePageViewForIdentifier:@"TOUnitTestPageView"];
    if (pageView == nil) { pageView = [[TOUnitTestPageView alloc] initWithFrame:CGRectZero]; }
    pageView.pageNumber = index;
    return pageView;
}

@end

#pragma mark - Test Delegate

@interface TOUnitTestDelegate : NSObject <TOPagingViewDelegate>
@property (nonatomic, assign) NSInteger willTurnCallCount;
@property (nonatomic, assign) NSInteger didTurnCallCount;
@property (nonatomic, assign) TOPagingViewPageType lastDidTurnType;
@end

@implementation TOUnitTestDelegate

- (void)pagingView:(TOPagingView *)pagingView willTurnToPageOfType:(TOPagingViewPageType)type {
    _willTurnCallCount++;
}

- (void)pagingView:(TOPagingView *)pagingView didTurnToPageOfType:(TOPagingViewPageType)type {
    _didTurnCallCount++;
    _lastDidTurnType = type;
}

@end

#pragma mark - Tests

@interface TOPagingViewTests : XCTestCase
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) TOPagingView *pagingView;
@property (nonatomic, strong) TOUnitTestDataSource *dataSource;
@property (nonatomic, strong) TOUnitTestDelegate *testDelegate;
@end

@implementation TOPagingViewTests

- (void)setUp {
    [super setUp];
    _window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 375, 812)];
    _dataSource = [[TOUnitTestDataSource alloc] init];
    _testDelegate = [[TOUnitTestDelegate alloc] init];

    _pagingView = [[TOPagingView alloc] initWithFrame:_window.bounds];
    _pagingView.delegate = _testDelegate;
    [_pagingView registerPageViewClass:TOUnitTestPageView.class];
    _pagingView.dataSource = _dataSource;
    [_window addSubview:_pagingView];
    [_pagingView layoutIfNeeded];
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
    TOUnitTestPageView *current = (TOUnitTestPageView *)self.pagingView.currentPageView;
    XCTAssertEqual(current.pageNumber, 0, @"Initial page should be index 0");
}

- (void)testAdjacentPagesLoadedOnInit {
    XCTAssertNotNil(self.pagingView.nextPageView, @"Next page should be loaded");
    XCTAssertNotNil(self.pagingView.previousPageView, @"Previous page should be loaded");
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

    TOUnitTestPageView *current = (TOUnitTestPageView *)self.pagingView.currentPageView;
    XCTAssertNotNil(current);
    // After turning next, the delegate should have been informed
    XCTAssertGreaterThan(_testDelegate.didTurnCallCount, 0u);
}

- (void)testTurnToPreviousPageNonAnimated {
    [self.pagingView turnToPreviousPageAnimated:NO];
    [self.pagingView layoutIfNeeded];

    XCTAssertNotNil(self.pagingView.currentPageView);
    XCTAssertGreaterThan(_testDelegate.didTurnCallCount, 0u);
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
}

- (void)testReloadAdjacentKeepsCurrentPage {
    UIView *currentBefore = self.pagingView.currentPageView;
    [self.pagingView reloadAdjacentPages];
    [self.pagingView layoutIfNeeded];

    XCTAssertEqual(self.pagingView.currentPageView, currentBefore, @"Current page should be unchanged");
}

#pragma mark - Scroll Direction

- (void)testSetScrollDirectionRTL {
    self.pagingView.pageScrollDirection = TOPagingViewDirectionRightToLeft;
    XCTAssertEqual(self.pagingView.pageScrollDirection, TOPagingViewDirectionRightToLeft);
    // Pages should still be loaded
    XCTAssertNotNil(self.pagingView.currentPageView);
    XCTAssertNotNil(self.pagingView.nextPageView);
    XCTAssertNotNil(self.pagingView.previousPageView);
}

#pragma mark - Page Spacing

- (void)testCustomPageSpacing {
    self.pagingView.pageSpacing = 20.0f;
    XCTAssertEqual(self.pagingView.pageSpacing, 20.0f);
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
