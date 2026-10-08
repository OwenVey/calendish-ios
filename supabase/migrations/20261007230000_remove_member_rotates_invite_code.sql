-- The household owner can remove another member. Removal also replaces the invite code
-- in the same transaction, so the removed person can't rejoin with the code they had.
-- This replaces the direct delete policy, which couldn't rotate the code.
drop policy "Owners can remove members" on public.household_members;
drop function private.is_household_owner(uuid);

create function private.remove_household_member(target_household uuid, target_user uuid)
returns public.households language plpgsql security definer set search_path = ''
as $$
declare h public.households;
begin
    if not exists (
        select 1 from public.household_members
        where household_id = target_household and user_id = (select auth.uid()) and role = 'owner'
    ) then
        raise exception 'Only the household owner can remove members' using errcode = '42501';
    end if;
    delete from public.household_members
    where household_id = target_household and user_id = target_user and role <> 'owner';
    if not found then
        raise exception 'That person isn’t a member of this household' using errcode = 'P0002';
    end if;
    update public.households set invite_code = default
    where id = target_household returning * into h;
    return h;
end;
$$;
revoke all on function private.remove_household_member(uuid, uuid) from public, anon, authenticated, service_role;
grant execute on function private.remove_household_member(uuid, uuid) to authenticated;

create function public.remove_household_member(target_household uuid, target_user uuid)
returns public.households language sql security invoker set search_path = ''
as $$ select * from private.remove_household_member(target_household, target_user); $$;
revoke all on function public.remove_household_member(uuid, uuid) from public, anon, authenticated, service_role;
grant execute on function public.remove_household_member(uuid, uuid) to authenticated;
