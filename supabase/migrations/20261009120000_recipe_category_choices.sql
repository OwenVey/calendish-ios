-- A recipe's category is one of a fixed set of meals. Existing labels that match one, ignoring case
-- and a plural "s", keep it; anything else, such as an imported "Main Course", is cleared.
update public.recipes r
set category = (
    select choice from unnest(array['Breakfast', 'Lunch', 'Dinner', 'Dessert', 'Snack']) as choice
    where lower(trim(r.category)) in (lower(choice), lower(choice) || 's')
)
where category is not null;

alter table public.recipes
    add constraint recipes_category_check
    check (category in ('Breakfast', 'Lunch', 'Dinner', 'Dessert', 'Snack'));
