create extension if not exists pgcrypto;

create table if not exists public.content (
  id text primary key,
  title text not null,
  content_type text not null check (content_type in ('movie','series','anime')),
  synopsis text,
  poster_url text,
  backdrop_url text,
  release_year integer,
  rating numeric,
  language text,
  source text not null,
  source_url text,
  video_url text,
  updated_at timestamptz not null default now()
);

create index if not exists content_type_idx on public.content(content_type);
create index if not exists content_title_idx on public.content using gin (to_tsvector('simple', title));

alter table public.content enable row level security;
drop policy if exists "Public can read catalog" on public.content;
create policy "Public can read catalog" on public.content for select using (true);
