-- Linkup LinkedIn picture column (session 4).
-- The OIDC userinfo response includes a `picture` URL; we now thread it through
-- the Edge Function and persist it here for the profile sheet + connection pins.

alter table public.linkup_account
  add column if not exists linkedin_picture_url text;
