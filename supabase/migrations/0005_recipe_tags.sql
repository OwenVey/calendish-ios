-- Recipes can carry any number of tags instead of exactly one.

alter table public.recipes add column tags text[] not null default '{}';
update public.recipes set tags = array[tag] where tag <> '';
alter table public.recipes drop column tag;
