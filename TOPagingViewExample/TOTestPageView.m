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
        
        self.numberLabel = [[UILabel alloc] initWithFrame:(CGRect){0,0,320,128}];
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

    self.numberLabel.center = (CGPoint){CGRectGetMidX(self.bounds),
                                        CGRectGetMidY(self.bounds)};
    self.numberLabel.frame = CGRectIntegral(self.numberLabel.frame);

    // Private API. Don't actually use this.
    if (@available(iOS 13.0, *)) {
        CGFloat cornerRadius = [[[UIScreen mainScreen] valueForKey:@"_displayCornerRadius"] floatValue];
        self.layer.cornerRadius = cornerRadius;
        self.layer.cornerCurve = kCACornerCurveContinuous;
    }
}

- (void)setNumber:(NSInteger)number
{
    _number = number;
    self.numberLabel.text = [NSString stringWithFormat:@"%ld", (long)number];
    [self setNeedsLayout];
}

#pragma mark - TOPagingViewPage

- (BOOL)isInitialPage {
    return [self.numberLabel.text isEqualToString:@"0"];
}

@end
