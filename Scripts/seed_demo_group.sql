-- Permanent seeded demo group for App Review. Phase 4.
--
-- THE REJECTION RISK THAT MATTERS: a reviewer opens the app alone, joins nothing, and
-- sees an empty widget. They mark it incomplete. This script is the mitigation -- a
-- standing group with three members whose moods move on a schedule, so a reviewer who
-- joins with the code below sees live cats within a minute.
--
-- Run it once, in the Supabase SQL editor, against production. It is idempotent.
--
-- Then put this in App Review Notes, verbatim:
--
--   Tap Join Group and enter code CATS99. Then long press the Home Screen, tap +,
--   search MoodCats, and add the small widget. Long press the widget, tap Edit Widget,
--   and select a friend.
--
-- Write those notes BEFORE submitting, not after the rejection.

begin;

-- ---------------------------------------------------------------------------------------
-- Three demo users. Fixed uuids so re-running this replaces rather than duplicates.
-- ---------------------------------------------------------------------------------------
insert into auth.users (
  id, instance_id, aud, role, is_anonymous, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  email_change_token_current, phone_change, phone_change_token, reauthentication_token
)
values
  ('d0000000-0000-4000-a000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', true, now(), now(), '', '', '', '', '', '', '', ''),
  ('d0000000-0000-4000-a000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', true, now(), now(), '', '', '', '', '', '', '', ''),
  ('d0000000-0000-4000-a000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', true, now(), now(), '', '', '', '', '', '', '', '')
on conflict (id) do nothing;

insert into public.profiles (id, display_name, mood_id, mood_updated_at, created_at)
values
  ('d0000000-0000-4000-a000-000000000001', 'Mochi',  0, now() - interval '4 minutes',  now() - interval '30 days'),
  ('d0000000-0000-4000-a000-000000000002', 'Biscuit',5, now() - interval '18 minutes', now() - interval '30 days'),
  ('d0000000-0000-4000-a000-000000000003', 'Pepper', 2, now() - interval '51 minutes', now() - interval '30 days')
on conflict (id) do update set display_name = excluded.display_name;

-- ---------------------------------------------------------------------------------------
-- The group. CATS99 is valid Crockford base32 (the client strips anything that is not),
-- and it is memorable enough to type off a review note.
-- ---------------------------------------------------------------------------------------
insert into public.groups (id, code, owner_id, created_at)
values ('d0000000-0000-4000-a000-0000000000aa', 'CATS99',
        'd0000000-0000-4000-a000-000000000001', now() - interval '30 days')
on conflict (id) do update set code = excluded.code;

update public.profiles
set group_id = 'd0000000-0000-4000-a000-0000000000aa'
where id in ('d0000000-0000-4000-a000-000000000001',
             'd0000000-0000-4000-a000-000000000002',
             'd0000000-0000-4000-a000-000000000003');

commit;

-- ---------------------------------------------------------------------------------------
-- Mood rotation.
--
-- The demo members have no devices, so nothing pushes on their behalf -- but a reviewer
-- foregrounding the app calls get_roster, which reads whatever these rows currently say.
-- Rotating them means the group looks alive on every launch.
--
-- Uncomment to schedule. pg_cron is available on the free tier but must be enabled first
-- (Dashboard > Database > Extensions > pg_cron).
-- ---------------------------------------------------------------------------------------

-- create extension if not exists pg_cron with schema extensions;
--
-- create or replace function public.rotate_demo_moods()
-- returns void
-- language sql
-- security definer
-- set search_path = public
-- as $$
--   update public.profiles
--   set mood_id = (mood_id + 1 + floor(random() * 3)::int) % 8,
--       mood_updated_at = now()
--   where group_id = 'd0000000-0000-4000-a000-0000000000aa'
--     and id = (
--       select id from public.profiles
--       where group_id = 'd0000000-0000-4000-a000-0000000000aa'
--       order by mood_updated_at asc
--       limit 1
--     );
-- $$;
--
-- revoke all on function public.rotate_demo_moods() from public, anon, authenticated;
--
-- -- One member changes mood every 20 minutes, oldest first.
-- select cron.schedule('moodcats-demo-rotation', '*/20 * * * *',
--                      'select public.rotate_demo_moods()');

-- ---------------------------------------------------------------------------------------
-- Teardown, if you ever need it. Deleting the auth rows cascades profiles, which cascades
-- the group through groups_owner_fk.
-- ---------------------------------------------------------------------------------------
-- select cron.unschedule('moodcats-demo-rotation');
-- delete from auth.users where id::text like 'd0000000-0000-4000-a000-%';
