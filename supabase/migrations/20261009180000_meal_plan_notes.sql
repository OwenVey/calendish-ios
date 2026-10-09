-- A note on a meal plan day, such as "Leftovers" or "Dinner at Mom's", for plans that aren't a
-- recipe. Its optional grocery items join the day's ingredients when adding the day to groceries.
create table public.meal_plan_notes (
    id uuid primary key default gen_random_uuid(),
    household_id uuid not null references public.households (id) on delete cascade,
    date date not null,
    text text not null check (length(trim(text)) between 1 and 200),
    items text[] not null default '{}' check (cardinality(items) <= 50),
    created_at timestamptz not null default now()
);
create index meal_plan_notes_household_date_idx on public.meal_plan_notes (household_id, date, created_at);

alter table public.meal_plan_notes enable row level security;
grant select, insert, update, delete on public.meal_plan_notes to authenticated;
create policy "Members manage meal plan notes" on public.meal_plan_notes
    for all to authenticated
    using (private.is_household_member(household_id))
    with check (private.is_household_member(household_id));

create trigger broadcast_meal_note_changes after insert or update or delete on public.meal_plan_notes
    for each row execute function private.broadcast_household_change();

-- Deleting household data also clears the meal plan's notes.
create or replace function private.delete_household_data(target_household uuid)
returns text[] language plpgsql security definer set search_path = ''
as $$
declare photos text[];
begin
    if not exists (
        select 1 from public.household_members
        where household_id = target_household and user_id = (select auth.uid()) and role = 'owner'
    ) then
        raise exception 'Only the household owner can delete its data' using errcode = '42501';
    end if;
    delete from public.grocery_items where household_id = target_household;
    delete from public.planned_meals where household_id = target_household;
    delete from public.meal_plan_notes where household_id = target_household;
    with deleted as (
        delete from public.recipes where household_id = target_household returning image_path
    )
    select coalesce(array_agg(image_path), '{}') into photos from deleted;
    return private.unused_photos(photos);
end;
$$;
