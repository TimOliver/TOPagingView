//
//  TOPagingViewDelegateProxy.h
//
//  Copyright 2018-2026 Timothy Oliver. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
//  OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR
//  IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#import <Foundation/Foundation.h>
#import <UIKit/UIScrollView.h>

@class TOPagingView;

FOUNDATION_EXTERN void TOPagingViewHandleScrollViewDidScroll(TOPagingView *pagingView);
FOUNDATION_EXTERN void TOPagingViewHandleScrollViewWillBeginDragging(TOPagingView *pagingView);

/// A lightweight proxy that intercepts UIScrollViewDelegate calls.
/// Uses NSProxy message forwarding to automatically forward all delegate methods
/// to the external delegate, while intercepting scrollViewDidScroll: and
/// scrollViewWillBeginDragging: for internal state tracking.
/// This approach avoids manually implementing every UIScrollViewDelegate method.
@interface TOScrollViewDelegateProxy : NSProxy <UIScrollViewDelegate>

/// The parent paging view which delegate calls will be forwarded to
@property (nonatomic, weak) TOPagingView *pagingView;

/// The external object that has subscribed to UIScrollViewDelegate;
@property (nonatomic, weak) id<UIScrollViewDelegate> externalDelegate;

// Creates a new instance of this proxy class
- (instancetype)init;

@end
