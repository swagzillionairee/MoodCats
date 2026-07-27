-- Advisor 0003 auth_rls_initplan: bare auth.uid() / current_group_id() inside a policy
-- is re-evaluated once per candidate row. Wrapping each in (select ...) turns it into
-- an InitPlan that Postgres evaluates exactly once per statement. Semantics are
-- unchanged -- these are the same policies as in 20260727032711, only faster.

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select
  using (
    id = (select auth.uid())
    or (group_id is not null and group_id = (select public.current_group_id()))
  );

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists groups_select on public.groups;
create policy groups_select on public.groups for select
  using (id = (select public.current_group_id()));

drop policy if exists tokens_all on public.device_tokens;
create policy tokens_all on public.device_tokens for all
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
