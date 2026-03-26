//
//  TOPagingViewTypes.h
//
//  Copyright 2018-2026 Timothy Oliver. All rights reserved.
//

#pragma once

#import <UIKit/UIKit.h>

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
