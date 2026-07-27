-- MoodCats roster contract, device tokens, mood write, and data deletion.
--
-- ===========================================================================
-- UNITS: `t` and `at` are unix milliseconds, not seconds.
-- ===========================================================================
-- roster_for() below is the ONLY producer of these numbers in the entire system --
-- the get_roster RPC, the set-mood Edge Function response, and the APNs payload all
-- come out of this one function. Milliseconds rather than seconds because `t` is the
-- monotonic sequence number that drives "only write if incoming t > stored t"; at
-- second resolution a foreground refresh and a push landing in the same second tie,
-- and a tie is silently dropped. The Swift side divides by 1000 for Date.
--
-- Shape (spec section 9):
--   { "v":1, "t":<ms>, "groupId":<uuid|null>, "me":<uuid>,
--     "members":[ { "id":<uuid>, "n":<name>, "m":<mood 0-7>, "at":<ms> } ] }
--
-- The APNs payload is this blob minus `me` (the receiving device fills in its own),
-- plus the `aps` block.

create or replace function public.roster_for(p_user_id uuid)
returns json
language sql
stable
security definer
set search_path = public
as $$
  select json_build_object(
    'v', 1,
    't', (extract(epoch from clock_timestamp()) * 1000)::bigint,
    'groupId', p.group_id,
    'me', p.id,
    'members', coalesce((
      select json_agg(
               json_build_object(
                 'id', m.id,
                 'n',  m.display_name,
                 'm',  m.mood_id,
                 'at', (extract(epoch from m.mood_updated_at) * 1000)::bigint
               )
               order by m.created_at, m.id
             )
      from public.profiles m
      where (p.group_id is not null and m.group_id = p.group_id)
         or (p.group_id is null and m.id = p.id)
    ), '[]'::json)
  )
  from public.profiles p
  where p.id = p_user_id;
$$;

-- roster_for takes an arbitrary user id, so exposing it to clients would leak other
-- groups' rosters. Only the security definer wrappers and the service role may call it.
revoke all on function public.roster_for(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- get_roster -- the client's repair path, called on every app foreground
-- ---------------------------------------------------------------------------

create or replace function public.get_roster()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_out json;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select public.roster_for(v_uid) into v_out;

  if v_out is null then
    raise exception 'profile_missing' using errcode = 'P0002';
  end if;

  return v_out;
end;
$$;

-- ---------------------------------------------------------------------------
-- register_device_token
-- ---------------------------------------------------------------------------

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

  -- NOTE: this pattern is invalid at runtime and is corrected in
  -- 20260727033137_fix_device_token_validation.sql. Left as applied so the migration
  -- history reproduces exactly. See that file for the explanation.
  if v_token !~ '^[0-9a-f]{32,256}$' then
    raise exception 'invalid_token' using errcode = '22023';
  end if;

  if v_env not in ('sandbox', 'production') then
    raise exception 'invalid_environment' using errcode = '22023';
  end if;

  if not exists (select 1 from public.profiles p where p.id = v_uid) then
    raise exception 'profile_missing' using errcode = 'P0002';
  end if;

  -- A device that changes hands (or a reinstall that produces a fresh anonymous user)
  -- must not leave the old account pushing to it. One token belongs to one user.
  delete from public.device_tokens
  where token = v_token and user_id <> v_uid;

  insert into public.device_tokens (user_id, token, environment)
  values (v_uid, v_token, v_env)
  on conflict (user_id, token) do update
    set environment = excluded.environment,
        updated_at  = now();
end;
$$;

-- ---------------------------------------------------------------------------
-- apply_mood -- service role only, called by the set-mood Edge Function
-- ---------------------------------------------------------------------------
-- Rate limit, mood write, roster read and recipient token read in a single round trip
-- so the Edge Function touches the database exactly once. set_mood stays out of the
-- client-callable RPC surface deliberately: the write and the push fanout are one hop.

create or replace function public.apply_mood(
  p_user_id        uuid,
  p_mood_id        smallint,
  p_min_interval_ms int default 3000
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_gid      uuid;
  v_last     timestamptz;
  v_elapsed  bigint;
  v_roster   json;
  v_tokens   json;
begin
  if p_user_id is null then
    return json_build_object('ok', false, 'reason', 'not_authenticated');
  end if;

  if p_mood_id is null or p_mood_id < 0 or p_mood_id > 7 then
    return json_build_object('ok', false, 'reason', 'invalid_mood');
  end if;

  select p.group_id, p.mood_updated_at into v_gid, v_last
  from public.profiles p where p.id = p_user_id for update;

  if not found then
    return json_build_object('ok', false, 'reason', 'profile_missing');
  end if;

  v_elapsed := (extract(epoch from (clock_timestamp() - v_last)) * 1000)::bigint;

  if v_elapsed < p_min_interval_ms then
    return json_build_object(
      'ok', false,
      'reason', 'rate_limited',
      'retry_after_ms', p_min_interval_ms - v_elapsed
    );
  end if;

  update public.profiles
  set mood_id = p_mood_id,
      mood_updated_at = now()
  where id = p_user_id;

  v_roster := public.roster_for(p_user_id);

  -- Recipients: every OTHER member of the caller's group. Distinct because two members
  -- sharing one device would otherwise get the same push twice.
  if v_gid is null then
    v_tokens := '[]'::json;
  else
    select coalesce(json_agg(json_build_object('t', d.token, 'e', d.environment)), '[]'::json)
    into v_tokens
    from (
      select distinct dt.token, dt.environment
      from public.device_tokens dt
      join public.profiles p on p.id = dt.user_id
      where p.group_id = v_gid
        and dt.user_id <> p_user_id
    ) d;
  end if;

  return json_build_object('ok', true, 'roster', v_roster, 'tokens', v_tokens);
end;
$$;

revoke all on function public.apply_mood(uuid, smallint, int) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- delete_my_data
-- ---------------------------------------------------------------------------

create or replace function public.delete_my_data()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_gid uuid;
  v_owner uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select p.group_id into v_gid from public.profiles p where p.id = v_uid for update;

  if found and v_gid is not null then
    select g.owner_id into v_owner from public.groups g where g.id = v_gid;
    if v_owner = v_uid then
      delete from public.groups where id = v_gid;
    end if;
  end if;

  -- Cascades device_tokens via device_tokens.user_id -> profiles.id on delete cascade.
  delete from public.profiles where id = v_uid;

  -- Also drop the anonymous auth row so nothing survives deletion. Guarded: if this
  -- deployment does not grant the function owner rights on auth.users, the profile is
  -- already gone and an orphaned anonymous auth row carries no user data.
  begin
    delete from auth.users where id = v_uid;
  exception
    when insufficient_privilege then null;
  end;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

grant execute on function public.get_roster()                          to authenticated;
grant execute on function public.register_device_token(text, text)     to authenticated;
grant execute on function public.delete_my_data()                      to authenticated;
