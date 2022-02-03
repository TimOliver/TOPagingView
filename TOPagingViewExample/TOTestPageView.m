//
//  TOTestPageView.m
//  TOPagingViewExample
//
//  Created by Tim Oliver on 2020/03/25.
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import "TOTestPageView.h"
#import "TOPagingView.h"

@interface TOTestPageView () <TOPagingViewPage>

@property (nonatomic, strong) UILabel *numberLabel;

@end

@implementation TOTestPageView

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor redColor];
        
        self.numberLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        self.numberLabel.textColor = [UIColor whiteColor];
        self.numberLabel.font = [UIFont boldSystemFontOfSize:100.0f];
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

- (void)setNumber:(NSInteger)number
{
    _number = number;
    self.numberLabel.text = [NSString stringWithFormat:@"%ld", (long)number];
    [self setNeedsLayout];
}

@end
