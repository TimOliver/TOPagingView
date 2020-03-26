//
//  ViewController.m
//  TODynamicPageViewExample
//
//  Created by Tim Oliver on 2020/03/23.
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import "TOViewController.h"
#import "TODynamicPageView.h"
#import "TOTestPageView.h"

@interface TOViewController () <TODynamicPageViewDataSource>

@property (nonatomic, strong) TODynamicPageView *pageView;
@property (nonatomic, strong) UIButton *button;

@end

@implementation TOViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor blackColor];
    
    self.pageView = [[TODynamicPageView alloc] initWithFrame:self.view.bounds];
    self.pageView.dataSource = self;
    [self.pageView registerPageViewClass:TOTestPageView.class];
    self.pageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.pageView];
    
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tintColor = [UIColor whiteColor];
    [button setTitle:@"Right" forState:UIControlStateNormal];
    [button addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
    button.titleLabel.font = [UIFont systemFontOfSize:22];
    button.frame = (CGRect){0,0,100,50};
    button.center = (CGPoint){CGRectGetMidX(self.pageView.frame), CGRectGetHeight(self.pageView.frame) - 50};
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |  UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:button];
    
    self.button = button;
}

- (UIView *)initialPageViewForDynamicPageView:(TODynamicPageView *)dynamicPageView
{
    TOTestPageView *pageView = [dynamicPageView dequeueReusablePageView];
    pageView.number = 0;
    return pageView;
}

- (UIView *)dynamicPageView:(TODynamicPageView *)dynamicPageView previousPageViewBeforePageView:(TOTestPageView *)currentPageView
{
    TOTestPageView *pageView = [dynamicPageView dequeueReusablePageView];
    pageView.number = currentPageView.number - 1;
    return pageView;
}

- (UIView *)dynamicPageView:(TODynamicPageView *)dynamicPageView nextPageViewAfterPageView:(TOTestPageView *)currentPageView
{
    TOTestPageView *pageView = [dynamicPageView dequeueReusablePageView];
    pageView.number = currentPageView.number + 1;
    return pageView;
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }

- (void)buttonTapped
{
    TODynamicPageViewDirection direction = self.pageView.pageScrollDirection;
    if (direction == TODynamicPageViewDirectionLeftToRight) {
        direction = TODynamicPageViewDirectionRightToLeft;
        [self.button setTitle:@"Left" forState:UIControlStateNormal];
    }
    else {
        direction = TODynamicPageViewDirectionLeftToRight;
        [self.button setTitle:@"Right" forState:UIControlStateNormal];
    }
    self.pageView.pageScrollDirection = direction;
}

@end
