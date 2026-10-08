-- A private recipe has no household, so the comparisons below were NULL rather than false.
-- Policies treat NULL as denied, but `not can_view_recipe(...)` in functions did not.
create or replace function private.can_view_recipe(recipe_owner uuid, recipe_household uuid, shared boolean)
returns boolean language sql stable security definer set search_path = ''
as $$
    select coalesce(
        recipe_owner = (select auth.uid())
            or recipe_household = private.current_household()
            or (shared and private.household_of(recipe_owner) = private.current_household()),
        false);
$$;
