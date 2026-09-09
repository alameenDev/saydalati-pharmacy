-- Applied after security advisor review on the selected project.
revoke execute on function public.rls_auto_enable() from public,anon,authenticated;
create policy requests_deny_client on pharmacy_private.requests for all to authenticated using(false) with check(false);
