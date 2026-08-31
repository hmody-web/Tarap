Tarab + fleXD Editable Runtime Explorer V2

هذه الحزمة تحتوي:
- نفس Tarab RuntimeDiag V9 IPA
- مشروع Swift Package يبني أحدث TimOliver/fleXD من GitHub
- FLEXDInject dynamic framework
- Trigger: ضغط مطول بثلاث أصابع ~0.5 ثانية
- حقن تلقائي داخل IPA
- الناتج: Tarab_fleXD_Editable.ipa

ليش هذه النسخة؟
fleXD الحديثة تدعم:
- تعديل العديد من properties و ivars
- استدعاء instance/class methods
- تعديل ألوان وخلفيات قابلة للكتابة
- فحص View Hierarchy
- تعديل NSUserDefaults

طريقة الاستخدام:
1) ارفع محتويات ZIP إلى repository جديد أو نفس مستودع Codemagic.
2) شغّل workflow: Build Tarab with editable fleXD
3) نزّل Tarab_fleXD_Editable.ipa
4) وقّعه بأداتك المعتادة وثبته.
5) افتح التطبيق واضغط بثلاث أصابع ضغط مطول نصف ثانية تقريباً.

ملاحظة:
بعض قيم SwiftUI / Auto Layout ممكن تتغير ثم يرجع النظام يحسبها،
لكن fleXD نفسها تدعم الكتابة والتعديل Runtime.

V2 fix:
- Removed direct FLEX header import from trigger.
- FLEXManager is invoked using Objective-C runtime.
- Avoids ScanDependencies/header-path failure with current fleXD.
