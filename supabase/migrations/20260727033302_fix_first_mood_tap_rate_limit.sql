-- profiles.mood_updated_at defaults to now(), and apply_mood() rejects any change
-- within 3 seconds of the last one. Together that means a user who signs up and taps a
-- mood quickly -- a deep-linked join, a fast re-onboard after Delete My Data, or any
-- automated test -- gets a 429 on their very FIRST tap, with nothing to retry against
-- except a stopwatch. Backdate the column on insert so the first tap is always free.
-- The rate limit still applies to every subsequent change.
--
-- Only the INSERT branch is backdated; the ON CONFLICT branch (a display name change)
-- must not touch mood state at all.

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

  insert into public.profiles (id, display_name, mood_updated_at)
  values (v_uid, v_name, now() - interval '1 minute')
  on conflict (id) do update set display_name = excluded.display_name
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.bootstrap_profile(text) from public, anon;
grant execute on function public.bootstrap_profile(text) to authenticated;

notify pgrst, 'reload schema';
