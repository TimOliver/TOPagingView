//
//  TOViewControllerTests.m
//  TOPagingViewTests
//
//  Created by Codex on 2026/05/10.
//

#import <XCTest/XCTest.h>

#import "TOPagingView.h"
#import "TOViewController.h"

@interface TOViewController (TOUnitTests)
- (NSString *)stringForType:(TOPagingViewPageType)type;
- (void)tapGestureRecognized:(UITapGestureRecognizer *)recognizer;
- (void)buttonTapped;
@end

@interface TOUnitTestViewControllerPagingView : TOPagingView
@property (nonatomic, assign) NSInteger leftTurnCallCount;
@property (nonatomic, assign) NSInteger rightTurnCallCount;
@end

@implementation TOUnitTestViewControllerPagingView

- (void)turnToLeftPageAnimated:(BOOL)animated {
    _leftTurnCallCount++;
}

- (void)turnToRightPageAnimated:(BOOL)animated {
    _rightTurnCallCount++;
}

@end

@interface TOUnitTestTapGestureRecognizer : UITapGestureRecognizer
@property (nonatomic, assign) CGPoint testLocation;
@end

@implementation TOUnitTestTapGestureRecognizer

- (CGPoint)locationInView:(UIView *)view {
    return _testLocation;
}

@end

@interface TOViewControllerTests : XCTestCase
@property (nonatomic, strong) TOViewController *viewController;
@property (nonatomic, strong) TOUnitTestViewControllerPagingView *pagingView;
@property (nonatomic, strong) UIButton *button;
@end

@implementation TOViewControllerTests

- (void)setUp {
    [super setUp];
    _viewController = [[TOViewController alloc] init];
    _viewController.view = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 400.0f, 300.0f)];
    _pagingView = [[TOUnitTestViewControllerPagingView alloc] initWithFrame:_viewController.view.bounds];
    _button = [UIButton buttonWithType:UIButtonTypeSystem];
    [_viewController setValue:_pagingView forKey:@"pagingView"];
    [_viewController setValue:_button forKey:@"button"];
}

- (void)tearDown {
    _button = nil;
    _pagingView = nil;
    _viewController = nil;
    [super tearDown];
}

- (void)testStringForTypeReturnsExpectedLabels {
    XCTAssertEqualObjects([self.viewController stringForType:TOPagingViewPageTypeCurrent], @"Current");
    XCTAssertEqualObjects([self.viewController stringForType:TOPagingViewPageTypeNext], @"Next");
    XCTAssertEqualObjects([self.viewController stringForType:TOPagingViewPageTypePrevious], @"Previous");
    XCTAssertNil([self.viewController stringForType:(TOPagingViewPageType)NSIntegerMax]);
}

- (void)testTapGestureTurnsLeftAndRightPages {
    TOUnitTestTapGestureRecognizer *recognizer = [[TOUnitTestTapGestureRecognizer alloc] init];

    recognizer.testLocation = CGPointMake(100.0f, 150.0f);
    [self.viewController tapGestureRecognized:recognizer];
    XCTAssertEqual(self.pagingView.leftTurnCallCount, 1);
    XCTAssertEqual(self.pagingView.rightTurnCallCount, 0);

    recognizer.testLocation = CGPointMake(300.0f, 150.0f);
    [self.viewController tapGestureRecognized:recognizer];
    XCTAssertEqual(self.pagingView.leftTurnCallCount, 1);
    XCTAssertEqual(self.pagingView.rightTurnCallCount, 1);
}

- (void)testButtonTappedTogglesPageDirectionAndButtonTitle {
    self.pagingView.pageScrollDirection = TOPagingViewDirectionLeftToRight;

    [self.viewController buttonTapped];
    XCTAssertEqual(self.pagingView.pageScrollDirection, TOPagingViewDirectionRightToLeft);
    XCTAssertEqualObjects([self.button titleForState:UIControlStateNormal], @"Left");

    [self.viewController buttonTapped];
    XCTAssertEqual(self.pagingView.pageScrollDirection, TOPagingViewDirectionLeftToRight);
    XCTAssertEqualObjects([self.button titleForState:UIControlStateNormal], @"Right");
}

@end
