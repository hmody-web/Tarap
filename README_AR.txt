Tarab MKTabBar Fix V8

هذه النسخة تستهدف الكلاس الحقيقي الموجود داخل Tarab:
MKTabBarViewController

ولا تعمل hook عام على UIViewController.

العمل:
- override لـ viewDidLayoutSubviews فقط داخل MKTabBarViewController.
- override لـ viewSafeAreaInsetsDidChange فقط داخل MKTabBarViewController.
- تصفير additionalSafeAreaInsets.
- تمديد child controllers وcontainers إلى أسفل الشاشة.
- تمديد أكبر UIScrollView داخل كل tab.
- عدم تغيير حجم/إخفاء الـtab bar نفسه.
- إبقاء UITabBar شفاف/زجاجي.
- تنظيف background/backdrop containers داخل MKTabBar root فقط.

Codemagic:
- يقبل أي IPA مهما كان اسمه.
- الأفضل وجود IPA واحد فقط في الريبو.
- الناتج:
  Tarab_MKTabBarFix_V8.zip

داخل ZIP:
- Tarab_MKTabBarFix_V8.ipa
- README_AR.txt

استخرج IPA ثم أعد توقيعه وجربه.
