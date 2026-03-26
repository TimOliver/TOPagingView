//
//  TOScrollViewDelegateProxy.m
//
//  Copyright 2018-2026 Timothy Oliver. All rights reserved.
//

#import "TOScrollViewDelegateProxy.h"

/// The delegate selectors we intercept to notify the paging view of scroll events.
static inline BOOL TOScrollViewDelegateProxyIsInterceptedSelector(SEL sel) {
    return sel == @selector(scrollViewDidScroll:) || sel == @selector(scrollViewWillBeginDragging:);
}

@implementation TOScrollViewDelegateProxy

- (instancetype)init {
    // NSProxy doesn't have a default -init, so we just return self.
    return self;
}

#pragma mark - Intercepted Methods

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    TOPagingViewHandleScrollViewDidScroll(_pagingView);

    if ([_externalDelegate respondsToSelector:@selector(scrollViewDidScroll:)]) {
        [_externalDelegate scrollViewDidScroll:scrollView];
    }
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    TOPagingViewHandleScrollViewWillBeginDragging(_pagingView);

    if ([_externalDelegate respondsToSelector:@selector(scrollViewWillBeginDragging:)]) {
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
