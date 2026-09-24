//
//  TOPagingViewUITests.m
//  TOPagingViewUITests
//
//  Created by Codex on 2026/03/24.
//

#import <XCTest/XCTest.h>

static NSString *const kTOPagingViewAccessibilityIdentifier = @"paging_view";
static NSString *const kTODirectionButtonAccessibilityIdentifier = @"direction_button";
static NSString *const kTOLaunchArgumentAdaptive = @"--topaging-adaptive";
static NSString *const kTOLaunchArgumentMaxPage = @"--topaging-max-page";

@interface TOPagingViewUITests : XCTestCase
@property (nonatomic, strong) XCUIApplication *app;
@end

@implementation TOPagingViewUITests

- (void)setUp {
    [super setUp];
    self.continueAfterFailure = NO;
    self.app = [[XCUIApplication alloc] init];
}

- (void)tearDown {
    [[XCUIDevice sharedDevice] setOrientation:UIDeviceOrientationLandscapeRight];
    self.app = nil;
    [super tearDown];
}

- (XCUIElement *)_launchPagingViewWithArguments:(NSArray<NSString *> *)arguments {
    self.app.launchArguments = arguments;
    // Launch into the test orientation so the first gesture doesn't race a window rotation.
    [[XCUIDevice sharedDevice] setOrientation:UIDeviceOrientationLandscapeRight];
    [self.app launch];

    XCUIElement *const pagingView = self.app.otherElements[kTOPagingViewAccessibilityIdentifier];
    XCTAssertTrue([pagingView waitForExistenceWithTimeout:5.0]);
    XCTAssertTrue([self _waitForPagingView:pagingView toReachPage:0 maxOffsetError:0.5f timeout:5.0],
                  @"Initial paging state was %@",
                  pagingView.value);
    return pagingView;
}

- (nullable NSDictionary<NSString *, NSNumber *> *)_pagingStateForElement:(XCUIElement *)pagingView {
    id const rawValue = pagingView.value;
    if (![rawValue isKindOfClass:NSString.class]) {
        return nil;
    }

    NSString *const value = (NSString *)rawValue;
    NSArray<NSString *> *const components = [value componentsSeparatedByString:@";"];
    if (components.count < 2) {
        return nil;
    }

    NSInteger page = NSNotFound;
    CGFloat offset = CGFLOAT_MAX;
    CGFloat peak = 0;
    CGFloat handoff = 0;

    for (NSString *const component in components) {
        NSArray<NSString *> *const parts = [component componentsSeparatedByString:@"="];
        if (parts.count != 2) {
            continue;
        }

        NSString *const key = parts.firstObject;
        NSString *const stringValue = parts.lastObject;
        if ([key isEqualToString:@"page"]) {
            page = stringValue.integerValue;
        } else if ([key isEqualToString:@"offset"]) {
            offset = (CGFloat)stringValue.doubleValue;
        } else if ([key isEqualToString:@"peak"]) {
            peak = (CGFloat)stringValue.doubleValue;
        } else if ([key isEqualToString:@"handoff"]) {
            handoff = (CGFloat)stringValue.doubleValue;
        }
    }

    if (page == NSNotFound || offset == CGFLOAT_MAX) {
        return nil;
    }

    return @{@"page": @(page), @"offset": @(offset), @"peak": @(peak), @"handoff": @(handoff)};
}

- (BOOL)_waitForPagingView:(XCUIElement *)pagingView
               toReachPage:(NSInteger)page
            maxOffsetError:(CGFloat)maxOffsetError
                   timeout:(NSTimeInterval)timeout {
    NSDate *const deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];

    while (deadline.timeIntervalSinceNow > 0.0) {
        NSDictionary<NSString *, NSNumber *> *const state = [self _pagingStateForElement:pagingView];
        if (state != nil) {
            const NSInteger currentPage = state[@"page"].integerValue;
            const CGFloat offset = state[@"offset"].doubleValue;
            if (currentPage == page && fabs(offset) <= maxOffsetError) {
                return YES;
            }
        }

        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }

    return NO;
}

- (void)_dragPagingView:(XCUIElement *)pagingView fromNormalizedPoint:(CGVector)startPoint toNormalizedPoint:(CGVector)endPoint {
    XCUICoordinate *const dragStart = [pagingView coordinateWithNormalizedOffset:startPoint];
    XCUICoordinate *const dragEnd = [pagingView coordinateWithNormalizedOffset:endPoint];
    [dragStart pressForDuration:0.05 thenDragToCoordinate:dragEnd];
}

- (void)testRepeatedRightTapsStopAtBookBoundaryInLandscape {
    XCUIElement *const pagingView = [self _launchPagingViewWithArguments:@[]];

    XCUICoordinate *const rightTapCoordinate = [pagingView coordinateWithNormalizedOffset:CGVectorMake(0.9, 0.5)];
    for (NSInteger i = 0; i < 16; i++) {
        [rightTapCoordinate tap];
    }

    XCTAssertTrue([self _waitForPagingView:pagingView toReachPage:10 maxOffsetError:0.5f timeout:5.0],
                  @"Final paging state was %@",
                  pagingView.value);
}

- (void)testDraggingMidAnimationCancelsProgrammaticTurnAndHandsOffToPaging {
    XCUIElement *const pagingView = [self _launchPagingViewWithArguments:@[@"--topaging-test-drag-handoff"]];
    XCUICoordinate *const start = [pagingView coordinateWithNormalizedOffset:CGVectorMake(0.35, 0.5)];
    XCUICoordinate *const end = [pagingView coordinateWithNormalizedOffset:CGVectorMake(0.95, 0.5)];
    [start pressForDuration:0.15 thenDragToCoordinate:end];

    XCTAssertGreaterThan([self _pagingStateForElement:pagingView][@"handoff"].doubleValue,
                         20.0,
                         @"The drag must interrupt an unfinished turn away from center. State was %@",
                         pagingView.value);

    XCTAssertTrue([self _waitForPagingView:pagingView toReachPage:0 maxOffsetError:0.5f timeout:5.0],
                  @"Final paging state after drag handoff was %@",
                  pagingView.value);
}

- (void)testUserSwipeLeftTurnsToNextPageAndSettles {
    XCUIElement *const pagingView = [self _launchPagingViewWithArguments:@[]];

    [self _dragPagingView:pagingView fromNormalizedPoint:CGVectorMake(0.85, 0.5) toNormalizedPoint:CGVectorMake(0.15, 0.5)];

    XCTAssertTrue([self _waitForPagingView:pagingView toReachPage:1 maxOffsetError:0.5f timeout:5.0],
                  @"Final paging state after left swipe was %@",
                  pagingView.value);
}

- (void)testUserSwipeRightTurnsToPreviousPageAndSettles {
    XCUIElement *const pagingView = [self _launchPagingViewWithArguments:@[]];

    [self _dragPagingView:pagingView fromNormalizedPoint:CGVectorMake(0.15, 0.5) toNormalizedPoint:CGVectorMake(0.85, 0.5)];

    XCTAssertTrue([self _waitForPagingView:pagingView toReachPage:-1 maxOffsetError:0.5f timeout:5.0],
                  @"Final paging state after right swipe was %@",
                  pagingView.value);
}

- (void)testRightEdgeRubberBandSnapsBackToCurrentPage {
    XCUIElement *const pagingView = [self _launchPagingViewWithArguments:@[kTOLaunchArgumentMaxPage, @"0"]];

    XCUICoordinate *const rightTapCoordinate = [pagingView coordinateWithNormalizedOffset:CGVectorMake(0.9, 0.5)];
    [rightTapCoordinate tap];

    XCTAssertGreaterThan([self _pagingStateForElement:pagingView][@"peak"].doubleValue,
                         1.0,
                         @"Paging view never rubber-banded away from center. State was %@",
                         pagingView.value);
    XCTAssertTrue([self _waitForPagingView:pagingView toReachPage:0 maxOffsetError:0.5f timeout:5.0],
                  @"Final paging state after rubber-band was %@",
                  pagingView.value);
}

- (void)testAdaptiveInitialRightSwipeCommitsToLeftDirection {
    XCUIElement *const pagingView = [self _launchPagingViewWithArguments:@[kTOLaunchArgumentAdaptive]];

    [self _dragPagingView:pagingView fromNormalizedPoint:CGVectorMake(0.15, 0.5) toNormalizedPoint:CGVectorMake(0.85, 0.5)];

    XCTAssertTrue([self _waitForPagingView:pagingView toReachPage:1 maxOffsetError:0.5f timeout:5.0],
                  @"Final paging state after adaptive right swipe was %@",
                  pagingView.value);
    XCTAssertEqualObjects(self.app.buttons[kTODirectionButtonAccessibilityIdentifier].label, @"Left");
}

- (void)testDirectionToggleMakesRightTapTurnToPreviousPage {
    XCUIElement *const pagingView = [self _launchPagingViewWithArguments:@[]];
    XCUIElement *const directionButton = self.app.buttons[kTODirectionButtonAccessibilityIdentifier];
    XCTAssertTrue([directionButton waitForExistenceWithTimeout:5.0]);

    [directionButton tap];
    XCTAssertEqualObjects(directionButton.label, @"Left");

    XCUICoordinate *const rightTapCoordinate = [pagingView coordinateWithNormalizedOffset:CGVectorMake(0.9, 0.5)];
    [rightTapCoordinate tap];

    XCTAssertTrue([self _waitForPagingView:pagingView toReachPage:-1 maxOffsetError:0.5f timeout:5.0],
                  @"Final paging state after RTL right tap was %@",
                  pagingView.value);
}

- (void)testRotationKeepsCurrentPageCentered {
    XCUIElement *const pagingView = [self _launchPagingViewWithArguments:@[]];

    XCUICoordinate *const rightTapCoordinate = [pagingView coordinateWithNormalizedOffset:CGVectorMake(0.9, 0.5)];
    [rightTapCoordinate tap];
    XCTAssertTrue([self _waitForPagingView:pagingView toReachPage:1 maxOffsetError:0.5f timeout:5.0],
                  @"Paging view did not reach page 1 before rotation. State was %@",
                  pagingView.value);

    [[XCUIDevice sharedDevice] setOrientation:UIDeviceOrientationPortrait];
    XCTAssertTrue([self _waitForPagingView:pagingView toReachPage:1 maxOffsetError:0.5f timeout:5.0],
                  @"Paging view did not stay centered after portrait rotation. State was %@",
                  pagingView.value);

    [[XCUIDevice sharedDevice] setOrientation:UIDeviceOrientationLandscapeRight];
    XCTAssertTrue([self _waitForPagingView:pagingView toReachPage:1 maxOffsetError:0.5f timeout:5.0],
                  @"Paging view did not stay centered after landscape rotation. State was %@",
                  pagingView.value);
}

@end
