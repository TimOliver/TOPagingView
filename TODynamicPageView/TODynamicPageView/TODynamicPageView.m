//
//  TODynamicPageView.m
//  TODynamicPageViewExample
//
//  Created by Tim Oliver on 2020/03/24.
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import "TODynamicPageView.h"

@interface TODynamicPageView ()

@property (nonatomic, strong) UIScrollView *scrollView;

@end

@implementation TODynamicPageView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) { [self setUp]; }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) { [self setUp]; }
    return self;
}

- (void)setUp
{
    // Configure the main properties of this view
    self.clipsToBounds = YES;
    
    // Create the scroll view
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.scrollView addObserver:self forKeyPath:@"contentOffset" options:0 context:nil];
    [self addSubview:self.scrollView];
}

- (void)didMoveToSuperview
{
    [super didMoveToSuperview];
    
    CGRect frame = self.frame;
    CGSize contentSize = self.bounds.size;
    
}

- (void)scrollViewDidScroll
{
    NSLog(@"%@", NSStringFromCGPoint(self.scrollView.contentOffset));
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context
{
    [self scrollViewDidScroll];
}

@end
