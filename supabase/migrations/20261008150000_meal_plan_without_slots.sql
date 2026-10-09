-- A day in the meal plan holds any number of recipes, in the order they were planned,
-- instead of one each for breakfast, lunch, and dinner.

drop function public.save_planned_meal(uuid, uuid, date, text, uuid, integer, uuid, boolean);
drop function private.save_planned_meal(uuid, uuid, date, text, uuid, integer, uuid, boolean);

-- Also drops the one-meal-per-slot unique constraint.
alter table public.planned_meals drop column slot;
create index planned_meals_household_date_idx on public.planned_meals (household_id, date, created_at);

-- Plans a recipe, capturing its current version, or updates a meal already in the plan. With
-- keep_version, an existing meal keeps the recipe version and source it already had, and
-- meal_recipe is ignored. Updating in place keeps the meal's position within its day.
create function private.save_planned_meal(
    target_household uuid, meal_id uuid, meal_date date,
    meal_recipe uuid, meal_servings integer, keep_version boolean
)
returns public.planned_meals language plpgsql security definer set search_path = ''
as $$
declare saved public.planned_meals; existing public.planned_meals; version jsonb; source uuid; r public.recipes;
begin
    if target_household is null or target_household is distinct from private.current_household() then
        raise exception 'Household access denied' using errcode = '42501';
    end if;
    select * into existing from public.planned_meals where id = meal_id for update;
    if existing.id is not null and existing.household_id is distinct from target_household then
        raise exception 'Household access denied' using errcode = '42501';
    end if;
    if keep_version and existing.id is not null then
        version := existing.recipe;
        source := existing.recipe_id;
    else
        select * into r from public.recipes where id = meal_recipe;
        if r.id is null or not private.can_view_recipe(r.owner_id, r.household_id, r.is_shared) then
            raise exception 'That recipe isn’t available anymore' using errcode = '23503';
        end if;
        version := private.recipe_version(r);
        source := r.id;
    end if;
    if existing.id is not null then
        update public.planned_meals set date = meal_date, recipe_id = source, servings = meal_servings, recipe = version
        where id = meal_id returning * into saved;
    else
        insert into public.planned_meals (id, household_id, date, recipe_id, servings, recipe)
        values (meal_id, target_household, meal_date, source, meal_servings, version)
        returning * into saved;
    end if;
    return saved;
end;
$$;

create function public.save_planned_meal(
    target_household uuid, meal_id uuid, meal_date date,
    meal_recipe uuid, meal_servings integer, keep_version boolean default false
)
returns public.planned_meals language sql security invoker set search_path = ''
as $$ select * from private.save_planned_meal(target_household, meal_id, meal_date,
    meal_recipe, meal_servings, keep_version); $$;

revoke all on function private.save_planned_meal(uuid, uuid, date, uuid, integer, boolean) from public, anon, authenticated, service_role;
revoke all on function public.save_planned_meal(uuid, uuid, date, uuid, integer, boolean) from public, anon, authenticated, service_role;
grant execute on function private.save_planned_meal(uuid, uuid, date, uuid, integer, boolean) to authenticated;
grant execute on function public.save_planned_meal(uuid, uuid, date, uuid, integer, boolean) to authenticated;
