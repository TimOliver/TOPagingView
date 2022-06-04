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

@interface TOViewController () <TOPagingViewDataSource, TOPagingViewDelegate>

// Current page state tracking
@property (nonatomic, assign) NSInteger pageIndex;

// UI
@property (nonatomic, strong) TOPagingView *pagingView;
@property (nonatomic, strong) UIButton *button;

@end

@implementation TOViewController

#pragma mark - Paging View Data Source -

- (TOTestPageView *)pagingView:(TOPagingView *)pagingView
                                  pageViewForType:(TOPagingViewPageType)type
                                  currentPageView:(TOTestPageView *)currentPageView
{
    TOTestPageView *pageView = [pagingView dequeueReusablePageView];

    switch (type) {
        case TOPagingViewPageTypeInitial:
            pageView.number = self.pageIndex;
            break;
        case TOPagingViewPageTypeNext:
            pageView.number = self.pageIndex + 1;
            break;
        case TOPagingViewPageTypePrevious:
            pageView.number = self.pageIndex - 1;
            break;
    }

    return pageView;
}

#pragma mark - Paging View Delegate -

-(void)pagingView:(TOPagingView *)pagingView willTurnToPageOfType:(TOPagingViewPageType)type
{
    // This delegate event is called quite liberally every time the user causes an action that
    // 'might' result in a page turn transaction occurring. This is useful as a catch to check the current
    // state of incoming data, and perform any new pre-loads that may have occurred in the meantime.

    NSLog(@"Paging view will to turn to: %@", [self stringForType:type]);
}

- (void)pagingView:(TOPagingView *)pagingView didTurnToPageOfType:(TOPagingViewPageType)type
{
    // This delegate event is called once it has been confirmed that the pages have crossed over the threshold
    // and a new page just officially became the "current" page. This is where any UI or state attached to this
    // view can be safely updated to match this view. This is called before the data source requests the next page
    // in order to update the state that will reflect what the data source needs to generate.

    if (type == TOPagingViewPageTypeNext) { self.pageIndex++; }
    if (type == TOPagingViewPageTypePrevious) { self.pageIndex--; }

    NSLog(@"Paging view did to turn to: %@ at page %ld", [self stringForType:type], (long)self.pageIndex);
}

- (NSString *)stringForType:(TOPagingViewPageType)type
{
    switch(type) {
        case TOPagingViewPageTypeInitial: return @"Initial";
        case TOPagingViewPageTypeNext: return @"Next";
        case TOPagingViewPageTypePrevious: return @"Previous";
    }
    return nil;
}

#pragma mark - Gesture Recognizer -

- (void)tapGestureRecognized:(UITapGestureRecognizer *)recgonizer
{
    CGPoint tapPoint = [recgonizer locationInView:self.view];
    CGFloat halfBoundWidth = CGRectGetWidth(self.view.bounds) / 2.0f;
    
    if (tapPoint.x < halfBoundWidth) {
        [self.pagingView turnToLeftPageAnimated:YES];
    }
    else {
        [self.pagingView turnToRightPageAnimated:YES];
    }
}

#pragma mark - View Controller Lifecycle -

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }

- (void)viewDidLoad {
    [super viewDidLoad];

    // State tracking
    self.pageIndex = 0;

    // View Controller Config
    self.view.backgroundColor = [UIColor blackColor];

    // Paging view set-up and configuration
    self.pagingView = [[TOPagingView alloc] initWithFrame:self.view.bounds];
    self.pagingView.dataSource = self;
    self.pagingView.delegate = self;
    [self.pagingView registerPageViewClass:TOTestPageView.class];
    self.pagingView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.pagingView];

    // Force it to become first responder to receive keyboard input
    [self.pagingView becomeFirstResponder];

    // Add a tap recognizer to turn pages
    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapGestureRecognized:)];
    [self.pagingView addGestureRecognizer:tapRecognizer];

    // Add a button to toggle page turning direction
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tintColor = [UIColor whiteColor];
    [button setTitle:@"Right" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
    button.titleLabel.font = [UIFont systemFontOfSize:22];
    button.frame = (CGRect){0,0,100,50};
    button.center = (CGPoint){CGRectGetMidX(self.pagingView.frame), CGRectGetHeight(self.pagingView.frame) - 50};
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:button];
    self.button = button;
}

- (void)buttonTapped
{
    TOPagingViewDirection direction = self.pagingView.pageScrollDirection;
    if (direction == TOPagingViewDirectionLeftToRight) {
        direction = TOPagingViewDirectionRightToLeft;
        [self.button setTitle:@"Left" forState:UIControlStateNormal];
    }
    else {
        direction = TOPagingViewDirectionLeftToRight;
        [self.button setTitle:@"Right" forState:UIControlStateNormal];
    }
    self.pagingView.pageScrollDirection = direction;
}

@end
