//
//  TOPagingViewConstants.h
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

#import <UIKit/UIView.h>

/// For pages that don't specify an identifier, this string will be used.
static NSString *const kTOPagingViewDefaultIdentifier = @"TOPagingView.DefaultPageIdentifier";

/// There are always 3 slots, with content insetting used to block pages on either side.
static const CGFloat kTOPagingViewPageSlotCount = 3.0f;

/// The amount of padding along the edge of the screen shown when the "no incoming page" animation plays.
static const CGFloat kTOPagingViewBumperWidthCompact = 48.0f;
static const CGFloat kTOPagingViewBumperWidthRegular = 96.0f;

/// The animation options used for the bounce animation.
static const NSInteger kTOPagingViewAnimationOptions = (UIViewAnimationOptionAllowUserInteraction);
