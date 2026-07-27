-- Advisor remediation (lints 0011 and 0028).
--
-- Postgres grants EXECUTE on new functions to PUBLIC by default, and in Supabase the
-- `anon` role inherits that. So `grant execute ... to authenticated` in the earlier
-- migrations did not actually close the door: every RPC was reachable unauthenticated
-- at /rest/v1/rpc/<name>. Each one raises not_authenticated, so nothing leaked, but
-- the surface should not exist at all. Revoke from PUBLIC first, then re-grant
-- narrowly.
--
-- This also fixes a latent break: `revoke all ... from public` on apply_mood and
-- roster_for in the previous migration stripped service_role's implicit grant too, so
-- service_role is re-granted apply_mood explicitly below. Without it, set-mood 404s.

-- max_group_members had a mutable search_path (lint 0011).
create or replace function public.max_group_members()
returns int
language sql
immutable
set search_path = ''
as $$ select 8 $$;

comment on function public.max_group_members() is
  'Target group size. A taste limit, not a technical one -- change this one line to move it.';

revoke all on function public.max_group_members()               from public, anon;
revoke all on function public.current_group_id()                from public, anon;
revoke all on function public.bootstrap_profile(text)           from public, anon;
revoke all on function public.create_group()                    from public, anon;
revoke all on function public.join_group(text)                  from public, anon;
revoke all on function public.leave_group()                     from public, anon;
revoke all on function public.kick_member(uuid)                 from public, anon;
revoke all on function public.get_roster()                      from public, anon;
revoke all on function public.register_device_token(text, text) from public, anon;
revoke all on function public.delete_my_data()                  from public, anon;
revoke all on function public.new_group_code()                  from public, anon, authenticated;
revoke all on function public.roster_for(uuid)                  from public, anon, authenticated;
revoke all on function public.apply_mood(uuid, smallint, int)   from public, anon, authenticated;

-- The client-callable surface, and nothing else.
grant execute on function public.bootstrap_profile(text)           to authenticated;
grant execute on function public.create_group()                    to authenticated;
grant execute on function public.join_group(text)                  to authenticated;
grant execute on function public.leave_group()                     to authenticated;
grant execute on function public.kick_member(uuid)                 to authenticated;
grant execute on function public.get_roster()                      to authenticated;
grant execute on function public.register_device_token(text, text) to authenticated;
grant execute on function public.delete_my_data()                  to authenticated;

-- RLS policies on profiles and groups call current_group_id(). Policy expressions are
-- evaluated as the querying role, so `authenticated` must be able to execute it or
-- every select on profiles fails with permission denied. max_group_members() is called
-- inside join_group(), which is security definer, but grant it too so the constant
-- stays usable from a policy later without another migration.
grant execute on function public.current_group_id()  to authenticated;
grant execute on function public.max_group_members() to authenticated;

-- The set-mood Edge Function authenticates as service_role and calls exactly this one.
grant execute on function public.apply_mood(uuid, smallint, int) to service_role;

notify pgrst, 'reload schema';
