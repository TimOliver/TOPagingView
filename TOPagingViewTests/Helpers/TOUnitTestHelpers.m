//
//  TOUnitTestHelpers.m
//  TOPagingViewTests
//
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import "TOUnitTestHelpers.h"

#import <objc/runtime.h>

UIView *TOCreatePrivateScrollViewSubview(void) {
    static Class privateSubviewClass;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        privateSubviewClass = objc_getClass("_TOPrivateScrollViewSubview");
        if (privateSubviewClass == Nil) {
            privateSubviewClass = objc_allocateClassPair(UIView.class, "_TOPrivateScrollViewSubview", 0);
            objc_registerClassPair(privateSubviewClass);
        }
    });
    return [[privateSubviewClass alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
}

TOUnitTestPageView *TOTestPageView(UIView<TOPagingViewPage> *pageView) {
    return (TOUnitTestPageView *)pageView;
}
