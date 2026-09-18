begin;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare requested_role public.app_role;
begin
  insert into public.users (id, email, full_name)
  values (new.id, coalesce(new.email, ''), coalesce(new.raw_user_meta_data ->> 'full_name', ''))
  on conflict(id) do nothing;

  insert into public.user_roles (user_id, role)
  values (new.id, 'customer') on conflict do nothing;

  if new.raw_user_meta_data ->> 'requested_role' = 'vendor' then
    insert into public.user_roles (user_id, role)
    values (new.id, 'vendor') on conflict do nothing;
  end if;
  return new;
end; $$;

create or replace function public.prevent_role_self_escalation()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.role = 'admin' and auth.role() <> 'service_role' and not public.is_admin() then
    raise exception 'Only an administrator can grant the admin role';
  end if;
  return new;
end; $$;

create trigger prevent_admin_self_escalation
before insert or update on public.user_roles
for each row execute function public.prevent_role_self_escalation();

commit;
