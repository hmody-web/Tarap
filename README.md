Tarab Banner Safe Override

This revision narrows the hook to Tarab item-list JSON only.
It does NOT recursively modify arbitrary JSON and does NOT register UIApplication observers.

Forced banner values:
- title: سكربتاتي
- subtitle: عالمك البرمجي في تطبيق واحد !
- cover: https://scrptaty.com/apps/tarab/media/1.jpg
- icon: https://scrptaty.com/apps/tarab/media/icon1.png
- action: https://scrptaty.com/

The hook activates only when the JSON contains isBanner + coverURL and Tarab/Panorama media paths.
Every later re-parse of a refreshed item list gets patched again.

IMPORTANT: the injection step strips the original app code signature. The resulting IPA must be re-signed with your valid certificate/profile before installation.
