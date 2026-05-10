//
//  TOUnitTestPageView.m
//  TOPagingViewTests
//
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import "TOUnitTestPageView.h"

@implementation TOUnitTestPageView

- (void)prepareForReuse {
    _prepareForReuseCalled = YES;
    _prepareForReuseCount++;
}

+ (NSString *)pageIdentifier {
    return @"TOUnitTestPageView";
}

- (NSString *)uniqueIdentifier {
    return [NSString stringWithFormat:@"page-%@", @(_pageNumber)];
}

- (BOOL)isInitialPage {
    return _initialPage;
}

- (void)setPageDirection:(TOPagingViewDirection)pageDirection {
    _pageDirection = pageDirection;
    _pageDirectionWasSet = YES;
}

@end
