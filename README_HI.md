# MovieBox — Flutter Android catalog

Android media catalog built with Flutter and Supabase.

## Features
- Movies, web series and anime catalog
- Search, category filters and content details
- Metadata sync crawler: Jikan (anime), TVmaze (TV), and Internet Archive catalog records
- Daily catalog refresh through GitHub Actions
- Direct playback only for authorized media URLs

## Setup
1. Create a Supabase project and run `supabase/schema.sql` in the SQL Editor.
2. In GitHub repository Settings → Secrets and variables → Actions, add:
   - `SUPABASE_URL`: your Supabase project URL
   - `SUPABASE_ANON_KEY`: your Supabase publishable/anon key (used by the Android app)
   - `SUPABASE_SERVICE_ROLE_KEY`: service-role key used only by the server-side catalog crawler
3. Never place the service-role key in the Android app or in a `--dart-define`.
4. Push to `main` or run the Android build workflow manually. The APK is uploaded as the `moviebox-android-apk` artifact.
5. The catalog crawler runs daily on its scheduled workflow; it can also be started manually.
6. For local Android builds, run:
   `cd app && flutter pub get`
   then pass the URL and anon key as build-time defines:
   `flutter build apk --release --dart-define=SUPABASE_URL=YOUR_URL --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY`

## Notes
The Android app uses only the public anon key with Row Level Security. The service-role key stays in GitHub Actions for the crawler. Metadata records do not grant video playback or download rights: only use media URLs you own or are authorized to access. Website sources must permit metadata access; MovieBox does not bypass paywalls, DRM, or access controls.


## APK update / same-app installation

To install future APKs over the existing MovieBox app (without deleting app data), every release must keep the same Android application ID and be signed with the same private signing key. The CI build now increments Android `versionCode` automatically and supports a persistent release keystore.

Configure these four GitHub Actions repository secrets once:

- `ANDROID_KEYSTORE_BASE64`: Base64-encoded release keystore file
- `ANDROID_KEYSTORE_PASSWORD`: keystore password
- `ANDROID_KEY_ALIAS`: key alias
- `ANDROID_KEY_PASSWORD`: key password

Create the keystore privately (keep a safe backup; never commit it):

```bash
keytool -genkeypair -v -keystore moviebox-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias moviebox
base64 -w 0 moviebox-upload.jks
```

Put the second command's complete output in `ANDROID_KEYSTORE_BASE64`, and use the passwords and alias chosen in the first command for the other secrets. Once configured, all future APKs use this same key and can update the installed app in place. The first switch from an older CI debug-signed APK to this stable key requires one uninstall/reinstall; after that, updates install over the app normally. If signing secrets are absent, CI deliberately warns that the temporary debug-signed APK is not suitable for seamless updates.
