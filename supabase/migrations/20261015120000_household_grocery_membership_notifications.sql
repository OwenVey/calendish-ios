-- Household alerts beyond new recipes: groceries another member added, batched over a short window,
-- and membership changes (someone joined, or the owner removed you). The recipe queue becomes one
-- household queue; each event has a kind, and each device opts in to each kind separately.

alter table public.push_devices
    add column groceries_enabled boolean not null default false,
    add column membership_enabled boolean not null default false;
-- Membership changes are rare and important, so people who already opted in to recipes get them too.
update public.push_devices set membership_enabled = recipes_enabled;

alter table public.recipe_push_events rename to push_events;
alter table public.recipe_push_deliveries rename to push_deliveries;
alter table public.push_events
    add column kind text not null default 'recipe' check (kind in ('recipe', 'groceries', 'member_joined', 'member_removed')),
    -- A removed member can no longer read the household, so its name is saved when they're removed.
    add column household_name text check (char_length(household_name) <= 200),
    -- Groceries added before this time join the same alert. Other kinds send right away.
    add column closes_at timestamptz,
    alter column recipe_id drop not null,
    add constraint push_events_kind_subject check ((kind = 'recipe') = (recipe_id is not null));
alter table public.push_events alter column kind drop default;
create index push_events_open_groceries_idx on public.push_events (household_id, actor_id, closes_at) where kind = 'groceries';

-- Items stay linked to their alert so it counts only what's still on the list when it sends.
create table public.push_event_groceries (
    event_id uuid not null references public.push_events (id) on delete cascade,
    item_id uuid not null references public.grocery_items (id) on delete cascade,
    primary key (event_id, item_id)
);
create index push_event_groceries_item_id_idx on public.push_event_groceries (item_id);
alter table public.push_event_groceries enable row level security;
revoke all on public.push_event_groceries from anon, authenticated;
grant all on public.push_event_groceries to service_role;
grant select on public.grocery_items, public.households to service_role;

drop function public.register_push_device(uuid, text, text, boolean);
drop function private.register_push_device(uuid, text, text, boolean);
-- Builds without grocery and membership settings omit them: groceries stay off and membership follows recipes.
create function private.register_push_device(installation uuid, device_token text, push_environment text, recipes_enabled boolean,
    groceries_enabled boolean default false, membership_enabled boolean default null)
returns void language plpgsql security definer set search_path = '' as $$
declare person uuid := (select auth.uid()); session uuid := ((select auth.jwt()) ->> 'session_id')::uuid;
    members boolean := coalesce(membership_enabled, recipes_enabled);
begin
    if person is null then raise exception 'Sign in to register notifications' using errcode = '42501'; end if;
    if session is null or not exists (select 1 from auth.sessions where id = session and user_id = person) then
        raise exception 'Sign in again to register notifications' using errcode = '42501';
    end if;
    if installation is null or device_token is null or (device_token !~ '^[0-9a-f]+$' or length(device_token) not between 64 and 512)
       or push_environment is null or push_environment not in ('sandbox', 'production') or recipes_enabled is null
       or groceries_enabled is null or members is null then
        raise exception 'Invalid push registration' using errcode = '22023';
    end if;
    -- Remove old-account deliveries before reusing an installation or a rotated APNs token.
    delete from public.push_devices as d
    where (d.installation_id = installation or d.token = device_token) and d.environment = push_environment
      and (d.user_id <> person or d.session_id <> session or d.token <> device_token or d.installation_id <> installation);
    insert into public.push_devices (installation_id, user_id, session_id, token, environment, recipes_enabled, groceries_enabled, membership_enabled)
    values (installation, person, session, device_token, push_environment, recipes_enabled, groceries_enabled, members)
    on conflict (installation_id, environment) do update
        set recipes_enabled = excluded.recipes_enabled, groceries_enabled = excluded.groceries_enabled,
            membership_enabled = excluded.membership_enabled, updated_at = now();
    -- Turning a kind off cancels its alerts that haven't sent yet.
    update public.push_deliveries as delivery set status = 'cancelled', lease_id = null
    from public.push_devices as d, public.push_events as event
    where delivery.device_id = d.id and d.installation_id = installation and d.user_id = person
      and event.id = delivery.event_id and delivery.status in ('pending', 'sending')
      and case event.kind when 'recipe' then not register_push_device.recipes_enabled
          when 'groceries' then not register_push_device.groceries_enabled else not members end;
end;
$$;
revoke all on function private.register_push_device(uuid, text, text, boolean, boolean, boolean) from public, anon, authenticated;
grant execute on function private.register_push_device(uuid, text, text, boolean, boolean, boolean) to authenticated;
create function public.register_push_device(installation uuid, device_token text, push_environment text, recipes_enabled boolean,
    groceries_enabled boolean default false, membership_enabled boolean default null)
returns void language sql security invoker set search_path = '' as $$
    select private.register_push_device(installation, device_token, push_environment, recipes_enabled, groceries_enabled, membership_enabled);
$$;
revoke all on function public.register_push_device(uuid, text, text, boolean, boolean, boolean) from public, anon, authenticated;
grant execute on function public.register_push_device(uuid, text, text, boolean, boolean, boolean) to authenticated;

select cron.unschedule('household-recipe-push');
select cron.unschedule('household-recipe-push-cleanup');
drop trigger enqueue_recipe_push on public.recipes;
drop function private.enqueue_recipe_push();
drop function private.wake_recipe_push_worker();
drop function public.claim_recipe_pushes(integer, text[]);
drop function public.prepare_recipe_push(uuid, uuid);
drop function public.finish_recipe_push(uuid, uuid, text, text);

-- Vault configuration is optional: households still change while push delivery has not been configured.
create function private.wake_household_push_worker()
returns void language plpgsql security definer set search_path = '' as $$
declare endpoint text; secret text;
begin
    if not exists (select 1 from public.push_deliveries
        where status in ('pending', 'sending') and available_at <= now() and created_at > now() - interval '1 hour' and attempts < 6) then return; end if;
    select decrypted_secret into endpoint from vault.decrypted_secrets where name = 'recipe_push_url';
    select decrypted_secret into secret from vault.decrypted_secrets where name = 'recipe_push_worker_secret';
    if endpoint is null or secret is null then return; end if;
    perform net.http_post(url := endpoint, headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-worker-secret', secret),
        body := '{}'::jsonb, timeout_milliseconds := 5000);
exception when others then
    -- Network setup must never prevent a household change from saving. Cron retries the durable queue.
    raise log 'Household push wake failed: %', sqlstate;
end;
$$;
revoke all on function private.wake_household_push_worker() from public, anon, authenticated;

-- One event for the household, and one delivery per opted-in device of each recipient.
create function private.enqueue_household_push(push_kind text, home uuid, actor uuid, recipients uuid[], recipe uuid default null,
    home_name text default null, send_at timestamptz default now())
returns uuid language plpgsql security definer set search_path = '' as $$
declare event uuid;
begin
    insert into public.push_events (kind, recipe_id, household_id, actor_id, household_name, closes_at)
    values (push_kind, recipe, home, actor, home_name, case when push_kind = 'groceries' then send_at end)
    on conflict (recipe_id) do nothing returning id into event;
    if event is null then return null; end if;
    insert into public.push_deliveries (event_id, device_id, recipient_id, available_at)
    select event, d.id, d.user_id, send_at from public.push_devices as d
    where d.user_id = any(recipients) and d.user_id <> actor
      and case push_kind when 'recipe' then d.recipes_enabled when 'groceries' then d.groceries_enabled else d.membership_enabled end;
    if send_at <= now() then perform private.wake_household_push_worker(); end if;
    return event;
end;
$$;
revoke all on function private.enqueue_household_push(text, uuid, uuid, uuid[], uuid, text, timestamptz) from public, anon, authenticated;

create function private.enqueue_recipe_push()
returns trigger language plpgsql security definer set search_path = '' as $$
declare home uuid;
begin
    -- Only a person's newly added shared recipe, never household-preservation copies or edits.
    if new.owner_id is null or not new.is_shared then return null; end if;
    select household_id into home from public.household_members where user_id = new.owner_id;
    if home is null then return null; end if;
    perform private.enqueue_household_push('recipe', home, new.owner_id,
        array(select user_id from public.household_members where household_id = home), new.id);
    return null;
end;
$$;
revoke all on function private.enqueue_recipe_push() from public, anon, authenticated;
create trigger enqueue_recipe_push after insert on public.recipes for each row execute function private.enqueue_recipe_push();

-- Groceries one person adds within two minutes of their last addition share one alert, sent at most
-- ten minutes after the first. Only people's additions count, never server-side copies.
create function private.enqueue_grocery_push()
returns trigger language plpgsql security definer set search_path = '' as $$
declare actor uuid := (select auth.uid()); home uuid; event uuid; opened timestamptz; due timestamptz;
begin
    if actor is null then return null; end if;
    for home in select distinct a.household_id from added as a
        join public.household_members as m on m.household_id = a.household_id and m.user_id = actor loop
        perform pg_advisory_xact_lock(hashtextextended('calendish-grocery-push:' || home::text || ':' || actor::text, 0));
        select id, created_at into event, opened from public.push_events
        where kind = 'groceries' and household_id = home and actor_id = actor and closes_at > now()
        order by closes_at desc limit 1;
        if event is null then
            event := private.enqueue_household_push('groceries', home, actor,
                array(select user_id from public.household_members where household_id = home), send_at => now() + interval '2 minutes');
        else
            due := least(opened + interval '10 minutes', now() + interval '2 minutes');
            update public.push_events set closes_at = due where id = event;
            update public.push_deliveries set available_at = due where event_id = event and status = 'pending';
        end if;
        insert into public.push_event_groceries (event_id, item_id)
        select event, a.id from added as a where a.household_id = home on conflict do nothing;
    end loop;
    return null;
end;
$$;
revoke all on function private.enqueue_grocery_push() from public, anon, authenticated;
create trigger enqueue_grocery_push after insert on public.grocery_items
    referencing new table as added for each statement execute function private.enqueue_grocery_push();

-- Starting a household adds only its first member, so only joining an existing household alerts anyone.
create function private.enqueue_member_joined_push()
returns trigger language plpgsql security definer set search_path = '' as $$
declare others uuid[] := array(select user_id from public.household_members where household_id = new.household_id and user_id <> new.user_id);
begin
    if cardinality(others) = 0 then return null; end if;
    perform private.enqueue_household_push('member_joined', new.household_id, new.user_id, others);
    return null;
end;
$$;
revoke all on function private.enqueue_member_joined_push() from public, anon, authenticated;
create trigger enqueue_member_joined_push after insert on public.household_members
    for each row execute function private.enqueue_member_joined_push();

-- Leaving, moving, and deleting an account are the member's own action; only the owner removing someone alerts them.
create function private.enqueue_member_removed_push()
returns trigger language plpgsql security definer set search_path = '' as $$
declare actor uuid := (select auth.uid()); removed_from text;
begin
    if actor is null or actor = old.user_id then return null; end if;
    if not exists (select 1 from public.household_members where household_id = old.household_id and user_id = actor and role = 'owner') then
        return null;
    end if;
    select name into removed_from from public.households where id = old.household_id;
    if removed_from is null then return null; end if;
    perform private.enqueue_household_push('member_removed', old.household_id, actor, array[old.user_id], home_name => removed_from);
    return null;
end;
$$;
revoke all on function private.enqueue_member_removed_push() from public, anon, authenticated;
create trigger enqueue_member_removed_push after delete on public.household_members
    for each row execute function private.enqueue_member_removed_push();

-- SKIP LOCKED and per-attempt leases keep concurrent workers from sending the same delivery.
create function public.claim_household_pushes(batch_size integer default 25, push_environments text[] default array['sandbox', 'production'])
returns table (id uuid, lease_id uuid) language sql security invoker set search_path = '' as $$
    with candidates as (
        select d.id from public.push_deliveries as d
        join public.push_devices as device on device.id = d.device_id and device.environment = any(push_environments)
        where d.status in ('pending', 'sending') and d.available_at <= now()
          and d.created_at > now() - interval '1 hour' and d.attempts < 6
        order by d.available_at, d.id limit least(greatest(batch_size, 1), 50)
        for update of d skip locked
    )
    update public.push_deliveries as d
    set status = 'sending', attempts = d.attempts + 1, lease_id = gen_random_uuid(), available_at = now() + interval '2 minutes'
    from candidates as c where d.id = c.id returning d.id, d.lease_id;
$$;
revoke all on function public.claim_household_pushes(integer, text[]) from public, anon, authenticated;
grant execute on function public.claim_household_pushes(integer, text[]) to service_role;

-- Recheck memberships, the opt-in, account ownership, and what the alert describes immediately before sending.
-- Removed members must still be outside the household; everyone else must still be in it.
create function public.prepare_household_push(delivery_id uuid, delivery_lease uuid)
returns table (token text, environment text, recipient_id uuid, household_id uuid, kind text, actor_name text,
    recipe_id uuid, recipe_title text, household_name text, item_count integer, item_names text[], expires_at timestamptz)
language sql security invoker set search_path = '' as $$
    select device.token, device.environment, delivery.recipient_id, event.household_id, event.kind, actor.display_name,
        recipe.id, recipe.title, coalesce(event.household_name, home.name), groceries.count, groceries.names,
        delivery.created_at + interval '1 hour'
    from public.push_deliveries as delivery
    join public.push_events as event on event.id = delivery.event_id
    join public.push_devices as device on device.id = delivery.device_id and device.user_id = delivery.recipient_id
        and case event.kind when 'recipe' then device.recipes_enabled when 'groceries' then device.groceries_enabled
            else device.membership_enabled end
    left join public.households as home on home.id = event.household_id
    left join public.recipes as recipe on recipe.id = event.recipe_id and recipe.owner_id = event.actor_id and recipe.is_shared
    left join public.household_members as actor on actor.user_id = event.actor_id and actor.household_id = event.household_id
    left join public.household_members as recipient on recipient.user_id = delivery.recipient_id and recipient.household_id = event.household_id
    left join lateral (
        select count(*)::integer as count, (array_agg(item.name order by item.created_at, item.id))[1:3] as names
        from public.push_event_groceries as link
        join public.grocery_items as item on item.id = link.item_id and item.household_id = event.household_id
        where link.event_id = event.id
    ) as groceries on event.kind = 'groceries'
    where delivery.id = delivery_id and delivery.lease_id = delivery_lease and delivery.status = 'sending'
      and delivery.available_at > now() and delivery.created_at > now() - interval '1 hour'
      and delivery.recipient_id <> event.actor_id
      and case event.kind
          when 'recipe' then recipe.id is not null and actor.user_id is not null and recipient.user_id is not null
          when 'groceries' then groceries.count > 0 and actor.user_id is not null and recipient.user_id is not null
          when 'member_joined' then actor.user_id is not null and recipient.user_id is not null
          when 'member_removed' then recipient.user_id is null
      end;
$$;
revoke all on function public.prepare_household_push(uuid, uuid) from public, anon, authenticated;
grant execute on function public.prepare_household_push(uuid, uuid) to service_role;

create function public.finish_household_push(delivery_id uuid, delivery_lease uuid, result text, error_reason text default null)
returns void language plpgsql security invoker set search_path = '' as $$
begin
    if result not in ('delivered', 'retry', 'failed', 'cancelled', 'invalid_token') then
        raise exception 'Invalid push result' using errcode = '22023';
    end if;
    if result = 'invalid_token' then
        -- Only remove the device associated with this lease, never a newer registration.
        delete from public.push_devices as device using public.push_deliveries as delivery
        where delivery.id = delivery_id and delivery.lease_id = delivery_lease and delivery.status = 'sending' and device.id = delivery.device_id
          and device.updated_at <= delivery.available_at - interval '2 minutes';
        update public.push_deliveries set status = 'failed', lease_id = null, last_error = left(error_reason, 120)
          where id = delivery_id and lease_id = delivery_lease and status = 'sending';
        return;
    end if;
    update public.push_deliveries set
        status = case when result = 'retry' and attempts < 6 then 'pending' when result = 'retry' then 'failed' else result end,
        available_at = now() + make_interval(secs => least(900, 15 * (2 ^ attempts)::integer)),
        lease_id = null, last_error = left(error_reason, 120)
    where id = delivery_id and lease_id = delivery_lease and status = 'sending';
end;
$$;
revoke all on function public.finish_household_push(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.finish_household_push(uuid, uuid, text, text) to service_role;

-- Expire old alerts rather than delivering yesterday's news when credentials become available.
select cron.schedule('household-push', '* * * * *', 'select private.wake_household_push_worker()');
select cron.schedule('household-push-cleanup', '17 3 * * *',
    $job$delete from public.push_events where created_at < now() - interval '7 days';
    update public.push_deliveries set status = 'cancelled', lease_id = null
      where status in ('pending', 'sending') and (created_at < now() - interval '1 hour' or attempts >= 6);$job$);
