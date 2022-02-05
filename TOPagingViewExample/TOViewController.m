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

@interface TOViewController () <TOPagingViewDataSource>

@property (nonatomic, strong) TOPagingView *pagingView;
@property (nonatomic, strong) UIButton *button;

@end

@implementation TOViewController

#pragma mark - Page View Data Source -

- (TOTestPageView *)pagingView:(TOPagingView *)pagingView
                                  pageViewForType:(TOPagingViewPageType)type
                                  currentPageView:(TOTestPageView *)currentPageView
{
    TOTestPageView *pageView = [pagingView dequeueReusablePageView];

    switch (type) {
        case TOPagingViewPageTypeInitial:
            pageView.number = 0;
            break;
        case TOPagingViewPageTypeNext:
            pageView.number = currentPageView.number + 1;
            break;
        case TOPagingViewPageTypePrevious:
            pageView.number = currentPageView.number - 1;
            break;
    }

    return pageView;
}

#pragma mark - Gesture Recognizer -

- (void)tapGestureRecognized:(UITapGestureRecognizer *)recgonizer
{
    CGPoint tapPoint = [recgonizer locationInView:self.view];
    CGFloat halfBoundWidth = CGRectGetWidth(self.view.bounds) / 2.0f;
    
    if (tapPoint.x < halfBoundWidth) {
        //        [self.pagingView jumpToPreviousPageAnimated:YES withBlock:^UIView *(TOPagingView *dynamicPagingView, UIView *currentView) {
        //            TOTestPageView *pageView = [dynamicPagingView dequeueReusablePageView];
        //            pageView.number = rand() % 100;
        //            return pageView;
        //        }];
        [self.pagingView turnToLeftPageAnimated:YES];
    }
    else {
        //        [self.pagingView jumpToNextPageAnimated:YES withBlock:^UIView *(TOPagingView *dynamicPagingView, UIView *currentView) {
        //            TOTestPageView *pageView = [dynamicPagingView dequeueReusablePageView];
        //            pageView.number = rand() % 100;
        //            return pageView;
        //        }];
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
    
    self.view.backgroundColor = [UIColor blackColor];
    
    self.pagingView = [[TOPagingView alloc] initWithFrame:self.view.bounds];
    self.pagingView.dataSource = self;
    [self.pagingView registerPageViewClass:TOTestPageView.class];
    self.pagingView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.pagingView];

    [self.pagingView becomeFirstResponder];

    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapGestureRecognized:)];
    [self.pagingView addGestureRecognizer:tapRecognizer];
    
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tintColor = [UIColor whiteColor];
    [button setTitle:@"Right" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
    button.titleLabel.font = [UIFont systemFontOfSize:22];
    button.frame = (CGRect){0,0,100,50};
    button.center = (CGPoint){CGRectGetMidX(self.pagingView.frame), CGRectGetHeight(self.pagingView.frame) - 50};
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |  UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
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
