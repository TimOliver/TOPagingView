//
//  TOPagingViewPage.h
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
#import "TOPagingViewTypes.h"

/// Optional protocol that page views may implement.
NS_SWIFT_NAME(PagingViewPage)
@protocol TOPagingViewPage <NSObject>

@optional

/// A unique string value that can be used to let the pager view
/// dequeue pre-made objects with the same identifier, or if pre-registered,
/// create new instances automatically on request.
///
/// If this property is not overridden, the page will be treated as the default
/// type that will be returned whenever the identifier is nil.
+ (NSString *)pageIdentifier;

/// A globally unique identifier that can be used to uniquely tag this specific
/// page objects when they are in active use. This must be finalized before the page
/// is inserted into the paging view.
- (NSString *)uniqueIdentifier;

/// Called just before the page object is removed from the visible page set,
/// and re-enqueued by the data source. Use this method to return the page to a default state.
/// Most importantly, be sure to use this method to release memory heavy objects like images.
- (void)prepareForReuse;

/// The current page on screen is the first page in the current sequence.
/// When dynamic page direction is enabled, scrolling past the initial page in either
/// direction will start incrementing pages in that direction.
- (BOOL)isInitialPage;

/// Passes the current reading direction from the hosting paging view to this page.
/// Use this to re-arrange any sets of subviews that depend on the direction that the pages flow in.
/// - Parameter direction: The ascending direction that the pages will flow in.
- (void)setPageDirection:(TOPagingViewDirection)direction;

@end
