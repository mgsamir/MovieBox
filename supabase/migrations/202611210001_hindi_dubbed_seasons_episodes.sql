-- Hindi-dubbed series and anime catalog.
-- Run this migration in the Supabase SQL editor before adding season/episode rows.

create table if not exists public.seasons (
  id uuid primary key default gen_random_uuid(),
  content_id text not null,
  season_number integer not null check (season_number > 0),
  title text not null,
  synopsis text,
  poster_url text,
  created_at timestamptz not null default now(),
  unique (content_id, season_number)
);

create table if not exists public.episodes (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.seasons(id) on delete cascade,
  episode_number integer not null check (episode_number > 0),
  title text not null,
  synopsis text,
  video_url text not null,
  audio_language text not null default 'Hindi Dubbed',
  subtitle_url text,
  duration_seconds integer check (duration_seconds is null or duration_seconds > 0),
  created_at timestamptz not null default now(),
  unique (season_id, episode_number)
);

create index if not exists seasons_content_order_idx
  on public.seasons (content_id, season_number);
create index if not exists episodes_season_order_idx
  on public.episodes (season_id, episode_number);

alter table public.seasons enable row level security;
alter table public.episodes enable row level security;

drop policy if exists "MovieBox catalog seasons are readable" on public.seasons;
create policy "MovieBox catalog seasons are readable"
  on public.seasons for select to anon, authenticated using (true);

drop policy if exists "MovieBox catalog episodes are readable" on public.episodes;
create policy "MovieBox catalog episodes are readable"
  on public.episodes for select to anon, authenticated using (true);
