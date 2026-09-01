Tarab Banner Hider FORCE

الهدف:
- إخفاء البنر الأصلي الظاهر في FLEX كـ UIView بحجم 358x160.
- إخفاء مرفقاته القريبة مثل نقاط UIPageControl.
- إجبار hidden=YES و alpha=0 حتى لو التطبيق حاول إظهاره من جديد.
- فحص مستمر وإعادة الإخفاء عند إعادة إنشاء البنر.
- لا يعيد إضافة TarabRemoteBanner السابق.

ارفع محتويات هذا المشروع إلى Codemagic وشغّل workflow: ios-unsigned.

v1.1 BUILD FIX:
- Added explicit xcodebuild destination:
  -destination 'generic/platform=iOS'
- No changes to the forced banner hiding logic.

v1.2 FIXED:
- Build output is a framework, not a dylib.
- Correctly locates TarabBannerHider.framework.
- Unzips the IPA.
- Copies the framework into App/Frameworks.
- Injects @rpath/TarabBannerHider.framework/TarabBannerHider into the app executable.
- Verifies injection with otool.
- Repackages the IPA.
- No changes to the forced hiding logic.

v1.3 PAGING:
- Keeps the previous forced banner-hiding changes.
- Adds exact targeting for SwiftUI UIKitPagingCell.
- Target signature: UICollectionViewCell / UIKitPagingCell with 358x160 bounds.
- Force-hides the owning UICollectionView and its same-sized wrapper.
- Re-applies after didMoveToWindow and layoutSubviews so SwiftUI cannot simply restore it.

v1.4 DOTS:
- Keeps the successful v1.3 UIKitPagingCell 358x160 banner hiding.
- Hides the four remaining SwiftUI page dots.
- FLEX cannot select those dots because SwiftUI renders them internally.
- Adds a narrow theme-aware systemBackgroundColor cover directly below
  the detected original banner paging collection.
- Reapplies every 0.10s so SwiftUI cannot redraw the dots.
- Does not globally hide UIPageControl or other indicators in the app.

Sources Top Header v1:
- Uses the user's exact supplied JPEG; no image was generated or altered.
- Full-width systemBackgroundColor rectangle at the very top.
- Centered image with Aspect Fit.
- Visible only on the root Sources page and hidden on source detail pages/other tabs.
- Re-evaluated every 0.05s for immediate return when Sources becomes visible.

v1.1 PACKAGE FIX:
- Fixed Package.swift syntax.
- resources is now correctly inside the TarabBannerHider target.
- platforms remains .iOS(.v15).
- No visual or runtime behavior changed.

v1.2 RESOURCE FIX:
- Removed SwiftPM resources completely because this Objective-C target/toolchain
  does not accept the resources argument.
- Package.swift is now the same compatible format used by the successful hider.
- build_and_inject.sh copies the user's exact TarabSourcesHeader.jpeg directly
  into TarabBannerHider.framework after xcodebuild succeeds.
- Runtime loads the JPEG directly from TarabBannerHider.framework.
- No image generation or modification.
- No change to banner hiding or Sources-only top header behavior.

v1.3 REAL RUNTIME CLASS:
- Header now uses real Objective-C classes:
  TRBSourcesTopHeaderView
  TRBSourcesTopHeaderImageView
- These names are visible/searchable in FLEX Runtime Browser.
- Existing accessibility identifiers remain unchanged.

v1.4 IMMEDIATE CREATE:
- TRBSourcesTopHeaderView and TRBSourcesTopHeaderImageView are real Objective-C runtime classes.
- Header instance is created immediately when the framework constructor executes.
- It is attached to every available UIWindow immediately, hidden by default.
- Sources visibility only toggles hidden/alpha; it no longer controls object creation.
- Also creates/refreshes on UIWindowDidBecomeKey and UIApplicationDidBecomeActive.
- Fast 0.05s fallback remains.
- FLEX Runtime Browser should find TRBSourcesTopHeaderView even when hidden.

v1.5 FORCE VISIBLE:
- Header is attached directly to the current Sources UIViewController.view, not the UIWindow.
- On Sources: hidden=NO and alpha=1 are forced continuously.
- zPosition=99999999 inside the current page only.
- Sources detection uses tab/controller title plus visible source-button markers.
- Legacy window-level header is disabled.
- Other pages do not receive the header.
- Refresh fallback is 0.03 seconds.

v1.6 GLASS ROOT ONLY:
- Uses the user's exact transparent PNG, no generated/edited image.
- Replaces flat/systemBackgroundColor header with UIKit system-material blur glass.
- 12pt horizontal safe margins, continuous rounded corners.
- Image reduced and centered with Aspect Fit.
- Header qualifies ONLY on the current Sources HOME controller.
- Child pages (YouTube/Google/Instagram/TikTok/etc.) cannot inherit Sources status
  from parent/tab controllers.
- Requires at least 3 visible Sources-home markers on the current VC.

v1.7 RUNTIME GLASS:
- TRBSourcesTopHeaderView is now a real UIVisualEffectView subclass.
- Instance is created immediately on each active UIWindow.
- FLEX Runtime Browser / View hierarchy can find TRBSourcesTopHeaderView even when hidden.
- Visibility uses frontmost visible Sources-home markers across the window.
- Underlying Sources controls covered by YouTube/Google/etc. do not count as frontmost.
- Header is shown only when at least 3 Sources-home markers are actually frontmost.
- Exact transparent PNG and system-material glass are preserved.

v1.8 FORCE SOURCES TAB:
- Header class already exists; this fixes it remaining hidden.
- Visibility no longer depends on frontmost text markers.
- Uses selected Sources tab + navigation root state.
- On Sources root: hidden=NO and alpha=1 are forced every refresh.
- On pushed child pages (YouTube/Google/Instagram/TikTok/etc.): hidden=YES.
- On other tabs: hidden=YES.
- Refresh interval reduced to 0.01s for instant return.
