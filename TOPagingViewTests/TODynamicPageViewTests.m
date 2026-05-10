//
//  TOPagingViewTests.m
//  TOPagingViewTests
//
//  Created by Tim Oliver on 2020/03/23.
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "TOPagingView.h"
#import "TOPagingViewAnimator.h"
#import "TOUnitTestDataSource.h"
#import "TOUnitTestDelegate.h"
#import "TOUnitTestHelpers.h"

#pragma mark - Test Helpers

@interface TOPagingView (TOUnitTestKeyboard)
- (void)arrowKeyPressed:(UIKeyCommand *)command;
@end

@interface TOUnitTestScrollViewDelegate : NSObject <UIScrollViewDelegate>
@property (nonatomic, assign) NSInteger didEndScrollingAnimationCallCount;
@end

@implementation TOUnitTestScrollViewDelegate

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    _didEndScrollingAnimationCallCount++;
}

@end

@interface TOUnitTestKeyboardPagingView : TOPagingView
@property (nonatomic, assign) NSInteger leftTurnCallCount;
@property (nonatomic, assign) NSInteger rightTurnCallCount;
@property (nonatomic, assign) BOOL lastTurnWasAnimated;
@end

@implementation TOUnitTestKeyboardPagingView

- (void)turnToLeftPageAnimated:(BOOL)animated {
    _leftTurnCallCount++;
    _lastTurnWasAnimated = animated;
}

- (void)turnToRightPageAnimated:(BOOL)animated {
    _rightTurnCallCount++;
    _lastTurnWasAnimated = animated;
}

@end

@interface TOUnitTestDeceleratingScrollView : UIScrollView
@property (nonatomic, assign) BOOL deceleratingForUnitTest;
@property (nonatomic, assign) NSInteger cancelDecelerationCallCount;
@end

@implementation TOUnitTestDeceleratingScrollView

- (BOOL)isDecelerating {
    return _deceleratingForUnitTest || [super isDecelerating];
}

- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated {
    if (_deceleratingForUnitTest && !animated) { _cancelDecelerationCallCount++; }
    [super setContentOffset:contentOffset animated:animated];
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

- (TOUnitTestDeceleratingScrollView *)replaceScrollViewWithDeceleratingScrollViewForPagingView:(TOPagingView *)pagingView {
    UIScrollView *originalScrollView = pagingView.scrollView;
    TOUnitTestDeceleratingScrollView *scrollView = [[TOUnitTestDeceleratingScrollView alloc] initWithFrame:originalScrollView.frame];
    scrollView.delegate = originalScrollView.delegate;
    scrollView.pagingEnabled = originalScrollView.pagingEnabled;
    scrollView.bounces = originalScrollView.bounces;
    scrollView.alwaysBounceHorizontal = originalScrollView.alwaysBounceHorizontal;
    scrollView.directionalLockEnabled = originalScrollView.directionalLockEnabled;
    scrollView.keyboardDismissMode = originalScrollView.keyboardDismissMode;
    scrollView.showsHorizontalScrollIndicator = originalScrollView.showsHorizontalScrollIndicator;

    [originalScrollView removeFromSuperview];
    [pagingView setValue:scrollView forKey:@"_scrollView"];
    ((TOPagingViewAnimator *)[pagingView valueForKey:@"_pageAnimator"]).scrollView = scrollView;
    [pagingView addSubview:scrollView];
    return scrollView;
}

- (CGFloat)activeTimingValueForAnimator:(TOPagingViewAnimator *)animator atTime:(CFTimeInterval)time {
    id timingParameters = [animator valueForKey:@"_activeTiming"];
    SEL valueSelector = NSSelectorFromString(@"valueAtTime:");
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[timingParameters methodSignatureForSelector:valueSelector]];
    CGFloat value = 0.0f;
    invocation.selector = valueSelector;
    [invocation setArgument:&time atIndex:2];
    [invocation invokeWithTarget:timingParameters];
    [invocation getReturnValue:&value];
    return value;
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

- (void)testInitCreatesConfiguredScrollView {
    TOPagingView *pagingView = [[TOPagingView alloc] init];

    XCTAssertNotNil(pagingView.scrollView);
    XCTAssertEqual(pagingView.scrollView.superview, pagingView);
    XCTAssertTrue(pagingView.clipsToBounds);
    XCTAssertEqual(pagingView.pageSpacing, 40.0f);
}

- (void)testInitWithCoderCreatesConfiguredScrollView {
    TOPagingView *originalPagingView = [[TOPagingView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 375.0f, 812.0f)];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:originalPagingView];
    TOPagingView *pagingView = [NSKeyedUnarchiver unarchiveObjectWithData:data];
#pragma clang diagnostic pop

    XCTAssertNotNil(pagingView);
    XCTAssertNotNil(pagingView.scrollView);
    XCTAssertEqual(pagingView.scrollView.superview, pagingView);
    XCTAssertEqual(pagingView.pageSpacing, 40.0f);
}

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

- (void)testTurnToLeftPageNoOpsAtLeftBoundaryWhenNotAnimated {
    _dataSource.minIndex = 0;
    _dataSource.currentIndex = 0;
    [self.pagingView reload];
    [self.pagingView layoutIfNeeded];

    [self.pagingView turnToLeftPageAnimated:NO];

    XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageNumber, 0);
}

- (void)testTurnToRightPageNoOpsAtRightBoundaryWhenNotAnimated {
    _dataSource.maxIndex = 0;
    _dataSource.currentIndex = 0;
    [self.pagingView reload];
    [self.pagingView layoutIfNeeded];

    [self.pagingView turnToRightPageAnimated:NO];

    XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageNumber, 0);
}

- (void)testTurnToLeftPageStopsRubberBandWhenMissingPageAppears {
    _dataSource.minIndex = 0;
    _dataSource.currentIndex = 0;
    [self.pagingView reload];
    [self.pagingView layoutIfNeeded];

    [self.pagingView turnToLeftPageAnimated:YES];
    _dataSource.minIndex = -1;
    [self.pagingView turnToLeftPageAnimated:NO];

    XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageNumber, -1);
}

- (void)testTurnToRightPageStopsRubberBandWhenMissingPageAppears {
    _dataSource.maxIndex = 0;
    _dataSource.currentIndex = 0;
    [self.pagingView reload];
    [self.pagingView layoutIfNeeded];

    [self.pagingView turnToRightPageAnimated:YES];
    _dataSource.maxIndex = 1;
    [self.pagingView turnToRightPageAnimated:NO];

    XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageNumber, 1);
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

- (void)testDragInteractionIgnoresUnmovedDragOffset {
    id<UIScrollViewDelegate> scrollViewDelegate = self.pagingView.scrollView.delegate;
    NSInteger countBefore = _testDelegate.willTurnCallCount;

    [scrollViewDelegate scrollViewWillBeginDragging:self.pagingView.scrollView];
    [scrollViewDelegate scrollViewDidScroll:self.pagingView.scrollView];
    [scrollViewDelegate scrollViewDidScroll:self.pagingView.scrollView];
    [scrollViewDelegate scrollViewDidEndDragging:self.pagingView.scrollView willDecelerate:NO];

    XCTAssertEqual(_testDelegate.willTurnCallCount, countBefore);
}

- (void)testDragInteractionNoOpsWithoutWillTurnDelegate {
    self.pagingView.delegate = nil;
    id<UIScrollViewDelegate> scrollViewDelegate = self.pagingView.scrollView.delegate;

    [scrollViewDelegate scrollViewWillBeginDragging:self.pagingView.scrollView];
    [scrollViewDelegate scrollViewDidScroll:self.pagingView.scrollView];
    [scrollViewDelegate scrollViewDidEndDragging:self.pagingView.scrollView willDecelerate:NO];

    XCTAssertNil(self.pagingView.delegate);
}

- (void)testDragBeginStopsInProgressPageAnimatorAndNotifiesScrollDelegate {
    TOUnitTestScrollViewDelegate *scrollViewDelegate = [[TOUnitTestScrollViewDelegate alloc] init];
    self.pagingView.scrollViewDelegate = scrollViewDelegate;
    TOPagingViewAnimator *animator = [self.pagingView valueForKey:@"_pageAnimator"];

    [self.pagingView turnToRightPageAnimated:YES];
    XCTAssertTrue(animator.isAnimating);

    [(id<UIScrollViewDelegate>)self.pagingView.scrollView.delegate scrollViewWillBeginDragging:self.pagingView.scrollView];

    XCTAssertFalse(animator.isAnimating);
    XCTAssertEqual(scrollViewDelegate.didEndScrollingAnimationCallCount, 1);
}

#pragma mark - Keyboard

- (void)testArrowKeyPressesTurnPages {
    TOUnitTestKeyboardPagingView *pagingView = [[TOUnitTestKeyboardPagingView alloc] init];
    UIKeyCommand *leftArrowCommand = [UIKeyCommand keyCommandWithInput:UIKeyInputLeftArrow
                                                         modifierFlags:0
                                                                action:@selector(arrowKeyPressed:)];
    [pagingView arrowKeyPressed:leftArrowCommand];

    XCTAssertEqual(pagingView.leftTurnCallCount, 1);
    XCTAssertEqual(pagingView.rightTurnCallCount, 0);
    XCTAssertTrue(pagingView.lastTurnWasAnimated);

    UIKeyCommand *rightArrowCommand = [UIKeyCommand keyCommandWithInput:UIKeyInputRightArrow
                                                          modifierFlags:0
                                                                 action:@selector(arrowKeyPressed:)];
    [pagingView arrowKeyPressed:rightArrowCommand];

    XCTAssertEqual(pagingView.leftTurnCallCount, 1);
    XCTAssertEqual(pagingView.rightTurnCallCount, 1);
    XCTAssertTrue(pagingView.lastTurnWasAnimated);

    UIKeyCommand *ignoredCommand = [UIKeyCommand keyCommandWithInput:@"x"
                                                       modifierFlags:0
                                                              action:@selector(arrowKeyPressed:)];
    [pagingView arrowKeyPressed:ignoredCommand];

    XCTAssertEqual(pagingView.leftTurnCallCount, 1);
    XCTAssertEqual(pagingView.rightTurnCallCount, 1);
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

- (void)testReloadAdjacentPagesSkipsPreviousFetchInAdaptiveInitialMode {
    TOUnitTestDataSource *dataSource = [[TOUnitTestDataSource alloc] init];
    [self installPagingViewWithDataSource:dataSource configure:^(TOPagingView *pagingView) {
        pagingView.isAdaptivePageDirectionEnabled = YES;
    }];
    [dataSource.requestedPageTypes removeAllObjects];

    [self.pagingView reloadAdjacentPages];

    XCTAssertEqualObjects(dataSource.requestedPageTypes, (@[@(TOPagingViewPageTypeNext)]));
    XCTAssertNil(self.pagingView.previousPageView);
    XCTAssertNotNil(self.pagingView.nextPageView);
}

- (void)testReloadDoesNotRemovePrivateScrollViewSubviews {
    UIView *privateSubview = TOCreatePrivateScrollViewSubview();
    [self.pagingView.scrollView addSubview:privateSubview];

    [self.pagingView reload];

    XCTAssertEqual(privateSubview.superview, self.pagingView.scrollView);
}

#pragma mark - Pending Page Requests

- (void)testPendingPageRequestsProcessBothSidesWhenNextAndPreviousArePending {
    [self.pagingView setValue:@(YES) forKey:@"needsNextPage"];
    [self.pagingView setValue:@(YES) forKey:@"needsPreviousPage"];

    [self.pagingView setNeedsLayout];
    [self.pagingView layoutIfNeeded];

    XCTAssertFalse([[self.pagingView valueForKey:@"needsNextPage"] boolValue]);
    XCTAssertFalse([[self.pagingView valueForKey:@"needsPreviousPage"] boolValue]);
    XCTAssertNotNil(self.pagingView.nextPageView);
    XCTAssertNotNil(self.pagingView.previousPageView);
}

- (void)testPendingPreviousPageRequestIsClearedOnAdaptiveInitialPage {
    TOUnitTestDataSource *dataSource = [[TOUnitTestDataSource alloc] init];
    [self installPagingViewWithDataSource:dataSource configure:^(TOPagingView *pagingView) {
        pagingView.isAdaptivePageDirectionEnabled = YES;
    }];
    [self.pagingView setValue:@(YES) forKey:@"needsPreviousPage"];

    [self.pagingView setNeedsLayout];
    [self.pagingView layoutIfNeeded];

    XCTAssertFalse([[self.pagingView valueForKey:@"needsPreviousPage"] boolValue]);
    XCTAssertNil(self.pagingView.previousPageView);
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

- (void)testResizeDuringProgrammaticTurnStopsAnimationAndRecenters {
    [self.pagingView turnToNextPageAnimated:YES];

    self.pagingView.frame = CGRectMake(0.0f, 0.0f, 414.0f, 812.0f);
    [self.pagingView layoutIfNeeded];

    XCTAssertEqualWithAccuracy(self.pagingView.scrollView.contentOffset.x,
                               self.pagingView.scrollView.bounds.size.width,
                               0.5);
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

- (void)testFetchAdjacentPagesNoOpsWithoutDataSource {
    self.pagingView.dataSource = nil;
    NSInteger callCount = _dataSource.dataSourceCallCount;

    [self.pagingView fetchAdjacentPagesIfAvailable];

    XCTAssertEqual(_dataSource.dataSourceCallCount, callCount);
    XCTAssertNil(self.pagingView.currentPageView);
    XCTAssertNil(self.pagingView.nextPageView);
    XCTAssertNil(self.pagingView.previousPageView);
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

- (void)testFetchAdjacentPagesInAdaptiveInitialModeKeepsPreviousMirroredToNext {
    TOUnitTestDataSource *dataSource = [[TOUnitTestDataSource alloc] init];
    [self installPagingViewWithDataSource:dataSource configure:^(TOPagingView *pagingView) {
        pagingView.isAdaptivePageDirectionEnabled = YES;
    }];
    [dataSource.requestedPageTypes removeAllObjects];

    [self.pagingView fetchAdjacentPagesIfAvailable];

    XCTAssertEqualObjects(dataSource.requestedPageTypes, (@[]));
    XCTAssertNil(self.pagingView.previousPageView);
    XCTAssertNotNil(self.pagingView.nextPageView);
}

- (void)testAdaptiveInitialLayoutCanCommitBackToLeftToRightDirection {
    TOUnitTestDataSource *dataSource = [[TOUnitTestDataSource alloc] init];
    [self installPagingViewWithDataSource:dataSource configure:^(TOPagingView *pagingView) {
        pagingView.pageScrollDirection = TOPagingViewDirectionRightToLeft;
        pagingView.isAdaptivePageDirectionEnabled = YES;
    }];
    _testDelegate.directionChangeCallCount = 0;

    const CGFloat pageWidth = self.pagingView.scrollView.bounds.size.width;
    self.pagingView.scrollView.contentOffset = CGPointMake(pageWidth * 2.0f, 0.0f);
    [self.pagingView layoutIfNeeded];

    XCTAssertEqual(self.pagingView.pageScrollDirection, TOPagingViewDirectionLeftToRight);
    XCTAssertEqual(_testDelegate.lastDirection, TOPagingViewDirectionLeftToRight);
    XCTAssertGreaterThan(_testDelegate.directionChangeCallCount, 0);
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

- (void)testCompletedPageAnimatorRebasesToActualOffsetWhenPageTransitionCommits {
    TOPagingViewAnimator *animator = [self.pagingView valueForKey:@"_pageAnimator"];
    animator.duration = 0.0f;

    [self.pagingView turnToRightPageAnimated:YES];
    XCTAssertTrue(animator.isAnimating);

    const CGFloat pageWidth = self.pagingView.scrollView.contentSize.width / 3.0f;
    self.pagingView.scrollView.contentOffset = CGPointMake(pageWidth + 2.0f, 0.0f);
    [(id<UIScrollViewDelegate>)self.pagingView.scrollView.delegate scrollViewDidScroll:self.pagingView.scrollView];

    const CGFloat expectedOffset = self.pagingView.scrollView.contentOffset.x;
    XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageNumber, 1);
    XCTAssertEqualWithAccuracy([self activeTimingValueForAnimator:animator atTime:0.0f], expectedOffset, 0.001f);

    [self.pagingView reload];
}

- (void)testSkipForwardToNewPageCancelsDeceleratingScrollView {
    TOUnitTestDataSource *dataSource = [[TOUnitTestDataSource alloc] init];
    __block TOUnitTestDeceleratingScrollView *scrollView = nil;
    [self installPagingViewWithDataSource:dataSource configure:^(TOPagingView *pagingView) {
        scrollView = [self replaceScrollViewWithDeceleratingScrollViewForPagingView:pagingView];
    }];
    dataSource.currentIndex = 42;
    scrollView.deceleratingForUnitTest = YES;

    [self.pagingView skipForwardToNewPageAnimated:NO];
    [self.pagingView layoutIfNeeded];

    XCTAssertEqual(scrollView.cancelDecelerationCallCount, 1);
    XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageNumber, 42);
}

- (void)testSkipBackwardToNewPageAnimatedRunsCompletionAndRefreshesAdjacentPages {
    TOUnitTestScrollViewDelegate *scrollViewDelegate = [[TOUnitTestScrollViewDelegate alloc] init];
    self.pagingView.scrollViewDelegate = scrollViewDelegate;
    _dataSource.currentIndex = -42;

    [self.pagingView skipBackwardToNewPageAnimated:YES];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Animated skip completed"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.pagingView layoutIfNeeded];
        XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageNumber, -42);
        XCTAssertEqual(TOTestPageView(self.pagingView.previousPageView).pageNumber, -43);
        XCTAssertEqual(TOTestPageView(self.pagingView.nextPageView).pageNumber, -41);
        XCTAssertEqual(scrollViewDelegate.didEndScrollingAnimationCallCount, 1);
        XCTAssertEqualWithAccuracy(self.pagingView.scrollView.contentOffset.x, self.pagingView.scrollView.bounds.size.width, 0.5);
        [expectation fulfill];
    });
    [self waitForExpectationsWithTimeout:2.0 handler:nil];
}

#pragma mark - Scroll View Delegate

- (void)testScrollViewDelegateGetterReturnsExternalDelegate {
    TOUnitTestScrollViewDelegate *scrollViewDelegate = [[TOUnitTestScrollViewDelegate alloc] init];

    self.pagingView.scrollViewDelegate = scrollViewDelegate;

    XCTAssertEqual(self.pagingView.scrollViewDelegate, scrollViewDelegate);
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
