//
//  TOPagingViewDelegateProxy.m
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

#import "TOScrollViewDelegateProxy.h"

/// The delegate selectors we intercept to notify the paging view of scroll events.
static inline BOOL TOScrollViewDelegateProxyIsInterceptedSelector(SEL sel) {
    return sel == @selector(scrollViewDidScroll:)
        || sel == @selector(scrollViewWillBeginDragging:)
        || sel == @selector(scrollViewDidEndDragging:willDecelerate:);
}

/// Cached respondsToSelector results for the intercepted methods. Refreshed whenever
/// the external delegate is (re)assigned so the forwarding hot path avoids per-tick lookups.
typedef struct {
    unsigned int externalRespondsToDidScroll : 1;
    unsigned int externalRespondsToWillBeginDragging : 1;
    unsigned int externalRespondsToDidEndDragging : 1;
} TOScrollViewDelegateProxyFlags;

@implementation TOScrollViewDelegateProxy {
    TOScrollViewDelegateProxyFlags _externalDelegateFlags;
}

- (instancetype)init {
    // NSProxy doesn't have a default -init, so we just return self.
    return self;
}

#pragma mark - External Delegate

- (void)setExternalDelegate:(id<UIScrollViewDelegate>)externalDelegate {
    _externalDelegate = externalDelegate;
    _externalDelegateFlags.externalRespondsToDidScroll =
        [externalDelegate respondsToSelector:@selector(scrollViewDidScroll:)];
    _externalDelegateFlags.externalRespondsToWillBeginDragging =
        [externalDelegate respondsToSelector:@selector(scrollViewWillBeginDragging:)];
    _externalDelegateFlags.externalRespondsToDidEndDragging =
        [externalDelegate respondsToSelector:@selector(scrollViewDidEndDragging:willDecelerate:)];
}

#pragma mark - Intercepted Methods

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    NSAssert(_pagingView != nil, @"Paging view must exist when the delegate proxy receives scroll events.");
    TOPagingViewHandleScrollViewDidScroll(_pagingView);
    if (_externalDelegateFlags.externalRespondsToDidScroll) {
        [_externalDelegate scrollViewDidScroll:scrollView];
    }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    NSAssert(_pagingView != nil, @"Paging view must exist when the delegate proxy receives scroll events.");
    TOPagingViewHandleScrollViewWillBeginDragging(_pagingView);
    if (_externalDelegateFlags.externalRespondsToWillBeginDragging) {
        [_externalDelegate scrollViewWillBeginDragging:scrollView];
    }
}

#pragma mark - NSProxy Message Forwarding

- (BOOL)respondsToSelector:(SEL)sel {
    if (TOScrollViewDelegateProxyIsInterceptedSelector(sel)) { return YES; }
    return [_externalDelegate respondsToSelector:sel];
}

- (id)forwardingTargetForSelector:(SEL)sel {
    if (!TOScrollViewDelegateProxyIsInterceptedSelector(sel)) { return _externalDelegate; }
    return nil;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    NSMethodSignature *signature = [(NSObject *)_externalDelegate methodSignatureForSelector:sel];
    if (signature) { return signature; }
    return [NSMethodSignature signatureWithObjCTypes:"v@:"];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    if ([_externalDelegate respondsToSelector:invocation.selector]) { [invocation invokeWithTarget:_externalDelegate]; }
}

@end
