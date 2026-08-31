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

V4:
- Targets SwiftUI.UpdateCoalescingCollectionView on Sources page.
- Detects original frame around {{0,0},{358,257}}.
- Forces height to 360 on every setFrame call, including after scroll/layout refresh.
- fleXD remains available with the 3-finger long-press trigger.

V5:
- Force all matching UpdateCoalescingCollectionView frames around 358x257 to height 450.
- Restore the previous permanent 390x701 -> 855 patch.
- Both are enforced on every setFrame call, so SwiftUI scroll/layout should not restore old heights.
- fleXD remains available with the 3-finger long-press trigger.

V6:
- Corrected the Sources list patch based on FLEX screenshot.
- SwiftUI._UIInheritedView at 358x257 is now also forced to 358x450.
- UpdateCoalescingCollectionView at 358x257 remains forced to 450.
- Previous UpdateCoalescingCollectionView 390x701 -> 855 patch is preserved.

V8 FROM USER V6:
- Built directly from the user-uploaded working V6 project.
- Preserves all existing 450 and 855 patches.
- Adds a stronger Files-page UITableView patch for {{0,205},{390,556}} -> height 700.
- Enforces 700 in UITableView setFrame:, setBounds:, and after every layoutSubviews pass.
- This is intended to survive scroll/Auto Layout attempts to restore 556.
