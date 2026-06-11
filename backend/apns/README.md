# Linkup APNs Sender — Deploy Runbook

Deno Edge Function that signs an ES256 JWT and POSTs alert pushes to Apple's
HTTP/2 endpoint. Source of truth: `backend/apns/index.ts`. The older
`send-notification.ts` is kept as historical reference; deploy `index.ts`.

The function is invoked two ways:

1. **From Postgres** — the `0004_message_push_trigger.sql` trigger calls
   `/apns/send` via `pg_net.http_post` after every `chat_message` insert.
2. **From the iOS app or other services** — for share-expiring / share-expired
   warnings, use the legacy `/apns/message`, `/apns/share-expiring`, and
   `/apns/share-expired` routes (kept for backward compatibility).

---

## 1. Where this deploys

- Supabase organization: **Forge AI Advisory**
- Supabase project: **Linkup** (`ghkzdhdwnpppeivwyaej`)
- Edge Function name: `apns`

## 2. Set the env vars

These secrets live ONLY in Supabase, never in the iOS app or this repo.

```bash
supabase secrets set \
  APNS_KEY_ID="####### ENTER APNS KEY ID HERE #######" \
  APNS_TEAM_ID="####### ENTER APPLE TEAM ID HERE #######" \
  APNS_TOPIC="####### ENTER BUNDLE ID e.g. com.linkup.app #######" \
  APNS_ENVIRONMENT="production" \
  APNS_PRIVATE_KEY="$(cat AuthKey_XXXXXXXXXX.p8)"
```

Where to find each:

- **APNS_KEY_ID** — Apple Developer → Certificates, Identifiers & Profiles →
  Keys → your APNs key. It's the 10-char string in the filename
  `AuthKey_<KEY_ID>.p8`.
- **APNS_TEAM_ID** — Apple Developer → Membership → Team ID (10 chars).
- **APNS_TOPIC** — your iOS bundle id, e.g. `com.linkup.app`. Defaults to
  `com.linkup.app` if unset; set it explicitly to be safe.
- **APNS_ENVIRONMENT** — `sandbox` for TestFlight + dev builds, `production`
  for App Store. Defaults to `production`.
- **APNS_PRIVATE_KEY** — the entire PEM contents of your `.p8` file, including
  the `-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----` lines.

Verify:

```bash
supabase secrets list
```

## 3. Stage the function in the CLI layout

```bash
mkdir -p supabase/functions/apns
cp backend/apns/index.ts supabase/functions/apns/index.ts
```

(Or symlink. The source of truth stays at `backend/apns/index.ts`.)

## 4. Deploy

```bash
supabase functions deploy apns --no-verify-jwt
```

`--no-verify-jwt` is required because the function is called by Postgres
(via pg_net) and other server-side callers; Supabase JWT verification would
reject those.

## 5. Smoke-test

```bash
# health
curl -s https://<project-ref>.supabase.co/functions/v1/apns/health
# -> {"ok":true}

# version
curl -s https://<project-ref>.supabase.co/functions/v1/apns/version
# -> {"version":"linkup-apns@..."}
```

## 6. Wire the chat_message trigger to the deployed URL

After the function is live, point Postgres at it (one-time per project):

```sql
alter database postgres
  set app.apns_function_url
    = 'https://<project-ref>.supabase.co/functions/v1/apns/apns/send';
```

(The double `apns` is correct: Supabase prefixes the function name, and the
internal route is `/apns/send`.)

Until that GUC is set the `trg_chat_message_push` trigger is a silent no-op,
so message inserts continue to work even before APNs is deployed.

## 7. View logs

```bash
supabase functions logs apns --tail
```

## Endpoint reference

`POST /apns/send`

```json
{ "deviceToken": "<hex-device-token>", "title": "Alice", "body": "hello", "payload": { "type": "message" } }
```

`POST /apns/message` (legacy compatibility)

```json
{ "deviceToken": "...", "eventName": "SaaStr Annual 2026", "message": "...", "senderName": "Alice", "muted": false }
```

`POST /apns/share-expiring` / `POST /apns/share-expired` (legacy)

```json
{ "deviceToken": "...", "eventName": "SaaStr Annual 2026" }
```

`GET /health` → `{ "ok": true }`
`GET /version` → `{ "version": "linkup-apns@<date>" }`

## Local development

```bash
APNS_KEY_ID="..." \
APNS_TEAM_ID="..." \
APNS_TOPIC="com.linkup.app" \
APNS_ENVIRONMENT="sandbox" \
APNS_PRIVATE_KEY="$(cat AuthKey_XXXXXXXXXX.p8)" \
deno run --allow-net --allow-env backend/apns/index.ts
```

Serves on `http://localhost:8000`.
