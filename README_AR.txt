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
