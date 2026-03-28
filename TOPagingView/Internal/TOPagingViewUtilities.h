//
//  TOPagingViewUtilities.h
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

#pragma once

#import <Foundation/Foundation.h>
#import "TOPagingViewTypes.h"
#import "TOPagingViewTypesPrivate.h"

/// Convert an Objective-C class pointer into an NSValue that can be stored in a dictionary.
static inline NSValue *TOPagingViewValueForClass(Class *class) {
    return [NSValue valueWithBytes:class objCType:@encode(Class)];
}

/// Convert an Objective-C class that was encoded to NSValue back out again.
static inline Class TOPagingViewClassForValue(NSValue *value) {
    Class class;
    [value getValue:&class];
    return class;
}

/// Convenience function for detecting when the paging view is set right-to-left.
static inline BOOL TOPagingViewIsDirectionReversed(TOPagingViewDirection direction) {
    return (direction == TOPagingViewDirectionRightToLeft);
}

/// Convenience function to reset dragging state once we've fired the previous delegate call.
static inline TOPagingViewDraggingState TOPagingViewDraggingStateReset(void) {
    return (TOPagingViewDraggingState){
        .origin = -CGFLOAT_MAX,
        .directionType = TOPagingViewPageTypeCurrent
    };
}
