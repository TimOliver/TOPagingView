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

// Current page state tracking
@property (nonatomic, assign) NSInteger pageIndex;
@property (nonatomic, assign) NSInteger maximumPageIndex;
@property (nonatomic, assign) BOOL startsWithAdaptivePageDirection;
@property (nonatomic, assign) TOPagingViewDirection startingPageScrollDirection;

// UI
@property (nonatomic, strong) TOPagingView *pagingView;
@property (nonatomic, strong) UIButton *button;

@end

@implementation TOViewController

#pragma mark - Accessibility -

- (NSArray<NSString *> *)launchArguments {
    return NSProcessInfo.processInfo.arguments;
}

- (BOOL)launchArgumentsContainValue:(NSString *)value {
    return [[self launchArguments] containsObject:value];
}

- (NSInteger)integerLaunchArgumentAfterValue:(NSString *)value defaultValue:(NSInteger)defaultValue {
    NSArray<NSString *> *arguments = [self launchArguments];
    const NSUInteger index = [arguments indexOfObject:value];
    if (index == NSNotFound || index + 1 >= arguments.count) { return defaultValue; }

    return arguments[index + 1].integerValue;
}

- (void)configureFromLaunchArguments {
    self.pageIndex = 0;
    self.maximumPageIndex = [self integerLaunchArgumentAfterValue:kTOLaunchArgumentMaxPage defaultValue:10];
    self.startsWithAdaptivePageDirection = [self launchArgumentsContainValue:kTOLaunchArgumentAdaptive];
    self.startingPageScrollDirection =
        [self launchArgumentsContainValue:kTOLaunchArgumentRTL] ? TOPagingViewDirectionRightToLeft : TOPagingViewDirectionLeftToRight;
}

- (void)updatePagingViewAccessibilityState {
    if (self.pagingView == nil) { return; }

    const CGFloat pageWidth = CGRectGetWidth(self.pagingView.bounds) + self.pagingView.pageSpacing;
    CGFloat offsetError = self.pagingView.scrollView.contentOffset.x - pageWidth;
    if (fabs(offsetError) < 0.0005f) { offsetError = 0.0f; }

    self.pagingView.accessibilityValue = [NSString stringWithFormat:@"page=%ld;offset=%.3f", (long)self.pageIndex, offsetError];
}

- (void)updateDirectionButtonTitle {
    const BOOL isReversed = (self.pagingView.pageScrollDirection == TOPagingViewDirectionRightToLeft);
    [self.button setTitle:(isReversed ? @"Left" : @"Right") forState:UIControlStateNormal];
}

#pragma mark - Paging View Data Source -

- (TOTestPageView *)pagingView:(TOPagingView *)pagingView
	               pageViewForType:(TOPagingViewPageType)type
	              currentPageView:(TOTestPageView *)currentPageView {
    (void)currentPageView;

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

    if (labs(pageNumber) > self.maximumPageIndex) { return nil; }

    // Dequeue a fresh page view and configure it.
    TOTestPageView *pageView = [pagingView dequeueReusablePageView];
    pageView.number = pageNumber;
    return pageView;
}

#pragma mark - Paging View Delegate -

- (void)pagingView:(TOPagingView *)pagingView willTurnToPageOfType:(TOPagingViewPageType)type {
    // This delegate event is called quite liberally every time the user causes an action that
    // 'might' result in a page turn transaction occurring. This is useful as a catch to check the current
    // state of incoming data, and perform any new pre-loads that may have occurred in the meantime.

    NSLog(@"Paging view will turn to: %@", [self stringForType:type]);
}

- (void)pagingView:(TOPagingView *)pagingView didTurnToPageOfType:(TOPagingViewPageType)type {
    // This delegate event is called once it has been confirmed that the pages have crossed over the threshold
    // and a new page just officially became the "current" page. This is where any UI or state attached to this
    // view can be safely updated to match this view. This is called before the data source requests the next page
    // in order to update the state that will reflect what the data source needs to generate.

    if (type == TOPagingViewPageTypeNext) { _pageIndex++; }
    if (type == TOPagingViewPageTypePrevious) { _pageIndex--; }

    [self updatePagingViewAccessibilityState];
    NSLog(@"Paging view did turn to: %@ at page %ld", [self stringForType:type], (long)self.pageIndex);
}

- (void)pagingView:(TOPagingView *)pagingView didChangeToPageDirection:(TOPagingViewDirection)direction {
    // This delegate is called when adaptive page direction detection is enabled and the scroll view
    // has determined the user has committed to a new page direction. It is only called once per interaction.
    [self updateDirectionButtonTitle];

    NSLog(@"Paging view did change reading direction to: %@", (direction == TOPagingViewDirectionRightToLeft) ? @"Left" : @"Right");
}

- (NSString *)stringForType:(TOPagingViewPageType)type {
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

- (void)tapGestureRecognized:(UITapGestureRecognizer *)recognizer {
    CGPoint tapPoint = [recognizer locationInView:self.view];
    CGFloat halfBoundWidth = CGRectGetWidth(self.view.bounds) / 2.0f;

    if (tapPoint.x < halfBoundWidth) {
        [self.pagingView turnToLeftPageAnimated:YES];
    } else {
        [self.pagingView turnToRightPageAnimated:YES];
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

#pragma mark - UIScrollViewDelegate -

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self updatePagingViewAccessibilityState];
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView {
    [self updatePagingViewAccessibilityState];
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
    [self configureFromLaunchArguments];

    // View Controller Config
    self.view.backgroundColor = [UIColor blackColor];

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

    // Add a tap recognizer to turn pages. The delegate lets it recognize alongside the scroll
    // view's pan, otherwise taps during deceleration get held up by gesture coordination.
    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                    action:@selector(tapGestureRecognized:)];
    tapRecognizer.delegate = self;
    [self.pagingView addGestureRecognizer:tapRecognizer];
    [self.pagingView.scrollView.panGestureRecognizer requireGestureRecognizerToFail:tapRecognizer];

    // Add a button to toggle page turning direction
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tintColor = [UIColor whiteColor];
    [button setTitle:@"Right" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
    button.titleLabel.font = [UIFont systemFontOfSize:22];
    button.frame = CGRectMake(0.0f, 0.0f, 100.0f, 50.0f);
    button.center = (CGPoint){CGRectGetMidX(self.pagingView.frame), CGRectGetHeight(self.pagingView.frame) - 50};
    button.autoresizingMask =
        UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    button.accessibilityIdentifier = kTODirectionButtonAccessibilityIdentifier;
    [self.view addSubview:button];
    self.button = button;
    [self updateDirectionButtonTitle];

    [self updatePagingViewAccessibilityState];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updatePagingViewAccessibilityState];
}

- (void)buttonTapped {
    TOPagingViewDirection direction = self.pagingView.pageScrollDirection;
    if (direction == TOPagingViewDirectionLeftToRight) {
        direction = TOPagingViewDirectionRightToLeft;
    } else {
        direction = TOPagingViewDirectionLeftToRight;
    }
    self.pagingView.pageScrollDirection = direction;
    [self updateDirectionButtonTitle];
}

@end
