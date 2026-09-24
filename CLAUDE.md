# CLAUDE.md

## Project Overview

TOPagingView is an Objective-C iOS library for horizontal paged scrolling with an arbitrary (potentially infinite) number of pages. It uses a three-slot virtual carousel and recycles page views as the user scrolls. Reuse queues may retain additional pages. Version 1.5.0, MIT licensed, minimum iOS 12.0, no external dependencies.

## Architecture

**Three-slot carousel**: The scroll view always has 3 page-width segments. The current page sits in the center slot. When a turn crosses its commit threshold, pages rotate (previous is reclaimed, current becomes previous, next becomes current) and the content offset is rebased back to center. User swipes commit when the adjacent page lands; programmatic turns commit just after leaving center so recycling keeps ahead of the animation. This creates the illusion of infinite scrolling.

**Key files:**
- `TOPagingView/TOPagingView.h` - Public API (data source, delegate, control methods)
- `TOPagingView/TOPagingView.m` - Core implementation: layout, transitions, recycling
- `TOPagingView/TOPagingViewTypes.h` - Public enums (direction, page type)
- `TOPagingView/TOPagingViewPage.h` - Optional protocol for page views
- `TOPagingView/Internal/TOPagingViewAnimator.h/.m` - Native spring page turns with a display-link adapter for slot recycling
- `TOPagingView/Internal/TOScrollViewDelegateProxy.h/.m` - NSProxy that intercepts scroll events
- `TOPagingView/Internal/TOPagingView+Keyboard.h/.m` - Arrow key support (category)
- `TOPagingView/Internal/TOPageViewProtocolCache.h/.m` - Caches which protocol methods each page class implements
- `TOPagingView/Internal/TOPagingViewConstants.h` - Static configuration constants
- `TOPagingView/Internal/TOPagingViewMacros.h` - objc_direct macro
- `TOPagingView/Internal/TOPagingViewTypesPrivate.h` - Private structs (flags, metrics, state)
- `TOPagingView/Internal/TOPagingViewUtilities.h` - Inline utility functions

**Internal components:**
- **Animator** (`TOPagingViewAnimator`): UIViewPropertyAnimator supplies spring timing through a transparent carrier view. A CADisplayLink samples its presentation position at up to 120Hz and applies it to the scroll view. Slot recycling changes a coordinate translation without retiming the spring. Each tap restarts the duration for the entire queued distance; missing pages hand the current velocity to a boundary spring.
- **Delegate Proxy** (`TOScrollViewDelegateProxy`): NSProxy subclass that intercepts `scrollViewDidScroll:`, `scrollViewWillBeginDragging:`, and `scrollViewDidEndDragging:willDecelerate:` while forwarding all other `UIScrollViewDelegate` methods
- **Protocol Cache**: NSMapTable with pointer-based keys to avoid NSStringFromClass allocations; caches which optional `TOPagingViewPage` methods each page view class responds to

## Build & Test

Open `TOPagingView.xcodeproj` in Xcode. Four targets:
- **TOPagingView** - The library framework
- **TOPagingViewExample** - Demo app with tap-to-turn, direction toggle, keyboard support
- **TOPagingViewTests** - Unit tests (initialization, recycling, boundaries, delegate callbacks, reload, direction)
- **TOPagingViewUITests** - UI automation tests (repeated edge taps, drag handoff, swipes, bounce, direction, and rotation)

Distribution: CocoaPods (`TOPagingView.podspec`) and Swift Package Manager (`Package.swift`).

## Code Conventions

- **Objective-C only**, ARC enabled, no Swift bridging
- **Formatting**: `.clang-format` config present (LLVM base, 4-space indent, 130-char column limit, pointer-right alignment)
- **Internal methods**: Prefix internal helpers and actions with `_`, including internal component APIs and test helpers. Preserve public API names, property accessors, framework overrides, protocol callbacks, and XCTest test entry points.
- **Immutable locals**: Use `const Type` for values and `Type *const` for object references that are not reassigned. Use `Class const` and `void (^const handler)(void)` where appropriate. Mutable objects can still have constant pointers; leave counters, out parameters, and reassigned locals mutable.
- **Readability**: Separate logical operations with blank lines. Keep conditionals, callbacks, and method bodies expanded; the formatter must preserve this style.
- **Performance-critical internal methods**: Use `TOPAGINGVIEW_OBJC_DIRECT` macro for static dispatch
- **Hot-path logic**: Implemented as `static inline` C functions rather than Objective-C methods (e.g., `TOPagingViewLayoutPages`, `TOPagingViewTransitionOverToNextPage`)
- **ivars over properties** for internal state (declared in `@implementation {}` block)
- **Struct caching**: Layout metrics, delegate flags, and protocol flags are cached in C structs to avoid repeated computation
- **`_disableLayout` guard pattern**: Reentrant layout is temporarily suppressed during multi-step scroll view modifications using this flag
- **Run-loop deferral**: Page refills are normally deferred via `_needsNextPage`/`_needsPreviousPage` and `setNeedsLayout`, but a subsequent turn or scroll callback can fulfill a pending slot synchronously before committing it
- **NS_SWIFT_NAME annotations** on all public types for clean Swift interop
- **Commit style**: Short imperative sentences (e.g., "Fixed potential nil-terminated crash", "Removed unused ivar and grammar improvements")
