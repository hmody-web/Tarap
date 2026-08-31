Tarab DeepFix V6.1

الهدف:
1) إبقاء Liquid Glass للـ UITabBar.
2) جعل محتوى الصفحة الحقيقي يمتد خلف الـ floating tab bar في iOS 26.
3) تصفير حجز الإعلانات من AdsManager و BannerHeightManager.
4) تصفير additionalSafeAreaInsets.bottom على الصفحة الفعالة.
5) معالجة adHeight / webViewBottomConstraint عند وجودهما.
6) عدم عمل hook عام على UIViewController.

Codemagic:
- يقبل أي IPA مهما كان اسمه.
- الأفضل إبقاء IPA واحد فقط في الريبو.
- الناتج الوحيد كـ Artifact:
  Tarab_DeepFix_V6_1.zip

داخل ZIP:
- Tarab_DeepFix_V6_1.ipa
- V6_Report/app_info.txt
- V6_Report/macho.txt
- V6_Report/relevant_strings.txt
- V6_Report/frameworks.txt
- V6_Report/post_build.txt

وقّع Tarab_DeepFix_V6_1.ipa بعد استخراجه من ZIP.
إذا بقيت الخلفية، ارفع ZIP الناتج نفسه حتى نقرأ تقرير V6 ونحدد الطبقة التالية.


V6.1: تم إزالة جميع CGRectGetHeight / CGRectGetMinY / CGRectGetMaxY واستبدالها بحسابات مباشرة لتجنب linker errors على Xcode 26.4.
