Tarab Ads Source Fix V5

تم تتبع مصدر مساحة الإعلان من الملف التنفيذي نفسه.

المصدر الحقيقي داخل:
_TtC5Tarab10AdsManager

ووجد داخله:
- bannerBottomConstraint
- bannerBottomPadding
- _bannerHeight
- _inlineBannerHeight
- bannerView
- inlineBannerView
- shouldShowBanner
- updateBannerPosition

V5 لا يلمس UIViewController أو UITabBarController.
يستهدف AdsManager فقط ويصفر الحجز بعد updateBannerPosition.

ويبقي شفافية UITabBar بطريقة V2 التي اشتغلت سابقاً.

السكربت يقبل أي IPA مهما كان اسمه.
الأفضل وضع IPA واحد فقط داخل الريبو.

الناتج:
Tarab_AdsSourceFix_V5.ipa
ثم أعد توقيعه.
