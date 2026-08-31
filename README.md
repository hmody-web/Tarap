Tarab CodeMagic Auto IPA Fix

- لا يعتمد على اسم ثابت للـ IPA.
- يبحث تلقائياً عن أول ملف .ipa داخل مستودع CodeMagic.
- يبني TarabBannerForce مع ldid.
- يبني insert_dylib ثم يضيف LC_LOAD_DYLIB إلى executable.
- يضع الناتج باسم Tarab_Banner_Forced.ipa ضمن Artifacts.

ضع ملف IPA واحد داخل جذر المستودع ثم شغّل workflow: tarab-banner-inject.
ملاحظة: الناتج بعد الحقن غير موقع للتوزيع؛ وقّعه بالطريقة التي تستخدمها عادة قبل التثبيت.
