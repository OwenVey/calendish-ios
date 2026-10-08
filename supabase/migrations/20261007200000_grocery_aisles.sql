-- The store aisle an item is shelved in, sorted automatically by whichever member's device sees it first.
-- Null means not yet sorted. Values are app-defined keys, so new aisles need no schema change.
alter table public.grocery_items add column aisle text check (char_length(aisle) <= 40);

-- A renamed item may belong in another aisle. Clearing it here also covers
-- older app versions that rename items without knowing about aisles.
create function private.reset_renamed_grocery_aisle()
returns trigger language plpgsql set search_path = ''
as $$
begin
    if new.name is distinct from old.name and new.aisle is not distinct from old.aisle then
        new.aisle := null;
    end if;
    return new;
end;
$$;
revoke all on function private.reset_renamed_grocery_aisle() from public, anon, authenticated, service_role;

create trigger reset_renamed_grocery_aisle before update of name on public.grocery_items
    for each row execute function private.reset_renamed_grocery_aisle();
