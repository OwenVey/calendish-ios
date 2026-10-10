-- Categories have their own filter; remove category labels from free-form recipe tags.
-- Preserve the spelling and order of all remaining tags, including recipes left with no tags.
update public.recipes r
set tags = array(
    select tag
    from unnest(r.tags) with ordinality as saved(tag, position)
    where lower(trim(tag)) not in (
        'breakfast', 'breakfasts', 'lunch', 'lunchs', 'lunches',
        'dinner', 'dinners', 'dessert', 'desserts', 'snack', 'snacks'
    )
    order by position
)
where exists (
    select 1 from unnest(r.tags) as tag
    where lower(trim(tag)) in (
        'breakfast', 'breakfasts', 'lunch', 'lunchs', 'lunches',
        'dinner', 'dinners', 'dessert', 'desserts', 'snack', 'snacks'
    )
);
