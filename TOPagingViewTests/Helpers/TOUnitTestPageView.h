//
//  TOUnitTestPageView.h
//  TOPagingViewTests
//
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "TOPagingView.h"

NS_ASSUME_NONNULL_BEGIN

@interface TOUnitTestPageView : UIView <TOPagingViewPage>
@property (nonatomic, assign) NSInteger pageNumber;
@property (nonatomic, assign) BOOL prepareForReuseCalled;
@property (nonatomic, assign) NSInteger prepareForReuseCount;
@property (nonatomic, assign) BOOL initialPage;
@property (nonatomic, assign) TOPagingViewDirection pageDirection;
@property (nonatomic, assign) BOOL pageDirectionWasSet;
@end

NS_ASSUME_NONNULL_END
