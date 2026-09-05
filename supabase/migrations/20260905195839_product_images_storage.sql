-- Chez Yasmine — bucket de stockage des photos produit
--
-- Chemin des objets : {organization_id}/{establishment_id}/{product_id}/{uuid}-{variant}.webp
-- (le nom du bucket lui-même n'apparaît pas dans `storage.objects.name`).
-- Bucket privé : l'accès passe par des URLs signées générées par NestJS,
-- jamais par une URL publique directe.

insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', false)
on conflict (id) do nothing;

-- Réutilise user_has_establishment_access(uuid), définie dans
-- 20260905191510_rls_policies.sql, en la pointant vers le 2e segment du
-- chemin ({establishment_id}). storage.foldername() renvoie les segments de
-- dossier (sans le nom de fichier final).
create policy tenant_isolation on storage.objects for all to authenticated
  using (
    bucket_id = 'product-images'
    and array_length(storage.foldername(name), 1) >= 2
    and user_has_establishment_access(((storage.foldername(name))[2])::uuid)
  )
  with check (
    bucket_id = 'product-images'
    and array_length(storage.foldername(name), 1) >= 2
    and user_has_establishment_access(((storage.foldername(name))[2])::uuid)
  );
