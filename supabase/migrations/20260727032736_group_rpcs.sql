-- MoodCats group + profile RPCs (spec section 6.3)
--
-- Every function here is security definer with a pinned search_path and validates that
-- auth.uid() is not null. Errors are raised with stable snake_case messages so the iOS
-- client can switch on them: not_authenticated, profile_missing, already_in_group,
-- group_not_found, group_full, not_owner, cannot_kick_owner, not_a_member,
-- invalid_display_name, code_generation_failed.

create or replace function public.max_group_members()
returns int
language sql
immutable
as $$ select 8 $$;

comment on function public.max_group_members() is
  'Target group size. A taste limit, not a technical one -- change this one line to move it.';

-- ---------------------------------------------------------------------------
-- Invite code generation
-- ---------------------------------------------------------------------------

create or replace function public.new_group_code()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  -- Crockford base32: no I, L, O or U, so nothing reads ambiguously out loud or on a
  -- screen. To switch to a 6 digit numeric code, change this one line to '0123456789'
  -- and nothing else in the system needs to move.
  CODE_ALPHABET constant text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  CODE_LENGTH   constant int  := 6;
  MAX_ATTEMPTS  constant int  := 10;
  v_alphabet_len constant int := char_length(CODE_ALPHABET);
  v_bytes bytea;
  v_code  text;
  v_i     int;
  v_try   int;
begin
  for v_try in 1..MAX_ATTEMPTS loop
    -- gen_random_uuid() is a CSPRNG in PG13+ and needs no extension. 32 divides 256
    -- evenly, so `% 32` introduces no modulo bias.
    v_bytes := uuid_send(gen_random_uuid());
    v_code := '';
    for v_i in 1..CODE_LENGTH loop
      v_code := v_code || substr(
        CODE_ALPHABET,
        1 + (get_byte(v_bytes, v_i) % v_alphabet_len),
        1
      );
    end loop;

    if not exists (select 1 from public.groups g where g.code = v_code) then
      return v_code;
    end if;
  end loop;

  raise exception 'code_generation_failed' using errcode = '55000';
end;
$$;

-- Never callable by a client: it burns codes and leaks nothing useful.
revoke all on function public.new_group_code() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- bootstrap_profile
-- ---------------------------------------------------------------------------

create or replace function public.bootstrap_profile(p_name text)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_name text := btrim(coalesce(p_name, ''));
  v_row  public.profiles;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  if char_length(v_name) < 1 or char_length(v_name) > 20 then
    raise exception 'invalid_display_name' using errcode = '22023';
  end if;

  -- Idempotent: called after every anonymous sign in, and again whenever the user
  -- changes their display name in Settings.
  insert into public.profiles (id, display_name)
  values (v_uid, v_name)
  on conflict (id) do update set display_name = excluded.display_name
  returning * into v_row;

  return v_row;
end;
$$;

-- ---------------------------------------------------------------------------
-- create_group
-- ---------------------------------------------------------------------------

create or replace function public.create_group()
returns public.groups
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_existing uuid;
  v_group    public.groups;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  -- Row lock so two concurrent create_group calls from the same user cannot both win.
  select p.group_id into v_existing
  from public.profiles p where p.id = v_uid for update;

  if not found then
    raise exception 'profile_missing' using errcode = 'P0002';
  end if;

  if v_existing is not null then
    raise exception 'already_in_group' using errcode = 'P0001';
  end if;

  insert into public.groups (code, owner_id)
  values (public.new_group_code(), v_uid)
  returning * into v_group;

  update public.profiles set group_id = v_group.id where id = v_uid;

  return v_group;
end;
$$;

-- ---------------------------------------------------------------------------
-- join_group
-- ---------------------------------------------------------------------------

create or replace function public.join_group(p_code text)
returns public.groups
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_code     text := upper(btrim(coalesce(p_code, '')));
  v_existing uuid;
  v_group    public.groups;
  v_members  int;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select p.group_id into v_existing
  from public.profiles p where p.id = v_uid for update;

  if not found then
    raise exception 'profile_missing' using errcode = 'P0002';
  end if;

  if v_existing is not null then
    raise exception 'already_in_group' using errcode = 'P0001';
  end if;

  -- Lock the group row so concurrent joins cannot both squeeze past the member cap.
  select * into v_group from public.groups g where g.code = v_code for update;

  if not found then
    raise exception 'group_not_found' using errcode = 'P0002';
  end if;

  select count(*) into v_members
  from public.profiles p where p.group_id = v_group.id;

  if v_members >= public.max_group_members() then
    raise exception 'group_full' using errcode = 'P0001';
  end if;

  update public.profiles set group_id = v_group.id where id = v_uid;

  return v_group;
end;
$$;

-- ---------------------------------------------------------------------------
-- leave_group
-- ---------------------------------------------------------------------------

create or replace function public.leave_group()
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

  select p.group_id into v_gid
  from public.profiles p where p.id = v_uid for update;

  if not found then
    raise exception 'profile_missing' using errcode = 'P0002';
  end if;

  if v_gid is null then
    return; -- Already groupless. Leaving is idempotent.
  end if;

  select g.owner_id into v_owner from public.groups g where g.id = v_gid;

  if v_owner = v_uid then
    -- Owner leaving dissolves the group. Every member's group_id drops to null via
    -- the `on delete set null` on profiles.group_id, including the owner's own.
    delete from public.groups where id = v_gid;
  else
    update public.profiles set group_id = null where id = v_uid;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- kick_member
-- ---------------------------------------------------------------------------

create or replace function public.kick_member(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_gid uuid;
  v_owner uuid;
  v_target_gid uuid;
begin
  if v_uid is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  select p.group_id into v_gid from public.profiles p where p.id = v_uid;

  if not found then
    raise exception 'profile_missing' using errcode = 'P0002';
  end if;

  if v_gid is null then
    raise exception 'not_in_a_group' using errcode = 'P0001';
  end if;

  select g.owner_id into v_owner from public.groups g where g.id = v_gid;

  if v_owner is distinct from v_uid then
    raise exception 'not_owner' using errcode = '42501';
  end if;

  if p_user_id = v_owner then
    raise exception 'cannot_kick_owner' using errcode = 'P0001';
  end if;

  select p.group_id into v_target_gid
  from public.profiles p where p.id = p_user_id for update;

  if not found or v_target_gid is distinct from v_gid then
    raise exception 'not_a_member' using errcode = 'P0002';
  end if;

  update public.profiles set group_id = null where id = p_user_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------

grant execute on function public.bootstrap_profile(text) to authenticated;
grant execute on function public.create_group()          to authenticated;
grant execute on function public.join_group(text)        to authenticated;
grant execute on function public.leave_group()           to authenticated;
grant execute on function public.kick_member(uuid)       to authenticated;
