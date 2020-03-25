//
//  TOTestPageView.m
//  TODynamicPageViewExample
//
//  Created by Tim Oliver on 2020/03/25.
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import "TOTestPageView.h"
#import "TODynamicPageView.h"

@interface TOTestPageView () <TODynamicPageViewPageProtocol>

@property (nonatomic, strong) UILabel *numberLabel;

@end

@implementation TOTestPageView

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor redColor];
        
        self.numberLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.numberLabel.textColor = [UIColor whiteColor];
        self.numberLabel.font = [UIFont boldSystemFontOfSize:30.0f];
        self.numberLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:self.numberLabel];
    }
    
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];
    
    [self.numberLabel sizeToFit];
    self.numberLabel.center = (CGPoint){CGRectGetMidX(self.bounds),
                                        CGRectGetMidY(self.bounds)};
    self.numberLabel.frame = CGRectIntegral(self.numberLabel.frame);
}

+ (NSString *)pageIdentifier
{
    return @"TestApp.TestPage";
}

@end
