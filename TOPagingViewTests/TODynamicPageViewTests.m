//
//  TOPagingViewTests.m
//  TOPagingViewTests
//
//  Created by Tim Oliver on 2020/03/23.
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import <XCTest/XCTest.h>

#import "TOPagingView.h"
#import "TOPagingViewAnimator.h"
#import "TOUnitTestDataSource.h"
#import "TOUnitTestDelegate.h"
#import "TOUnitTestHelpers.h"

#pragma mark - Test Helpers

@interface TOPagingView (TOUnitTestKeyboard)
- (void)_arrowKeyPressed:(UIKeyCommand *)command;
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
    if (_deceleratingForUnitTest && !animated) {
        _cancelDecelerationCallCount++;
    }
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
                              configure:(void (^_Nullable)(TOPagingView *pagingView))configure {
    [_pagingView removeFromSuperview];

    _dataSource = dataSource;
    _testDelegate = [[TOUnitTestDelegate alloc] init];
    _pagingView = [[TOPagingView alloc] initWithFrame:_window.bounds];
    _pagingView.delegate = _testDelegate;
    [_pagingView registerPageViewClass:TOUnitTestPageView.class];
    if (configure) {
        configure(_pagingView);
    }
    _pagingView.dataSource = _dataSource;
    [_window addSubview:_pagingView];
    [_pagingView layoutIfNeeded];
}

- (TOUnitTestDeceleratingScrollView *)replaceScrollViewWithDeceleratingScrollViewForPagingView:(TOPagingView *)pagingView {
    UIScrollView *originalScrollView = pagingView.scrollView;
    TOUnitTestDeceleratingScrollView *scrollView =
        [[TOUnitTestDeceleratingScrollView alloc] initWithFrame:originalScrollView.frame];
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

#pragma mark - Animated Turn Commit Counts

/// Spins the main run loop until a page turn animation has settled. The animator
/// runs off a CADisplayLink, so the run loop has to actually turn for frames to fire.
- (void)waitForPageTurnAnimationToSettle {
    XCTestExpectation *settled = [self expectationWithDescription:@"page turn animation settled"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [settled fulfill];
    });
    [self waitForExpectations:@[settled] timeout:5.0];
}

// One tap turns one page, however many frames the animation needs to settle.
// The animator drives the scroll offset frame by frame, so the hazard is frames
// being counted as pages: an animation that lingers near the commit boundary
// while it settles must not rack up a transition on every tick.
- (void)testSingleAnimatedTurnCommitsExactlyOnePage {
    const NSInteger countBefore = _testDelegate.didTurnCallCount;

    [self.pagingView turnToRightPageAnimated:YES];
    [self waitForPageTurnAnimationToSettle];

    XCTAssertEqual(_testDelegate.didTurnCallCount - countBefore, 1, @"A single tap must commit exactly one page turn");
}

/// Pumps the main run loop for `interval`, so display-link frames and layout
/// passes actually happen between simulated taps.
- (void)pumpRunLoopForInterval:(NSTimeInterval)interval {
    XCTestExpectation *elapsed = [self expectationWithDescription:@"run loop pumped"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [elapsed fulfill];
    });
    [self waitForExpectations:@[elapsed] timeout:interval + 3.0];
}

// The counterpart, and the reason the fix can't just be "commit less eagerly":
// tapping again mid-flight is the point. Each tap bumps the destination by a
// page and resets the curve so the pages keep flowing, and N taps must still
// land exactly N pages. Taps are spaced like real ones — firing them in a single
// run-loop turn would never let a frame render or a page refill between them.
- (void)testStackedAnimatedTurnsCommitOnePagePerTap {
    // The pager refills the next page on a deferred layout pass, so the window
    // has to be live or layout never runs and the refill can't happen.
    [_window makeKeyAndVisible];

    const NSInteger countBefore = _testDelegate.didTurnCallCount;

    [self.pagingView turnToRightPageAnimated:YES];
    [self pumpRunLoopForInterval:0.1];
    [self.pagingView turnToRightPageAnimated:YES];
    [self pumpRunLoopForInterval:0.1];
    [self.pagingView turnToRightPageAnimated:YES];
    [self waitForPageTurnAnimationToSettle];

    XCTAssertEqual(_testDelegate.didTurnCallCount - countBefore, 3, @"Three queued taps must land exactly three pages");
}

- (void)testEachTapRestartsOneDurationForAllQueuedPages {
    [_window makeKeyAndVisible];
    TOPagingViewAnimator *animator = [self.pagingView valueForKey:@"_pageAnimator"];
    for (NSNumber *tapLeft in @[@NO, @YES]) {
        // One page, queued bursts, and mid-flight taps all share one duration after the final tap.
        // The large burst also crosses multiple recycled slots within a single animation frame.
        for (NSArray<NSNumber *> *scenario in @[@[@1, @0.0], @[@3, @0.0], @[@3, @0.15], @[@100, @0.0]]) {
            [self.pagingView reload];
            [self.pagingView layoutIfNeeded];
            const NSInteger turns = scenario[0].integerValue;
            const NSTimeInterval interval = scenario[1].doubleValue;
            const NSInteger countBefore = _testDelegate.didTurnCallCount;
            CFTimeInterval lastTapTime = 0;
            for (NSInteger tap = 0; tap < turns; tap++) {
                const CGFloat offset = self.pagingView.scrollView.contentOffset.x;
                lastTapTime = CACurrentMediaTime();
                if (tapLeft.boolValue) {
                    [self.pagingView turnToLeftPageAnimated:YES];
                } else {
                    [self.pagingView turnToRightPageAnimated:YES];
                }
                XCTAssertEqual(self.pagingView.scrollView.contentOffset.x, offset, @"Retargeting must not jump the page");
                if (tap + 1 < turns && interval > 0) {
                    [self pumpRunLoopForInterval:interval];
                }
            }

            XCTestExpectation *completed = [self expectationWithDescription:@"The entire queued journey completed"];
            __block CFTimeInterval completionTime = 0;
            void (^originalCompletion)(void) = animator.completionHandler;
            animator.completionHandler = ^{
                completionTime = CACurrentMediaTime();
                if (originalCompletion) {
                    originalCompletion();
                }
                [completed fulfill];
            };
            [self waitForExpectations:@[completed] timeout:2.0];

            // Allow frame scheduling tolerance while rejecting both the original deadline
            // and a separate animation duration for each queued page.
            const CFTimeInterval elapsed = completionTime - lastTapTime;
            XCTAssertGreaterThanOrEqual(elapsed, animator.duration - 0.04);
            XCTAssertLessThanOrEqual(elapsed, animator.duration + 0.15);
            XCTAssertEqual(_testDelegate.didTurnCallCount - countBefore, turns);
            XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageNumber, tapLeft.boolValue ? -turns : turns);
            XCTAssertEqualWithAccuracy(
                self.pagingView.scrollView.contentOffset.x, self.pagingView.scrollView.bounds.size.width, 0.5);
            XCTAssertFalse(animator.isAnimating);
            XCTAssertTrue(self.pagingView.scrollView.pagingEnabled);
        }
    }
}

// A missing page becomes available before the tap. Keep both edges unavailable
// initially: an available previous page used to mask the stale forward bounce.
- (void)testTurnCommitsOnePageAfterAMissingPageLaterArrives {
    [_window makeKeyAndVisible];

    _dataSource.minIndex = 0;
    _dataSource.maxIndex = 0;
    _dataSource.currentIndex = 0;
    [self.pagingView reload];
    [self.pagingView layoutIfNeeded];

    // The page finishes loading, and the pager picks it up: _hasNextPage is YES again.
    _dataSource.maxIndex = 10;
    [self.pagingView fetchAdjacentPagesIfAvailable];
    [self.pagingView layoutIfNeeded];

    const NSInteger countBefore = _testDelegate.didTurnCallCount;
    [self.pagingView turnToRightPageAnimated:YES];
    [self waitForPageTurnAnimationToSettle];

    XCTAssertEqual(_testDelegate.didTurnCallCount - countBefore,
                   1,
                   @"A real turn must commit one page even if an earlier failed fetch armed the rubber band");
}

#pragma mark - Edge Bounce Regressions

- (void)waitForEdgeBounceToStart {
    TOPagingViewAnimator *animator = [self.pagingView valueForKey:@"_pageAnimator"];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    // XCTest's predicate polling can miss the entire sub-second spring animation.
    while (deadline.timeIntervalSinceNow > 0.0) {
        if (animator.isRubberBanding) {
            return;
        }
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    XCTFail(@"The edge tap did not start a bounce");
}

- (void)assertSettledOnPage:(NSInteger)page turnsSince:(NSInteger)countBefore expectedTurns:(NSInteger)expectedTurns {
    [self waitForPageTurnAnimationToSettle];
    XCTAssertEqual(_testDelegate.didTurnCallCount - countBefore, expectedTurns);
    XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageNumber, page);
    XCTAssertEqualWithAccuracy(self.pagingView.scrollView.contentOffset.x, self.pagingView.scrollView.bounds.size.width, 0.5);
    XCTAssertFalse(((TOPagingViewAnimator *)[self.pagingView valueForKey:@"_pageAnimator"]).isAnimating);
    XCTAssertTrue(self.pagingView.scrollView.pagingEnabled);
}

- (void)testSingleTurnAwayFromEitherBookBoundaryCommitsOnePageInBothDirections {
    [_window makeKeyAndVisible];
    for (NSNumber *reversed in @[@NO, @YES]) {
        self.pagingView.pageScrollDirection =
            reversed.boolValue ? TOPagingViewDirectionRightToLeft : TOPagingViewDirectionLeftToRight;
        for (NSNumber *fromLastPage in @[@NO, @YES]) {
            _dataSource.minIndex = 0;
            _dataSource.maxIndex = 10;
            _dataSource.currentIndex = fromLastPage.boolValue ? 10 : 0;
            [self.pagingView reload];
            [self.pagingView layoutIfNeeded];
            const NSInteger before = _testDelegate.didTurnCallCount;

            if (fromLastPage.boolValue) {
                [self.pagingView turnToPreviousPageAnimated:YES];
            } else {
                [self.pagingView turnToNextPageAnimated:YES];
            }

            [self assertSettledOnPage:fromLastPage.boolValue ? 9 : 1 turnsSince:before expectedTurns:1];
        }
    }
}

- (void)testAsyncPageArrivesBeforeAdaptiveInitialTapInEitherDirection {
    [_window makeKeyAndVisible];
    self.pagingView.isAdaptivePageDirectionEnabled = YES;
    for (NSNumber *tapLeft in @[@NO, @YES]) {
        self.pagingView.pageScrollDirection = TOPagingViewDirectionLeftToRight;
        _dataSource.minIndex = 0;
        _dataSource.maxIndex = 0;
        [self.pagingView reload];
        [self.pagingView layoutIfNeeded];

        _dataSource.maxIndex = 10;
        [self.pagingView fetchAdjacentPagesIfAvailable];
        const NSInteger before = _testDelegate.didTurnCallCount;
        if (tapLeft.boolValue) {
            [self.pagingView turnToLeftPageAnimated:YES];
        } else {
            [self.pagingView turnToRightPageAnimated:YES];
        }

        [self assertSettledOnPage:1 turnsSince:before expectedTurns:1];
        XCTAssertEqual(self.pagingView.pageScrollDirection,
                       tapLeft.boolValue ? TOPagingViewDirectionRightToLeft : TOPagingViewDirectionLeftToRight);
    }
}

- (void)testPagesArrivingDuringBounceDoNotCommitUntilAnotherTap {
    [_window makeKeyAndVisible];
    for (NSNumber *reversed in @[@NO, @YES]) {
        self.pagingView.pageScrollDirection =
            reversed.boolValue ? TOPagingViewDirectionRightToLeft : TOPagingViewDirectionLeftToRight;
        for (NSNumber *reloadAdjacent in @[@NO, @YES]) {
            _dataSource.minIndex = 0;
            _dataSource.maxIndex = 0;
            [self.pagingView reload];
            [self.pagingView layoutIfNeeded];
            const NSInteger before = _testDelegate.didTurnCallCount;

            [self.pagingView turnToNextPageAnimated:YES];
            [self waitForEdgeBounceToStart];
            _dataSource.maxIndex = 10;
            if (reloadAdjacent.boolValue) {
                [self.pagingView reloadAdjacentPages];
            } else {
                [self.pagingView fetchAdjacentPagesIfAvailable];
            }

            [self assertSettledOnPage:0 turnsSince:before expectedTurns:0];
            [self.pagingView turnToNextPageAnimated:YES];
            [self assertSettledOnPage:1 turnsSince:before expectedTurns:1];
        }
    }
}

- (void)testTapRedirectsActiveBounceAfterAsyncPageArrival {
    [_window makeKeyAndVisible];
    for (NSNumber *tapLeft in @[@NO, @YES]) {
        for (NSNumber *refreshBeforeTap in @[@NO, @YES]) {
            _dataSource.minIndex = 0;
            _dataSource.maxIndex = 0;
            [self.pagingView reload];
            [self.pagingView layoutIfNeeded];
            const NSInteger before = _testDelegate.didTurnCallCount;

            if (tapLeft.boolValue) {
                [self.pagingView turnToLeftPageAnimated:YES];
            } else {
                [self.pagingView turnToRightPageAnimated:YES];
            }
            [self waitForEdgeBounceToStart];
            _dataSource.minIndex = -10;
            _dataSource.maxIndex = 10;
            if (refreshBeforeTap.boolValue) {
                [self.pagingView fetchAdjacentPagesIfAvailable];
            }
            XCTAssertEqual(_testDelegate.didTurnCallCount, before);

            if (tapLeft.boolValue) {
                [self.pagingView turnToLeftPageAnimated:YES];
            } else {
                [self.pagingView turnToRightPageAnimated:YES];
            }
            [self assertSettledOnPage:tapLeft.boolValue ? -1 : 1 turnsSince:before expectedTurns:1];
        }
    }
}

- (void)testReloadAdjacentBeforeFirstFrameUsesOnlyTheRequestedEdge {
    [_window makeKeyAndVisible];
    for (NSNumber *hasNextPage in @[@NO, @YES]) {
        _dataSource.minIndex = hasNextPage.boolValue ? 0 : -10;
        _dataSource.maxIndex = hasNextPage.boolValue ? 10 : 0;
        [self.pagingView reload];
        [self.pagingView layoutIfNeeded];
        const NSInteger before = _testDelegate.didTurnCallCount;

        [self.pagingView turnToNextPageAnimated:YES];
        [self.pagingView reloadAdjacentPages];

        const NSInteger expectedTurns = hasNextPage.boolValue ? 1 : 0;
        [self assertSettledOnPage:expectedTurns turnsSince:before expectedTurns:expectedTurns];
    }
}

- (void)testAdaptiveBounceDoesNotCommitDirectionWhenPageArrives {
    [_window makeKeyAndVisible];
    self.pagingView.isAdaptivePageDirectionEnabled = YES;
    _dataSource.minIndex = 0;
    _dataSource.maxIndex = 0;
    [self.pagingView reload];
    [self.pagingView layoutIfNeeded];
    const NSInteger before = _testDelegate.didTurnCallCount;

    [self.pagingView turnToLeftPageAnimated:YES];
    [self waitForEdgeBounceToStart];
    _dataSource.maxIndex = 10;
    [self.pagingView fetchAdjacentPagesIfAvailable];

    [self assertSettledOnPage:0 turnsSince:before expectedTurns:0];
    XCTAssertEqual(self.pagingView.pageScrollDirection, TOPagingViewDirectionLeftToRight);
    XCTAssertEqual(_testDelegate.directionChangeCallCount, 0);
    [self.pagingView turnToLeftPageAnimated:YES];
    [self assertSettledOnPage:1 turnsSince:before expectedTurns:1];
    XCTAssertEqual(self.pagingView.pageScrollDirection, TOPagingViewDirectionRightToLeft);
}

- (void)testReversingBounceOnSinglePageStillSettlesAtCenter {
    [_window makeKeyAndVisible];
    _dataSource.minIndex = 0;
    _dataSource.maxIndex = 0;
    [self.pagingView reload];
    [self.pagingView layoutIfNeeded];
    const NSInteger before = _testDelegate.didTurnCallCount;

    [self.pagingView turnToRightPageAnimated:YES];
    [self waitForEdgeBounceToStart];
    [self.pagingView turnToLeftPageAnimated:YES];
    [self assertSettledOnPage:0 turnsSince:before expectedTurns:0];
}

- (void)testRepeatedEdgeTapsPreserveOffsetAndCompleteOnce {
    [_window makeKeyAndVisible];
    _dataSource.minIndex = 0;
    _dataSource.maxIndex = 0;
    TOUnitTestScrollViewDelegate *scrollDelegate = [[TOUnitTestScrollViewDelegate alloc] init];
    self.pagingView.scrollViewDelegate = scrollDelegate;
    for (NSNumber *tapLeft in @[@NO, @YES]) {
        [self.pagingView reload];
        const NSInteger before = _testDelegate.didTurnCallCount;
        const NSInteger completionsBefore = scrollDelegate.didEndScrollingAnimationCallCount;
        if (tapLeft.boolValue) {
            [self.pagingView turnToLeftPageAnimated:YES];
        } else {
            [self.pagingView turnToRightPageAnimated:YES];
        }
        [self waitForEdgeBounceToStart];

        const CGFloat offset = self.pagingView.scrollView.contentOffset.x;
        for (NSInteger tap = 0; tap < 8; tap++) {
            if (tapLeft.boolValue) {
                [self.pagingView turnToLeftPageAnimated:YES];
            } else {
                [self.pagingView turnToRightPageAnimated:YES];
            }
            XCTAssertEqual(self.pagingView.scrollView.contentOffset.x,
                           offset,
                           @"Re-energizing the spring must not jump its visible position");
        }
        [self assertSettledOnPage:0 turnsSince:before expectedTurns:0];
        XCTAssertEqual(scrollDelegate.didEndScrollingAnimationCallCount - completionsBefore, 1);
    }
}

- (void)testRepeatedEdgeTapsWithZeroDurationStillSettle {
    [_window makeKeyAndVisible];
    _dataSource.minIndex = 0;
    _dataSource.maxIndex = 0;
    [self.pagingView reload];
    const NSInteger before = _testDelegate.didTurnCallCount;
    TOPagingViewAnimator *animator = [self.pagingView valueForKey:@"_pageAnimator"];
    animator.duration = 0.0;

    [self.pagingView turnToRightPageAnimated:YES];
    [self waitForEdgeBounceToStart];
    for (NSInteger tap = 0; tap < 4; tap++) {
        [self.pagingView turnToRightPageAnimated:YES];
    }
    [self assertSettledOnPage:0 turnsSince:before expectedTurns:0];
}

- (void)testStackedTurnsStopAtLastPageAndAllowTurningBack {
    [_window makeKeyAndVisible];
    _dataSource.minIndex = 0;
    _dataSource.maxIndex = 2;
    [self.pagingView reload];
    [self.pagingView layoutIfNeeded];
    const NSInteger before = _testDelegate.didTurnCallCount;

    for (NSInteger tap = 0; tap < 4; tap++) {
        [self.pagingView turnToNextPageAnimated:YES];
        [self pumpRunLoopForInterval:0.1];
    }
    [self assertSettledOnPage:2 turnsSince:before expectedTurns:2];
    [self.pagingView turnToPreviousPageAnimated:YES];
    [self assertSettledOnPage:1 turnsSince:before expectedTurns:3];
}

- (void)testStackedTurnsBeforeFirstDisplayFrameCommitOnePagePerTap {
    [_window makeKeyAndVisible];
    self.pagingView.frame = CGRectMake(0, 0, 744.5, 768);
    self.pagingView.pageSpacing = 0.5;
    for (NSNumber *reversed in @[@NO, @YES]) {
        self.pagingView.pageScrollDirection =
            reversed.boolValue ? TOPagingViewDirectionRightToLeft : TOPagingViewDirectionLeftToRight;
        [self.pagingView reload];
        [self.pagingView layoutIfNeeded];
        const NSInteger before = _testDelegate.didTurnCallCount;

        // Queue the entire burst before the display link has delivered its first timestamp.
        for (NSInteger tap = 0; tap < 8; tap++) {
            [self.pagingView turnToNextPageAnimated:YES];
        }

        [self assertSettledOnPage:8 turnsSince:before expectedTurns:8];
    }
}

- (void)testStackedTurnsKeepFractionalPageTargetsAligned {
    [_window makeKeyAndVisible];
    self.pagingView.frame = CGRectMake(0, 0, 744.5, 768);
    self.pagingView.pageSpacing = 80.25;
    for (NSNumber *reversed in @[@NO, @YES]) {
        self.pagingView.pageScrollDirection =
            reversed.boolValue ? TOPagingViewDirectionRightToLeft : TOPagingViewDirectionLeftToRight;
        [self.pagingView reload];
        [self.pagingView layoutIfNeeded];
        const NSInteger before = _testDelegate.didTurnCallCount;

        for (NSInteger tap = 0; tap < 6; tap++) {
            [self.pagingView turnToNextPageAnimated:YES];
        }

        [self assertSettledOnPage:6 turnsSince:before expectedTurns:6];
    }
}

- (void)testConsecutiveTurnsRefillSlotsBeforeDeferredLayout {
    for (NSNumber *reversed in @[@NO, @YES]) {
        self.pagingView.pageScrollDirection =
            reversed.boolValue ? TOPagingViewDirectionRightToLeft : TOPagingViewDirectionLeftToRight;
        _dataSource.minIndex = 0;
        _dataSource.maxIndex = 10;
        [self.pagingView reload];
        [self.pagingView layoutIfNeeded];
        const NSInteger before = _testDelegate.didTurnCallCount;

        for (NSInteger tap = 0; tap < 12; tap++) {
            [self.pagingView turnToNextPageAnimated:NO];
        }
        XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageNumber, 10);
        XCTAssertEqual(_testDelegate.didTurnCallCount - before, 10);
        XCTAssertEqualWithAccuracy(self.pagingView.scrollView.contentOffset.x, self.pagingView.scrollView.bounds.size.width, 0.5);

        for (NSInteger tap = 0; tap < 12; tap++) {
            [self.pagingView turnToPreviousPageAnimated:NO];
        }
        XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageNumber, 0);
        XCTAssertEqual(_testDelegate.didTurnCallCount - before, 20);
        XCTAssertEqualWithAccuracy(self.pagingView.scrollView.contentOffset.x, self.pagingView.scrollView.bounds.size.width, 0.5);
    }
}

- (void)testScrollCallbacksRefillSlotsBeforeDeferredLayout {
    for (NSNumber *reversed in @[@NO, @YES]) {
        self.pagingView.pageScrollDirection =
            reversed.boolValue ? TOPagingViewDirectionRightToLeft : TOPagingViewDirectionLeftToRight;
        [self.pagingView reload];
        [self.pagingView layoutIfNeeded];
        const CGFloat width = self.pagingView.scrollView.bounds.size.width;
        const NSInteger before = _testDelegate.didTurnCallCount;

        // Simulate consecutive frame callbacks with no intervening UIKit layout pass.
        for (NSInteger page = 1; page <= 5; page++) {
            self.pagingView.scrollView.contentOffset = CGPointMake(reversed.boolValue ? 0 : width * 2, 0);
            XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageNumber, page);
        }
        for (NSInteger page = 4; page >= 0; page--) {
            self.pagingView.scrollView.contentOffset = CGPointMake(reversed.boolValue ? width * 2 : 0, 0);
            XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageNumber, page);
        }
        XCTAssertEqual(_testDelegate.didTurnCallCount - before, 10);
    }
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
                                                                action:@selector(_arrowKeyPressed:)];
    [pagingView _arrowKeyPressed:leftArrowCommand];

    XCTAssertEqual(pagingView.leftTurnCallCount, 1);
    XCTAssertEqual(pagingView.rightTurnCallCount, 0);
    XCTAssertTrue(pagingView.lastTurnWasAnimated);

    UIKeyCommand *rightArrowCommand = [UIKeyCommand keyCommandWithInput:UIKeyInputRightArrow
                                                          modifierFlags:0
                                                                 action:@selector(_arrowKeyPressed:)];
    [pagingView _arrowKeyPressed:rightArrowCommand];

    XCTAssertEqual(pagingView.leftTurnCallCount, 1);
    XCTAssertEqual(pagingView.rightTurnCallCount, 1);
    XCTAssertTrue(pagingView.lastTurnWasAnimated);

    UIKeyCommand *ignoredCommand = [UIKeyCommand keyCommandWithInput:@"x" modifierFlags:0 action:@selector(_arrowKeyPressed:)];
    [pagingView _arrowKeyPressed:ignoredCommand];

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
    [self installPagingViewWithDataSource:dataSource
                                configure:^(TOPagingView *pagingView) {
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
    [self installPagingViewWithDataSource:dataSource
                                configure:^(TOPagingView *pagingView) {
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

    XCTAssertEqualWithAccuracy(self.pagingView.scrollView.contentOffset.x, self.pagingView.scrollView.bounds.size.width, 0.5);
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
    [self installPagingViewWithDataSource:dataSource
                                configure:^(TOPagingView *pagingView) {
                                    pagingView.isAdaptivePageDirectionEnabled = YES;
                                }];

    XCTAssertEqualObjects(dataSource.requestedPageTypes, (@[@(TOPagingViewPageTypeCurrent), @(TOPagingViewPageTypeNext)]));
    XCTAssertNotNil(self.pagingView.currentPageView);
    XCTAssertNotNil(self.pagingView.nextPageView);
    XCTAssertNil(self.pagingView.previousPageView);
}

- (void)testFetchAdjacentPagesInAdaptiveInitialModeKeepsPreviousMirroredToNext {
    TOUnitTestDataSource *dataSource = [[TOUnitTestDataSource alloc] init];
    [self installPagingViewWithDataSource:dataSource
                                configure:^(TOPagingView *pagingView) {
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
    [self installPagingViewWithDataSource:dataSource
                                configure:^(TOPagingView *pagingView) {
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
    [self waitForPageTurnAnimationToSettle];
    XCTAssertEqualWithAccuracy(self.pagingView.scrollView.contentOffset.x, expectedOffset, 0.001f);
    XCTAssertEqual(TOTestPageView(self.pagingView.currentPageView).pageNumber, 1);

    [self.pagingView reload];
}

- (void)testSkipForwardToNewPageCancelsDeceleratingScrollView {
    TOUnitTestDataSource *dataSource = [[TOUnitTestDataSource alloc] init];
    __block TOUnitTestDeceleratingScrollView *scrollView = nil;
    [self installPagingViewWithDataSource:dataSource
                                configure:^(TOPagingView *pagingView) {
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
