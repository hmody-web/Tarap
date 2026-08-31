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
