-- Calendish initial schema: households, their members, and the shared recipe book,
-- meal plan, and grocery list. Every row belongs to a household, and Row Level
-- Security limits access to that household's members.

-- Tables ---------------------------------------------------------------------

create table public.households (
    id uuid primary key default gen_random_uuid(),
    name text not null check (char_length(name) between 1 and 80),
    invite_code text not null unique
        default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8)),
    created_at timestamptz not null default now()
);

create table public.household_members (
    household_id uuid not null references public.households (id) on delete cascade,
    user_id uuid not null references auth.users (id) on delete cascade,
    display_name text not null default '',
    role text not null default 'member' check (role in ('owner', 'member')),
    joined_at timestamptz not null default now(),
    primary key (household_id, user_id)
);
create index household_members_user_id_idx on public.household_members (user_id);

create table public.recipes (
    id uuid primary key default gen_random_uuid(),
    household_id uuid not null references public.households (id) on delete cascade,
    title text not null,
    summary text not null default '',
    minutes integer not null default 0 check (minutes >= 0),
    servings integer not null default 1 check (servings >= 0),
    tag text not null default 'Homemade',
    symbol text not null default 'fork.knife',
    -- [{ "id": uuid, "text": "2 cups flour" }]
    ingredients jsonb not null default '[]'::jsonb,
    -- ["Preheat the oven.", ...]
    steps jsonb not null default '[]'::jsonb,
    created_at timestamptz not null default now()
);
create index recipes_household_id_idx on public.recipes (household_id);

create table public.planned_meals (
    id uuid primary key default gen_random_uuid(),
    household_id uuid not null references public.households (id) on delete cascade,
    date date not null,
    slot text not null check (slot in ('breakfast', 'lunch', 'dinner')),
    recipe_id uuid not null references public.recipes (id) on delete cascade,
    servings integer not null check (servings > 0),
    created_at timestamptz not null default now(),
    unique (household_id, date, slot)
);
create index planned_meals_recipe_id_idx on public.planned_meals (recipe_id);

create table public.grocery_items (
    id uuid primary key default gen_random_uuid(),
    household_id uuid not null references public.households (id) on delete cascade,
    name text not null,
    amount text not null default '',
    source text not null default 'General',
    is_complete boolean not null default false,
    position double precision not null default 0,
    created_at timestamptz not null default now()
);
create index grocery_items_household_id_idx on public.grocery_items (household_id);

-- Membership helpers ---------------------------------------------------------

-- Security definer so policies on household_members can call it without recursing.
create function public.is_household_member(hid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1 from public.household_members m
        where m.household_id = hid and m.user_id = (select auth.uid())
    );
$$;

create function public.create_household(household_name text, member_name text)
returns public.households
language plpgsql
security definer
set search_path = ''
as $$
declare
    h public.households;
begin
    if auth.uid() is null then
        raise exception 'Sign in to create a household';
    end if;
    insert into public.households (name) values (trim(household_name)) returning * into h;
    insert into public.household_members (household_id, user_id, display_name, role)
    values (h.id, auth.uid(), trim(member_name), 'owner');
    return h;
end;
$$;

create function public.join_household(code text, member_name text)
returns public.households
language plpgsql
security definer
set search_path = ''
as $$
declare
    h public.households;
begin
    if auth.uid() is null then
        raise exception 'Sign in to join a household';
    end if;
    select * into h from public.households where invite_code = upper(trim(code));
    if h.id is null then
        raise exception 'No household matches that invite code';
    end if;
    insert into public.household_members (household_id, user_id, display_name)
    values (h.id, auth.uid(), trim(member_name))
    on conflict (household_id, user_id) do nothing;
    return h;
end;
$$;

-- Privileges -----------------------------------------------------------------
-- New tables aren't exposed automatically, so grant exactly what the app uses.

revoke all on function public.is_household_member(uuid) from public, anon;
revoke all on function public.create_household(text, text) from public, anon;
revoke all on function public.join_household(text, text) from public, anon;
grant execute on function public.is_household_member(uuid) to authenticated;
grant execute on function public.create_household(text, text) to authenticated;
grant execute on function public.join_household(text, text) to authenticated;

grant select on public.households to authenticated;
grant update (name) on public.households to authenticated;
grant select, delete on public.household_members to authenticated;
grant update (display_name) on public.household_members to authenticated;
grant select, insert, update, delete on public.recipes to authenticated;
grant select, insert, update, delete on public.planned_meals to authenticated;
grant select, insert, update, delete on public.grocery_items to authenticated;

-- Row Level Security ---------------------------------------------------------

alter table public.households enable row level security;
alter table public.household_members enable row level security;
alter table public.recipes enable row level security;
alter table public.planned_meals enable row level security;
alter table public.grocery_items enable row level security;

create policy "Members can view their household" on public.households
    for select to authenticated using (public.is_household_member(id));
create policy "Members can rename their household" on public.households
    for update to authenticated
    using (public.is_household_member(id)) with check (public.is_household_member(id));

create policy "Members can view fellow members" on public.household_members
    for select to authenticated using (public.is_household_member(household_id));
create policy "Members can update their own profile" on public.household_members
    for update to authenticated
    using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "Members can leave a household" on public.household_members
    for delete to authenticated using (user_id = (select auth.uid()));

create policy "Members manage recipes" on public.recipes
    for all to authenticated
    using (public.is_household_member(household_id))
    with check (public.is_household_member(household_id));
create policy "Members manage planned meals" on public.planned_meals
    for all to authenticated
    using (public.is_household_member(household_id))
    with check (public.is_household_member(household_id));
create policy "Members manage grocery items" on public.grocery_items
    for all to authenticated
    using (public.is_household_member(household_id))
    with check (public.is_household_member(household_id));

-- Realtime -------------------------------------------------------------------
-- Lets each phone hear about the other's changes. Realtime applies the policies above.

alter publication supabase_realtime add table
    public.households, public.recipes, public.planned_meals, public.grocery_items;
