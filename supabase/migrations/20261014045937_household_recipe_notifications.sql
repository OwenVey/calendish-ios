grant select on public.recipes, public.household_members to service_role;

-- Device associations are opaque to app clients. The worker uses only service-role RPCs.
create table public.push_devices (
    id uuid primary key default gen_random_uuid(),
    installation_id uuid not null,
    user_id uuid not null references auth.users (id) on delete cascade,
    session_id uuid not null references auth.sessions (id) on delete cascade,
    token text not null check (token ~ '^[0-9a-f]+$' and length(token) between 64 and 512),
    environment text not null check (environment in ('sandbox', 'production')),
    recipes_enabled boolean not null default false,
    updated_at timestamptz not null default now(),
    unique (installation_id, environment),
    unique (token, environment)
);
create index push_devices_session_id_idx on public.push_devices (session_id);
create index push_devices_user_id_idx on public.push_devices (user_id);
alter table public.push_devices enable row level security;
revoke all on public.push_devices from anon, authenticated;
grant all on public.push_devices to service_role;

create table public.recipe_push_events (
    id uuid primary key default gen_random_uuid(),
    recipe_id uuid not null unique references public.recipes (id) on delete cascade,
    household_id uuid not null references public.households (id) on delete cascade,
    actor_id uuid not null references auth.users (id) on delete cascade,
    created_at timestamptz not null default now()
);
create index recipe_push_events_household_id_idx on public.recipe_push_events (household_id);
create index recipe_push_events_actor_id_idx on public.recipe_push_events (actor_id);
create index recipe_push_events_created_at_idx on public.recipe_push_events (created_at);
alter table public.recipe_push_events enable row level security;
revoke all on public.recipe_push_events from anon, authenticated;
grant all on public.recipe_push_events to service_role;

create table public.recipe_push_deliveries (
    id uuid primary key default gen_random_uuid(),
    event_id uuid not null references public.recipe_push_events (id) on delete cascade,
    device_id uuid not null references public.push_devices (id) on delete cascade,
    recipient_id uuid not null references auth.users (id) on delete cascade,
    status text not null default 'pending' check (status in ('pending', 'sending', 'delivered', 'cancelled', 'failed')),
    attempts integer not null default 0,
    available_at timestamptz not null default now(),
    lease_id uuid,
    last_error text,
    created_at timestamptz not null default now(),
    unique (event_id, device_id)
);
create index recipe_push_deliveries_device_id_idx on public.recipe_push_deliveries (device_id);
create index recipe_push_deliveries_recipient_id_idx on public.recipe_push_deliveries (recipient_id);
create index recipe_push_deliveries_pending_idx on public.recipe_push_deliveries (available_at)
    where status in ('pending', 'sending');
alter table public.recipe_push_deliveries enable row level security;
revoke all on public.recipe_push_deliveries from anon, authenticated;
grant all on public.recipe_push_deliveries to service_role;

create function private.register_push_device(installation uuid, device_token text, push_environment text, recipes_enabled boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare person uuid := (select auth.uid()); session uuid := ((select auth.jwt()) ->> 'session_id')::uuid;
begin
    if person is null then raise exception 'Sign in to register notifications' using errcode = '42501'; end if;
    if session is null or not exists (select 1 from auth.sessions where id = session and user_id = person) then
        raise exception 'Sign in again to register notifications' using errcode = '42501';
    end if;
    if installation is null or device_token is null or (device_token !~ '^[0-9a-f]+$' or length(device_token) not between 64 and 512)
       or push_environment is null or push_environment not in ('sandbox', 'production') or recipes_enabled is null then
        raise exception 'Invalid push registration' using errcode = '22023';
    end if;
    -- Remove old-account deliveries before reusing an installation or a rotated APNs token.
    delete from public.push_devices as d
    where (d.installation_id = installation or d.token = device_token) and d.environment = push_environment
      and (d.user_id <> person or d.session_id <> session or d.token <> device_token or d.installation_id <> installation);
    insert into public.push_devices (installation_id, user_id, session_id, token, environment, recipes_enabled)
    values (installation, person, session, device_token, push_environment, recipes_enabled)
    on conflict (installation_id, environment) do update
        set recipes_enabled = excluded.recipes_enabled, updated_at = now();
    if not recipes_enabled then
        update public.recipe_push_deliveries as delivery set status = 'cancelled', lease_id = null
        from public.push_devices as d
        where delivery.device_id = d.id and d.installation_id = installation and d.user_id = person
          and delivery.status in ('pending', 'sending');
    end if;
end;
$$;
revoke all on function private.register_push_device(uuid, text, text, boolean) from public, anon, authenticated;
grant execute on function private.register_push_device(uuid, text, text, boolean) to authenticated;
create function public.register_push_device(installation uuid, device_token text, push_environment text, recipes_enabled boolean)
returns void language sql security invoker set search_path = '' as $$
    select private.register_push_device(installation, device_token, push_environment, recipes_enabled);
$$;
revoke all on function public.register_push_device(uuid, text, text, boolean) from public, anon, authenticated;
grant execute on function public.register_push_device(uuid, text, text, boolean) to authenticated;

create function private.unregister_push_device(installation uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
    if (select auth.uid()) is null then raise exception 'Sign in to unregister notifications' using errcode = '42501'; end if;
    delete from public.push_devices where installation_id = installation and user_id = (select auth.uid());
end;
$$;
revoke all on function private.unregister_push_device(uuid) from public, anon, authenticated;
grant execute on function private.unregister_push_device(uuid) to authenticated;
create function public.unregister_push_device(installation uuid)
returns void language sql security invoker set search_path = '' as $$ select private.unregister_push_device(installation); $$;
revoke all on function public.unregister_push_device(uuid) from public, anon, authenticated;
grant execute on function public.unregister_push_device(uuid) to authenticated;

-- Vault configuration is optional: recipes still save while push delivery has not been configured.
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;
create function private.wake_recipe_push_worker()
returns void language plpgsql security definer set search_path = '' as $$
declare endpoint text; secret text;
begin
    if not exists (select 1 from public.recipe_push_deliveries
        where status in ('pending', 'sending') and available_at <= now() and created_at > now() - interval '1 hour' and attempts < 6) then return; end if;
    select decrypted_secret into endpoint from vault.decrypted_secrets where name = 'recipe_push_url';
    select decrypted_secret into secret from vault.decrypted_secrets where name = 'recipe_push_worker_secret';
    if endpoint is null or secret is null then return; end if;
    perform net.http_post(url := endpoint, headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-worker-secret', secret),
        body := '{}'::jsonb, timeout_milliseconds := 5000);
exception when others then
    -- Network setup must never prevent a recipe from saving. Cron retries the durable queue.
    raise log 'Recipe push wake failed: %', sqlstate;
end;
$$;
revoke all on function private.wake_recipe_push_worker() from public, anon, authenticated;

create function private.enqueue_recipe_push()
returns trigger language plpgsql security definer set search_path = '' as $$
declare home uuid; event uuid;
begin
    -- Only a person's newly added shared recipe, never household-preservation copies or edits.
    if new.owner_id is null or not new.is_shared then return null; end if;
    select household_id into home from public.household_members where user_id = new.owner_id;
    if home is null then return null; end if;
    insert into public.recipe_push_events (recipe_id, household_id, actor_id) values (new.id, home, new.owner_id)
    on conflict (recipe_id) do nothing returning id into event;
    if event is null then return null; end if;
    insert into public.recipe_push_deliveries (event_id, device_id, recipient_id)
    select event, d.id, m.user_id from public.household_members as m
    join public.push_devices as d on d.user_id = m.user_id and d.recipes_enabled
    where m.household_id = home and m.user_id <> new.owner_id;
    perform private.wake_recipe_push_worker();
    return null;
end;
$$;
revoke all on function private.enqueue_recipe_push() from public, anon, authenticated;
create trigger enqueue_recipe_push after insert on public.recipes for each row execute function private.enqueue_recipe_push();

-- SKIP LOCKED and per-attempt leases keep concurrent workers from sending the same delivery.
create function public.claim_recipe_pushes(batch_size integer default 25, push_environments text[] default array['sandbox', 'production'])
returns table (id uuid, lease_id uuid) language sql security invoker set search_path = '' as $$
    with candidates as (
        select d.id from public.recipe_push_deliveries as d
        join public.push_devices as device on device.id = d.device_id and device.environment = any(push_environments)
        where d.status in ('pending', 'sending') and d.available_at <= now()
          and d.created_at > now() - interval '1 hour' and d.attempts < 6
        order by d.available_at, d.id limit least(greatest(batch_size, 1), 50)
        for update of d skip locked
    )
    update public.recipe_push_deliveries as d
    set status = 'sending', attempts = d.attempts + 1, lease_id = gen_random_uuid(), available_at = now() + interval '2 minutes'
    from candidates as c where d.id = c.id returning d.id, d.lease_id;
$$;
revoke all on function public.claim_recipe_pushes(integer, text[]) from public, anon, authenticated;
grant execute on function public.claim_recipe_pushes(integer, text[]) to service_role;

-- Recheck visibility, both memberships, the opt-in, and account ownership immediately before sending.
create function public.prepare_recipe_push(delivery_id uuid, delivery_lease uuid)
returns table (token text, environment text, recipient_id uuid, recipe_id uuid, household_id uuid, title text, actor_name text, expires_at timestamptz)
language sql security invoker set search_path = '' as $$
    select device.token, device.environment, delivery.recipient_id, recipe.id, event.household_id, recipe.title, actor.display_name, delivery.created_at + interval '1 hour'
    from public.recipe_push_deliveries as delivery
    join public.recipe_push_events as event on event.id = delivery.event_id
    join public.push_devices as device on device.id = delivery.device_id and device.user_id = delivery.recipient_id and device.recipes_enabled
    join public.recipes as recipe on recipe.id = event.recipe_id and recipe.owner_id = event.actor_id and recipe.is_shared
    join public.household_members as actor on actor.user_id = event.actor_id and actor.household_id = event.household_id
    join public.household_members as recipient on recipient.user_id = delivery.recipient_id and recipient.household_id = event.household_id
    where delivery.id = delivery_id and delivery.lease_id = delivery_lease and delivery.status = 'sending'
      and delivery.available_at > now() and delivery.created_at > now() - interval '1 hour'
      and delivery.recipient_id <> event.actor_id;
$$;
revoke all on function public.prepare_recipe_push(uuid, uuid) from public, anon, authenticated;
grant execute on function public.prepare_recipe_push(uuid, uuid) to service_role;

create function public.finish_recipe_push(delivery_id uuid, delivery_lease uuid, result text, error_reason text default null)
returns void language plpgsql security invoker set search_path = '' as $$
begin
    if result not in ('delivered', 'retry', 'failed', 'cancelled', 'invalid_token') then
        raise exception 'Invalid push result' using errcode = '22023';
    end if;
    if result = 'invalid_token' then
        -- Only remove the device associated with this lease, never a newer registration.
        delete from public.push_devices as device using public.recipe_push_deliveries as delivery
        where delivery.id = delivery_id and delivery.lease_id = delivery_lease and delivery.status = 'sending' and device.id = delivery.device_id
          and device.updated_at <= delivery.available_at - interval '2 minutes';
        update public.recipe_push_deliveries set status = 'failed', lease_id = null, last_error = left(error_reason, 120)
          where id = delivery_id and lease_id = delivery_lease and status = 'sending';
        return;
    end if;
    update public.recipe_push_deliveries set
        status = case when result = 'retry' and attempts < 6 then 'pending' when result = 'retry' then 'failed' else result end,
        available_at = now() + make_interval(secs => least(900, 15 * (2 ^ attempts)::integer)),
        lease_id = null, last_error = left(error_reason, 120)
    where id = delivery_id and lease_id = delivery_lease and status = 'sending';
end;
$$;
revoke all on function public.finish_recipe_push(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.finish_recipe_push(uuid, uuid, text, text) to service_role;

-- Expire old alerts rather than delivering yesterday's recipe when credentials become available.
select cron.schedule('household-recipe-push', '* * * * *', 'select private.wake_recipe_push_worker()');
select cron.schedule('household-recipe-push-cleanup', '17 3 * * *',
    $job$delete from public.recipe_push_events where created_at < now() - interval '7 days';
    update public.recipe_push_deliveries set status = 'cancelled', lease_id = null
      where status in ('pending', 'sending') and (created_at < now() - interval '1 hour' or attempts >= 6);$job$);
