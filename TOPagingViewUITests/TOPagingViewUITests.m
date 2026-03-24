//
//  TOPagingViewUITests.m
//  TOPagingViewUITests
//
//  Created by Codex on 2026/03/24.
//

#import <XCTest/XCTest.h>

static NSString *const kTOPagingViewAccessibilityIdentifier = @"paging_view";

@interface TOPagingViewUITests : XCTestCase
@property (nonatomic, strong) XCUIApplication *app;
@end

@implementation TOPagingViewUITests

- (void)setUp
{
    [super setUp];
    self.continueAfterFailure = NO;

    self.app = [[XCUIApplication alloc] init];
    [self.app launch];

    [[XCUIDevice sharedDevice] setOrientation:UIDeviceOrientationLandscapeRight];
}

- (nullable NSDictionary<NSString *, NSNumber *> *)pagingStateForElement:(XCUIElement *)pagingView
{
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
                timeout:(NSTimeInterval)timeout
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];

    while (deadline.timeIntervalSinceNow > 0.0) {
        NSDictionary<NSString *, NSNumber *> *state = [self pagingStateForElement:pagingView];
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

- (BOOL)waitForPagingView:(XCUIElement *)pagingView
    toExceedOffsetError:(CGFloat)minimumOffsetError
                timeout:(NSTimeInterval)timeout
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];

    while (deadline.timeIntervalSinceNow > 0.0) {
        NSDictionary<NSString *, NSNumber *> *state = [self pagingStateForElement:pagingView];
        if (state != nil) {
            const CGFloat offset = state[@"offset"].doubleValue;
            if (fabs(offset) >= minimumOffsetError) {
                return YES;
            }
        }

        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }

    return NO;
}

- (void)testRapidRightTapsLandOnExpectedPageInLandscape
{
    XCUIElement *pagingView = self.app.otherElements[kTOPagingViewAccessibilityIdentifier];
    XCTAssertTrue([pagingView waitForExistenceWithTimeout:5.0]);

    XCUICoordinate *rightTapCoordinate = [pagingView coordinateWithNormalizedOffset:CGVectorMake(0.9, 0.5)];
    for (NSInteger i = 0; i < 10; i++) {
        [rightTapCoordinate tap];
    }

    XCTAssertTrue([self waitForPagingView:pagingView toReachPage:10 maxOffsetError:0.5f timeout:5.0],
                  @"Final paging state was %@", pagingView.value);
}

- (void)testDraggingMidAnimationCancelsProgrammaticTurnAndHandsOffToPaging
{
    XCUIElement *pagingView = self.app.otherElements[kTOPagingViewAccessibilityIdentifier];
    XCTAssertTrue([pagingView waitForExistenceWithTimeout:5.0]);

    XCUICoordinate *rightTapCoordinate = [pagingView coordinateWithNormalizedOffset:CGVectorMake(0.9, 0.5)];
    [rightTapCoordinate tap];

    XCTAssertTrue([self waitForPagingView:pagingView toExceedOffsetError:20.0f timeout:1.0],
                  @"Paging view never moved far enough off center. State was %@", pagingView.value);

    XCUICoordinate *dragStart = [pagingView coordinateWithNormalizedOffset:CGVectorMake(0.35, 0.5)];
    XCUICoordinate *dragEnd = [pagingView coordinateWithNormalizedOffset:CGVectorMake(0.95, 0.5)];
    [dragStart pressForDuration:0.05 thenDragToCoordinate:dragEnd];

    XCTAssertTrue([self waitForPagingView:pagingView toReachPage:0 maxOffsetError:0.5f timeout:5.0],
                  @"Final paging state after drag handoff was %@", pagingView.value);
}

@end
