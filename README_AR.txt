Tarab Runtime Diagnostic V9

هذه النسخة للتشخيص فقط، ولا تعدل تخطيط الشاشة.

بعد البناء:
1. استخرج Tarab_RuntimeDiag_V9.ipa
2. وقعه وثبته.
3. افتح التطبيق.
4. افتح الصفحات التي يظهر بها الفراغ/الخلفية:
   - الملفات
   - المزيد
   - المصادر
5. انتظر ثانية تقريباً داخل كل صفحة.
6. الديلب سيكتب تقارير داخل Documents للتطبيق بأسماء:
   TarabDiag_*.txt

التقرير يحتوي:
- اسم الـ UIViewController
- parent controllers
- frame/bounds
- backgroundColor
- alpha / hidden / opaque
- safeAreaInsets
- additionalSafeAreaInsets
- superview class
- كل Views التي تقع ضمن آخر 320pt من الشاشة

المطلوب بعد التجربة:
استخرج ملفات TarabDiag_*.txt من Documents ودزها.
منها نحدد اسم الطبقة المسؤولة بدقة.

Codemagic يقبل أي IPA مهما كان اسمه.
الأفضل وجود IPA واحد فقط داخل الريبو.

الناتج:
Tarab_RuntimeDiag_V9.zip
