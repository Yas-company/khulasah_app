# Khulasah Flutter UI Specification

## Project Identity

**App Name Arabic:** خُلاصة  
**App Name English:** Khulasah  
**Flutter Project Name:** khulasah_app  

Khulasah is an Arabic/English PDF and document summarizer app.  
It is not only for educational files. It can summarize books, reports, notes, articles, business documents, training materials, and long PDFs.

The first version should be UI only with dummy data.  
Do not connect Firebase, OpenAI, or any backend yet.

---

## Brand Direction

The design should feel:

- Professional
- Clean
- Arabic-first
- Suitable for Saudi users and official/semi-official use
- Simple and trustworthy
- Not childish
- Not too colorful
- Modern Material 3 style

---

## Provided Logo Assets

Use the provided logo image assets instead of creating the logo manually with Flutter widgets.

Place all logo files inside:

```text
assets/images/
```

Provided files:

```text
assets/images/khulasah_app_icon_1024.png
assets/images/khulasah_logo_icon_transparent.png
assets/images/khulasah_full_logo_vertical_transparent.png
assets/images/khulasah_full_logo_horizontal_transparent.png
assets/images/khulasah_logo_icon.svg
```

### Logo usage

Use these files like this:

```text
Splash Screen:
assets/images/khulasah_full_logo_vertical_transparent.png

App header / small logo:
assets/images/khulasah_logo_icon_transparent.png

Login Screen:
assets/images/khulasah_full_logo_vertical_transparent.png or khulasah_logo_icon_transparent.png

Launcher icon source:
assets/images/khulasah_app_icon_1024.png

Optional website/header logo:
assets/images/khulasah_full_logo_horizontal_transparent.png
```

### Important Logo Rules

- Do not recreate the logo with Flutter drawing widgets.
- Do not change the logo colors.
- Do not crop the logo badly.
- Keep the logo clear and centered.
- Use `Image.asset()` for PNG files.
- If SVG support is needed, use `flutter_svg`, but PNG is enough for this UI version.

---

## Required Assets Setup

Add this to `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/images/
```

Optional but recommended for app launcher icon:

```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.14.3

flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/images/khulasah_app_icon_1024.png"
  remove_alpha_ios: true
```

If using launcher icons, run:

```bash
flutter pub get
dart run flutter_launcher_icons
```

If you want to avoid extra dependencies for now, skip launcher icons and only use the images inside the UI.

---

## Color Palette

Use these exact colors:

```dart
class AppColors {
  static const primary = Color(0xFF0F5132);      // Main dark Saudi green
  static const primaryDark = Color(0xFF004D25);  // Dark green
  static const secondary = Color(0xFF2E7D53);    // Secondary green
  static const accent = Color(0xFFD4AF37);       // Muted gold
  static const background = Color(0xFFF4F6F8);   // Soft light gray
  static const surface = Color(0xFFFFFFFF);      // White cards
  static const textPrimary = Color(0xFF111827);  // Almost black
  static const textSecondary = Color(0xFF6B7280);// Gray
  static const border = Color(0xFFE5E7EB);       // Light border
  static const success = Color(0xFF16A34A);
  static const error = Color(0xFFDC2626);
}
```

General usage:

- Primary buttons: dark Saudi green
- Secondary buttons: white with green border
- Background: soft off-white / light gray
- Cards: white
- Small highlights: muted gold only
- Avoid neon colors
- Avoid heavy gradients
- Keep the UI formal and clean

---

## Typography

Use Arabic-friendly fonts.

Preferred:

- Arabic: Cairo or Tajawal
- English: Inter or default system font

If adding dependencies is okay, use:

```yaml
dependencies:
  google_fonts: ^6.2.1
```

If you want to avoid dependencies for now, use default Flutter fonts.

Text direction:

- Arabic screens should support RTL.
- Use `Directionality(textDirection: TextDirection.rtl)` where needed.
- Main language should be Arabic for UI labels.

---

## Folder Structure

Create or update these files:

```text
lib/
├── main.dart
├── app.dart
├── screens/
│   ├── splash_screen.dart
│   ├── login_screen.dart
│   ├── home_screen.dart
│   ├── upload_pdf_screen.dart
│   ├── summary_options_screen.dart
│   ├── result_screen.dart
│   └── history_screen.dart
├── widgets/
│   ├── app_logo.dart
│   ├── custom_button.dart
│   ├── option_card.dart
│   ├── loading_widget.dart
│   └── file_upload_box.dart
└── utils/
    ├── app_colors.dart
    ├── app_text_styles.dart
    └── constants.dart
```

Also create this folder:

```text
assets/
└── images/
    ├── khulasah_app_icon_1024.png
    ├── khulasah_logo_icon_transparent.png
    ├── khulasah_full_logo_vertical_transparent.png
    ├── khulasah_full_logo_horizontal_transparent.png
    └── khulasah_logo_icon.svg
```

---

## App Requirements

Use:

- Flutter
- Material 3
- Simple Navigator navigation
- No Firebase
- No OpenAI
- No real PDF picker yet
- Dummy data only
- Clean readable code
- Comments where useful
- Responsive layout for mobile screens
- Use the provided logo image assets

The app must run with:

```bash
flutter pub get
flutter run
```

---

## Screens Details

### 1. Splash Screen

Show:

- Full vertical logo image:
  `assets/images/khulasah_full_logo_vertical_transparent.png`
- If the image already contains the app name, do not duplicate the name too close.
- Subtitle under logo if needed:
  `لخص ملفاتك ومستنداتك بسهولة`

After 2 seconds, navigate to Login Screen.

---

### 2. Login Screen

Simple professional login UI.

Show small logo at top:

```text
assets/images/khulasah_logo_icon_transparent.png
```

Fields:

- البريد الإلكتروني
- كلمة المرور

Buttons:

- تسجيل الدخول
- المتابعة كضيف

For now, both buttons navigate to Home Screen.

---

### 3. Home Screen

Show:

- Header with small logo:
  `assets/images/khulasah_logo_icon_transparent.png`
- Welcome text: مرحباً بك في خُلاصة
- Subtitle: ارفع ملف PDF واحصل على ملخص أو أسئلة في دقائق
- Main button: رفع ملف PDF

Cards:

1. تلخيص PDF
2. إنشاء سؤال وجواب
3. ملخص + أسئلة
4. السجل

Clicking upload or cards should navigate logically:
- Upload PDF goes to Upload PDF Screen
- History goes to History Screen

---

### 4. Upload PDF Screen

Show:

- Large upload box
- Text: اسحب ملفك هنا أو اختر ملف PDF
- Button: اختيار ملف PDF

Since this is dummy UI:
- When user taps choose file, show fake selected file:
  `sample_document.pdf`

Then enable button:

- متابعة

Continue goes to Summary Options Screen.

---

### 5. Summary Options Screen

User chooses output type:

- ملخص فقط
- سؤال وجواب
- ملخص + سؤال وجواب

User chooses length:

- صفحة واحدة
- 5 صفحات
- 10 صفحات
- مخصص

Button:

- إنشاء النتيجة

Clicking it navigates to Result Screen with dummy result.

---

### 6. Result Screen

Show:

Title:

- النتيجة

Show dummy result card with Arabic sample summary:

```text
هذا ملخص تجريبي للملف الذي تم رفعه. في النسخة النهائية سيتم تحليل محتوى الملف وإنشاء ملخص واضح ومنظم حسب الاختيارات التي حددها المستخدم.
```

Buttons:

- تحميل PDF
- حفظ النتيجة
- العودة للرئيسية

Buttons are dummy for now except Back Home.

---

### 7. History Screen

Show fake previous documents list.

Each item includes:

- File title
- Date
- Type

Example:

- تقرير العمل.pdf — ملخص — 2026/06/13
- كتاب الإدارة.pdf — سؤال وجواب — 2026/06/10
- ملف تدريبي.pdf — ملخص + أسئلة — 2026/06/08

---

## UI Component Requirements

### Custom Button

Create reusable button:

- text
- onPressed
- isOutlined optional
- isLoading optional
- full width by default

### Option Card

Reusable card:

- icon
- title
- subtitle
- selected state
- onTap

### File Upload Box

Reusable upload UI:

- icon
- title
- subtitle
- selected file name optional
- onTap

### App Logo

Reusable logo widget that uses the provided image assets.

Suggested implementation:

- `AppLogo.full()` uses:
  `assets/images/khulasah_full_logo_vertical_transparent.png`
- `AppLogo.icon()` uses:
  `assets/images/khulasah_logo_icon_transparent.png`
- Allow width and height customization.
- Use `Image.asset()`.

Do not draw the logo manually.

---

## Important Notes

- Keep everything simple.
- Do not over-engineer.
- Do not add state management packages.
- Do not add backend code.
- Do not add Firebase yet.
- Do not add real OpenAI integration yet.
- The goal is only to finish a clean UI starter that runs successfully.
- Make sure asset paths are correct.
- Make sure `pubspec.yaml` indentation is correct.

---

## Final Output Needed

After finishing, provide:

1. The updated file tree.
2. Full code for each file.
3. Any dependencies added to `pubspec.yaml`.
4. Terminal commands to run the app.
5. Notes if any file must be created manually.
6. Confirmation that logo assets are used from `assets/images/`.
