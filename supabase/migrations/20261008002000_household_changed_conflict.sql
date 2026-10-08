-- PostgREST retries serialization failures (40001) until the request times out, so a stale move
-- confirmation reports a conflict (HTTP 409) instead.
create or replace function private.join_household(code text, save_household_recipes boolean, expected_household uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare uid uuid := (select auth.uid()); me public.household_members; destination public.households; photos text[];
begin
    if uid is null then raise exception 'Sign in to join a household' using errcode = '42501'; end if;
    perform private.lock_people(array[uid]);
    select * into destination from public.households where invite_code = upper(trim(code));
    if destination.id is null then
        raise exception 'This invitation isn’t valid anymore. Ask for a new invite code.' using errcode = 'P0002';
    end if;
    select * into me from public.household_members where user_id = uid;
    if me.household_id = destination.id then
        return jsonb_build_object('household', to_jsonb(destination), 'unused_photos', '[]'::jsonb);
    end if;
    if me.household_id is distinct from expected_household then
        raise exception 'Your household changed. Review the move again.' using errcode = 'PT409';
    end if;
    perform private.lock_households(array[me.household_id, destination.id]);
    -- The code may have been replaced while waiting for the lock.
    select * into destination from public.households where id = destination.id and invite_code = upper(trim(code));
    if destination.id is null then
        raise exception 'This invitation isn’t valid anymore. Ask for a new invite code.' using errcode = 'P0002';
    end if;
    photos := private.depart_household(uid, save_household_recipes);
    insert into public.household_members (household_id, user_id, display_name, avatar_url)
    values (destination.id, uid, coalesce(me.display_name, ''), me.avatar_url);
    update public.recipes set is_shared = true where owner_id = uid and not is_shared;
    return jsonb_build_object('household', to_jsonb(destination), 'unused_photos', to_jsonb(photos));
end;
$$;

create or replace function private.leave_household(save_household_recipes boolean, expected_household uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare uid uuid := (select auth.uid()); me public.household_members; h public.households; photos text[];
begin
    if uid is null then raise exception 'Sign in to leave a household' using errcode = '42501'; end if;
    perform private.lock_people(array[uid]);
    select * into me from public.household_members where user_id = uid;
    if me.household_id is null or me.household_id is distinct from expected_household then
        raise exception 'Your household changed. Review the move again.' using errcode = 'PT409';
    end if;
    perform private.lock_households(array[me.household_id]);
    photos := private.depart_household(uid, save_household_recipes);
    h := private.create_solo_household(uid, me.display_name, me.avatar_url);
    return jsonb_build_object('household', to_jsonb(h), 'unused_photos', to_jsonb(photos));
end;
$$;
