LayoutCleaner - النسخة المصححة

طريقة الاستخدام:

1. ارفع هذه الملفات إلى GitHub / Codemagic:
   - LayoutCleaner.c
   - inject_dylib.py
   - build_and_merge.sh
   - codemagic.yaml

2. ضع ملف الـ IPA داخل نفس الريبو.
   لا يهم اسم الملف.

3. شغّل Workflow:
   Build LayoutCleaner IPA

4. السكربت سيبحث تلقائياً عن أول ملف .ipa.

5. الناتج:
   Tarab_5.11_LayoutCleaner.ipa

6. أعد توقيع الناتج قبل التثبيت.

وظيفة LayoutCleaner:
- إخفاء حاويات الإعلان المعروفة.
- تصفير ارتفاع حاوية الإعلان عند الإمكان.
- إزالة/تقليص المساحة الفارغة القريبة من Bottom Tab Bar.
- جعل خلفية UITabBar شفافة.
- الإبقاء على ProfileOverlay.framework و PortraitOverlay.framework بدون حذف.

مهم:
إذا ظهر:
No IPA file found

فهذا يعني أن ملف IPA نفسه غير موجود داخل Git repository الذي يقوم Codemagic باستنساخه.
