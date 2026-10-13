-- Auto planning adds proposed dinners only to days that are still empty, with the recipe version the
-- person reviewed, and recognizes a retried meal instead of adding it twice. Manual planning is unchanged.

-- Recipes count content edits, so a save can confirm it captures the version someone reviewed.
alter table public.recipes add column revision bigint not null default 1;

create function private.advance_recipe_revision()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
    -- Ownership and sharing changes keep the revision. Column privileges keep clients from setting it.
    new.revision := old.revision
        + case when private.recipe_version(new) is distinct from private.recipe_version(old) then 1 else 0 end;
    return new;
end;
$$;

create trigger advance_recipe_revision before update on public.recipes
    for each row execute function private.advance_recipe_revision();

-- Every write to a day's meals or notes takes the same lock, so a guarded add sees entries
-- committed by anyone who reached the day first.
create function private.lock_meal_plan_day(target_household uuid, day date)
returns void language sql set search_path = ''
as $$ select pg_advisory_xact_lock(hashtextextended('calendish-meal-day:' || target_household::text || ':' || day::text, 0)); $$;

create function private.lock_meal_plan_day_entry()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
    perform private.lock_meal_plan_day(new.household_id, new.date);
    return new;
end;
$$;

create trigger lock_meal_plan_day before insert or update on public.planned_meals
    for each row execute function private.lock_meal_plan_day_entry();
create trigger lock_meal_plan_day before insert or update on public.meal_plan_notes
    for each row execute function private.lock_meal_plan_day_entry();

-- Adds one dinner from a meal plan proposal and reports what happened:
--   added          the meal was saved with the reviewed recipe version
--   already_added  a meal with this ID was saved earlier, such as before a lost response
--   occupied       the day has a recipe or a note, so nothing was added
--   changed        the recipe's revision isn't the reviewed one, so nothing was added
--   unavailable    the recipe was deleted or isn't available to the person anymore
create function private.add_planned_meal(
    target_household uuid, meal_id uuid, meal_date date,
    meal_recipe uuid, expected_revision bigint, meal_servings integer
)
returns text language plpgsql security definer set search_path = ''
as $$
declare existing public.planned_meals; r public.recipes;
begin
    -- Waits for any household move in progress, then confirms the person is still a member.
    perform private.lock_people(array[(select auth.uid())]);
    if target_household is null or target_household is distinct from private.current_household() then
        raise exception 'Household access denied' using errcode = '42501';
    end if;
    perform private.lock_meal_plan_day(target_household, meal_date);
    select * into existing from public.planned_meals where id = meal_id;
    if existing.id is not null then
        if existing.household_id is distinct from target_household then
            raise exception 'Household access denied' using errcode = '42501';
        end if;
        return 'already_added';
    end if;
    if exists (select 1 from public.planned_meals where household_id = target_household and date = meal_date)
        or exists (select 1 from public.meal_plan_notes where household_id = target_household and date = meal_date) then
        return 'occupied';
    end if;
    -- Holds the recipe until commit, so an edit can't land between the revision check and the capture.
    select * into r from public.recipes where id = meal_recipe for share;
    if r.id is null or not private.can_view_recipe(r.owner_id, r.household_id, r.is_shared) then
        return 'unavailable';
    end if;
    if r.revision is distinct from expected_revision then
        return 'changed';
    end if;
    insert into public.planned_meals (id, household_id, date, recipe_id, servings, recipe)
    values (meal_id, target_household, meal_date, r.id, meal_servings, private.recipe_version(r));
    return 'added';
end;
$$;

create function public.add_planned_meal(
    target_household uuid, meal_id uuid, meal_date date,
    meal_recipe uuid, expected_revision bigint, meal_servings integer
)
returns text language sql security invoker set search_path = ''
as $$ select private.add_planned_meal(target_household, meal_id, meal_date, meal_recipe, expected_revision, meal_servings); $$;

revoke all on function private.advance_recipe_revision(), private.lock_meal_plan_day(uuid, date),
    private.lock_meal_plan_day_entry() from public, anon, authenticated, service_role;
revoke all on function private.add_planned_meal(uuid, uuid, date, uuid, bigint, integer) from public, anon, authenticated, service_role;
revoke all on function public.add_planned_meal(uuid, uuid, date, uuid, bigint, integer) from public, anon, authenticated, service_role;
grant execute on function private.add_planned_meal(uuid, uuid, date, uuid, bigint, integer) to authenticated;
grant execute on function public.add_planned_meal(uuid, uuid, date, uuid, bigint, integer) to authenticated;
