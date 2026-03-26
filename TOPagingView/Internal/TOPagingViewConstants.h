//
//  TOPagingViewConstants.h
//
//  Copyright 2018-2026 Timothy Oliver. All rights reserved.
//

#pragma once

#import <UIKit/UIKit.h>

/// For pages that don't specify an identifier, this string will be used.
static NSString *const kTOPagingViewDefaultIdentifier = @"TOPagingView.DefaultPageIdentifier";

/// There are always 3 slots, with content insetting used to block pages on either side.
static const CGFloat kTOPagingViewPageSlotCount = 3.0f;

/// The amount of padding along the edge of the screen shown when the "no incoming page" animation plays.
static const CGFloat kTOPagingViewBumperWidthCompact = 48.0f;
static const CGFloat kTOPagingViewBumperWidthRegular = 96.0f;

/// The animation options used for the bounce animation.
static const NSInteger kTOPagingViewAnimationOptions = (UIViewAnimationOptionAllowUserInteraction);
