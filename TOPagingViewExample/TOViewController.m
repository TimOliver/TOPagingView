//
//  ViewController.m
//  TOPagingViewExample
//
//  Created by Tim Oliver on 2020/03/23.
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import "TOViewController.h"

#import "TOPagingView.h"
#import "TOTestPageView.h"

static NSString *const kTOPagingViewAccessibilityIdentifier = @"paging_view";
static NSString *const kTODirectionButtonAccessibilityIdentifier = @"direction_button";
static NSString *const kTOLaunchArgumentAdaptive = @"--topaging-adaptive";
static NSString *const kTOLaunchArgumentRTL = @"--topaging-rtl";
static NSString *const kTOLaunchArgumentMaxPage = @"--topaging-max-page";

@interface TOViewController () <TOPagingViewDataSource, TOPagingViewDelegate, UIScrollViewDelegate, UIGestureRecognizerDelegate>

// Persist transient motion for UI automation, which waits for native animations to finish.
@property (nonatomic, assign) CGFloat peakOffsetError;
@property (nonatomic, assign) CGFloat handoffOffsetError;
@property (nonatomic, assign) BOOL pendingHandoffTestTurn;

// Current page state tracking
@property (nonatomic, assign) NSInteger pageIndex;
@property (nonatomic, assign) NSInteger maximumPageIndex;
@property (nonatomic, assign) BOOL startsWithAdaptivePageDirection;
@property (nonatomic, assign) TOPagingViewDirection startingPageScrollDirection;

// UI
@property (nonatomic, strong) TOPagingView *pagingView;
@property (nonatomic, strong) UIButton *directionButton;

@end

@implementation TOViewController

#pragma mark - Paging View Data Source -

- (nullable TOTestPageView *)pagingView:(TOPagingView *)pagingView
                        pageViewForType:(TOPagingViewPageType)type
                        currentPageView:(nullable TOTestPageView *)currentPageView {
    NSInteger pageNumber = self.pageIndex;
    switch (type) {
    case TOPagingViewPageTypeCurrent:
        pageNumber = self.pageIndex;
        break;
    case TOPagingViewPageTypeNext:
        pageNumber = self.pageIndex + 1;
        break;
    case TOPagingViewPageTypePrevious:
        pageNumber = self.pageIndex - 1;
        break;
    }

    if (labs(pageNumber) > self.maximumPageIndex) {
        return nil;
    }

    // Dequeue a fresh page view and configure it.
    TOTestPageView *const pageView = [pagingView dequeueReusablePageView];
    pageView.number = pageNumber;
    return pageView;
}

#pragma mark - Paging View Delegate -

- (void)pagingView:(TOPagingView *)pagingView willTurnToPageOfType:(TOPagingViewPageType)type {
    // The attempted turn may hit a boundary. Use this callback to start loading adjacent content.
    NSLog(@"Paging view will turn to: %@", [self _stringForType:type]);
}

- (void)pagingView:(TOPagingView *)pagingView didTurnToPageOfType:(TOPagingViewPageType)type {
    // Update the index before the data source is asked to supply the next adjacent page.
    if (type == TOPagingViewPageTypeNext) {
        _pageIndex++;
    }
    if (type == TOPagingViewPageTypePrevious) {
        _pageIndex--;
    }

    [self _updatePagingViewAccessibilityState];
    NSLog(@"Paging view did turn to: %@ at page %ld", [self _stringForType:type], (long)self.pageIndex);
}

- (void)pagingView:(TOPagingView *)pagingView didChangeToPageDirection:(TOPagingViewDirection)direction {
    // This delegate is called when adaptive page direction detection is enabled and the scroll view
    // has determined the user has committed to a new page direction. It is only called once per interaction.
    [self _updateDirectionButtonTitle];

    NSLog(@"Paging view did change reading direction to: %@",
          (direction == TOPagingViewDirectionRightToLeft) ? @"Left" : @"Right");
}

- (nullable NSString *)_stringForType:(TOPagingViewPageType)type {
    switch (type) {
    case TOPagingViewPageTypeCurrent:
        return @"Current";
    case TOPagingViewPageTypeNext:
        return @"Next";
    case TOPagingViewPageTypePrevious:
        return @"Previous";
    }

    return nil;
}

#pragma mark - Gesture Recognizer -

- (void)_tapGestureRecognized:(UITapGestureRecognizer *)recognizer {
    self.peakOffsetError = 0;
    const CGPoint tapPoint = [recognizer locationInView:self.view];
    const CGFloat halfBoundWidth = CGRectGetWidth(self.view.bounds) / 2.0f;

    if (tapPoint.x < halfBoundWidth) {
        [self.pagingView turnToLeftPageAnimated:YES];
    } else {
        [self.pagingView turnToRightPageAnimated:YES];
    }
}

- (void)_startTurnForDragHandoffTest:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) {
        return;
    }

    self.peakOffsetError = 0;
    self.pendingHandoffTestTurn = YES;
    [self.pagingView turnToNextPageAnimated:YES];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

#pragma mark - UIScrollViewDelegate -

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self _updatePagingViewAccessibilityState];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    [self _updatePagingViewAccessibilityState];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (self.pendingHandoffTestTurn) {
        // The proxy stops the animation before forwarding this event. If it had
        // already completed naturally, the offset would be centered here.
        self.handoffOffsetError = fabs(scrollView.contentOffset.x - scrollView.bounds.size.width);
        self.pendingHandoffTestTurn = NO;
        [self _updatePagingViewAccessibilityState];
    }
}

#pragma mark - View Controller Lifecycle -

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // State tracking
    [self _configureFromLaunchArguments];

    // View Controller Config
    self.view.backgroundColor = [UIColor blackColor];

    [self _setUpPagingView];
    [self _setUpGestures];
    [self _setUpDirectionButton];

    [self _updatePagingViewAccessibilityState];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self _updatePagingViewAccessibilityState];
}

#pragma mark - View Setup

- (void)_setUpPagingView {
    // Paging view set-up and configuration
    self.pagingView = [[TOPagingView alloc] initWithFrame:self.view.bounds];
    self.pagingView.isAdaptivePageDirectionEnabled = self.startsWithAdaptivePageDirection;
    self.pagingView.pageScrollDirection = self.startingPageScrollDirection;
    self.pagingView.dataSource = self;
    self.pagingView.delegate = self;
    self.pagingView.scrollViewDelegate = self;
    self.pagingView.isAccessibilityElement = YES;
    self.pagingView.accessibilityIdentifier = kTOPagingViewAccessibilityIdentifier;
    [self.pagingView registerPageViewClass:TOTestPageView.class];
    self.pagingView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.pagingView];

    // Force it to become first responder to receive keyboard input
    [self.pagingView becomeFirstResponder];
}

- (void)_setUpGestures {
    // Add a tap recognizer to turn pages. The delegate lets it recognize alongside the scroll
    // view's pan, otherwise taps during deceleration get held up by gesture coordination.
    UITapGestureRecognizer *const tapRecognizer =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_tapGestureRecognized:)];
    tapRecognizer.delegate = self;
    [self.pagingView addGestureRecognizer:tapRecognizer];
    [self.pagingView.scrollView.panGestureRecognizer requireGestureRecognizerToFail:tapRecognizer];

    // Start the turn while XCTest is holding a finger down, then interrupt it as
    // that same gesture starts dragging. Separate actions wait for UIKit to settle.
    if ([self _launchArgumentsContainValue:@"--topaging-test-drag-handoff"]) {
        UILongPressGestureRecognizer *const press =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_startTurnForDragHandoffTest:)];
        press.minimumPressDuration = 0.01;
        press.cancelsTouchesInView = NO;
        press.delegate = self;
        [self.pagingView addGestureRecognizer:press];
    }
}

- (void)_setUpDirectionButton {
    // Add a button to toggle page turning direction
    UIButton *const directionButton = [UIButton buttonWithType:UIButtonTypeSystem];
    directionButton.tintColor = [UIColor whiteColor];
    [directionButton setTitle:@"Right" forState:UIControlStateNormal];
    [directionButton addTarget:self action:@selector(_directionButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    directionButton.titleLabel.font = [UIFont systemFontOfSize:22];
    directionButton.frame = CGRectMake(0.0f, 0.0f, 100.0f, 50.0f);
    directionButton.center = (CGPoint){CGRectGetMidX(self.pagingView.frame), CGRectGetHeight(self.pagingView.frame) - 50};
    directionButton.autoresizingMask =
        UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    directionButton.accessibilityIdentifier = kTODirectionButtonAccessibilityIdentifier;
    [self.view addSubview:directionButton];
    self.directionButton = directionButton;
    [self _updateDirectionButtonTitle];
}

- (void)_directionButtonTapped {
    TOPagingViewDirection direction = self.pagingView.pageScrollDirection;
    if (direction == TOPagingViewDirectionLeftToRight) {
        direction = TOPagingViewDirectionRightToLeft;
    } else {
        direction = TOPagingViewDirectionLeftToRight;
    }
    self.pagingView.pageScrollDirection = direction;
    [self _updateDirectionButtonTitle];
}

#pragma mark - UI Test Configuration

- (NSArray<NSString *> *)_launchArguments {
    return NSProcessInfo.processInfo.arguments;
}

- (BOOL)_launchArgumentsContainValue:(NSString *)value {
    return [[self _launchArguments] containsObject:value];
}

- (NSInteger)_integerLaunchArgumentAfterValue:(NSString *)value defaultValue:(NSInteger)defaultValue {
    NSArray<NSString *> *const arguments = [self _launchArguments];
    const NSUInteger index = [arguments indexOfObject:value];
    if (index == NSNotFound || index + 1 >= arguments.count) {
        return defaultValue;
    }

    return arguments[index + 1].integerValue;
}

- (void)_configureFromLaunchArguments {
    self.pageIndex = 0;
    self.maximumPageIndex = [self _integerLaunchArgumentAfterValue:kTOLaunchArgumentMaxPage defaultValue:10];
    self.startsWithAdaptivePageDirection = [self _launchArgumentsContainValue:kTOLaunchArgumentAdaptive];
    self.startingPageScrollDirection = [self _launchArgumentsContainValue:kTOLaunchArgumentRTL]
                                           ? TOPagingViewDirectionRightToLeft
                                           : TOPagingViewDirectionLeftToRight;
}

#pragma mark - Accessibility

- (void)_updatePagingViewAccessibilityState {
    if (self.pagingView == nil) {
        return;
    }

    const CGFloat pageWidth = CGRectGetWidth(self.pagingView.bounds) + self.pagingView.pageSpacing;
    CGFloat offsetError = self.pagingView.scrollView.contentOffset.x - pageWidth;
    if (fabs(offsetError) < 0.0005f) {
        offsetError = 0.0f;
    }

    self.peakOffsetError = MAX(self.peakOffsetError, fabs(offsetError));
    self.pagingView.accessibilityValue = [NSString stringWithFormat:@"page=%ld;offset=%.3f;peak=%.3f;handoff=%.3f",
                                                                    (long)self.pageIndex,
                                                                    offsetError,
                                                                    self.peakOffsetError,
                                                                    self.handoffOffsetError];
}

- (void)_updateDirectionButtonTitle {
    const BOOL isReversed = (self.pagingView.pageScrollDirection == TOPagingViewDirectionRightToLeft);
    [self.directionButton setTitle:(isReversed ? @"Left" : @"Right") forState:UIControlStateNormal];
}

@end
