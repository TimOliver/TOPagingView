//
//  TOScrollViewDelegateProxy.h
//
//  Copyright 2018-2026 Timothy Oliver. All rights reserved.
//

#import <UIKit/UIKit.h>

@class TOPagingView;

FOUNDATION_EXTERN void TOPagingViewHandleScrollViewDidScroll(TOPagingView *pagingView);
FOUNDATION_EXTERN void TOPagingViewHandleScrollViewWillBeginDragging(TOPagingView *pagingView);

/// A lightweight proxy that intercepts UIScrollViewDelegate calls.
/// Uses NSProxy message forwarding to automatically forward all delegate methods
/// to the external delegate, while intercepting scrollViewDidScroll: and
/// scrollViewWillBeginDragging: for internal state tracking.
/// This approach avoids manually implementing every UIScrollViewDelegate method.
@interface TOScrollViewDelegateProxy : NSProxy <UIScrollViewDelegate>
@property (nonatomic, weak) TOPagingView *pagingView;
@property (nonatomic, weak) id<UIScrollViewDelegate> externalDelegate;
- (instancetype)init;
@end
