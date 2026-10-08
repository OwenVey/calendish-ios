-- Personal and household recipe ownership, one household per person, automatic onboarding,
-- membership transitions, and saved recipe versions for planned meals.
-- See docs/adr/0001-personal-and-household-recipe-ownership.md and 0002-household-onboarding-and-ownership.md.

-- Membership -----------------------------------------------------------------

-- Each person belongs to exactly one household. Earlier versions allowed several; keep the oldest.
delete from public.household_members as m
using public.household_members as older
where m.user_id = older.user_id
  and (older.joined_at, older.household_id) < (m.joined_at, m.household_id);
alter table public.household_members add constraint household_members_user_id_key unique (user_id);
drop index public.household_members_user_id_idx;
create unique index household_members_one_owner_idx on public.household_members (household_id) where role = 'owner';

-- Membership only changes through the functions below, which keep these rules together.
drop policy "Members can leave a household" on public.household_members;
revoke delete on public.household_members from authenticated;

create function private.current_household()
returns uuid language sql stable security definer set search_path = ''
as $$ select household_id from public.household_members where user_id = (select auth.uid()); $$;

create function private.household_of(person uuid)
returns uuid language sql stable security definer set search_path = ''
as $$ select household_id from public.household_members where user_id = person; $$;

-- A household is never left without an owner or members, even when an account is deleted outright.
-- The longest-standing member succeeds an owner; ties resolve by user ID.
create function private.after_member_removed()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
    if not exists (select 1 from public.households where id = old.household_id) then
        return null;
    end if;
    if not exists (select 1 from public.household_members where household_id = old.household_id) then
        delete from public.households where id = old.household_id;
    elsif not exists (select 1 from public.household_members where household_id = old.household_id and role = 'owner') then
        update public.household_members set role = 'owner'
        where household_id = old.household_id and user_id = (
            select user_id from public.household_members where household_id = old.household_id
            order by joined_at, user_id limit 1
        );
    end if;
    return null;
end;
$$;
create trigger after_member_removed after delete on public.household_members
    for each row execute function private.after_member_removed();

create function private.check_household_has_owner()
returns trigger language plpgsql set search_path = ''
as $$
declare hid uuid := coalesce(new.household_id, old.household_id);
begin
    if exists (select 1 from public.household_members where household_id = hid)
       and not exists (select 1 from public.household_members where household_id = hid and role = 'owner') then
        raise exception 'A household with members needs an owner' using errcode = '23514';
    end if;
    return null;
end;
$$;
create constraint trigger household_has_owner after insert or update or delete on public.household_members
    deferrable initially deferred for each row execute function private.check_household_has_owner();

-- Recipes --------------------------------------------------------------------

-- A recipe belongs to a person or to a household, never both. Sharing applies only to personal recipes.
alter table public.recipes
    add column owner_id uuid references auth.users (id) on delete cascade,
    add column is_shared boolean not null default false,
    alter column household_id drop not null;

-- Every existing household has one member, so its recipes become that person's shared recipes.
-- Any household with several members keeps them as household recipes.
update public.recipes as r set owner_id = m.user_id, household_id = null, is_shared = true
from public.household_members as m
where m.household_id = r.household_id and m.role = 'owner'
  and (select count(*) from public.household_members where household_id = r.household_id) = 1;

alter table public.recipes
    add constraint recipes_one_owner check ((owner_id is null) <> (household_id is null)),
    add constraint recipes_sharing_is_personal check (not is_shared or owner_id is not null);
create index recipes_owner_id_idx on public.recipes (owner_id);
create index recipes_image_path_idx on public.recipes (image_path) where image_path is not null;

create function private.can_view_recipe(recipe_owner uuid, recipe_household uuid, shared boolean)
returns boolean language sql stable security definer set search_path = ''
as $$
    select recipe_owner = (select auth.uid())
        or recipe_household = private.current_household()
        or (shared and private.household_of(recipe_owner) = private.current_household());
$$;

drop policy "Members manage recipes" on public.recipes;
create policy "People view recipes available to them" on public.recipes
    for select to authenticated using (private.can_view_recipe(owner_id, household_id, is_shared));
create policy "People add personal recipes" on public.recipes
    for insert to authenticated with check (owner_id = (select auth.uid()) and household_id is null);
create policy "Owners edit originals and members edit household recipes" on public.recipes
    for update to authenticated
    using (owner_id = (select auth.uid()) or household_id = private.current_household())
    with check (owner_id = (select auth.uid()) or household_id = private.current_household());

-- Ownership, sharing, and deletion go through functions that keep household copies.
revoke all on public.recipes from authenticated;
grant select on public.recipes to authenticated;
grant insert (id, owner_id, is_shared, title, summary, minutes, prep_minutes, cook_minutes, servings, tags, symbol,
    ingredients, steps, image_path, recipe_link, category, yield_text) on public.recipes to authenticated;
grant update (title, summary, minutes, prep_minutes, cook_minutes, servings, tags, symbol,
    ingredients, steps, image_path, recipe_link, category, yield_text) on public.recipes to authenticated;

-- A photo must be uploaded to the person's or their household's folder before a recipe can point at it.
-- Copies made by the functions below may keep the original's photo.
create function private.check_recipe_photo()
returns trigger language plpgsql set search_path = ''
as $$
begin
    if tg_op = 'UPDATE' then
        if new.image_path is not distinct from old.image_path then return new; end if;
    end if;
    if current_user = 'authenticated' and new.image_path is not null
       and split_part(new.image_path, '/', 1) not in (
           (select auth.uid())::text, coalesce(private.current_household()::text, '')) then
        raise exception 'Recipe photos must be uploaded to your own or your household’s folder' using errcode = '42501';
    end if;
    return new;
end;
$$;
create trigger check_recipe_photo before insert or update of image_path on public.recipes
    for each row execute function private.check_recipe_photo();

-- Favorites belong to each person rather than the whole household.
create table public.recipe_favorites (
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    recipe_id uuid not null references public.recipes (id) on delete cascade,
    created_at timestamptz not null default now(),
    primary key (user_id, recipe_id)
);
create index recipe_favorites_recipe_id_idx on public.recipe_favorites (recipe_id);
insert into public.recipe_favorites (user_id, recipe_id)
select coalesce(r.owner_id, m.user_id), r.id
from public.recipes as r left join public.household_members as m on m.household_id = r.household_id
where r.is_favorite and coalesce(r.owner_id, m.user_id) is not null;
alter table public.recipes drop column is_favorite;

alter table public.recipe_favorites enable row level security;
grant select, insert, delete on public.recipe_favorites to authenticated;
create policy "People view their favorites" on public.recipe_favorites
    for select to authenticated using (user_id = (select auth.uid()));
create policy "People favorite recipes available to them" on public.recipe_favorites
    for insert to authenticated with check (
        user_id = (select auth.uid()) and exists (select 1 from public.recipes as r where r.id = recipe_id));
create policy "People remove their favorites" on public.recipe_favorites
    for delete to authenticated using (user_id = (select auth.uid()));

-- Planned meals --------------------------------------------------------------

-- A planned meal keeps the recipe version captured when it was planned. The source recipe link
-- survives only while that recipe exists, for an explicit update to its latest version.
create function private.recipe_version(r public.recipes)
returns jsonb language sql immutable set search_path = ''
as $$
    select jsonb_build_object(
        'id', r.id, 'title', r.title, 'summary', r.summary, 'minutes', r.minutes,
        'prep_minutes', r.prep_minutes, 'cook_minutes', r.cook_minutes, 'servings', r.servings,
        'tags', to_jsonb(r.tags), 'symbol', r.symbol, 'ingredients', r.ingredients, 'steps', r.steps,
        'image_path', r.image_path, 'recipe_link', r.recipe_link, 'category', r.category, 'yield_text', r.yield_text);
$$;

alter table public.planned_meals drop constraint planned_meals_household_recipe_fkey;
drop index public.planned_meals_household_recipe_idx;
alter table public.recipes drop constraint recipes_household_id_id_key;
alter table public.planned_meals
    alter column recipe_id drop not null,
    add constraint planned_meals_recipe_id_fkey foreign key (recipe_id) references public.recipes (id) on delete set null,
    add column recipe jsonb;
update public.planned_meals as p set recipe = private.recipe_version(r) from public.recipes as r where r.id = p.recipe_id;
delete from public.planned_meals where recipe is null;
alter table public.planned_meals alter column recipe set not null;
create index planned_meals_recipe_id_idx on public.planned_meals (recipe_id);
create index planned_meals_photo_idx on public.planned_meals ((recipe ->> 'image_path')) where recipe ->> 'image_path' is not null;

-- Meals are saved through save_planned_meal so their recipe versions come from the database.
revoke insert, update on public.planned_meals from authenticated;

-- Photos ---------------------------------------------------------------------

-- Copies and planned meals share a photo with the recipe they came from, so a photo
-- stays readable wherever it is used and is only deleted once nothing uses it.
create function private.recipe_photo_in_use(path text)
returns boolean language sql stable security definer set search_path = ''
as $$
    select exists (select 1 from public.recipes where image_path = path)
        or exists (select 1 from public.planned_meals where recipe ->> 'image_path' = path);
$$;

create function private.unused_photos(paths text[])
returns text[] language sql stable security definer set search_path = ''
as $$
    select coalesce(array_agg(distinct p), '{}') from unnest(paths) as p
    where p is not null and not private.recipe_photo_in_use(p);
$$;

drop policy "Members can view recipe photos" on storage.objects;
drop policy "Members can add recipe photos" on storage.objects;
drop policy "Members can delete recipe photos" on storage.objects;

-- The subqueries run under the recipes and planned_meals policies, so a photo is visible exactly
-- where a recipe or planned meal using it is.
create policy "People view photos they can use" on storage.objects
    for select to authenticated using (
        bucket_id = 'recipe-images' and (
            owner_id = (select auth.uid())::text
            or exists (select 1 from public.recipes as r where r.image_path = storage.objects.name)
            or exists (select 1 from public.planned_meals as p where p.recipe ->> 'image_path' = storage.objects.name)
        )
    );
create policy "People add photos to their own or household folder" on storage.objects
    for insert to authenticated with check (
        bucket_id = 'recipe-images'
        and (storage.foldername(name))[1] in ((select auth.uid())::text, private.current_household()::text)
    );
-- Abandoned photos from departed members or deleted households become removable after a day,
-- which leaves in-progress uploads alone.
create policy "People delete photos nothing uses" on storage.objects
    for delete to authenticated using (
        bucket_id = 'recipe-images'
        and not private.recipe_photo_in_use(name)
        and (
            owner_id = (select auth.uid())::text
            or (storage.foldername(name))[1] in ((select auth.uid())::text, private.current_household()::text)
            or created_at < now() - interval '1 day'
        )
    );

-- Recipe operations ----------------------------------------------------------

create function private.has_other_members(hid uuid, person uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.household_members where household_id = hid and user_id <> person); $$;

-- Gives a household its own copy of a shared recipe, which no longer follows the original.
-- The household's planned meals and members' favorites move to the copy.
create function private.retain_household_copy(source public.recipes, target_household uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare copy_id uuid;
begin
    insert into public.recipes (household_id, title, summary, minutes, prep_minutes, cook_minutes, servings, tags, symbol,
        ingredients, steps, image_path, recipe_link, category, yield_text, created_at)
    values (target_household, source.title, source.summary, source.minutes, source.prep_minutes, source.cook_minutes,
        source.servings, source.tags, source.symbol, source.ingredients, source.steps, source.image_path,
        source.recipe_link, source.category, source.yield_text, source.created_at)
    returning id into copy_id;
    update public.planned_meals set recipe_id = copy_id where household_id = target_household and recipe_id = source.id;
    insert into public.recipe_favorites (user_id, recipe_id)
    select f.user_id, copy_id from public.recipe_favorites as f
    join public.household_members as m on m.user_id = f.user_id and m.household_id = target_household
    where f.recipe_id = source.id and f.user_id <> source.owner_id;
    return copy_id;
end;
$$;

create function private.copy_to_person(source public.recipes, person uuid)
returns public.recipes language plpgsql security definer set search_path = ''
as $$
declare copied public.recipes;
begin
    insert into public.recipes (owner_id, is_shared, title, summary, minutes, prep_minutes, cook_minutes, servings, tags,
        symbol, ingredients, steps, image_path, recipe_link, category, yield_text)
    values (person, false, source.title, source.summary, source.minutes, source.prep_minutes, source.cook_minutes,
        source.servings, source.tags, source.symbol, source.ingredients, source.steps, source.image_path,
        source.recipe_link, source.category, source.yield_text)
    returning * into copied;
    return copied;
end;
$$;

-- Saves a private copy of a recipe the caller can see into their own collection.
create function private.save_recipe_copy(source_recipe uuid)
returns public.recipes language plpgsql security definer set search_path = ''
as $$
declare source public.recipes;
begin
    if auth.uid() is null then raise exception 'Sign in to save recipes' using errcode = '42501'; end if;
    select * into source from public.recipes where id = source_recipe;
    if source.id is null or not private.can_view_recipe(source.owner_id, source.household_id, source.is_shared) then
        raise exception 'That recipe isn’t available anymore' using errcode = 'P0002';
    end if;
    return private.copy_to_person(source, auth.uid());
end;
$$;

-- Only the owner shares or unshares. Ending sharing leaves the household its own copy
-- when anyone else is in it, since sharing is a lasting contribution.
create function private.set_recipe_sharing(target_recipe uuid, shared boolean)
returns public.recipes language plpgsql security definer set search_path = ''
as $$
declare r public.recipes; hid uuid := private.current_household();
begin
    select * into r from public.recipes where id = target_recipe and owner_id = (select auth.uid()) for update;
    if r.id is null then raise exception 'Only the recipe’s owner can change its sharing' using errcode = '42501'; end if;
    if r.is_shared and not shared and private.has_other_members(hid, r.owner_id) then
        perform private.retain_household_copy(r, hid);
    end if;
    update public.recipes set is_shared = shared where id = r.id returning * into r;
    return r;
end;
$$;

-- Owners delete their originals, and members delete household recipes. A shared original
-- leaves its household a copy. Planned meals keep their saved versions.
-- Returns photos nothing uses anymore, for the app to remove from Storage.
create function private.delete_recipe(target_recipe uuid)
returns text[] language plpgsql security definer set search_path = ''
as $$
declare r public.recipes; hid uuid := private.current_household();
begin
    select * into r from public.recipes where id = target_recipe for update;
    if r.id is null then return '{}'; end if;
    if r.owner_id = (select auth.uid()) then
        if r.is_shared and private.has_other_members(hid, r.owner_id) then
            perform private.retain_household_copy(r, hid);
        end if;
    elsif r.household_id is null or r.household_id is distinct from hid then
        raise exception 'You can’t delete this recipe' using errcode = '42501';
    end if;
    delete from public.recipes where id = r.id;
    return private.unused_photos(array[r.image_path]);
end;
$$;

-- Plans a recipe, capturing its current version, or moves a meal. With keep_version, a moved meal
-- keeps the recipe version and source it already had, and meal_recipe is ignored.
create function private.save_planned_meal(
    target_household uuid, meal_id uuid, meal_date date, meal_slot text,
    meal_recipe uuid, meal_servings integer, moving_id uuid, keep_version boolean
)
returns public.planned_meals language plpgsql security definer set search_path = ''
as $$
declare saved public.planned_meals; version jsonb; source uuid; r public.recipes;
begin
    if target_household is null or target_household is distinct from private.current_household() then
        raise exception 'Household access denied' using errcode = '42501';
    end if;
    if keep_version and moving_id is not null then
        select recipe, recipe_id into version, source from public.planned_meals
        where household_id = target_household and id = moving_id;
    end if;
    if version is null then
        select * into r from public.recipes where id = meal_recipe;
        if r.id is null or not private.can_view_recipe(r.owner_id, r.household_id, r.is_shared) then
            raise exception 'That recipe isn’t available anymore' using errcode = '23503';
        end if;
        version := private.recipe_version(r);
        source := r.id;
    end if;
    if moving_id is not null then
        delete from public.planned_meals where household_id = target_household and id = moving_id;
    end if;
    insert into public.planned_meals (id, household_id, date, slot, recipe_id, servings, recipe)
    values (meal_id, target_household, meal_date, meal_slot, source, meal_servings, version)
    on conflict (household_id, date, slot) do update
        set recipe_id = excluded.recipe_id, servings = excluded.servings, recipe = excluded.recipe
    returning * into saved;
    return saved;
end;
$$;

create function private.update_planned_meal_to_latest(target_meal uuid)
returns public.planned_meals language plpgsql security definer set search_path = ''
as $$
declare m public.planned_meals; r public.recipes;
begin
    select * into m from public.planned_meals where id = target_meal and household_id = private.current_household() for update;
    if m.id is null then raise exception 'That meal isn’t in your meal plan anymore' using errcode = 'P0002'; end if;
    select * into r from public.recipes where id = m.recipe_id;
    if r.id is null or not private.can_view_recipe(r.owner_id, r.household_id, r.is_shared) then
        raise exception 'That recipe isn’t available anymore' using errcode = 'P0002';
    end if;
    update public.planned_meals set recipe = private.recipe_version(r) where id = m.id returning * into m;
    return m;
end;
$$;

-- Household moves ------------------------------------------------------------

-- Serializes membership changes for each person involved, in a fixed order.
create function private.lock_people(people uuid[])
returns void language plpgsql set search_path = ''
as $$
declare person uuid;
begin
    for person in select distinct p from unnest(people) as p where p is not null order by 1 loop
        perform pg_advisory_xact_lock(hashtextextended('calendish-membership:' || person::text, 0));
    end loop;
end;
$$;

create function private.lock_households(ids uuid[])
returns void language sql set search_path = ''
as $$ select null from public.households where id = any (ids) order by id for update; $$;

create function private.create_solo_household(person uuid, member_name text, avatar text)
returns public.households language plpgsql security definer set search_path = ''
as $$
declare h public.households; name text := left(trim(member_name), 60);
begin
    insert into public.households (name)
    values (case when name = '' then 'My Household' else name || '’s Household' end) returning * into h;
    insert into public.household_members (household_id, user_id, display_name, avatar_url, role)
    values (h.id, person, trim(member_name), avatar, 'owner');
    return h;
end;
$$;

-- Removes a person from their household. Optionally saves its household recipes to their collection first.
-- The household keeps copies of their shared recipes and passes ownership on, or is deleted with its
-- groceries, meal plan, and household recipes when nobody remains. Returns photos nothing uses anymore.
create function private.depart_household(person uuid, save_household_recipes boolean)
returns text[] language plpgsql security definer set search_path = ''
as $$
declare hid uuid; r public.recipes; photos text[];
begin
    select household_id into hid from public.household_members where user_id = person;
    if hid is null then return '{}'; end if;
    if save_household_recipes then
        for r in select * from public.recipes where household_id = hid order by created_at loop
            perform private.copy_to_person(r, person);
        end loop;
    end if;
    if not private.has_other_members(hid, person) then
        select coalesce(array_agg(image_path), '{}') into photos from public.recipes where household_id = hid;
        delete from public.households where id = hid;
        return private.unused_photos(photos);
    end if;
    for r in select * from public.recipes where owner_id = person and is_shared order by created_at loop
        perform private.retain_household_copy(r, hid);
    end loop;
    -- after_member_removed passes ownership to the longest-standing remaining member.
    delete from public.household_members where household_id = hid and user_id = person;
    return '{}';
end;
$$;

-- What joining (with an invite code) or leaving (without one) would do, shown before confirming.
create function private.preview_household_move(code text)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
    uid uuid := (select auth.uid());
    me public.household_members;
    destination public.households;
    others integer;
    successor jsonb;
begin
    if uid is null then raise exception 'Sign in to join a household' using errcode = '42501'; end if;
    select * into me from public.household_members where user_id = uid;
    if code is not null then
        select * into destination from public.households where invite_code = upper(trim(code));
        if destination.id is null then
            raise exception 'This invitation isn’t valid anymore. Ask for a new invite code.' using errcode = 'P0002';
        end if;
    end if;
    select count(*) into others from public.household_members where household_id = me.household_id and user_id <> uid;
    if me.role = 'owner' and others > 0 then
        select jsonb_build_object('user_id', user_id, 'display_name', display_name) into successor
        from public.household_members where household_id = me.household_id and user_id <> uid
        order by joined_at, user_id limit 1;
    end if;
    return jsonb_build_object(
        'destination', case when destination.id is null then null else jsonb_build_object(
            'id', destination.id, 'name', destination.name,
            'members', (select coalesce(jsonb_agg(display_name order by joined_at), '[]')
                        from public.household_members where household_id = destination.id)) end,
        'current_household_id', me.household_id,
        'current_household_name', (select name from public.households where id = me.household_id),
        'is_current', destination.id is not null and destination.id = me.household_id,
        'other_members', others,
        'successor', successor,
        'deletes_household', me.household_id is not null and others = 0,
        'personal_recipes', (select count(*) from public.recipes where owner_id = uid),
        'shared_recipes', (select count(*) from public.recipes where owner_id = uid and is_shared),
        'household_recipes', (select count(*) from public.recipes where household_id = me.household_id),
        'planned_meals', (select count(*) from public.planned_meals where household_id = me.household_id),
        'groceries', (select count(*) from public.grocery_items where household_id = me.household_id)
    );
end;
$$;

-- Onboarding: joins the invited household, or starts a solo household. Repeating it returns the
-- household the person already has instead of creating another.
create function private.start_household(member_name text, code text)
returns public.households language plpgsql security definer set search_path = ''
as $$
declare uid uuid := (select auth.uid()); h public.households; name text := trim(member_name);
begin
    if uid is null then raise exception 'Sign in to get started' using errcode = '42501'; end if;
    perform private.lock_people(array[uid]);
    select h2.* into h from public.households as h2
    join public.household_members as m on m.household_id = h2.id where m.user_id = uid;
    if h.id is not null then return h; end if;
    if name = '' or char_length(name) > 80 then
        raise exception 'Enter your name to get started' using errcode = '22023';
    end if;
    if nullif(trim(code), '') is null then
        return private.create_solo_household(uid, name, null);
    end if;
    select * into h from public.households where invite_code = upper(trim(code)) for update;
    if h.id is null then
        raise exception 'This invitation isn’t valid anymore. Ask for a new invite code.' using errcode = 'P0002';
    end if;
    insert into public.household_members (household_id, user_id, display_name) values (h.id, uid, name);
    update public.recipes set is_shared = true where owner_id = uid and not is_shared;
    return h;
end;
$$;

-- Moves the caller into the invited household in one transaction. expected_household is the household
-- the caller confirmed leaving; if it changed since, nothing happens. Joining the current household is a no-op.
create function private.join_household(code text, save_household_recipes boolean, expected_household uuid)
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
        raise exception 'Your household changed. Review the move again.' using errcode = '40001';
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

-- Leaves for a fresh solo household with an empty grocery list and meal plan.
create function private.leave_household(save_household_recipes boolean, expected_household uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare uid uuid := (select auth.uid()); me public.household_members; h public.households; photos text[];
begin
    if uid is null then raise exception 'Sign in to leave a household' using errcode = '42501'; end if;
    perform private.lock_people(array[uid]);
    select * into me from public.household_members where user_id = uid;
    if me.household_id is null or me.household_id is distinct from expected_household then
        raise exception 'Your household changed. Review the move again.' using errcode = '40001';
    end if;
    perform private.lock_households(array[me.household_id]);
    photos := private.depart_household(uid, save_household_recipes);
    h := private.create_solo_household(uid, me.display_name, me.avatar_url);
    return jsonb_build_object('household', to_jsonb(h), 'unused_photos', to_jsonb(photos));
end;
$$;

create function private.transfer_household_ownership(target_household uuid, new_owner uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare uid uuid := (select auth.uid());
begin
    perform private.lock_people(array[uid, new_owner]);
    perform private.lock_households(array[target_household]);
    if not exists (select 1 from public.household_members
                   where household_id = target_household and user_id = uid and role = 'owner') then
        raise exception 'Only the household owner can transfer ownership' using errcode = '42501';
    end if;
    if new_owner = uid or not exists (select 1 from public.household_members
                                      where household_id = target_household and user_id = new_owner) then
        raise exception 'That person isn’t a member of this household' using errcode = 'P0002';
    end if;
    update public.household_members set role = 'member' where household_id = target_household and user_id = uid;
    update public.household_members set role = 'owner' where household_id = target_household and user_id = new_owner;
end;
$$;

-- The owner removes another member, who keeps their personal recipes and gets a fresh solo household.
-- The household keeps copies of their shared recipes. The invite code changes in the same transaction,
-- so the removed person can't rejoin with the code they had.
create or replace function private.remove_household_member(target_household uuid, target_user uuid)
returns public.households language plpgsql security definer set search_path = ''
as $$
declare h public.households; removed public.household_members;
begin
    perform private.lock_people(array[(select auth.uid()), target_user]);
    perform private.lock_households(array[target_household]);
    if not exists (
        select 1 from public.household_members
        where household_id = target_household and user_id = (select auth.uid()) and role = 'owner'
    ) then
        raise exception 'Only the household owner can remove members' using errcode = '42501';
    end if;
    select * into removed from public.household_members
    where household_id = target_household and user_id = target_user and role <> 'owner';
    if removed.user_id is null then
        raise exception 'That person isn’t a member of this household' using errcode = 'P0002';
    end if;
    perform private.depart_household(target_user, false);
    perform private.create_solo_household(target_user, removed.display_name, removed.avatar_url);
    update public.households set invite_code = default
    where id = target_household returning * into h;
    return h;
end;
$$;

-- Deleting household data removes household recipes, meals, and groceries. Personal recipes,
-- including ones shared with the household, stay with their owners.
create function private.delete_household_data(target_household uuid)
returns text[] language plpgsql security definer set search_path = ''
as $$
declare photos text[];
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
    select coalesce(array_agg(image_path), '{}') into photos from deleted;
    return private.unused_photos(photos);
end;
$$;

create or replace function public.delete_household_data(target_household uuid)
returns text[] language sql security invoker set search_path = ''
as $$ select private.delete_household_data(target_household); $$;

-- The old functions allowed several memberships and an onboarding choice.
drop function public.create_household(text, text);
drop function public.join_household(text, text);
drop function private.create_household(text, text);
drop function private.join_household(text, text);
drop function public.save_planned_meal(uuid, uuid, date, text, uuid, integer, uuid);

-- Client-callable wrappers run as the caller; the implementations check auth.uid() themselves.
create function public.preview_household_move(code text default null)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.preview_household_move(code); $$;
create function public.start_household(member_name text, code text default null)
returns public.households language sql security invoker set search_path = ''
as $$ select * from private.start_household(member_name, code); $$;
create function public.join_household(code text, save_household_recipes boolean, expected_household uuid)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.join_household(code, save_household_recipes, expected_household); $$;
create function public.leave_household(save_household_recipes boolean, expected_household uuid)
returns jsonb language sql security invoker set search_path = ''
as $$ select private.leave_household(save_household_recipes, expected_household); $$;
create function public.transfer_household_ownership(target_household uuid, new_owner uuid)
returns void language sql security invoker set search_path = ''
as $$ select private.transfer_household_ownership(target_household, new_owner); $$;
create function public.save_recipe_copy(source_recipe uuid)
returns public.recipes language sql security invoker set search_path = ''
as $$ select * from private.save_recipe_copy(source_recipe); $$;
create function public.set_recipe_sharing(target_recipe uuid, shared boolean)
returns public.recipes language sql security invoker set search_path = ''
as $$ select * from private.set_recipe_sharing(target_recipe, shared); $$;
create function public.delete_recipe(target_recipe uuid)
returns text[] language sql security invoker set search_path = ''
as $$ select private.delete_recipe(target_recipe); $$;
create function public.save_planned_meal(
    target_household uuid, meal_id uuid, meal_date date, meal_slot text,
    meal_recipe uuid, meal_servings integer, moving_id uuid default null, keep_version boolean default false
)
returns public.planned_meals language sql security invoker set search_path = ''
as $$ select * from private.save_planned_meal(target_household, meal_id, meal_date, meal_slot,
    meal_recipe, meal_servings, moving_id, keep_version); $$;
create function public.update_planned_meal_to_latest(target_meal uuid)
returns public.planned_meals language sql security invoker set search_path = ''
as $$ select * from private.update_planned_meal_to_latest(target_meal); $$;

-- Privileges -----------------------------------------------------------------

do $$
declare f regprocedure;
begin
    for f in
        select p.oid::regprocedure from pg_proc as p join pg_namespace as n on n.oid = p.pronamespace
        where n.nspname in ('public', 'private') and p.proname in (
            'current_household', 'household_of', 'after_member_removed', 'check_household_has_owner',
            'can_view_recipe', 'check_recipe_photo', 'recipe_version', 'recipe_photo_in_use', 'unused_photos',
            'has_other_members', 'retain_household_copy', 'copy_to_person', 'save_recipe_copy',
            'set_recipe_sharing', 'delete_recipe', 'save_planned_meal', 'update_planned_meal_to_latest',
            'lock_people', 'lock_households', 'create_solo_household', 'depart_household',
            'preview_household_move', 'start_household', 'join_household', 'leave_household',
            'transfer_household_ownership', 'remove_household_member', 'delete_household_data')
    loop
        execute format('revoke all on function %s from public, anon, authenticated, service_role', f);
    end loop;
end;
$$;

-- Policies, triggers, and the public wrappers below call these as the signed-in person.
grant execute on function private.current_household(), private.household_of(uuid),
    private.can_view_recipe(uuid, uuid, boolean), private.recipe_photo_in_use(text),
    private.preview_household_move(text), private.start_household(text, text),
    private.join_household(text, boolean, uuid), private.leave_household(boolean, uuid),
    private.transfer_household_ownership(uuid, uuid), private.remove_household_member(uuid, uuid),
    private.delete_household_data(uuid), private.save_recipe_copy(uuid), private.set_recipe_sharing(uuid, boolean),
    private.delete_recipe(uuid), private.save_planned_meal(uuid, uuid, date, text, uuid, integer, uuid, boolean),
    private.update_planned_meal_to_latest(uuid)
    to authenticated;
grant execute on function public.preview_household_move(text), public.start_household(text, text),
    public.join_household(text, boolean, uuid), public.leave_household(boolean, uuid),
    public.transfer_household_ownership(uuid, uuid), public.remove_household_member(uuid, uuid),
    public.delete_household_data(uuid), public.save_recipe_copy(uuid), public.set_recipe_sharing(uuid, boolean),
    public.delete_recipe(uuid), public.save_planned_meal(uuid, uuid, date, text, uuid, integer, uuid, boolean),
    public.update_planned_meal_to_latest(uuid)
    to authenticated;

-- Realtime -------------------------------------------------------------------

-- Each person also has a private topic, so their other devices hear about membership
-- changes such as being removed or joining another household.
create policy "People receive their own broadcasts" on realtime.messages
    for select to authenticated using (
        extension = 'broadcast' and (select realtime.topic()) = 'user:' || (select auth.uid())::text
    );

-- Personal recipes notify their owner and the household they're shared with.
create or replace function private.broadcast_household_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare topics text[] := '{}'; topic text; row_data jsonb;
begin
    foreach row_data in array array[
        case when tg_op <> 'DELETE' then to_jsonb(new) end,
        case when tg_op <> 'INSERT' then to_jsonb(old) end
    ] loop
        continue when row_data is null;
        if tg_table_name = 'households' then
            topics := topics || ('household:' || (row_data ->> 'id'));
        elsif tg_table_name = 'recipe_favorites' then
            topics := topics || ('user:' || (row_data ->> 'user_id'));
        elsif tg_table_name = 'recipes' and row_data ->> 'owner_id' is not null then
            topics := topics || ('user:' || (row_data ->> 'owner_id'))
                || ('household:' || private.household_of((row_data ->> 'owner_id')::uuid)::text);
        else
            topics := topics || ('household:' || (row_data ->> 'household_id'));
        end if;
        if tg_table_name = 'household_members' then
            topics := topics || ('user:' || (row_data ->> 'user_id'));
        end if;
    end loop;
    for topic in select distinct t from unnest(topics) as t where t is not null loop
        perform realtime.send(jsonb_build_object('table', tg_table_name), 'CHANGE', topic, true);
    end loop;
    return null;
end;
$$;

create trigger broadcast_favorite_changes after insert or delete on public.recipe_favorites
    for each row execute function private.broadcast_household_change();
