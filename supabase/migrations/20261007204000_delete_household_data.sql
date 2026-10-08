-- The household owner can delete all of its recipes, meal plans, and groceries in one
-- transaction. Members and the household remain. Storage objects can't be deleted from
-- SQL, so this returns the deleted recipes' photo paths for the client to remove.
create function public.delete_household_data(target_household uuid)
returns text[] language plpgsql security invoker set search_path = ''
as $$
declare photo_paths text[];
begin
    if not exists (
        select 1 from public.household_members
        where household_id = target_household and user_id = (select auth.uid()) and role = 'owner'
    ) then
        raise exception 'Only the household owner can delete its data' using errcode = '42501';
    end if;
    delete from public.grocery_items where household_id = target_household;
    delete from public.planned_meals where household_id = target_household;
    with deleted as (
        delete from public.recipes where household_id = target_household returning image_path
    )
    select coalesce(array_agg(image_path) filter (where image_path is not null), '{}')
    into photo_paths from deleted;
    return photo_paths;
end;
$$;
revoke all on function public.delete_household_data(uuid) from public, anon, authenticated, service_role;
grant execute on function public.delete_household_data(uuid) to authenticated;
