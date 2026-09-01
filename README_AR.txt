Tarab Remote Banner — مستقل

الأساس:
Tarab_fleXD_Editable (8)(2).ipa الذي رفعه المستخدم.

API:
https://scrptaty.com/apps/tarab/api.php

يقرأ:
banners[].id
banners[].title
banners[].description
banners[].cover_url
banners[].icon_url
banners[].download_url
banners[].enabled
banners[].sort_order

السلوك:
- يظهر فقط في صفحة المصادر.
- يضيف مساحة أعلى محتوى الصفحة ويضع البنر الجديد قبل البنر الأصلي.
- أكثر من بنر: سحب أفقي + تبديل تلقائي كل 5 ثوانٍ + نقاط صفحات.
- صورة غلاف + أيقونة + عنوان + وصف + زر تنزيل.
- enabled=false لا يظهر.
- sort_order يحدد الترتيب.
- إذا API فشل لا يظهر البنر.
- الصور تُحمّل وتُخزن مؤقتًا في الذاكرة.
- زر تنزيل يفتح download_url.
- لا يحذف أو يستبدل FLEXDInject / ProfileOverlay / PortraitOverlay أو أي Framework موجود.

الناتج:
Tarab_RemoteBanner_Injected.ipa

بعد البناء:
وقّع IPA الناتج بأداتك المعتادة ثم ثبته.

تعديل v2:
- إصلاح انعكاس الصور/المحتوى.
- المقاس إجباري 358x160.
- البنر Overlay فوق البنر الأصلي مباشرة، بدون دفع المحتوى للأسفل.

تعديل v3:
- Y ثابت وإجباري = -325 في الإنشاء وكل layout pass.
- المقاس ثابت 358x160.
- إلغاء الانعكاس البصري الناتج من SwiftUI المضيف على كامل البنر.
- اتجاه عربي RTL صريح للنصوص.
- ظل ناعم خلف الأيقونة.
- تحسين السحب/deceleration والحواف.
- نقاط الصفحات داخل البنر.
- فقاعات/نسيم برمجية خفيفة متحركة فوق الخلفية.

تعديل v4:
- Y ثابت = -157.
- رفع zPosition للبنر إلى 9999999.
- إعادة bringSubviewToFront بعد كل layout.
- رفع فرع الـUIScrollView داخل hierarchy حتى لا تغطيه SwiftUI sibling overlays.
- الحفاظ على باقي تعديلات v3 كاملة.

تعديل v5 FREE OVERLAY:
- البنر مستقل كلياً عن UITableView/UICollectionView/UIScrollView.
- TRBBannerCarousel يضاف مباشرة إلى root view لصفحة المصادر.
- لا contentInset ولا contentOffset ولا تحريك للقائمة.
- الإحداثيات الحالية الحرة: X=16, Y=-157, W=358, H=160.
- لتغيير المكان لاحقاً عدّل TRBFreeX وTRBFreeY فقط.
- يبقى فوق محتوى الصفحة عبر zPosition وbringSubviewToFront.

v5.1 build fix:
- Fix TRBOriginalViewDidLayout IMP invocation.
- Restore TRBInstallHooks after free-overlay refactor.
- No visual/layout/API changes.
- Keeps X=16, Y=-157, W=358, H=160 and independent root-view overlay.

v5.2:
- X=16, Y=117.
- Width remains 358.
- Height changed from 160 to 180.
- Removed the whole-banner horizontal flip.
- Cover image and icon forced to identity transform.
- Arabic title/description forced to proper RTL writing direction and right alignment.
- Keeps the free independent overlay and all previous API/design behavior.

v5.3 STRICT SOURCES:
- Banner appears only on main Sources root.
- Hides immediately on tab switch, push, modal, YouTube/Google/Instagram/Facebook/TikTok pages.
- Removes duplicate TRBBannerCarousel instances.
- Adds 12pt real spacing between banners with custom snapping.
- Keeps X=16, Y=117, W=358, H=180.

v5.3.1 BUILD FIX:
- No behavior/layout changes.
- Added forward declarations for TRBStringContains and TRBIsSourcesPage.
- Moved kTRBCarouselKey declaration before strict helper usage.
- Keeps strict Sources-only visibility, duplicate cleanup, 12pt banner spacing,
  and X=16 / Y=117 / W=358 / H=180.

v5.3.2:
- Fixes banner disappearing completely.
- Removes the fragile YouTube/Trending text scan.
- Sources root is detected using the original working Sources detector plus:
  top/root navigation controller checks and selected tab checks.
- Banner is explicitly unhidden on returning to Sources.
- Still hides in viewWillDisappear and on pushed/presented child pages.
- Keeps duplicate cleanup, 12pt spacing, X=16 Y=117 W=358 H=180.

v5.4:
- Keeps all v5.3.2 behavior.
- Adds accessibility identifiers: TRBBannerCarousel, TRBBannerPage, TRBBannerBackdrop.
- Banner is restored automatically when returning to Sources, even with custom tab containers.
- Adds full-width theme-aware background behind banner:
  x=0, y=117, width=100% of page, height=180.
  Uses systemBackgroundColor so it follows dark/light appearance automatically.
- Removes page dots completely from view.
- Keeps banner frame X=16 Y=117 W=358 H=180.
- Keeps 12pt spacing and duplicate cleanup.

v5.4.1 BUILD FIX:
- Fixed Objective-C compile error:
  vc.children -> vc.childViewControllers
- No visual or behavioral changes.
- Keeps return-to-Sources restore, theme-aware full-width backdrop,
  hidden page dots, duplicate cleanup, 12pt spacing,
  X=16 Y=117 W=358 H=180.

v5.5 INSTANT + OFFLINE CACHE:
- Preserves all v5.4.1 modifications.
- Restores banner synchronously/immediately when Sources becomes visible.
- Reads cached banners.json before any network wait.
- Successful API JSON is persisted to disk.
- Cover/icon image bytes are persisted to disk cache.
- Offline mode keeps the last successful banners, metadata, covers, and icons visible.
- Network failure never hides valid cached/current banners.
- UIPageControl is not created at all, so _UIPageControlIndicatorContentView is absent.
- Custom-tab fallback reconcile interval reduced to 0.15 sec.
- Keeps theme-aware full-width backdrop, X=16 Y=117 W=358 H=180, and 12pt page gap.

v5.6 SOURCES GUARD:
- Preserves all v5.5 cache/theme/size/spacing changes.
- Replaces fragile lifecycle-only visibility with a global Sources-page guard.
- Every 0.10 sec the current visible controller tree is inspected.
- Exactly one banner is allowed: only on the visible main Sources screen.
- All banners/backdrops attached to other pages are forcibly hidden.
- Returning to Sources forces cached banner + backdrop visible immediately.
- Initial reconciliation runs immediately, not after timer delay.
- Main Sources recognition uses visible YouTube + Trending controls together,
  with a standard selected-tab fallback.
- Still uses persistent JSON/image cache and no UIPageControl.

v5.7 SOURCES SUBTREE:
- Keeps all v5.6 cache/theme/spacing changes.
- Banner is mounted inside the Sources content subtree itself.
- It is never hidden on viewWillDisappear.
- Child pages naturally cover it because they are above the Sources subtree.
- Returning to Sources reveals the already-mounted banner instantly.
- Switching tabs hides the entire Sources subtree naturally.
- Timer is install-only fallback; it never hides or changes global z-order.
