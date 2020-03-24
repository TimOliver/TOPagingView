//
//  TODynamicPageView.h
//  TODynamicPageViewExample
//
//  Created by Tim Oliver on 2020/03/24.
//  Copyright © 2020 Tim Oliver. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class TODynamicPageView;

//-------------------------------------------------------------------
/** An enumeration of directions in which the scroll view may display pages. */
typedef enum {
    TODynamicPageViewDirectionLeftToRight = 0, /** Pages ascend from the left, to the right */
    TODynamicPageViewDirectionRightToLeft = 1 /** Pages ascend from the right, to the left */
} TODynamicPageViewDirection;

//-------------------------------------------------------------------

/** Optional protocol that page views may implement. */
@protocol TODynamicPageViewPageProtocol <NSObject>

@optional

/**
 A unique string value that can be used to differentiate
 separate view subclasses managed and displayed by the pager view.
 */
+ (NSString *)pageIdentifier;

/**
 A globally unique identifier that can be used to identify and re-retrieve
 specific page object instances from the page view.
 */
- (NSString *)uniqueIdentifier;

/**
 Called just before the page object is
 dequeued for re-use by the data source
 */
- (void)prepareForReuse;

@end

//-------------------------------------------------------------------

@protocol TODynamicPageViewDataSource <NSObject>

@required

/** Called once upon each reload, the initial page view that will be displayed intially. */
- (nullable UIView *)initialPageViewForDynamicPageView:(TODynamicPageView *)pageView;

/** Using the current page, fetch and return the next page view that will be displayed after it. */
- (nullable UIView *)dynamicPageView:(TODynamicPageView *)pageView
           nextPageViewAfterPageView:(UIView *)previousPageView;

/** Using the current page, fetch and return the previous page view that will be  */
- (nullable UIView *)dynamicPageView:(TODynamicPageView *)pageView
      previousPageViewBeforePageView:(UIView *)nextPageView;

@end

//-------------------------------------------------------------------

@protocol TODynamicPageViewDelegate <NSObject>

@optional

@end

//-------------------------------------------------------------------

@interface TODynamicPageView : UIView

/** Direct access to the scroll view object inside this view (read-only). */
@property (nonatomic, strong, readonly) UIScrollView *scrollView;

/** Data source object to supply page information to the scroll view */
@property (nonatomic, weak, nullable) id <TODynamicPageViewDataSource> dataSource;

/** Delegate object in which page scroll view events are sent. */
@property (nonatomic, weak, nullable) id <TODynamicPageViewDelegate> delegate;

/** Width of the spacing between pages in points (default value of 40). */
@property (nonatomic, assign) CGFloat pageSpacing;

/** The direction of the layout order of pages. */
@property (nonatomic, assign) TODynamicPageViewDirection pageScrollDirection;

/* All of the page view objects currently placed in the scroll view. */
@property (nonatomic, readonly) NSArray<UIView *> *visiblePages;

/** Reload the view from scratch and re-layout all pages */
- (void)reloadPageScrollView;

/** Registers a page view class that can be automatically instantiated as needed. */
- (void)registerPageViewClass:(Class)pageViewClass;

/** Returns a recycled page view from the default pool, ready for re-use. */
- (nullable __kindof UIView *)dequeueReusablePageView;

/** Returns a recycled page view from the pool matching the provided identifier string. */
- (nullable __kindof UIView *)dequeueReusablePageViewForIdentifier:(NSString *)identifier;

/** The currently visible primary view on screen. Can be a page or accessories. */
- (nullable __kindof UIView *)visibleView;

/** The currently visible primary page view on screen. Will be nil if an acessory is visible. */
- (nullable __kindof UIView *)visiblePageView;

/** Returns the visible page view for the supplied unique identifier, or nil otherwise. */
- (nullable __kindof UIView *)pageViewForUniqueIdentifier:(NSString *)identifier;

/** Advance/Retreat the page by one. */
- (void)turnToNextPageAnimated:(BOOL)animated;
- (void)turnToPreviousPageAnimated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
