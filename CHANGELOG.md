x.y.z Release Notes (yyyy-MM-dd)
=============================================================

1.5.0 Release Notes (2026-05-10)
=============================================================

## Enhancements

* Rebuilt the page-turn APIs to perform a rubber-banding animation when overshooting the first or final page.
* Replaced the pre-canned page-wall wobble animation with the new rubber-banding motion.

## Fixed

* Fixed stale scroll view edge insets that could keep newly available adjacent pages unreachable after async data updates.
* Fixed page width/layout metric drift when using fractional bounds or custom page spacing.
* Fixed `reload` behavior so active page-turn animations are stopped before page state is rebuilt.
* Fixed unnecessary page reload work when `TOPagingView` is removed from its superview.
* Fixed adaptive initial-page refresh so it no longer fetches or installs a separate previous page unnecessarily.
* Fixed rapid stacked page-turn animation timing to keep animation sampling and retiming on the same frame clock.
* Fixed reusable page pooling for manually-created page views whose reuse queue had not been created yet.
* Fixed skip-to-new-page calls so missing or already-visible replacement pages no longer corrupt the current paging state.

## Internal

* Corrected the pointer-drag scrolling selector invocation to use the expected BOOL calling convention.
* Cleaned up stale comments and removed a compiler warning.

1.4.0 Release Notes (2026-03-30)
=============================================================

## Enhancements

* Rebuilt scroll mechanism to rely on `UIScrollViewDelegate`, the official way to receive scroll notifications.
* Rebuilt `turnToNextPage` APIs to be driven dynamically, allowing more fluid motion and interruptibility.

## Breaking Changes

* Renamed `dynamicPageDirection` to `adaptivePageDirection`.
* Accessing the `scrollView` delegate must now be done via `scrollViewDelegate`.

1.3.0 Release Notes (2025-11-10)
=============================================================

## Added

* Dynamic page direction to allow the user to start advancing from either direction.

## Enhancements

* Refined the caching of delegate access checks for greater performance.


1.2.0 Release Notes (2023-10-23)
=============================================================

## Changes

* For greater efficiency, all of the data source methods are combined into one.
* More performance improvements.


1.1.0 Release Notes (2022-02-04)
=============================================================

## Fixed

* Keyboard controls not working in iOS 15.

## Enhancements

* Streamlined name of library to `TOPagingView`.

1.0.1 Release Notes (2020-04-19)
=============================================================

## Fixed

* A bug where page layout wouldn't align when the device was rotated.

1.0.0 Release Notes (2020-04-19)
=============================================================

* Initial Release! 🎉
