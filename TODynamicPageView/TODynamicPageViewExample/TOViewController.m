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

@end

@implementation TOViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor blackColor];
    
    TODynamicPageView *pageView = [[TODynamicPageView alloc] initWithFrame:self.view.bounds];
    pageView.dataSource = self;
    [pageView registerPageViewClass:TOTestPageView.class];
    pageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:pageView];
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

@end
