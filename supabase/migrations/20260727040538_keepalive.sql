-- Free tier projects pause after 7 days with no activity, and a paused project takes
-- 20 to 30 seconds to wake -- which reads as "the app is broken" to a user, and as a
-- failed launch to an App Store reviewer.
--
-- An external cron (see .github/workflows/keepalive.yml) calls this every three days. It
-- is a real API request that touches the database, which is what the pause timer
-- watches. It returns a timestamp and nothing else, so granting it to `anon` leaks
-- exactly nothing.

create or replace function public.keepalive()
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $$ select now() $$;

comment on function public.keepalive() is
  'Cheap no-op for the external keepalive cron. Returns now(). Safe for anon.';

revoke all on function public.keepalive() from public;
grant execute on function public.keepalive() to anon, authenticated;

notify pgrst, 'reload schema';
