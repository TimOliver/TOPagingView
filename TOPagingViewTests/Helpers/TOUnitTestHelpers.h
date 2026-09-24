//
//  TOUnitTestHelpers.h
//  TOPagingViewTests
//
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "TOUnitTestPageView.h"

NS_ASSUME_NONNULL_BEGIN

UIView *TOCreatePrivateScrollViewSubview(void);
TOUnitTestPageView *_Nullable TOTestPageView(UIView<TOPagingViewPage> *_Nullable pageView);

NS_ASSUME_NONNULL_END
