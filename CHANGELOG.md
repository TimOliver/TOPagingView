x.y.z Release Notes (yyyy-MM-dd)
=============================================================

1.4.0 Release Notes (2026-03-30)
=============================================================

## Enhancements

* Rebuilt scroll mechanism to rely on `UIScrollViewDelegate`, the official way to receive scroll notifications.
* Rebuilt `turnToNextPage` APIs to be driven dynamically, allowing more fluid motion and interruptibility.

## Breaking Changes

* Renamed `dynmamicPageDirection` to `adaptivePageDirection`.
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
