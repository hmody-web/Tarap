Tarab Runtime Diagnostic V9.3.1

إصلاحات هذه النسخة:
- إصلاح خطأ linker الخاص بـ CGRectZero.
- استخدام os_log بدل NSLog.
- تفعيل %{public} بشكل صحيح حتى تظهر أسماء الكلاسات بدل <private>.
- الإبقاء على طباعة frame / safeArea / backgroundColor بأرقام مباشرة.

مهم:
ضع IPA واحد فقط داخل المشروع قبل تشغيل Codemagic.
يفضل حذف أي IPA قديم مثل V9.2 حتى لا يختاره السكربت بالخطأ.

بعد التثبيت:
1) افتح الأقسام الأربعة.
2) انتظر ثانية بكل قسم.
3) استخرج System Log.
4) دزلي tarab.txt.

أركز فقط على:
[TarabBottom]

الناتج:
Tarab_RuntimeDiag_V9_3_1.zip
