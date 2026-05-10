//
//  TOUnitTestDataSource.h
//  TOPagingViewTests
//
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "TOUnitTestPageView.h"

NS_ASSUME_NONNULL_BEGIN

@interface TOUnitTestDataSource : NSObject <TOPagingViewDataSource>
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, assign) NSInteger minIndex;
@property (nonatomic, assign) NSInteger maxIndex;
@property (nonatomic, assign) NSInteger dataSourceCallCount;
@property (nonatomic, assign) BOOL usesDequeue;
@property (nonatomic, assign) BOOL returnsNilForCurrentPage;
@property (nonatomic, assign) BOOL returnsCurrentPageForCurrentRequest;
@property (nonatomic, assign) NSInteger reusedPageDequeueCount;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *requestedPageTypes;
@end

NS_ASSUME_NONNULL_END
