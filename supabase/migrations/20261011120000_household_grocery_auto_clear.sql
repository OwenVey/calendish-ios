-- Clearing checked groceries removes them for everyone, so the household shares one setting
-- instead of each device choosing its own interval.
alter table public.households
    add column grocery_auto_clear text not null default 'never'
        check (grocery_auto_clear in ('never', 'hour', 'day', 'week'));

-- Any member can change it, like the household name, under the existing update policy.
grant update (grocery_auto_clear) on public.households to authenticated;
