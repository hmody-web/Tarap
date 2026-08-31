LayoutCleaner SAFE V2

سبب التغيير:
النسخة السابقة كانت تعمل Hook عام على UIViewController وتفحص شجرة الـViews.
هذا ممكن يسبب crash عند الإقلاع.

SAFE V2:
- لا تعمل Hook على UIViewController نهائياً.
- تستهدف BannerHeightManager الموجود داخل Tarab فقط.
- تجبر:
  bannerHeight = 0
  inlineBannerHeight = 0
  bannerBottomPadding = 0 (إن وجد)
  shouldShowBanner = false (إن وجد)
- تجعل UITabBar شفاف باستخدام UITabBarAppearance.
- تبقي ProfileOverlay.framework وPortraitOverlay.framework بدون تغيير.

مهم:
ضع IPA الأصلي المدموج:
Tarab_5.11_ProfileOverlay_Merged.ipa
مع هذه الملفات في نفس GitHub repo.

شغل Codemagic.
الناتج:
Tarab_5.11_LayoutCleaner_SAFE_V2.ipa

ثم وقعه وثبته.
