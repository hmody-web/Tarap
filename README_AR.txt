SAFE V4

سبب crash V3/VANY:
كان hook لـ UITabBarController.viewDidLayoutSubviews يتم عبر Method موروث،
وهذا ممكن يعدل UIViewController.viewDidLayoutSubviews لكل التطبيق.

V4:
- ينشئ override خاص بـ UITabBarController فقط عبر class_addMethod.
- لا يغير UIViewController العام.
- يحتفظ بمنطق V2 للـ UITabBar لأنه ثبت أنه يعمل.
- يصفر BannerHeightManager.
- يحاول تمديد محتوى الصفحة خلف الـ tab bar بدون إخفاء views عشوائية.
- يقبل أي IPA موجود مهما كان اسمه.

الأفضل استخدام آخر IPA ثبت أنه يفتح عندك كـ input.
الناتج:
Tarab_5.11_LayoutCleaner_SAFE_V4.ipa
ثم أعد توقيعه.
