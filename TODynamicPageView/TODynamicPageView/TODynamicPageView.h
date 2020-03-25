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

/** An enumeration for identifying the types of pages in their specific order. */
typedef enum {
    TODynamicPageViewPageOrderCurrent, /** Pages ascend from the left, to the right */
    TODynamicPageViewPageOrderNext,
    TODynamicPageViewPageOrderPrevious/** Pages ascend from the right, to the left */
} TODynamicPageViewPageOrder;

//-------------------------------------------------------------------

/** Optional protocol that page views may implement. */
@protocol TODynamicPageViewPageProtocol <NSObject>

@optional

/**
 A unique string value that can be used to let the pager view
 dequeue pre-made objects with the same identifier, or if pre-registered,
 create new instances automatically on request.
 
 If this property is not overridden, the page will be treated as the default
 type that will be returned whenever the identifier is nil.
 */
+ (NSString *)pageIdentifier;

/**
 A globally unique identifier that can be used to uniquely tag this specific
 page object. This can be used to retrieve the page from the pager view at a later
 time.
 */
- (NSString *)uniqueIdentifier;

/**
 Called just before the page object is removed from the visible page set,
 and re-enqueud by the data source.
 
 Use this method to return the page to a default state, and to clear out any
 references to memory-heavy objects like images.
 */
- (void)prepareForReuse;

@end

//-------------------------------------------------------------------

@protocol TODynamicPageViewDataSource <NSObject>

@required

/** Called once upon each reload, the initial page view that will be displayed intially. */
- (nullable __kindof UIView *)initialPageViewForDynamicPageView:(TODynamicPageView *)dynamicPageView;

/** Using the current page, fetch and return the next page view that will be displayed after it. */
- (nullable __kindof  UIView *)dynamicPageView:(TODynamicPageView *)dynamicPageView
           nextPageViewAfterPageView:(__kindof UIView *)currentPageView;

/** Using the current page, fetch and return the previous page view that will be  */
- (nullable __kindof  UIView *)dynamicPageView:(TODynamicPageView *)dynamicPageView
      previousPageViewBeforePageView:(__kindof UIView *)currentPageView;

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

/**
 Registers a page view class that can be automatically instantiated as needed.
 If the class overrides `pageIdentifier`, new instances may automatically be created
 when needed. Any classes that do not override that property will become the default
 page class.
 */
- (void)registerPageViewClass:(Class)pageViewClass;

/** Reload the view from scratch and re-layout all pages. */
- (void)reload;

/** Perform a chcek in needing to add a previous or next page that didn't previously exist. */
- (void)setNeedsPageUpdate;

/** Returns a page view from the default queue of pages, ready for re-use. */
- (nullable __kindof UIView *)dequeueReusablePageView;

/** Returns a page view from the specific queue matching the provided identifier string. */
- (nullable __kindof UIView *)dequeueReusablePageViewForIdentifier:(nullable NSString *)identifier;

/** The currently visible primary page view on screen. */
- (nullable __kindof UIView *)currentPageView;

/** The next page after the currently visible page on the screen. */
- (nullable __kindof UIView *)nextPageView;

/** The previous page before the currently visible page on the screen. */
- (nullable __kindof UIView *)previousPageView;

/** Returns the visible page view for the supplied unique identifier, or nil otherwise. */
- (nullable __kindof UIView *)pageViewForUniqueIdentifier:(NSString *)identifier;

/** Advance/Retreat the page by one. */
- (void)turnToNextPageAnimated:(BOOL)animated;
- (void)turnToPreviousPageAnimated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
