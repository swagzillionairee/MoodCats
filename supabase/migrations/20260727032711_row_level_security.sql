-- MoodCats row level security (spec section 6.2)
--
-- READ THIS BEFORE EDITING:
-- A policy on `profiles` that subqueries `profiles` causes infinite recursion, and it
-- presents as a hang rather than an error. Every policy below that needs "the caller's
-- group" goes through public.current_group_id(), a security definer helper that bypasses
-- RLS because it executes as the table owner.

create or replace function public.current_group_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select group_id from public.profiles where id = auth.uid()
$$;

comment on function public.current_group_id() is
  'RLS helper. security definer so that policies on profiles never subquery profiles under RLS (infinite recursion).';

alter table public.groups        enable row level security;
alter table public.profiles      enable row level security;
alter table public.device_tokens enable row level security;

-- ---------------------------------------------------------------------------
-- profiles
-- ---------------------------------------------------------------------------

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select
  using (
    id = auth.uid()
    or (group_id is not null and group_id = public.current_group_id())
  );

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update
  using (id = auth.uid()) with check (id = auth.uid());

-- There is deliberately no insert or delete policy on profiles. Rows are created by
-- bootstrap_profile() and removed by delete_my_data(), both security definer.

-- ---------------------------------------------------------------------------
-- groups
-- ---------------------------------------------------------------------------

drop policy if exists groups_select on public.groups;
create policy groups_select on public.groups for select
  using (id = public.current_group_id());

-- groups has NO insert/update/delete policy. Every group mutation goes through an RPC.
-- This is intentional; do not "fix" it by adding one.

-- ---------------------------------------------------------------------------
-- device_tokens
-- ---------------------------------------------------------------------------

drop policy if exists tokens_all on public.device_tokens;
create policy tokens_all on public.device_tokens for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Column level grants
-- ---------------------------------------------------------------------------
-- RLS says *which rows* a caller may touch; grants say *which columns*. The
-- profiles_update_self policy on its own would let a client PATCH its own group_id or
-- mood_id directly, bypassing join_group() and the push fanout in set-mood. Narrowing
-- the UPDATE grant to display_name closes that without a trigger.
--
-- security definer RPCs are unaffected: they execute as the table owner.

revoke all on public.profiles      from anon, authenticated;
revoke all on public.groups        from anon, authenticated;
revoke all on public.device_tokens from anon, authenticated;

grant select           on public.profiles to authenticated;
grant update (display_name) on public.profiles to authenticated;

grant select on public.groups to authenticated;

grant select, insert, update, delete on public.device_tokens to authenticated;
