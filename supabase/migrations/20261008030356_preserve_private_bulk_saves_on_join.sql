-- Preserve private bulk saves, and serialize sharing-ending actions with household moves.
-- PostgREST retries serialization failures (40001) until the request times out, so a stale move
-- confirmation reports a conflict (HTTP 409) instead.
create or replace function private.join_household(code text, save_household_recipes boolean, expected_household uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare uid uuid := (select auth.uid()); me public.household_members; destination public.households; photos text[]; original_ids uuid[];
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
    select coalesce(array_agg(id), '{}') into original_ids from public.recipes where owner_id = uid;
    photos := private.depart_household(uid, save_household_recipes);
    insert into public.household_members (household_id, user_id, display_name, avatar_url)
    values (destination.id, uid, coalesce(me.display_name, ''), me.avatar_url);
    update public.recipes set is_shared = true where owner_id = uid and id = any(original_ids) and not is_shared;
    return jsonb_build_object('household', to_jsonb(destination), 'unused_photos', to_jsonb(photos));
end;
$$;

create or replace function private.set_recipe_sharing(target_recipe uuid, shared boolean)
returns public.recipes language plpgsql security definer set search_path = ''
as $$
declare r public.recipes; hid uuid;
begin
    if auth.uid() is null then raise exception 'Sign in to change recipes' using errcode = '42501'; end if;
    perform private.lock_people(array[auth.uid()]);
    hid := private.current_household();
    perform private.lock_households(array[hid]);
    select * into r from public.recipes where id = target_recipe and owner_id = (select auth.uid()) for update;
    if r.id is null then raise exception 'Only the recipe’s owner can change its sharing' using errcode = '42501'; end if;
    if r.is_shared and not shared and hid is not null then
        perform private.retain_household_copy(r, hid);
    end if;
    update public.recipes set is_shared = shared where id = r.id returning * into r;
    return r;
end;
$$;

-- Owners delete their originals, and members delete household recipes. A shared original
-- leaves its household a copy. Planned meals keep their saved versions.
-- Returns photos nothing uses anymore, for the app to remove from Storage.
create or replace function private.delete_recipe(target_recipe uuid)
returns text[] language plpgsql security definer set search_path = ''
as $$
declare r public.recipes; hid uuid;
begin
    if auth.uid() is null then raise exception 'Sign in to change recipes' using errcode = '42501'; end if;
    perform private.lock_people(array[auth.uid()]);
    hid := private.current_household();
    perform private.lock_households(array[hid]);
    select * into r from public.recipes where id = target_recipe for update;
    if r.id is null then return '{}'; end if;
    if r.owner_id = (select auth.uid()) then
        if r.is_shared and hid is not null then
            perform private.retain_household_copy(r, hid);
        end if;
    elsif r.household_id is null or r.household_id is distinct from hid then
        raise exception 'You can’t delete this recipe' using errcode = '42501';
    end if;
    delete from public.recipes where id = r.id;
    return private.unused_photos(array[r.image_path]);
end;
$$;

