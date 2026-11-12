-- Private storage bucket for pharmacy licence documents, and EXECUTE grants for the API surface.

-- ---------------------------------------------------------------------------
-- Storage: bucket `pharmacy-documents`
--   * private, 5 MB, PDF / JPEG / PNG only
--   * object path must be '<auth.uid()>/<file>'
--   * owners may upload and read their own files; admins may read all; nobody may update/delete from the client
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('pharmacy-documents', 'pharmacy-documents', false, 5242880,
        array['application/pdf', 'image/jpeg', 'image/png'])
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy pharmacy_documents_insert_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'pharmacy-documents'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy pharmacy_documents_select_own on storage.objects
  for select to authenticated
  using (
    bucket_id = 'pharmacy-documents'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy pharmacy_documents_select_admin on storage.objects
  for select to authenticated
  using (bucket_id = 'pharmacy-documents' and private.is_admin());

-- ---------------------------------------------------------------------------
-- Function grants
-- Every function in `public` is part of the client API and is callable by signed-in users only.
-- Internal helpers live in `private` and are never granted, except the three used by RLS policies
-- and generated columns. New public functions MUST be reviewed: this migration is the single place
-- where the API surface is declared, and tests/10_tests_security.sql fails if anon can execute any.
-- ---------------------------------------------------------------------------
grant execute on all functions in schema public to authenticated;
revoke execute on all functions in schema public from anon, public;

-- Final sweep of the internal schema (functions created after migration 4 included).
revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function private.is_admin() to authenticated;
grant execute on function private.is_member(uuid, public.member_role[]) to authenticated;
grant execute on function private.normalize_search(text) to authenticated;
