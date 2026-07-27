-- MoodCats core schema (spec section 6.1)
--
-- Ordering matters: `groups.owner_id` points at `profiles.id`, and `profiles.group_id`
-- points back at `groups.id`. The FK on groups.owner_id is therefore added after
-- profiles exists. There is no runtime circularity: a profile is created at sign in,
-- then a group is created referencing it, then the profile's group_id is updated.

create table if not exists public.groups (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,
  owner_id    uuid not null,
  created_at  timestamptz not null default now()
);

create table if not exists public.profiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  display_name     text not null check (char_length(display_name) between 1 and 20),
  group_id         uuid references public.groups(id) on delete set null,
  mood_id          smallint not null default 0 check (mood_id between 0 and 7),
  mood_updated_at  timestamptz not null default now(),
  created_at       timestamptz not null default now()
);

alter table public.groups
  drop constraint if exists groups_owner_fk;

alter table public.groups
  add constraint groups_owner_fk
  foreign key (owner_id) references public.profiles(id) on delete cascade;

create table if not exists public.device_tokens (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references public.profiles(id) on delete cascade,
  token        text not null,
  environment  text not null check (environment in ('sandbox','production')),
  updated_at   timestamptz not null default now(),
  unique (user_id, token)
);

create index if not exists profiles_group_idx on public.profiles(group_id);
create index if not exists device_tokens_user_idx on public.device_tokens(user_id);

-- Supporting index for the groups_owner_fk cascade and owner lookups in the RPCs.
create index if not exists groups_owner_idx on public.groups(owner_id);

comment on table public.groups is 'A friend group, max 8 members. Joined via a 6 character code.';
comment on table public.profiles is 'One row per auth user. mood_id is current state only -- there is deliberately no history table.';
comment on table public.device_tokens is 'APNs device tokens. environment decides which APNs host the Edge Function posts to.';
