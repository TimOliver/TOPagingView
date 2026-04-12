//
//  TOPagingViewTypesPrivate.h
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

/// A struct to cache which methods the current delegate implements.
typedef struct {
    unsigned int delegateWillTurnToPage : 1;
    unsigned int delegateDidTurnToPage : 1;
    unsigned int delegateDidChangeToPageDirection : 1;
} TOPagingViewDelegateFlags;

/// A struct to cache which methods each page view class implements.
typedef struct {
    unsigned int protocolPageIdentifier : 1;
    unsigned int protocolUniqueIdentifier : 1;
    unsigned int protocolPrepareForReuse : 1;
    unsigned int protocolIsInitialPage : 1;
    unsigned int protocolSetPageDirection : 1;
} TOPageViewProtocolFlags;

/// Per-scroll metrics cached once and threaded through the hot layout helpers.
typedef struct {
    CGFloat offsetX;
    CGFloat segmentWidth;
    CGFloat contentWidth;
    BOOL isReversed;
    BOOL isDetectingDirection;
} TOPagingViewScrollMetrics;

/// Cached geometry values used throughout layout, scrolling, and transitions.
typedef struct {
    CGFloat pageWidth;
    CGFloat halfPageSpacing;
    CGRect scrollViewFrame;
    CGRect currentPageFrame;
    CGRect nextPageFrame;
    CGRect previousPageFrame;
    CGRect leftPageFrame;
    CGRect rightPageFrame;
} TOPagingViewLayoutMetrics;

/// Cached device and motion metrics during a single animator session.
typedef struct {
    CGFloat displayScale;
    CGFloat pixelSize;
    CGFloat animationDragCoefficient;
} TOPagingViewAnimatorEnvironmentMetrics;

/// State used to detect when the user starts or changes swiping directions
typedef struct {
    CGFloat origin;
    TOPagingViewPageType directionType;
} TOPagingViewDraggingState;
