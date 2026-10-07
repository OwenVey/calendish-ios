-- Internal privileged helpers are not Data API endpoints. Public RPC wrappers
-- run as the caller; their implementations still check auth.uid() explicitly.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

alter function public.is_household_member(uuid) set schema private;
alter function public.create_household(text, text) set schema private;
alter function public.join_household(text, text) set schema private;

revoke all on function private.is_household_member(uuid),
    private.create_household(text, text), private.join_household(text, text)
    from public, anon, authenticated, service_role;
grant execute on function private.is_household_member(uuid),
    private.create_household(text, text), private.join_household(text, text) to authenticated;

create function public.create_household(household_name text, member_name text)
returns public.households language sql security invoker set search_path = ''
as $$ select * from private.create_household(household_name, member_name); $$;
create function public.join_household(code text, member_name text)
returns public.households language sql security invoker set search_path = ''
as $$ select * from private.join_household(code, member_name); $$;
revoke all on function public.create_household(text, text), public.join_household(text, text)
    from public, anon, authenticated, service_role;
grant execute on function public.create_household(text, text), public.join_household(text, text)
    to authenticated;

-- Supabase's automatic RLS event trigger is not a client-callable RPC.
-- Some projects do not have this helper; protect it only when present.
do $$
begin
    if to_regprocedure('public.rls_auto_enable()') is not null then
        revoke execute on function public.rls_auto_enable() from public, anon, authenticated, service_role;
    end if;
end;
$$;
alter default privileges for role postgres in schema public revoke execute on functions from public, anon, authenticated;
alter default privileges for role postgres in schema private revoke execute on functions from public, anon, authenticated;

-- A meal may only reference a recipe belonging to the same household.
alter table public.recipes add constraint recipes_household_id_id_key unique (household_id, id);
alter table public.planned_meals drop constraint planned_meals_recipe_id_fkey;
alter table public.planned_meals add constraint planned_meals_household_recipe_fkey
    foreign key (household_id, recipe_id) references public.recipes (household_id, id) on delete cascade;
create index planned_meals_household_recipe_idx on public.planned_meals (household_id, recipe_id);
drop index public.planned_meals_recipe_id_idx;

-- Moving/replacing a meal is one transaction. A failed insert rolls back the
-- removal, and concurrent inserts into the same slot resolve through ON CONFLICT.
create function public.save_planned_meal(
    target_household uuid, meal_id uuid, meal_date date, meal_slot text,
    meal_recipe uuid, meal_servings integer, moving_id uuid default null
)
returns public.planned_meals language plpgsql security invoker set search_path = ''
as $$
declare saved public.planned_meals;
begin
    if not private.is_household_member(target_household) then
        raise exception 'Household access denied' using errcode = '42501';
    end if;
    if moving_id is not null then
        delete from public.planned_meals where household_id = target_household and id = moving_id;
    end if;
    insert into public.planned_meals (id, household_id, date, slot, recipe_id, servings)
    values (meal_id, target_household, meal_date, meal_slot, meal_recipe, meal_servings)
    on conflict (household_id, date, slot) do update
        set recipe_id = excluded.recipe_id, servings = excluded.servings
    returning * into saved;
    return saved;
end;
$$;
revoke all on function public.save_planned_meal(uuid, uuid, date, text, uuid, integer, uuid)
    from public, anon, authenticated, service_role;
grant execute on function public.save_planned_meal(uuid, uuid, date, text, uuid, integer, uuid) to authenticated;

create function public.reorder_groceries(target_household uuid, item_ids uuid[], item_positions double precision[])
returns void language plpgsql security invoker set search_path = ''
as $$
begin
    if not private.is_household_member(target_household) then
        raise exception 'Household access denied' using errcode = '42501';
    end if;
    if cardinality(item_ids) is distinct from cardinality(item_positions)
       or cardinality(item_ids) > 5000
       or (select count(distinct id) from unnest(item_ids) as ids(id)) <> cardinality(item_ids) then
        raise exception 'Invalid grocery order' using errcode = '22023';
    end if;
    update public.grocery_items as g set position = ordering.position
    from unnest(item_ids, item_positions) as ordering(id, position)
    where g.id = ordering.id and g.household_id = target_household;
end;
$$;
revoke all on function public.reorder_groceries(uuid, uuid[], double precision[])
    from public, anon, authenticated, service_role;
grant execute on function public.reorder_groceries(uuid, uuid[], double precision[]) to authenticated;

-- Private Broadcast is Supabase's recommended database-change transport.
-- Clients can receive their household's messages but cannot publish fake changes.
create policy "Members receive household broadcasts" on realtime.messages
    for select to authenticated using (
        extension = 'broadcast' and exists (
            select 1 from public.household_members as m
            where m.user_id = (select auth.uid())
              and (select realtime.topic()) = 'household:' || m.household_id::text
        )
    );

create function private.broadcast_household_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare new_household uuid; old_household uuid;
begin
    if tg_op <> 'DELETE' then
        if tg_table_name = 'households' then new_household := new.id;
        else new_household := new.household_id; end if;
    end if;
    if tg_op <> 'INSERT' then
        if tg_table_name = 'households' then old_household := old.id;
        else old_household := old.household_id; end if;
    end if;
    perform realtime.send(
        jsonb_build_object('table', tg_table_name), 'CHANGE',
        'household:' || coalesce(new_household, old_household)::text, true
    );
    if tg_op = 'UPDATE' and old_household is distinct from new_household then
        perform realtime.send(
            jsonb_build_object('table', tg_table_name), 'CHANGE',
            'household:' || old_household::text, true
        );
    end if;
    return null;
end;
$$;
revoke all on function private.broadcast_household_change() from public, anon, authenticated, service_role;

create trigger broadcast_household_changes after insert or update or delete on public.households
    for each row execute function private.broadcast_household_change();
create trigger broadcast_member_changes after insert or update or delete on public.household_members
    for each row execute function private.broadcast_household_change();
create trigger broadcast_recipe_changes after insert or update or delete on public.recipes
    for each row execute function private.broadcast_household_change();
create trigger broadcast_meal_changes after insert or update or delete on public.planned_meals
    for each row execute function private.broadcast_household_change();
create trigger broadcast_grocery_changes after insert or update or delete on public.grocery_items
    for each row execute function private.broadcast_household_change();

-- Keep the existing publication for older installed app versions during rollout.
