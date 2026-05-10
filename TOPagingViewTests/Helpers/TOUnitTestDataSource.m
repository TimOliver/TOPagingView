//
//  TOUnitTestDataSource.m
//  TOPagingViewTests
//
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import "TOUnitTestDataSource.h"

@implementation TOUnitTestDataSource

- (instancetype)init {
    self = [super init];
    if (self) {
        _minIndex = NSIntegerMin;
        _maxIndex = NSIntegerMax;
        _usesDequeue = YES;
        _requestedPageTypes = [NSMutableArray array];
    }
    return self;
}

- (nullable UIView<TOPagingViewPage> *)pagingView:(TOPagingView *)pagingView
                                  pageViewForType:(TOPagingViewPageType)type
                                  currentPageView:(nullable TOUnitTestPageView *)currentPageView {
    _dataSourceCallCount++;
    [_requestedPageTypes addObject:@(type)];

    if (type == TOPagingViewPageTypeCurrent && _returnsNilForCurrentPage) { return nil; }
    if (type == TOPagingViewPageTypeCurrent && _returnsCurrentPageForCurrentRequest) { return currentPageView; }

    const NSInteger referenceIndex = currentPageView ? currentPageView.pageNumber : _currentIndex;
    NSInteger index;
    switch (type) {
    case TOPagingViewPageTypeCurrent:
        index = _currentIndex;
        break;
    case TOPagingViewPageTypeNext:
        index = referenceIndex + 1;
        if (index > _maxIndex) { return nil; }
        break;
    case TOPagingViewPageTypePrevious:
        index = referenceIndex - 1;
        if (index < _minIndex) { return nil; }
        break;
    }

    TOUnitTestPageView *pageView = nil;
    if (_usesDequeue) {
        pageView = [pagingView dequeueReusablePageViewForIdentifier:@"TOUnitTestPageView"];
        if (pageView.prepareForReuseCount > 0) { _reusedPageDequeueCount++; }
    }
    if (pageView == nil) { pageView = [[TOUnitTestPageView alloc] initWithFrame:CGRectZero]; }
    pageView.pageNumber = index;
    pageView.initialPage = (type == TOPagingViewPageTypeCurrent && index == 0);
    pageView.pageDirectionWasSet = NO;
    return pageView;
}

@end
