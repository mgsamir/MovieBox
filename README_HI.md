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
