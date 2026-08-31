# LayoutCleaner

هذا البكج يبني Framework داخل Codemagic/macOS ثم يدمجه داخل IPA الحالي.

الوظيفة:
- إخفاء/تصفير حاويات الإعلانات المعروفة.
- محاولة إزالة المساحة الفارغة القريبة من الـ Bottom Tab Bar.
- جعل خلفية UITabBar شفافة مع بقاء الأزرار.

الملفات:
- LayoutCleaner.c : كود التعديل Runtime
- inject_dylib.py : يضيف LC_LOAD_DYLIB إلى الملف التنفيذي
- build_and_merge.sh : يبني ويدمج ويخرج IPA
- codemagic.yaml : Workflow جاهز

طريقة الاستخدام في Codemagic:
1) ضع داخل الريبو هذه الملفات + Tarab_5.11_ProfileOverlay_Merged.ipa
2) استخدم codemagic.yaml
3) شغل workflow باسم Build LayoutCleaner IPA
4) الناتج: Tarab_5.11_LayoutCleaner.ipa
5) أعد توقيع الـ IPA قبل التثبيت.

ملاحظة:
هذا لا يحذف ProfileOverlay.framework ولا PortraitOverlay.framework الموجودين.
