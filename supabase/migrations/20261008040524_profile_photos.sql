-- Avatars are private to the person and their current household. Immutable paths allow
-- replacements without granting UPDATE on Storage or changing a cached object in place.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profile-photos', 'profile-photos', false, 2097152, array['image/jpeg']);

create policy "People view their own and household avatars" on storage.objects
for select to authenticated using (
    bucket_id = 'profile-photos' and (
        (storage.foldername(name))[1] = (select auth.uid())::text
        or (storage.foldername(name))[1] in (
            select user_id::text from public.household_members
            where household_id = (select private.current_household())
        )
    )
);
create policy "People upload their own avatars" on storage.objects
for insert to authenticated with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
);
create policy "People delete their own avatars" on storage.objects
for delete to authenticated using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
);
