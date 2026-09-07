# Class Timetable 📅

[![Flutter](https://img.shields.io/badge/Flutter-v3.0+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-v3.0+-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Android%20%7C%20Web-blue)]()

A modern, fast, and feature-packed class timetable application built with **Flutter** and **Material 3**. Designed specifically for students and educators with rotating schedules, customizable subjects, real-time ongoing class tracking, and seamless JSON backup & restore.

---

## ✨ Features

- **🔄 Multi-Week Rotation Schedules**: Configure rotation cycles from 1 up to 8 weeks (e.g., Week A / Week B or Odd / Even weeks) with automatic calendar date calculation and customizable reference start date.
- **⚡ Real-Time Active Class Highlighting**: Automatically detects and highlights the ongoing class based on current system time, keeping you focused on where you need to be.
- **📅 Intuitive Day & Date Navigation**: Easily toggle between weekdays (Monday to Friday) or select any date with the built-in calendar picker.
- **🎨 Custom Color Badges**: Assign unique colors to subjects using the color picker for quick visual distinction.
- **📝 Room & Notes Tracking**: Add classroom numbers, teacher details, reminders, and homework notes to every entry.
- **💾 JSON Backup & Restore**:
  - Export your entire schedule to a formatted JSON file or copy it directly to your clipboard.
  - Restore or share schedules across devices via file import or text paste.
- **🔔 Local Notifications**: Background notification alerts powered by `flutter_local_notifications`.
- **🖥️ Cross-Platform & Desktop Ready**: Full support for Windows Desktop (including Inno Setup installer script), Android, Web, macOS, and Linux.

---

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (version `>= 3.0.0 < 4.0.0`)
- Dart SDK included with Flutter
- A target platform setup (Windows build tools, Android Studio, or modern web browser)

### Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-username/class_timetable.git
   cd class_timetable
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run the application:**
   - **Windows:**
     ```bash
     flutter run -d windows
     ```
   - **Chrome / Web:**
     ```bash
     flutter run -d chrome
     ```
   - **Android:**
     ```bash
     flutter run -d android
     ```

---

## 📦 Building Releases Manually

### Windows Executable
To build a standalone Release binary for Windows:
```bash
flutter build windows --release
```
The compiled executable and required dependencies will be generated in:
`build/windows/x64/runner/Release/`

### Windows Installer (Inno Setup)
An [Inno Setup](https://jrsoftware.org/isinfo.php) compilation script [`inno_setup.iss`](inno_setup.iss) is included in the project root:
1. Build the Windows release bundle (`flutter build windows --release`).
2. Open [`inno_setup.iss`](inno_setup.iss) in Inno Setup Compiler.
3. Click **Compile** to generate a single setup installer under the `release/` directory.

### Android APK
To compile a release APK:
```bash
flutter build apk --release
```
The APK output is located at:
`build/app/outputs/flutter-apk/app-release.apk`

---

## 🤖 Automated CI/CD & GitHub Releases

This repository includes a fully automated **GitHub Actions** pipeline ([`.github/workflows/release.yml`](.github/workflows/release.yml)) that triggers on every version tag push (`v*`).

### Triggering a Release
Whenever you push a new version tag (e.g. `v1.0.2`):
```bash
git tag v1.0.2
git push origin v1.0.2
```

The automated pipeline performs the following steps:
1. **Windows Build & Packaging**:
   - Runs tests (`flutter test`).
   - Builds Windows release binaries (`flutter build windows --release`).
   - Compiles the Inno Setup installer (`class_timetable-v1.0.1-windows-setup.exe`).
   - Packages a portable ZIP (`class_timetable-windows-portable.zip`).
2. **Android APK Build**:
   - Builds release APK with signing fallback for CI (`class_timetable-android-release.apk`).
3. **Web Build & GitHub Pages Deployment**:
   - Builds Flutter web with custom repository base href.
   - Includes custom `404.html` with automatic route recovery and responsive fallback interface.
   - Automatically deploys the latest web app live to **GitHub Pages**.
   - Archives a portable web bundle (`class_timetable-web.zip`).
4. **Automatic GitHub Release**:
   - Creates a new release under your repository.
   - Generates release notes automatically from commits.
   - Attaches all release assets (Windows installer `.exe`, Windows `.zip`, Android `.apk`, Web `.zip`).

---

## 📄 JSON Schedule Format

The backup and restore tool allows you to import and export schedules using standard JSON format:

```json
{
  "app": "Class Timetable",
  "version": 2,
  "weeksCount": 2,
  "startDate": "2026-09-07T00:00:00.000",
  "timetable": {
    "0": {
      "Mon": [
        {
          "title": "Mathematics",
          "time": "09:00 AM - 10:30 AM",
          "room": "Room 101",
          "color": 4288597247,
          "note": "Bring scientific calculator"
        }
      ],
      "Tue": [],
      "Wed": [],
      "Thu": [],
      "Fri": []
    }
  }
}
```

---

## 📂 Project Structure

```text
class_timetable/
├── .github/
│   └── workflows/
│       └── release.yml    # Automated build, release & GitHub Pages deployment
├── android/               # Android native configuration & Gradle scripts
├── assets/                # App icons and media assets
├── inno_setup.iss         # Windows Inno Setup installer compilation script
├── lib/
│   ├── main.dart          # Primary application UI, models, and logic
│   └── utils/
│       ├── file_saver.dart       # Conditional export for cross-platform file saving
│       ├── file_saver_io.dart    # Desktop / Mobile file saver implementation
│       ├── file_saver_stub.dart  # Fallback stub
│       └── file_saver_web.dart   # Web file download implementation
├── web/                   # Web platform assets, manifest, and 404 error fallback
│   ├── 404.html           # GitHub Pages 404 error and recovery handler
│   └── index.html         # Flutter web bootstrap
├── windows/               # Windows native desktop runner (C++/CMake)
├── pubspec.yaml           # Flutter dependencies and metadata
├── LICENSE                # MIT License
└── README.md              # Project documentation
```

---

## 📜 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

Copyright (c) 2026 Danilo Stoletovic.
