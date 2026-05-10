//
//  TOUnitTestDelegate.h
//  TOPagingViewTests
//
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "TOPagingView.h"

@interface TOUnitTestDelegate : NSObject <TOPagingViewDelegate>
@property (nonatomic, assign) NSInteger willTurnCallCount;
@property (nonatomic, assign) NSInteger didTurnCallCount;
@property (nonatomic, assign) TOPagingViewPageType lastDidTurnType;
@property (nonatomic, assign) NSInteger directionChangeCallCount;
@property (nonatomic, assign) TOPagingViewDirection lastDirection;
@end
