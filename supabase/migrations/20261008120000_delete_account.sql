-- A person can delete their own account. They depart their household as when leaving it: the household
-- keeps copies of their shared recipes and passes ownership on, or is deleted when nobody remains.
-- Their personal recipes and favorites go with the account. Storage objects can't be deleted from SQL,
-- so this returns recipe photos nothing uses anymore for the client to remove.
create function private.delete_account()
returns text[] language plpgsql security definer set search_path = ''
as $$
declare uid uuid := (select auth.uid()); hid uuid; photos text[]; personal text[];
begin
    if uid is null then raise exception 'Sign in to delete your account' using errcode = '42501'; end if;
    perform private.lock_people(array[uid]);
    hid := private.household_of(uid);
    if hid is not null then perform private.lock_households(array[hid]); end if;
    photos := private.depart_household(uid, false);
    with deleted as (
        delete from public.recipes where owner_id = uid returning image_path
    )
    select coalesce(array_agg(image_path), '{}') into personal from deleted;
    delete from auth.users where id = uid;
    return photos || private.unused_photos(personal);
end;
$$;

create function public.delete_account()
returns text[] language sql security invoker set search_path = ''
as $$ select private.delete_account(); $$;

revoke all on function private.delete_account() from public, anon, authenticated, service_role;
revoke all on function public.delete_account() from public, anon, authenticated, service_role;
grant execute on function private.delete_account() to authenticated;
grant execute on function public.delete_account() to authenticated;
