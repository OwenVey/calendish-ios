-- Each person's rating and note for a recipe, such as four stars and "use half the salt", and the
-- days a household cooked a recipe. Ratings and history feed recipe sorting and meal suggestions.

-- Reviews ---------------------------------------------------------------------

-- One review per person and recipe. The household sees each member's review on recipes they can see;
-- a review leaves with its author when they move to another household.
create table public.recipe_reviews (
    -- A single-column key for the app's keyset pagination.
    id uuid not null default gen_random_uuid() unique,
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    recipe_id uuid not null references public.recipes (id) on delete cascade,
    rating smallint check (rating between 1 and 5),
    note text not null default '' check (length(note) <= 2000),
    updated_at timestamptz not null default now(),
    primary key (user_id, recipe_id),
    check (rating is not null or length(trim(note)) > 0)
);
create index recipe_reviews_recipe_id_idx on public.recipe_reviews (recipe_id);

alter table public.recipe_reviews enable row level security;
-- Saving upserts the whole review; the policies keep each person to their own.
grant select, insert, update, delete on public.recipe_reviews to authenticated;
-- The recipes subqueries run under the recipes policies, so a review is visible only with its recipe.
create policy "People view their own and their household’s reviews" on public.recipe_reviews
    for select to authenticated using (
        user_id = (select auth.uid())
        or (private.household_of(user_id) = private.current_household()
            and exists (select 1 from public.recipes as r where r.id = recipe_id))
    );
create policy "People review recipes available to them" on public.recipe_reviews
    for insert to authenticated with check (
        user_id = (select auth.uid()) and exists (select 1 from public.recipes as r where r.id = recipe_id));
create policy "People edit their reviews" on public.recipe_reviews
    for update to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()) and exists (select 1 from public.recipes as r where r.id = recipe_id));
create policy "People remove their reviews" on public.recipe_reviews
    for delete to authenticated using (user_id = (select auth.uid()));

-- Cooked history ---------------------------------------------------------------

-- A day the household cooked a recipe. Past planned meals count as cooked too; the app combines both.
create table public.recipe_cooks (
    id uuid not null default gen_random_uuid() unique,
    household_id uuid not null references public.households (id) on delete cascade,
    recipe_id uuid not null references public.recipes (id) on delete cascade,
    cooked_on date not null,
    cooked_by uuid default auth.uid() references auth.users (id) on delete set null,
    created_at timestamptz not null default now(),
    primary key (household_id, recipe_id, cooked_on)
);
create index recipe_cooks_recipe_id_idx on public.recipe_cooks (recipe_id);
create index recipe_cooks_cooked_by_idx on public.recipe_cooks (cooked_by);

alter table public.recipe_cooks enable row level security;
grant select, delete on public.recipe_cooks to authenticated;
grant insert (household_id, recipe_id, cooked_on) on public.recipe_cooks to authenticated;
create policy "Members view cooked history" on public.recipe_cooks
    for select to authenticated using (private.is_household_member(household_id));
create policy "Members record cooking recipes available to them" on public.recipe_cooks
    for insert to authenticated with check (
        private.is_household_member(household_id) and exists (select 1 from public.recipes as r where r.id = recipe_id));
create policy "Members remove cooked days" on public.recipe_cooks
    for delete to authenticated using (private.is_household_member(household_id));

-- Recipe operations ----------------------------------------------------------

-- A household copy of a shared recipe also keeps the household's cooked history and its members' reviews.
create or replace function private.retain_household_copy(source public.recipes, target_household uuid)
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
    update public.recipe_cooks set recipe_id = copy_id where household_id = target_household and recipe_id = source.id;
    insert into public.recipe_favorites (user_id, recipe_id)
    select f.user_id, copy_id from public.recipe_favorites as f
    join public.household_members as m on m.user_id = f.user_id and m.household_id = target_household
    where f.recipe_id = source.id and f.user_id <> source.owner_id;
    insert into public.recipe_reviews (user_id, recipe_id, rating, note, updated_at)
    select v.user_id, copy_id, v.rating, v.note, v.updated_at from public.recipe_reviews as v
    join public.household_members as m on m.user_id = v.user_id and m.household_id = target_household
    where v.recipe_id = source.id and v.user_id <> source.owner_id;
    return copy_id;
end;
$$;

-- Deleting household data also clears its cooked history.
create or replace function private.delete_household_data(target_household uuid)
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
    delete from public.meal_plan_notes where household_id = target_household;
    delete from public.recipe_cooks where household_id = target_household;
    with deleted as (
        delete from public.recipes where household_id = target_household returning image_path
    )
    select coalesce(array_agg(image_path), '{}') into photos from deleted;
    return private.unused_photos(photos);
end;
$$;

-- Realtime -------------------------------------------------------------------

-- A review notifies its author's other devices and their household.
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
        elsif tg_table_name = 'recipe_reviews' then
            topics := topics || ('user:' || (row_data ->> 'user_id'))
                || ('household:' || private.household_of((row_data ->> 'user_id')::uuid)::text);
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

create trigger broadcast_review_changes after insert or update or delete on public.recipe_reviews
    for each row execute function private.broadcast_household_change();
create trigger broadcast_cook_changes after insert or update or delete on public.recipe_cooks
    for each row execute function private.broadcast_household_change();
