-- Recipe photos. Files live in a private bucket under a folder named for the household
-- (`<household_id>/<file>.jpg`), and only that household's members can read or change them.
-- Each upload gets a new file name, so clients can cache a photo by its path forever.

alter table public.recipes add column image_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('recipe-images', 'recipe-images', false, 10485760, array['image/jpeg']);

create policy "Members can view recipe photos" on storage.objects
    for select to authenticated
    using (
        bucket_id = 'recipe-images'
        and (storage.foldername(name))[1] in (
            select household_id::text from public.household_members where user_id = (select auth.uid())
        )
    );
create policy "Members can add recipe photos" on storage.objects
    for insert to authenticated
    with check (
        bucket_id = 'recipe-images'
        and (storage.foldername(name))[1] in (
            select household_id::text from public.household_members where user_id = (select auth.uid())
        )
    );
create policy "Members can delete recipe photos" on storage.objects
    for delete to authenticated
    using (
        bucket_id = 'recipe-images'
        and (storage.foldername(name))[1] in (
            select household_id::text from public.household_members where user_id = (select auth.uid())
        )
    );
