# NDH Estore database

## Local setup

1. Install Docker and the Supabase CLI.
2. Copy `.env.example` to `.env` and populate the values printed by `supabase status`.
3. Run `supabase start`.
4. Run `supabase db reset` to apply migrations and the local seed.
5. Create a user through Supabase Auth. The database trigger creates the matching `public.users` record and customer role automatically.
6. Run `supabase db reset` again if you want the demonstration Amari vendor attached to the first local user.

## Security model

- `auth.users` is the authentication source of truth.
- `public.users` contains application profile data and never contains a role column.
- `public.user_roles` supports multiple roles per user.
- `public.has_role(user_id, role)` is a security-definer authorization check with a fixed search path.
- Vendor-owned rows are authorized by joining through `vendors.owner_user_id`.
- Public storefront reads are limited to published vendors, active products, active delivery profiles, and published reviews.
- The service-role key belongs only in server functions. Browser code receives only the anonymous key and remains subject to row-level security.

## Storage paths

Vendor assets must use an authenticated owner prefix:

```text
vendor-assets/{auth-user-id}/products/{file-name}
vendor-assets/{auth-user-id}/branding/{file-name}
```

Private digital products use:

```text
digital-products/{auth-user-id}/{product-id}/{file-name}
```

The public asset bucket accepts JPEG, PNG, WebP, and GIF files up to 20 MiB. Digital products remain private and permit files up to 100 MiB.

## Production migration

Link the CLI to the production project and review the SQL before applying it:

```bash
supabase link --project-ref YOUR_PROJECT_REF
supabase db push --dry-run
supabase db push
```

Generate canonical TypeScript definitions after each database change:

```bash
supabase gen types typescript --linked > src/types/database.generated.ts
```

Do not run `seed.sql` against production. Production roles, vendors, subscriptions, and payment records must be created through authenticated application workflows.
