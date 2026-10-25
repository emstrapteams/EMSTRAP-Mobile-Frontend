# EMSTRAP mobile (Flutter, Android)

Android app for EMSTRAP, using the existing EMSTRAP backend. The React web app lives in the repo
root and is unaffected.

- API contracts: [`docs/API_INVENTORY.md`](docs/API_INVENTORY.md)
- Plan, status and known gaps: [`docs/FRONTEND_PLAN.md`](docs/FRONTEND_PLAN.md)

## Requirements

- Flutter 3.41+ (Dart 3.11)
- Android SDK + **JDK 17–24** for Android builds. The project uses Gradle 8.14 (AGP 8.11.1), which
  cannot run on Java 25. Recent Android Studio releases bundle Java 25, so install JDK 21 and point
  Flutter at it:
  `brew install openjdk@21 && flutter config --jdk-dir=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home`
- An EMSTRAP backend you are allowed to test against. **Never test against production or real emergency services.**

## Run against a local backend

1. Start the backend (`EMSTRAP-Mobile-Backend`) with a local MongoDB and `PORT=5050`
   (port 5000 is taken by AirPlay on macOS).
2. Run the app:

   ```bash
   cd mobile
   flutter pub get
   # Android emulator (10.0.2.2 = your computer). This is also the debug default.
   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5050
   # Physical device on the same Wi-Fi:
   flutter run --dart-define=API_BASE_URL=http://<your-computer-LAN-IP>:5050
   ```

Plain HTTP is allowed in **debug builds only** (`android/app/src/debug/AndroidManifest.xml`).
Release builds require `--dart-define=API_BASE_URL=https://…` and refuse to start without it.

## Checks

```bash
dart format lib test
flutter analyze
flutter test                     # unit + widget tests (live tests skip themselves)
```

Live end-to-end tests drive the real data layer against a running local backend:

```bash
LIVE_API_BASE_URL=http://localhost:5050 \
LIVE_USER_EMAIL=… LIVE_USER_PASSWORD=… \
LIVE_DRIVER_EMAIL=… LIVE_DRIVER_PASSWORD=… \
flutter test test/live
```

They need a verified `user` account and a verified `ambulance_driver` account. They create and
cancel real emergency requests, so use a local or test database only.

## Configuration and secrets

The app holds no server secrets. The only build-time value is `API_BASE_URL`. Do not commit
`.env` files, keystores or test credentials.
