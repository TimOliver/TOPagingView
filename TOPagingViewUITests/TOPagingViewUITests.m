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

- (XCUIElement *)launchPagingViewWithArguments:(NSArray<NSString *> *)arguments {
    self.app.launchArguments = arguments;
    [self.app launch];
    [[XCUIDevice sharedDevice] setOrientation:UIDeviceOrientationLandscapeRight];

    XCUIElement *pagingView = self.app.otherElements[kTOPagingViewAccessibilityIdentifier];
    XCTAssertTrue([pagingView waitForExistenceWithTimeout:5.0]);
    XCTAssertTrue([self waitForPagingView:pagingView toReachPage:0 maxOffsetError:0.5f timeout:5.0],
                  @"Initial paging state was %@",
                  pagingView.value);
    return pagingView;
}

- (nullable NSDictionary<NSString *, NSNumber *> *)pagingStateForElement:(XCUIElement *)pagingView {
    id rawValue = pagingView.value;
    if (![rawValue isKindOfClass:NSString.class]) { return nil; }

    NSString *value = (NSString *)rawValue;
    NSArray<NSString *> *components = [value componentsSeparatedByString:@";"];
    if (components.count < 2) { return nil; }

    NSInteger page = NSNotFound;
    CGFloat offset = CGFLOAT_MAX;

    for (NSString *component in components) {
        NSArray<NSString *> *parts = [component componentsSeparatedByString:@"="];
        if (parts.count != 2) { continue; }

        NSString *key = parts.firstObject;
        NSString *stringValue = parts.lastObject;
        if ([key isEqualToString:@"page"]) {
            page = stringValue.integerValue;
        } else if ([key isEqualToString:@"offset"]) {
            offset = (CGFloat)stringValue.doubleValue;
        }
    }

    if (page == NSNotFound || offset == CGFLOAT_MAX) { return nil; }
    return @{@"page": @(page), @"offset": @(offset)};
}

- (BOOL)waitForPagingView:(XCUIElement *)pagingView
              toReachPage:(NSInteger)page
           maxOffsetError:(CGFloat)maxOffsetError
                  timeout:(NSTimeInterval)timeout {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];

    while (deadline.timeIntervalSinceNow > 0.0) {
        NSDictionary<NSString *, NSNumber *> *state = [self pagingStateForElement:pagingView];
        if (state != nil) {
            const NSInteger currentPage = state[@"page"].integerValue;
            const CGFloat offset = state[@"offset"].doubleValue;
            if (currentPage == page && fabs(offset) <= maxOffsetError) { return YES; }
        }

        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }

    return NO;
}

- (BOOL)waitForPagingView:(XCUIElement *)pagingView
      toExceedOffsetError:(CGFloat)minimumOffsetError
                  timeout:(NSTimeInterval)timeout {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];

    while (deadline.timeIntervalSinceNow > 0.0) {
        NSDictionary<NSString *, NSNumber *> *state = [self pagingStateForElement:pagingView];
        if (state != nil) {
            const CGFloat offset = state[@"offset"].doubleValue;
            if (fabs(offset) >= minimumOffsetError) { return YES; }
        }

        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }

    return NO;
}

- (void)dragPagingView:(XCUIElement *)pagingView
    fromNormalizedPoint:(CGVector)startPoint
      toNormalizedPoint:(CGVector)endPoint {
    XCUICoordinate *dragStart = [pagingView coordinateWithNormalizedOffset:startPoint];
    XCUICoordinate *dragEnd = [pagingView coordinateWithNormalizedOffset:endPoint];
    [dragStart pressForDuration:0.05 thenDragToCoordinate:dragEnd];
}

- (void)testRapidRightTapsLandOnExpectedPageInLandscape {
    XCUIElement *pagingView = [self launchPagingViewWithArguments:@[]];

    XCUICoordinate *rightTapCoordinate = [pagingView coordinateWithNormalizedOffset:CGVectorMake(0.9, 0.5)];
    for (NSInteger i = 0; i < 16; i++) {
        [rightTapCoordinate tap];
    }

    XCTAssertTrue([self waitForPagingView:pagingView toReachPage:10 maxOffsetError:0.5f timeout:5.0],
                  @"Final paging state was %@",
                  pagingView.value);
}

- (void)testDraggingMidAnimationCancelsProgrammaticTurnAndHandsOffToPaging {
    XCUIElement *pagingView = [self launchPagingViewWithArguments:@[]];

    XCUICoordinate *rightTapCoordinate = [pagingView coordinateWithNormalizedOffset:CGVectorMake(0.9, 0.5)];
    [rightTapCoordinate tap];

    XCTAssertTrue([self waitForPagingView:pagingView toExceedOffsetError:20.0f timeout:1.0],
                  @"Paging view never moved far enough off center. State was %@",
                  pagingView.value);

    [self dragPagingView:pagingView fromNormalizedPoint:CGVectorMake(0.35, 0.5) toNormalizedPoint:CGVectorMake(0.95, 0.5)];

    XCTAssertTrue([self waitForPagingView:pagingView toReachPage:0 maxOffsetError:0.5f timeout:5.0],
                  @"Final paging state after drag handoff was %@",
                  pagingView.value);
}

- (void)testUserSwipeLeftTurnsToNextPageAndSettles {
    XCUIElement *pagingView = [self launchPagingViewWithArguments:@[]];

    [self dragPagingView:pagingView fromNormalizedPoint:CGVectorMake(0.85, 0.5) toNormalizedPoint:CGVectorMake(0.15, 0.5)];

    XCTAssertTrue([self waitForPagingView:pagingView toReachPage:1 maxOffsetError:0.5f timeout:5.0],
                  @"Final paging state after left swipe was %@",
                  pagingView.value);
}

- (void)testUserSwipeRightTurnsToPreviousPageAndSettles {
    XCUIElement *pagingView = [self launchPagingViewWithArguments:@[]];

    [self dragPagingView:pagingView fromNormalizedPoint:CGVectorMake(0.15, 0.5) toNormalizedPoint:CGVectorMake(0.85, 0.5)];

    XCTAssertTrue([self waitForPagingView:pagingView toReachPage:-1 maxOffsetError:0.5f timeout:5.0],
                  @"Final paging state after right swipe was %@",
                  pagingView.value);
}

- (void)testRightEdgeRubberBandSnapsBackToCurrentPage {
    XCUIElement *pagingView = [self launchPagingViewWithArguments:@[kTOLaunchArgumentMaxPage, @"0"]];

    XCUICoordinate *rightTapCoordinate = [pagingView coordinateWithNormalizedOffset:CGVectorMake(0.9, 0.5)];
    [rightTapCoordinate tap];

    XCTAssertTrue([self waitForPagingView:pagingView toExceedOffsetError:1.0f timeout:1.0],
                  @"Paging view never rubber-banded away from center. State was %@",
                  pagingView.value);
    XCTAssertTrue([self waitForPagingView:pagingView toReachPage:0 maxOffsetError:0.5f timeout:5.0],
                  @"Final paging state after rubber-band was %@",
                  pagingView.value);
}

- (void)testAdaptiveInitialRightSwipeCommitsToLeftDirection {
    XCUIElement *pagingView = [self launchPagingViewWithArguments:@[kTOLaunchArgumentAdaptive]];

    [self dragPagingView:pagingView fromNormalizedPoint:CGVectorMake(0.15, 0.5) toNormalizedPoint:CGVectorMake(0.85, 0.5)];

    XCTAssertTrue([self waitForPagingView:pagingView toReachPage:1 maxOffsetError:0.5f timeout:5.0],
                  @"Final paging state after adaptive right swipe was %@",
                  pagingView.value);
    XCTAssertEqualObjects(self.app.buttons[kTODirectionButtonAccessibilityIdentifier].label, @"Left");
}

- (void)testDirectionToggleMakesRightTapTurnToPreviousPage {
    XCUIElement *pagingView = [self launchPagingViewWithArguments:@[]];
    XCUIElement *directionButton = self.app.buttons[kTODirectionButtonAccessibilityIdentifier];
    XCTAssertTrue([directionButton waitForExistenceWithTimeout:5.0]);

    [directionButton tap];
    XCTAssertEqualObjects(directionButton.label, @"Left");

    XCUICoordinate *rightTapCoordinate = [pagingView coordinateWithNormalizedOffset:CGVectorMake(0.9, 0.5)];
    [rightTapCoordinate tap];

    XCTAssertTrue([self waitForPagingView:pagingView toReachPage:-1 maxOffsetError:0.5f timeout:5.0],
                  @"Final paging state after RTL right tap was %@",
                  pagingView.value);
}

- (void)testRotationKeepsCurrentPageCentered {
    XCUIElement *pagingView = [self launchPagingViewWithArguments:@[]];

    XCUICoordinate *rightTapCoordinate = [pagingView coordinateWithNormalizedOffset:CGVectorMake(0.9, 0.5)];
    [rightTapCoordinate tap];
    XCTAssertTrue([self waitForPagingView:pagingView toReachPage:1 maxOffsetError:0.5f timeout:5.0],
                  @"Paging view did not reach page 1 before rotation. State was %@",
                  pagingView.value);

    [[XCUIDevice sharedDevice] setOrientation:UIDeviceOrientationPortrait];
    XCTAssertTrue([self waitForPagingView:pagingView toReachPage:1 maxOffsetError:0.5f timeout:5.0],
                  @"Paging view did not stay centered after portrait rotation. State was %@",
                  pagingView.value);

    [[XCUIDevice sharedDevice] setOrientation:UIDeviceOrientationLandscapeRight];
    XCTAssertTrue([self waitForPagingView:pagingView toReachPage:1 maxOffsetError:0.5f timeout:5.0],
                  @"Paging view did not stay centered after landscape rotation. State was %@",
                  pagingView.value);
}

@end
