# Wallpaper Changer

Flutter Android app that changes your wallpaper daily from the same sources as
KDE Plasma's Picture of the Day plugin: Simon Stålenhag, Bing, NASA APOD, and
Wikimedia Commons POTD.

## Dev

    flutter pub get
    flutter test
    flutter analyze
    flutter run

## Release signing (one-time setup)

1. Generate a keystore (keep it safe, it must never change):

       keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload

2. Base64 it:

       base64 -w0 upload-keystore.jks

3. Add GitHub repo secrets: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`,
   `KEY_ALIAS`, `KEY_PASSWORD`.

4. Bump `version:` in `pubspec.yaml`, commit, then tag:

       git tag v0.1.0 && git push origin v0.1.0

CI runs tests, builds, signs, and publishes the APK to a GitHub Release.

## Design docs

See `docs/superpowers/`.
