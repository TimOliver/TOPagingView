//
//  ViewController.m
//  TODynamicPageViewExample
//
//  Created by Tim Oliver on 2020/03/23.
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import "TOViewController.h"
#import "TODynamicPageView.h"

@interface TOViewController ()

@end

@implementation TOViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor blackColor];
    
    TODynamicPageView *pageView = [[TODynamicPageView alloc] initWithFrame:self.view.bounds];
    pageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:pageView];
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleLightContent;
}

- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }

@end
