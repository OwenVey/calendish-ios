-- Keep the legacy total for older clients, while storing each duration separately.
alter table public.recipes
    add column prep_minutes integer not null default 0 check (prep_minutes >= 0),
    add column cook_minutes integer not null default 0 check (cook_minutes >= 0);

-- Existing totals have no known breakdown; preserve them as cook time.
update public.recipes set cook_minutes = minutes;
