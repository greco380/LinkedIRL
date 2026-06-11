# Linkup — Alpha 2-Device Test Runbook

Last updated: 2026-06-07 (session 3 — live presence / real cross-device discovery).

This is the step-by-step to get two phones to actually **see each other** at the
same event. Read it top to bottom once before you start.

---

## What changed in this session

1. **Login errors are now visible.** Auth feedback (e.g. "Password must be at least
   8 characters", "An account already exists") used to be sent to a toast that only
   rendered *after* sign-in — so on the login screen the button looked dead. The toast
   now lives at the app root and shows on the login screen too. *(RootView.swift)*

2. **Real cross-device discovery was built.** Before this, the Discover map only ever
   showed hardcoded sample people, and the two phones could never see each other.
   Added:
   - `live_presence` table + RLS — `backend/supabase/migrations/0002_live_presence.sql`
   - `/presence/upsert`, `/presence/stop`, `/presence/nearby` endpoints in the Edge
     Function — `backend/linkedin/linkedin-oauth.ts`
   - iOS presence client + polling — `LinkupBackendService.swift`, `AppStore.swift`
   - Discover now shows live connections when the backend is configured.

   **How "seeing each other" works:** when you start sharing, your phone publishes a
   presence row (your name, your LinkedIn slug, the event name, a map spot, an expiry).
   It then polls every 7s for everyone else live at the *same event name* — and the
   server only returns the ones who are in **your** imported connection list. Matching
   is by LinkedIn slug first, normalized full name as a fallback.

> ⚠️ **I could not compile or deploy from here.** This sandbox can't run Xcode or the
> Supabase/Deno CLI. The matching logic was re-verified in Python (slug + name match,
> incl. case/trailing-slash differences). The Swift/TS still needs a clean build + deploy
> on your Mac — see steps below. If Xcode flags a project-format issue, no new files were
> added to the project this session (everything went into existing files), so it should
> build as-is.

---

## Prerequisites you must do (only you can — they need your accounts)

You do **not** need LinkedIn or Google OAuth, Apple sign-in, or push for this test.
Email/password + CSV import + presence is the whole path. You only need three things:

### 1. Apply the new DB migration
Project: **Forge AI Advisory → Linkup** (`ghkzdhdwnpppeivwyaej`).

- CLI: `supabase db push` (after `supabase link`), **or**
- Apply `backend/supabase/migrations/0002_live_presence.sql` via the Supabase dashboard
  SQL editor / MCP `apply_migration`.

Confirm the `live_presence` table exists.

### 2. Deploy the Edge Function
From `backend/linkedin/` (per the existing `README.md` runbook):

```
supabase functions deploy linkedin-oauth
```

Confirm it's the new build:

```
curl https://<your-function-base-url>/version
# -> {"version":"linkup-linkedin-oauth@2026-06-07-presence"}
```

The Supabase service-role key + URL are auto-injected — no secrets to set for this flow.

### 3. Point the app at the backend
In `Linkup/Resources/Info.plist`, set `LINKUP_API_BASE_URL` to your deployed function
base URL (the same base the `/version` check above used). This is the one placeholder
that gates the whole live feature — until it's a real URL, the app cleanly falls back to
the old sample-data demo and the two phones won't see each other.

> **Routing note:** the function routes on exact paths (`/presence/nearby`, etc.), exactly
> like the existing `/linkedin/archive/sync`. If `nearby`/`sync` ever returns 404 after
> deploy, it's a function-name-prefix routing issue that affects all endpoints equally —
> fix it once for the whole function.

---

## Build to both phones

1. Open `Linkup.xcodeproj` in Xcode.
2. `⌘U` to run the `LinkupTests` unit tests, then a clean build (`⌘⇧K`, then `⌘B`).
3. Select Phone 1 as the run destination → `⌘R`. Repeat for Phone 2.
   (Free Apple ID signing is fine for a 7-day on-device alpha; set your Team under
   Signing & Capabilities if Xcode asks.)

---

## The 2-phone test (turnkey)

Two ready-made import files are in `backend/linkedin/testdata/`. Use them exactly:

**Phone 1**
1. Create account → name **`Alice Tester`**, any valid email, password ≥ 8 chars.
2. Settings → Save LinkedIn profile → `https://www.linkedin.com/in/alice-tester`
3. Import connections (CSV) → **`phone1-alice-imports-this.csv`**
   (contains "Bob Tester" → lets Phone 1 see Phone 2).

**Phone 2**
1. Create account → name **`Bob Tester`**, any valid email, password ≥ 8 chars.
2. Settings → Save LinkedIn profile → `https://www.linkedin.com/in/bob-tester`
3. Import connections (CSV) → **`phone2-bob-imports-this.csv`**
   (contains "Alice Tester" → lets Phone 2 see Phone 1).

**Both phones**
4. Discover → Share my location → set the event name to the **same exact text on both**,
   e.g. `Test Event` (case/spaces don't matter), pick any duration, confirm.
5. Wait up to ~7 seconds. Phone 1 should see **Bob Tester** appear on the map + in the
   "at Test Event" list; Phone 2 should see **Alice Tester**. Tap a pin to open the profile;
   open Messages to DM.

If you'd rather use your real LinkedIn data: each phone imports its own
`Connections.csv` export, and for them to see each other the two accounts must be actual
1st-degree connections (each export contains the other person). Save each phone's own
LinkedIn profile URL so slug-matching is exact; otherwise it falls back to matching on the
name you signed up with.

---

## Troubleshooting

- **Nothing appears after ~10s.**
  - Both phones on the *exact same event name*? (it's matched case-insensitively, but must
    be the same words.)
  - Both actively sharing (green "live" pill in the header)?
  - `LINKUP_API_BASE_URL` set to the real deployed URL on the build installed on *both* phones?
  - `/version` returns the `…-presence` build?
  - Check the Supabase `live_presence` table — you should see one row per sharing phone with a
    future `expires_at`. If rows are there but phones don't see each other, the CSV/name link is
    the culprit (see next).
- **Rows exist but no match.** Phone A only sees Phone B if B is in A's imported connections.
  Confirm A's CSV actually contains B (by the name B signed up with, or by B's saved profile
  slug). The provided test CSVs are pre-wired for `Alice Tester` ↔ `Bob Tester`.
- **Login button seems to do nothing.** You'll now see the reason as a toast. Most common:
  password under 8 characters, or an email without a `.` in the domain.
- **Build error about the project file.** Nothing new was added to `project.pbxproj` this
  session, so this is unlikely; if it happens it predates this work — see HANDOFF.md §7.

---

## What's still simulated (next milestones, not built yet)

- **Messaging is local/simulated** — replies are canned ("Great timing. I am near the demo
  floor."). Real cross-device chat needs a `messages` table + send/poll endpoints, same
  pattern as presence.
- **Map positions are synthetic** — each person gets a stable random spot, not real GPS.
  Real positioning would feed CoreLocation into the presence row.
- **Auth is local (per device)** — fine for this alpha. Moving to Supabase Auth later lets
  you add real per-user RLS policies and recover accounts across devices.
