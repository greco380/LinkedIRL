# Linkup LinkedIn OAuth Worker — Deploy Runbook

This Deno worker exchanges a LinkedIn OAuth authorization code (with PKCE) for an access token, fetches the authenticated member's OpenID Connect userinfo, and returns a Linkup `member` + `importRecord` payload to the iOS app.

It does **not** call `/v2/connections` and does **not** request `r_1st_connections`. The user's connection list comes from their LinkedIn data export (`Connections.csv`), parsed in-app by `LinkedInNetworkImportService`.

---

## 1. Where this deploys

- Supabase organization: **Forge AI Advisory**
- Supabase project: **linkup**
- Edge Function name: `linkedin-oauth`

> Heads up: as of session 2 the Supabase MCP can see **Forge AI Advisory → Linkup** (`ghkzdhdwnpppeivwyaej`), and the database schema has already been applied (see `backend/supabase/migrations/0001_linkup_core_schema.sql`). The CLI steps below are still the supported path for deploying the **Edge Function**; the MCP can alternatively `deploy_edge_function`.
>
> The function now imports `@supabase/supabase-js` from esm.sh and writes to Postgres using the **auto-injected** `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` (you do NOT set these). The first deploy fetches the dependency, so deploy with network access.

## 2. One-time setup

### 2.1 Install the Supabase CLI

```bash
brew install supabase/tap/supabase
# verify
supabase --version
```

### 2.2 Log in

```bash
supabase login
```

This opens a browser. Log in with the account that owns Forge AI Advisory.

### 2.3 Link the local repo to the linkup project

From the repo root:

```bash
supabase link --project-ref ####### ENTER LINKUP PROJECT REF HERE #######
```

> Where to find the project ref:
> 1. https://supabase.com/dashboard
> 2. Select **Forge AI Advisory** in the org switcher (top-left)
> 3. Open the **linkup** project
> 4. Project Settings → General → "Reference ID" (looks like `abcdefghijklmnop`)

### 2.4 Move `linkedin-oauth.ts` into a `supabase/functions/<name>/index.ts` layout

The Supabase CLI expects functions under `supabase/functions/<function-name>/index.ts`. From the repo root:

```bash
mkdir -p supabase/functions/linkedin-oauth
cp backend/linkedin/linkedin-oauth.ts supabase/functions/linkedin-oauth/index.ts
```

(Or symlink. The source of truth stays at `backend/linkedin/linkedin-oauth.ts`; copy/symlink on deploy.)

## 3. Set Edge Function secrets

These three secrets live ONLY in Supabase, never in the iOS app or this repo.

```bash
supabase secrets set \
  LINKEDIN_CLIENT_ID="####### ENTER LINKEDIN CLIENT ID HERE #######" \
  LINKEDIN_CLIENT_SECRET="####### ENTER LINKEDIN CLIENT SECRET HERE #######" \
  LINKEDIN_REDIRECT_URI="linkup://linkedin-oauth"
```

> Where to find the LinkedIn values:
> 1. https://www.linkedin.com/developers/apps
> 2. Open your Linkup app
> 3. **Auth** tab → "Application credentials"
>    - **Client ID** → `LINKEDIN_CLIENT_ID`
>    - **Primary Client Secret** → `LINKEDIN_CLIENT_SECRET` (click the eye icon to reveal)
> 4. Same tab → "Authorized redirect URLs for your app"
>    - Confirm `linkup://linkedin-oauth` is listed. If not, **+ Add redirect URL** and add exactly that string.

Verify:

```bash
supabase secrets list
```

You should see all three keys (values masked).

## 4. Deploy the function

```bash
supabase functions deploy linkedin-oauth --no-verify-jwt
```

`--no-verify-jwt` is required because this endpoint is called by the iOS app before any Supabase auth session exists. The function itself validates the LinkedIn OAuth `state` and `code_verifier`, which is the security boundary.

## 5. Capture the function URL

```bash
supabase functions list
```

The URL format is:

```
https://<project-ref>.supabase.co/functions/v1/linkedin-oauth
```

The iOS `LINKUP_API_BASE_URL` in `Info.plist` should be set to the part **before** `/linkedin/oauth/exchange`:

```
https://<project-ref>.supabase.co/functions/v1/linkedin-oauth
```

(Yes, both the function name and the in-function endpoint path live in the URL — that's because the iOS service prefixes `linkedin/oauth/exchange` to the base URL.)

## 6. Smoke-test

```bash
# health
curl -s https://<project-ref>.supabase.co/functions/v1/linkedin-oauth/health
# expected: {"ok":true}

# version
curl -s https://<project-ref>.supabase.co/functions/v1/linkedin-oauth/version
# expected: {"version":"linkup-linkedin-oauth@..."}
```

If either returns HTML or a Supabase auth error, re-run `deploy` with `--no-verify-jwt`.

## 7. Then test the OAuth round-trip from the iOS simulator

1. Build and run the Linkup scheme on an iOS 17+ simulator.
2. Sign in / create an account.
3. Settings → "Import from LinkedIn API".
4. Complete the LinkedIn auth in the embedded browser.
5. Expect: the app reports a successful identity verification (no connections — those come from the CSV path).
6. Then test the CSV import path: Settings → "Import from LinkedIn archive" → select `Connections.csv` (a sample lives at `backend/linkedin/sample-Connections.csv`).

## 8. View logs when things break

```bash
supabase functions logs linkedin-oauth --tail
```

The worker writes `console.error` entries at each LinkedIn API boundary, including the HTTP status and response body.

---

## Endpoint reference

`POST /linkedin/oauth/exchange`

Request body:

```json
{
  "accountID": "LINKUP_ACCOUNT_UUID",
  "code": "LINKEDIN_AUTHORIZATION_CODE",
  "redirectURI": "linkup://linkedin-oauth",
  "codeVerifier": "PKCE_VERIFIER_FROM_IOS"
}
```

Response body (success):

```json
{
  "member": {
    "subject": "linkedin-user-sub",
    "name": "...",
    "givenName": "...",
    "familyName": "...",
    "email": "...",
    "profileURL": null,
    "profileSlug": null,
    "verifiedAt": "2026-05-30T12:34:56Z"
  },
  "importRecord": {
    "id": "uuid",
    "accountID": "uuid",
    "source": "linkedin_api",
    "importedAt": "2026-05-30T12:34:56Z",
    "rowCount": 0,
    "fileHash": "..."
  },
  "profiles": [],
  "connections": [],
  "profileObservations": []
}
```

On success the function also **persists** the account row + a `linkedin_api` import record (best-effort; a DB failure is logged but still returns the payload above).

`POST /linkedin/archive/sync`

Persists a LinkedIn CSV import that the iOS app already parsed locally. Request body:

```json
{
  "accountID": "LINKUP_ACCOUNT_UUID",
  "importRecord": { "id": "uuid", "accountID": "uuid", "source": "linkedin_archive", "importedAt": "2026-05-30T12:34:56Z", "rowCount": 42, "fileHash": "..." },
  "profiles": [ { "id": "linkedin:in:slug", "normalizedURL": "https://...", "slug": "slug", "firstName": "...", "lastName": "...", "company": "...", "position": "..." } ],
  "connections": [ { "id": "uuid", "accountID": "uuid", "connectionProfileID": "linkedin:in:slug", "verificationState": "imported", "confidenceScore": 0.9, "fieldMask": {"hasFirstName": true}, "firstName": "...", "lastName": "...", "profileURL": "https://...", "emailHash": null, "company": "...", "position": "...", "connectedOn": "2026-04-11T00:00:00Z", "importedAt": "2026-05-30T12:34:56Z" } ],
  "profileObservations": [ ... ]
}
```

Response: `{ "ok": true, "persisted": { "profiles": N, "connections": N, "observations": N } }`. Upserts are idempotent (`account_id + connection_profile_id`), so re-syncing the same export is safe. The iOS app calls this best-effort after a successful local import.

`POST /linkedin/archive/upload?accountID=<uuid>`

Server-side CSV parsing path (the "I lost my phone" re-import). Accepts either
`multipart/form-data` with a `file` field, or a raw text body containing the
LinkedIn `Connections.csv` (BOM-stripped, "Notes:" preamble skipped, quoted
commas + embedded newlines handled). On success runs the same upserts as
`/linkedin/archive/sync` and returns `{ "ok": true, "parsedRows": N, "persisted": { ... } }`.
iOS does NOT need to change — the existing JSON-sync flow is still primary.

`POST /messages/send`

```json
{ "senderAccountID": "uuid", "recipientAccountID": "uuid", "body": "text" }
```

Inserts a `chat_message` row with a canonical `thread_id` (sorted-pair join).
Returns `{ "message": { ... } }`. Triggers an APNs push via the
`trg_chat_message_push` trigger if the recipient has a `push_token`.

`POST /messages/poll`

```json
{ "accountID": "uuid", "sinceISO": "2026-06-09T12:34:56Z" }
```

Returns up to 200 messages where the account is sender OR recipient, newest
first. `sinceISO` is optional.

`POST /messages/threads`

```json
{ "accountID": "uuid" }
```

Returns one summary per thread: `{ threadID, otherAccountID, lastBody, lastSentAt, lastSenderAccountID, unreadCount }`.

`GET /health` → `{"ok": true}`

`GET /version` → `{"version": "linkup-linkedin-oauth@<date>"}`

## LinkedIn scopes

The iOS app requests:

```
openid profile email
```

`r_1st_connections` is intentionally NOT requested — connection data comes from the LinkedIn CSV export.

## Local development

To test the function locally before deploying:

```bash
LINKEDIN_CLIENT_ID="..." \
LINKEDIN_CLIENT_SECRET="..." \
LINKEDIN_REDIRECT_URI="linkup://linkedin-oauth" \
deno run --allow-net --allow-env backend/linkedin/linkedin-oauth.ts
```

Serves on `http://localhost:8000`. Point `LINKUP_API_BASE_URL` at `http://127.0.0.1:8000` for the iOS simulator.
