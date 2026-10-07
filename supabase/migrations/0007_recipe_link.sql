-- Preserve the source URL for imported and manually entered recipes.
alter table public.recipes add column recipe_link text;
