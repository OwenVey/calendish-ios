-- The household owner can remove other members. The owner's own row can't be removed this way.

-- Security definer so the household_members policy below can call it without recursing.
create function private.is_household_owner(hid uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
    select exists (
        select 1 from public.household_members m
        where m.household_id = hid and m.user_id = (select auth.uid()) and m.role = 'owner'
    );
$$;
revoke all on function private.is_household_owner(uuid) from public, anon, authenticated, service_role;
grant execute on function private.is_household_owner(uuid) to authenticated;

create policy "Owners can remove members" on public.household_members
    for delete to authenticated
    using (role <> 'owner' and private.is_household_owner(household_id));
