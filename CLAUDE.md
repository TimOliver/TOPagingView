# CLAUDE.md

## Project Overview

TOPagingView is an Objective-C iOS library for horizontal paged scrolling with an arbitrary (potentially infinite) number of pages. It uses a three-slot virtual carousel that keeps exactly 3 page views in memory, recycling them as the user scrolls. Version 1.3.0, MIT licensed, minimum iOS 12.0, no external dependencies.

## Architecture

**Three-slot carousel**: The scroll view always has 3 page-width segments. The current page sits in the center slot. When the user scrolls past the midpoint, pages rotate (previous is reclaimed, current becomes previous, next becomes current) and the content offset is rebased back to center. This creates the illusion of infinite scrolling.

**Key files:**
- `TOPagingView/TOPagingView.h` - Public API (data source, delegate, control methods)
- `TOPagingView/TOPagingView.m` - Core implementation (~1215 lines): layout, transitions, recycling
- `TOPagingView/TOPagingViewTypes.h` - Public enums (direction, page type)
- `TOPagingView/TOPagingViewPage.h` - Optional protocol for page views
- `TOPagingView/Internal/TOPagingViewAnimator.h/.m` - CADisplayLink-driven 120fps page turn animation
- `TOPagingView/Internal/TOScrollViewDelegateProxy.h/.m` - NSProxy that intercepts scroll events
- `TOPagingView/Internal/TOPagingView+Keyboard.h/.m` - Arrow key support (category)
- `TOPagingView/Internal/TOPageViewProtocolCache.h/.m` - Caches which protocol methods each page class implements
- `TOPagingView/Internal/TOPagingViewConstants.h` - Static configuration constants
- `TOPagingView/Internal/TOPagingViewMacros.h` - objc_direct macro
- `TOPagingView/Internal/TOPagingViewTypesPrivate.h` - Private structs (flags, metrics, state)
- `TOPagingView/Internal/TOPagingViewUtilities.h` - Inline utility functions

**Internal components:**
- **Animator** (`TOPagingViewAnimator`): CADisplayLink at 120fps, cubic bezier easing, velocity-aware clamping, animation stacking for rapid taps, handles page rebasing mid-animation
- **Delegate Proxy** (`TOScrollViewDelegateProxy`): NSProxy subclass that intercepts `scrollViewDidScroll:` and `scrollViewWillBeginDragging:` while forwarding all other `UIScrollViewDelegate` methods
- **Protocol Cache**: NSMapTable with pointer-based keys to avoid NSStringFromClass allocations; caches which optional `TOPagingViewPage` methods each page view class responds to

## Build & Test

Open `TOPagingView.xcodeproj` in Xcode. Four targets:
- **TOPagingView** - The library framework
- **TOPagingViewExample** - Demo app with tap-to-turn, direction toggle, keyboard support
- **TOPagingViewTests** - Unit tests (currently placeholder only)
- **TOPagingViewUITests** - UI automation tests (rapid tap test, drag-during-animation test)

Distribution: CocoaPods only (`TOPagingView.podspec`). No Swift Package Manager support yet.

## Code Conventions

- **Objective-C only**, ARC enabled, no Swift bridging
- **Formatting**: `.clang-format` config present (LLVM base, 4-space indent, 130-char column limit, pointer-right alignment)
- **Private methods**: Prefixed with underscore (e.g., `_setUp`, `_layoutPages`, `_fetchNewNextPage`)
- **Performance-critical internal methods**: Use `TOPAGINGVIEW_OBJC_DIRECT` macro for static dispatch
- **Hot-path logic**: Implemented as `static inline` C functions rather than Objective-C methods (e.g., `TOPagingViewLayoutPages`, `TOPagingViewTransitionOverToNextPage`)
- **ivars over properties** for internal state (declared in `@implementation {}` block)
- **Struct caching**: Layout metrics, delegate flags, and protocol flags are cached in C structs to avoid repeated computation
- **`_disableLayout` guard pattern**: Layout observers are temporarily paused during multi-step scroll view modifications using this flag
- **Run-loop deferral**: Heavy work (fetching new pages after a transition) is deferred to the next layout pass via `_needsNextPage`/`_needsPreviousPage` flags + `setNeedsLayout`
- **NS_SWIFT_NAME annotations** on all public types for clean Swift interop
- **Commit style**: Short imperative sentences (e.g., "Fixed potential nil-terminated crash", "Removed unused ivar and grammar improvements")
