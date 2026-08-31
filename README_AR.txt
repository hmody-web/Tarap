SAFE V3.1 - FIXED BUILD

الإصلاحات:
- إزالة CGRectGetMinY / CGRectGetMaxY التي سببت Undefined symbols.
- استخدام حساب مباشر للـ CGRect بدون أي رموز إضافية.
- استبدال scrollIndicatorInsets القديم بـ
  verticalScrollIndicatorInsets / horizontalScrollIndicatorInsets.
- نفس وظيفة V3 بدون تغيير:
  * محتوى الصفحة يمتد خلف الـ Bottom Tab Bar.
  * الـ Tab Bar يبقى شفاف/زجاجي.
  * BannerHeightManager يبقى مصفر.
  * لا يوجد UIViewController hook العام القديم.

ضع IPA الأصلي المدموج داخل نفس الريبو.
الناتج:
Tarab_5.11_LayoutCleaner_SAFE_V3_1.ipa

ثم أعد توقيعه قبل التثبيت.
