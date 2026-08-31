# Tarab Banner Force / CodeMagic

ضع ملف IPA في جذر المستودع باسم `Tarab_fleXD_Editable.ipa` أو عدّل `IPA_FILE` في codemagic.yaml.

التعديل يفرض على كل عنصر `isBanner=true`:
- coverURL: https://scrptaty.com/apps/tarab/media/1.jpg
- iconURL: https://scrptaty.com/apps/tarab/media/icon1.png
- title: سكربتاتي
- subtitle: عالمك البرمجي في تطبيق واحد !
- action: https://scrptaty.com/

الحقن يتم بعد بناء dylib. الـ IPA الناتج يحتاج إعادة توقيع صحيحة بشهادتك/Provisioning Profile قبل التثبيت إذا لم تكن خطوة التوقيع موجودة في workflow الخاص بك.

## CodeMagic ldid fix
The Build dylib step installs `ldid` with Homebrew before Theos builds/signs the tweak. This fixes `bash: ldid: command not found` / exit code 127.
