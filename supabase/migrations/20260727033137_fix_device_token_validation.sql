-- Postgres caps regex repetition counts at 255, so '^[0-9a-f]{32,256}$' raises
-- 2201B invalid repetition count(s) at runtime -- which would have failed EVERY call
-- to register_device_token, meaning no device would ever have received a push. It is
-- a runtime error, not a parse error, so the original migration applied cleanly and
-- the break only showed up under test. Split the bound out of the pattern.

create or replace function public.register_device_token(p_token text, p_environment text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_token text := lower(btrim(coalesce(p_token, '')));
  v_env   text := lower(btrim(coalesce(p_environment, '')));
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  -- APNs tokens are 32 bytes hex encoded (64 chars) today. The bounds are loose so a
  -- future Apple change in token length does not silently break registration.
  if v_token !~ '^[0-9a-f]+$'
     or char_length(v_token) < 32
     or char_length(v_token) > 256 then
    raise exception 'invalid_token' using errcode = '22023';
  end if;

  if v_env not in ('sandbox', 'production') then
    raise exception 'invalid_environment' using errcode = '22023';
  end if;

  if not exists (select 1 from public.profiles p where p.id = v_uid) then
    raise exception 'profile_missing' using errcode = 'P0002';
  end if;

  -- A device that changes hands (or a reinstall producing a fresh anonymous user)
  -- must not leave the old account pushing to it. One token belongs to one user.
  delete from public.device_tokens where token = v_token and user_id <> v_uid;

  insert into public.device_tokens (user_id, token, environment)
  values (v_uid, v_token, v_env)
  on conflict (user_id, token) do update
    set environment = excluded.environment, updated_at = now();
end;
$$;

revoke all on function public.register_device_token(text, text) from public, anon;
grant execute on function public.register_device_token(text, text) to authenticated;

notify pgrst, 'reload schema';
