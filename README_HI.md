# CineBox OTT Starter (Hindi + English)

Android OTT catalog starter built with Flutter + Supabase.

## Features
- Movies, Series and Anime catalog tabs
- Search and detail pages
- Metadata sync crawler: Jikan (anime), TVmaze (TV), Internet Archive (public-domain media)
- Optional RSS feeds and XML sitemaps
- Direct playback only for authorized/public-domain video URLs

## Setup
1. Create a Supabase project and run `supabase/schema.sql` in SQL Editor.
2. Add Supabase project URL and anon key in `app/lib/config.dart`.
3. Install Flutter, then run `cd app && flutter pub get && flutter run`.
4. For catalog sync, set GitHub Actions secrets `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`.
5. Run the workflow manually or wait for its daily schedule.

Never put the Supabase service-role key inside the Android app.

## Notes
This is a starter scaffold, not a production streaming service. Source websites must permit metadata access. It does not bypass paywalls, DRM, access controls, or extract unauthorized streams. Free hosting tiers have usage limits.
