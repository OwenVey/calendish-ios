-- Profile photos (from Google) shown to fellow household members.
-- Other members can't read a user's auth metadata, so each member copies their own URL here.

alter table public.household_members add column avatar_url text;

-- The existing "Members can update their own profile" policy limits this to the member's own row.
grant update (avatar_url) on public.household_members to authenticated;
