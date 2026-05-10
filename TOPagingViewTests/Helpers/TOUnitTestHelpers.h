//
//  TOUnitTestHelpers.h
//  TOPagingViewTests
//
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "TOUnitTestPageView.h"

UIView *TOCreatePrivateScrollViewSubview(void);
TOUnitTestPageView *TOTestPageView(UIView<TOPagingViewPage> *pageView);
