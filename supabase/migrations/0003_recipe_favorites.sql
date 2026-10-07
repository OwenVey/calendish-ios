-- Household-wide favorites: starring a recipe marks it for everyone in the household.
-- The existing table-level update grant and "Members manage recipes" policy cover the new column.

alter table public.recipes add column is_favorite boolean not null default false;
