# تطبيق سجل السيارات اليومي (Flutter Android App)

تطبيق أندرويد متكامل بواجهة عربية (RTL) لتتبع حركة وسجل السيارات اليومي وعدادات الكيلومترات مع التعبئة الذكية والربط السحابي مع Google Sheets.

## التجميع التلقائي بدون أخطاء عبر GitHub Actions
1. قم بفك الضغط (Extract) عن ملف الـ ZIP أولاً (لا ترفع ملف الـ ZIP مضغوطاً).
2. ارفع كافة الملفات والمجلدات (بما في ذلك مجلد `.github`) إلى مستودعك على GitHub.
3. من تبويب **Actions** في GitHub اضغط على **Build Android APK** ثم **Run workflow**.
4. بعد انتهاء البناء (حوالي دقيقتين)، ستجد ملف الـ APK جاهزاً للتحميل في قسم **Artifacts** باسم `car-log-app-release-apk`.

## أو البناء محلياً على حاسوبك:
```bash
flutter create --platforms=android --org com.carlog --project-name car_log_app .
flutter pub get
flutter build apk --release
```
وستجد الملف الناتج في: `build/app/outputs/flutter-apk/app-release.apk`
