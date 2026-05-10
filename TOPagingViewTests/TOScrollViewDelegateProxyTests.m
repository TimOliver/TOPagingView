//
//  TOScrollViewDelegateProxyTests.m
//  TOPagingViewTests
//
//  Created by Codex on 2026/05/10.
//

#import <XCTest/XCTest.h>

#import "TOPagingView.h"
#import "TOScrollViewDelegateProxy.h"

@interface TOScrollViewDelegateProxy (TOUnitTests)
- (id)forwardingTargetForSelector:(SEL)sel;
@end

@interface TOUnitTestScrollViewExternalDelegate : NSObject <UIScrollViewDelegate>
@property (nonatomic, assign) NSInteger didScrollCallCount;
@property (nonatomic, assign) NSInteger willBeginDraggingCallCount;
@property (nonatomic, assign) NSInteger didEndDraggingCallCount;
@property (nonatomic, assign) NSInteger didZoomCallCount;
@property (nonatomic, assign) BOOL lastDidEndDraggingDecelerate;
@end

@implementation TOUnitTestScrollViewExternalDelegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    _didScrollCallCount++;
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    _willBeginDraggingCallCount++;
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    _didEndDraggingCallCount++;
    _lastDidEndDraggingDecelerate = decelerate;
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    _didZoomCallCount++;
}

@end

@interface TOScrollViewDelegateProxyTests : XCTestCase
@property (nonatomic, strong) TOPagingView *pagingView;
@property (nonatomic, strong) TOScrollViewDelegateProxy *proxy;
@property (nonatomic, strong) TOUnitTestScrollViewExternalDelegate *externalDelegate;
@end

@implementation TOScrollViewDelegateProxyTests

- (void)setUp {
    [super setUp];
    _pagingView = [[TOPagingView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 375.0f, 812.0f)];
    _proxy = [[TOScrollViewDelegateProxy alloc] init];
    _proxy.pagingView = _pagingView;
    _externalDelegate = [[TOUnitTestScrollViewExternalDelegate alloc] init];
    _proxy.externalDelegate = _externalDelegate;
}

- (void)tearDown {
    _proxy = nil;
    _externalDelegate = nil;
    _pagingView = nil;
    [super tearDown];
}

- (void)testInterceptedScrollCallbacksNotifyPagingViewAndExternalDelegate {
    UIScrollView *scrollView = self.pagingView.scrollView;

    [self.proxy scrollViewWillBeginDragging:scrollView];
    [self.proxy scrollViewDidScroll:scrollView];
    [self.proxy scrollViewDidEndDragging:scrollView willDecelerate:YES];

    XCTAssertEqual(self.externalDelegate.willBeginDraggingCallCount, 1);
    XCTAssertEqual(self.externalDelegate.didScrollCallCount, 1);
    XCTAssertEqual(self.externalDelegate.didEndDraggingCallCount, 1);
    XCTAssertTrue(self.externalDelegate.lastDidEndDraggingDecelerate);
}

- (void)testProxyRespondsAndForwardsNonInterceptedDelegateMessages {
    SEL zoomSelector = @selector(scrollViewDidZoom:);

    XCTAssertTrue([self.proxy respondsToSelector:@selector(scrollViewDidScroll:)]);
    XCTAssertTrue([self.proxy respondsToSelector:zoomSelector]);
    XCTAssertNil([self.proxy forwardingTargetForSelector:@selector(scrollViewDidScroll:)]);
    XCTAssertEqual([self.proxy forwardingTargetForSelector:zoomSelector], self.externalDelegate);

    [(id<UIScrollViewDelegate>)self.proxy scrollViewDidZoom:self.pagingView.scrollView];

    XCTAssertEqual(self.externalDelegate.didZoomCallCount, 1);
}

- (void)testProxyIgnoresUnimplementedForwardedInvocations {
    SEL selector = @selector(scrollViewDidZoom:);
    NSMethodSignature *signature = [self.proxy methodSignatureForSelector:selector];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.selector = selector;

    self.proxy.externalDelegate = nil;
    [self.proxy forwardInvocation:invocation];

    XCTAssertEqual(self.externalDelegate.didZoomCallCount, 0);
}

@end
