-- Store the dish category apart from tags, and what a recipe makes beyond its servings count.
alter table public.recipes
    add column category text,
    add column yield_text text;
