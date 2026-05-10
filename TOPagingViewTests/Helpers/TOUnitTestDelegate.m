//
//  TOUnitTestDelegate.m
//  TOPagingViewTests
//
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import "TOUnitTestDelegate.h"

@implementation TOUnitTestDelegate

- (void)pagingView:(TOPagingView *)pagingView willTurnToPageOfType:(TOPagingViewPageType)type {
    _willTurnCallCount++;
}

- (void)pagingView:(TOPagingView *)pagingView didTurnToPageOfType:(TOPagingViewPageType)type {
    _didTurnCallCount++;
    _lastDidTurnType = type;
}

- (void)pagingView:(TOPagingView *)pagingView didChangeToPageDirection:(TOPagingViewDirection)direction {
    _directionChangeCallCount++;
    _lastDirection = direction;
}

@end
