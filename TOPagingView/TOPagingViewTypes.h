//
//  TOPagingViewTypes.h
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

/// An enumeration of directions in which the scroll view may display pages.
typedef NS_ENUM(NSInteger, TOPagingViewDirection) {
    TOPagingViewDirectionLeftToRight = 0, // Western style page ordering
    TOPagingViewDirectionRightToLeft = 1  // Eastern style page ordering
} NS_SWIFT_NAME(PagingViewDirection);

/// An enumeration denoting the kind of page being requested by the data source.
typedef NS_ENUM(NSInteger, TOPagingViewPageType) {
    TOPagingViewPageTypeCurrent,  // The center page, displayed by default.
    TOPagingViewPageTypeNext,     // The next, incoming page after the current page.
    TOPagingViewPageTypePrevious  // The previous, outgoing page before the current page.
} NS_SWIFT_NAME(PagingViewPageType);
