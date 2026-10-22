# Owner password recovery setup

1. Apply `supabase/migrations/20261018000800_owner_password_recovery.sql` to the Supabase project used by the POS.
2. Turn on 2-Step Verification for `help.synorra@gmail.com` and create a Google App Password for Mail. Do not use the account's normal Google password.
3. Add `GMAIL_APP_PASSWORD` as a server-side environment variable in Vercel and in local `.env` when testing locally. The sender is set in the app to `help.synorra@gmail.com`.
4. Set `APP_URL` to the public app origin if it differs from `https://synorra-pos.click.app`, then redeploy after changing Vercel environment variables.

Reset links expire after one hour and can be used once. Only Owner staff accounts can use this flow.

Gmail may block SMTP sign-ins from unfamiliar server locations and is designed primarily for personal mail use. If that happens, Google may require account-security review or a different transactional email provider.
