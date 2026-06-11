// Linkup LinkedIn OAuth exchange worker.
//
// Responsibilities:
//   - Exchange a LinkedIn authorization code (with PKCE code_verifier) for an access token.
//   - Fetch the authenticated member's OpenID Connect userinfo.
//   - Return a Linkup `importRecord` + `member` payload to the iOS app.
//   - Persist account identity + import records + connections to Supabase Postgres
//     using the Service Role key (see "Persistence" below).
//
// Non-responsibilities (intentional):
//   - We do NOT call /v2/connections. The LinkedIn data export (CSV archive)
//     is the source of truth for the user's network. This worker only verifies
//     identity and links the member's LinkedIn subject to the Linkup account.
//   - We do NOT request the `r_1st_connections` LinkedIn scope. Only `openid profile email`.
//
// Persistence:
//   - The connection list is parsed in-app (LinkedInNetworkImportService) and POSTed
//     to POST /linkedin/archive/sync, which writes profiles/connections/observations.
//   - Identity verification (POST /linkedin/oauth/exchange) writes the account row +
//     a linkedin_api import record.
//   - All writes use SUPABASE_SERVICE_ROLE_KEY, which is auto-injected into Supabase
//     Edge Functions alongside SUPABASE_URL. RLS is enabled on every table; the
//     service role bypasses it. These secrets must NEVER be shipped in the iOS app.

import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const BUILD_VERSION = "linkup-linkedin-oauth@2026-06-09-v3";

type ExchangeRequest = {
  accountID: string;
  code: string;
  redirectURI: string;
  codeVerifier: string;
};

type LinkedInUserInfo = {
  sub: string;
  name?: string;
  given_name?: string;
  family_name?: string;
  email?: string;
  email_verified?: boolean;
  picture?: string;
};

// ---- Shapes received from the iOS app on /linkedin/archive/sync ----
// These mirror the Swift Codable models (camelCase). Dates arrive as ISO-8601
// strings because the iOS client encodes this request with .iso8601.
type SyncImportRecord = {
  id: string;
  accountID: string;
  source: string;
  importedAt: string;
  rowCount: number;
  fileHash: string;
};

type SyncProfile = {
  id: string;
  normalizedURL: string;
  slug?: string | null;
  firstName?: string | null;
  lastName?: string | null;
  company?: string | null;
  position?: string | null;
};

type SyncConnection = {
  id: string;
  accountID: string;
  connectionProfileID: string;
  importID?: string | null;
  verificationState?: string | null;
  confidenceScore?: number | null;
  fieldMask?: Record<string, boolean> | null;
  firstName?: string | null;
  lastName?: string | null;
  profileURL: string;
  emailHash?: string | null;
  company?: string | null;
  position?: string | null;
  connectedOn?: string | null;
  importedAt: string;
};

type SyncObservation = {
  id: string;
  profileID: string;
  importID?: string | null;
  source: string;
  observedAt: string;
  firstName?: string | null;
  lastName?: string | null;
  company?: string | null;
  position?: string | null;
  rawURL: string;
  rawRowHash: string;
};

type SyncRequest = {
  accountID: string;
  importRecord: SyncImportRecord;
  profiles?: SyncProfile[];
  connections?: SyncConnection[];
  profileObservations?: SyncObservation[];
};

// ---- Live presence (real-time "who's at this event") ----
// Posted by iOS when a user starts sharing their location at an event, polled
// back via /presence/nearby to render connections on the venue map.
type PresenceUpsertRequest = {
  accountID: string;
  displayName?: string | null;
  headline?: string | null;
  linkedInSlug?: string | null;
  linkedInURL?: string | null;
  eventName: string;
  mapX?: number | null;
  mapY?: number | null;
  // Real-world GPS payload (CoreLocation on iOS). Optional — synthetic
  // positions don't carry these. The Edge Function range-checks each value
  // before writing; out-of-range payloads are silently dropped.
  latitude?: number | null;
  longitude?: number | null;
  accuracyMeters?: number | null;
  expiresAt: string; // ISO-8601
};

type PresenceStopRequest = { accountID: string };

type PresenceNearbyRequest = { accountID: string; eventName: string };

// ---- Messaging (real cross-device DMs, replacing simulated canned replies) ----
type MessageSendRequest = {
  senderAccountID: string;
  recipientAccountID: string;
  body: string;
};

type MessagePollRequest = {
  accountID: string;
  sinceISO?: string | null;
};

type MessageThreadsRequest = {
  accountID: string;
};

// ---- Deletion (Apple §5.1.1(v) + per-message housekeeping) ----
// /messages/delete accepts EITHER a single-message body OR a whole-thread body.
// Distinguished by presence of `messageID`. Both shapes are validated below.
type MessageDeleteRequest = {
  messageID?: string | null;
  accountID: string;
  otherAccountID?: string | null;
};

type AccountDeleteRequest = {
  accountID: string;
};

const linkedInTokenURL = "https://www.linkedin.com/oauth/v2/accessToken";
const linkedInUserInfoURL = "https://api.linkedin.com/v2/userinfo";

// Supabase serves this function at /functions/v1/linkedin-oauth/<route> and the
// worker sees the function name as the first pathname segment
// ("/linkedin-oauth/presence/upsert"). Local `deno run` serves bare routes
// ("/presence/upsert"). Strip the deployment prefixes so one route table works
// in both environments.
function routePath(rawPathname: string): string {
  let p = rawPathname;
  if (p.startsWith("/functions/v1/")) p = p.slice("/functions/v1".length);
  if (p === "/linkedin-oauth") return "/";
  if (p.startsWith("/linkedin-oauth/")) p = p.slice("/linkedin-oauth".length);
  return p === "" ? "/" : p;
}

Deno.serve(async (request) => {
  const url = new URL(request.url);
  const pathname = routePath(url.pathname);

  if (request.method === "GET" && pathname === "/health") {
    return json({ ok: true });
  }

  if (request.method === "GET" && pathname === "/version") {
    return json({ version: BUILD_VERSION });
  }

  if (request.method === "POST" && pathname === "/linkedin/oauth/exchange") {
    try {
      const body = await readJSON<ExchangeRequest>(request);
      return json(await exchangeAndVerify(body));
    } catch (error) {
      const status = error instanceof HTTPError ? error.status : 500;
      const message = error instanceof Error ? error.message : "LinkedIn import failed";
      console.error("[linkedin-oauth] /linkedin/oauth/exchange failed", { status, message });
      return json({ error: message }, status);
    }
  }

  if (request.method === "POST" && pathname === "/linkedin/archive/sync") {
    try {
      const body = await readJSON<SyncRequest>(request);
      return json(await syncArchive(body));
    } catch (error) {
      const status = error instanceof HTTPError ? error.status : 500;
      const message = error instanceof Error ? error.message : "LinkedIn archive sync failed";
      console.error("[linkedin-oauth] /linkedin/archive/sync failed", { status, message });
      return json({ error: message }, status);
    }
  }

  if (request.method === "POST" && pathname === "/presence/upsert") {
    try {
      const body = await readJSON<PresenceUpsertRequest>(request);
      return json(await upsertPresence(body));
    } catch (error) {
      const status = error instanceof HTTPError ? error.status : 500;
      const message = error instanceof Error ? error.message : "presence upsert failed";
      console.error("[linkedin-oauth] /presence/upsert failed", { status, message });
      return json({ error: message }, status);
    }
  }

  if (request.method === "POST" && pathname === "/presence/stop") {
    try {
      const body = await readJSON<PresenceStopRequest>(request);
      return json(await stopPresence(body));
    } catch (error) {
      const status = error instanceof HTTPError ? error.status : 500;
      const message = error instanceof Error ? error.message : "presence stop failed";
      console.error("[linkedin-oauth] /presence/stop failed", { status, message });
      return json({ error: message }, status);
    }
  }

  if (request.method === "POST" && pathname === "/presence/nearby") {
    try {
      const body = await readJSON<PresenceNearbyRequest>(request);
      return json(await nearbyPresence(body));
    } catch (error) {
      const status = error instanceof HTTPError ? error.status : 500;
      const message = error instanceof Error ? error.message : "presence nearby failed";
      console.error("[linkedin-oauth] /presence/nearby failed", { status, message });
      return json({ error: message }, status);
    }
  }

  if (request.method === "POST" && pathname === "/messages/send") {
    try {
      const body = await readJSON<MessageSendRequest>(request);
      return json(await sendMessage(body));
    } catch (error) {
      const status = error instanceof HTTPError ? error.status : 500;
      const message = error instanceof Error ? error.message : "message send failed";
      console.error("[linkedin-oauth] /messages/send failed", { status, message });
      return json({ error: message }, status);
    }
  }

  if (request.method === "POST" && pathname === "/messages/poll") {
    try {
      const body = await readJSON<MessagePollRequest>(request);
      return json(await pollMessages(body));
    } catch (error) {
      const status = error instanceof HTTPError ? error.status : 500;
      const message = error instanceof Error ? error.message : "message poll failed";
      console.error("[linkedin-oauth] /messages/poll failed", { status, message });
      return json({ error: message }, status);
    }
  }

  if (request.method === "POST" && pathname === "/messages/threads") {
    try {
      const body = await readJSON<MessageThreadsRequest>(request);
      return json(await listThreads(body));
    } catch (error) {
      const status = error instanceof HTTPError ? error.status : 500;
      const message = error instanceof Error ? error.message : "message threads failed";
      console.error("[linkedin-oauth] /messages/threads failed", { status, message });
      return json({ error: message }, status);
    }
  }

  if (request.method === "POST" && pathname === "/messages/delete") {
    try {
      const body = await readJSON<MessageDeleteRequest>(request);
      return json(await deleteMessages(body));
    } catch (error) {
      const status = error instanceof HTTPError ? error.status : 500;
      const message = error instanceof Error ? error.message : "message delete failed";
      console.error("[linkedin-oauth] /messages/delete failed", { status, message });
      return json({ error: message }, status);
    }
  }

  if (request.method === "POST" && pathname === "/account/delete") {
    try {
      const body = await readJSON<AccountDeleteRequest>(request);
      return json(await deleteAccount(body));
    } catch (error) {
      const status = error instanceof HTTPError ? error.status : 500;
      const message = error instanceof Error ? error.message : "account delete failed";
      console.error("[linkedin-oauth] /account/delete failed", { status, message });
      return json({ error: message }, status);
    }
  }

  if (request.method === "POST" && pathname === "/linkedin/archive/upload") {
    try {
      return json(await uploadArchive(request));
    } catch (error) {
      const status = error instanceof HTTPError ? error.status : 500;
      const message = error instanceof Error ? error.message : "archive upload failed";
      console.error("[linkedin-oauth] /linkedin/archive/upload failed", { status, message });
      return json({ error: message }, status);
    }
  }

  return json({ error: "Unknown endpoint" }, 404);
});

// ---------------------------------------------------------------------------
// Identity verification (+ persistence)
// ---------------------------------------------------------------------------

async function exchangeAndVerify(body: ExchangeRequest) {
  if (!body.accountID || !body.code || !body.redirectURI || !body.codeVerifier) {
    throw new HTTPError("accountID, code, redirectURI, and codeVerifier are required", 400);
  }
  if (!isUUID(body.accountID)) {
    throw new HTTPError("accountID must be a UUID", 400);
  }

  const configuredRedirectURI = requiredEnv("LINKEDIN_REDIRECT_URI");
  if (body.redirectURI !== configuredRedirectURI) {
    throw new HTTPError("redirectURI does not match LINKEDIN_REDIRECT_URI", 400);
  }

  const accessToken = await exchangeAuthorizationCode(body.code, body.redirectURI, body.codeVerifier);
  const member = await fetchUserInfo(accessToken);
  const payload = await toImportPayload(body.accountID, member);

  // Best-effort persistence: a DB hiccup must not block the user from completing
  // identity verification. Failures are logged; the payload is still returned.
  try {
    await persistIdentityVerification(body.accountID, member, payload.importRecord);
  } catch (error) {
    console.error("[linkedin-oauth] identity persistence failed (non-fatal)", {
      message: error instanceof Error ? error.message : String(error),
    });
  }

  return payload;
}

async function persistIdentityVerification(
  accountID: string,
  member: LinkedInUserInfo,
  importRecord: { id: string; importedAt: string },
) {
  const supabase = serviceClient();

  // Ensure the account row exists without clobbering an existing display_name/email
  // that iOS may have set. ignoreDuplicates => insert only when absent.
  const insertAccount = await supabase
    .from("linkup_account")
    .upsert(
      {
        id: accountID,
        display_name: member.name ?? "",
        email: member.email ?? "",
        auth_method: "linkedin",
        linkedin_connected: true,
        linkedin_member_id: member.sub,
        linkedin_verified_at: importRecord.importedAt,
        linkedin_picture_url: member.picture ?? null,
      },
      { onConflict: "id", ignoreDuplicates: true },
    );
  throwIfError(insertAccount.error, "upsert linkup_account");

  // Update only the LinkedIn identity columns on the (now-guaranteed) row.
  // We deliberately do NOT touch linkedin_imported_at / linkedin_connection_count
  // here — those belong to the CSV archive sync path.
  const updateAccount = await supabase
    .from("linkup_account")
    .update({
      linkedin_connected: true,
      linkedin_member_id: member.sub,
      linkedin_verified_at: importRecord.importedAt,
      linkedin_picture_url: member.picture ?? null,
    })
    .eq("id", accountID);
  throwIfError(updateAccount.error, "update linkup_account identity");

  const insertImport = await supabase
    .from("linkedin_import_record")
    .upsert(
      {
        id: importRecord.id,
        account_id: accountID,
        source: "linkedin_api",
        imported_at: importRecord.importedAt,
        row_count: 0,
        file_hash: "",
      },
      { onConflict: "id", ignoreDuplicates: true },
    );
  throwIfError(insertImport.error, "insert linkedin_import_record (api)");
}

// ---------------------------------------------------------------------------
// Archive sync (CSV connections parsed in-app, persisted here)
// ---------------------------------------------------------------------------

async function syncArchive(body: SyncRequest) {
  if (!body.accountID || !isUUID(body.accountID)) {
    throw new HTTPError("accountID (UUID) is required", 400);
  }
  if (!body.importRecord || !body.importRecord.id) {
    throw new HTTPError("importRecord is required", 400);
  }

  const accountID = body.accountID;
  const profiles = body.profiles ?? [];
  const connections = body.connections ?? [];
  const observations = body.profileObservations ?? [];
  const supabase = serviceClient();

  // 1. Ensure the account row exists (insert-if-absent; never overwrite identity).
  const insertAccount = await supabase
    .from("linkup_account")
    .upsert({ id: accountID, linkedin_connected: true }, { onConflict: "id", ignoreDuplicates: true });
  throwIfError(insertAccount.error, "ensure linkup_account");

  // 2. Import record.
  const insertImport = await supabase
    .from("linkedin_import_record")
    .upsert(
      {
        id: body.importRecord.id,
        account_id: accountID,
        source: body.importRecord.source || "linkedin_archive",
        imported_at: body.importRecord.importedAt,
        row_count: body.importRecord.rowCount ?? connections.length,
        file_hash: body.importRecord.fileHash ?? "",
      },
      { onConflict: "id" },
    );
  throwIfError(insertImport.error, "upsert linkedin_import_record (archive)");

  // 3. Profiles (idempotent per account_id + id).
  if (profiles.length > 0) {
    const rows = profiles.map((p) => ({
      account_id: accountID,
      id: p.id,
      normalized_url: p.normalizedURL ?? "",
      slug: p.slug ?? null,
      first_name: p.firstName ?? null,
      last_name: p.lastName ?? null,
      company: p.company ?? null,
      position: p.position ?? null,
    }));
    const res = await supabase.from("linkedin_profile").upsert(rows, { onConflict: "account_id,id" });
    throwIfError(res.error, "upsert linkedin_profile");
  }

  // 4. Connections (idempotent per account_id + connection_profile_id).
  if (connections.length > 0) {
    const rows = connections.map((c) => ({
      id: c.id,
      account_id: accountID,
      connection_profile_id: c.connectionProfileID,
      import_id: c.importID ?? body.importRecord.id,
      verification_state: c.verificationState ?? "imported",
      confidence_score: c.confidenceScore ?? 0.65,
      field_mask: c.fieldMask ?? {},
      first_name: c.firstName ?? "",
      last_name: c.lastName ?? "",
      profile_url: c.profileURL,
      email_hash: c.emailHash ?? null,
      company: c.company ?? null,
      position: c.position ?? null,
      connected_on: c.connectedOn ?? null,
      imported_at: c.importedAt,
    }));
    const res = await supabase
      .from("linkedin_connection")
      .upsert(rows, { onConflict: "account_id,connection_profile_id" });
    throwIfError(res.error, "upsert linkedin_connection");
  }

  // 5. Observations (append-only log of what each import saw).
  if (observations.length > 0) {
    const rows = observations.map((o) => ({
      id: o.id,
      account_id: accountID,
      profile_id: o.profileID,
      import_id: o.importID ?? body.importRecord.id,
      source: o.source,
      observed_at: o.observedAt,
      first_name: o.firstName ?? null,
      last_name: o.lastName ?? null,
      company: o.company ?? null,
      position: o.position ?? null,
      raw_url: o.rawURL ?? "",
      raw_row_hash: o.rawRowHash ?? "",
    }));
    const res = await supabase.from("linkedin_profile_observation").upsert(rows, { onConflict: "id" });
    throwIfError(res.error, "upsert linkedin_profile_observation");
  }

  // 6. Roll up the connection count + imported_at onto the account.
  const updateAccount = await supabase
    .from("linkup_account")
    .update({
      linkedin_connected: true,
      linkedin_connection_count: connections.length,
      linkedin_imported_at: body.importRecord.importedAt,
    })
    .eq("id", accountID);
  throwIfError(updateAccount.error, "roll up linkup_account counts");

  return {
    ok: true,
    persisted: {
      profiles: profiles.length,
      connections: connections.length,
      observations: observations.length,
    },
  };
}

// ---------------------------------------------------------------------------
// Live presence (real-time discovery)
// ---------------------------------------------------------------------------

async function upsertPresence(body: PresenceUpsertRequest) {
  if (!body.accountID || !isUUID(body.accountID)) {
    throw new HTTPError("accountID (UUID) is required", 400);
  }
  if (!body.eventName || !body.eventName.trim()) {
    throw new HTTPError("eventName is required", 400);
  }
  if (!body.expiresAt) {
    throw new HTTPError("expiresAt is required", 400);
  }

  const supabase = serviceClient();

  // The account row must exist (FK). Insert-if-absent without clobbering identity.
  const ensure = await supabase
    .from("linkup_account")
    .upsert({ id: body.accountID }, { onConflict: "id", ignoreDuplicates: true });
  throwIfError(ensure.error, "ensure linkup_account for presence");

  const row = {
    account_id: body.accountID,
    display_name: (body.displayName ?? "").trim(),
    headline: (body.headline ?? "").trim(),
    linkedin_slug: body.linkedInSlug ? body.linkedInSlug.toLowerCase() : null,
    linkedin_url: body.linkedInURL ?? null,
    event_name: body.eventName.trim(),
    event_name_key: normalizeKey(body.eventName),
    map_x: clamp01(body.mapX ?? 0.5),
    map_y: clamp01(body.mapY ?? 0.5),
    // Real GPS coordinates (PRD §6). Reject out-of-range values rather than
    // clamping — a -91 lat would be a client bug, not a near-miss.
    lat: rangedOrNull(body.latitude, -90, 90),
    lng: rangedOrNull(body.longitude, -180, 180),
    accuracy_m: body.accuracyMeters != null && body.accuracyMeters >= 0
      ? body.accuracyMeters
      : null,
    started_at: isoNow(),
    expires_at: body.expiresAt,
  };

  const res = await supabase.from("live_presence").upsert(row, { onConflict: "account_id" });
  throwIfError(res.error, "upsert live_presence");
  return { ok: true };
}

async function stopPresence(body: PresenceStopRequest) {
  if (!body.accountID || !isUUID(body.accountID)) {
    throw new HTTPError("accountID (UUID) is required", 400);
  }
  const supabase = serviceClient();
  const res = await supabase.from("live_presence").delete().eq("account_id", body.accountID);
  throwIfError(res.error, "delete live_presence");
  return { ok: true };
}

type LivePresenceRow = {
  account_id: string;
  display_name: string;
  headline: string;
  linkedin_slug: string | null;
  linkedin_url: string | null;
  event_name: string;
  map_x: number;
  map_y: number;
  started_at: string;
  expires_at: string;
};

type ConnectionRow = {
  connection_profile_id: string;
  first_name: string | null;
  last_name: string | null;
};

async function nearbyPresence(body: PresenceNearbyRequest) {
  if (!body.accountID || !isUUID(body.accountID)) {
    throw new HTTPError("accountID (UUID) is required", 400);
  }
  if (!body.eventName || !body.eventName.trim()) {
    throw new HTTPError("eventName is required", 400);
  }

  const supabase = serviceClient();
  const eventKey = normalizeKey(body.eventName);
  const nowISO = isoNow();

  // 1. Everyone live at this event right now, except me.
  const presenceRes = await supabase
    .from("live_presence")
    .select("*")
    .eq("event_name_key", eventKey)
    .gt("expires_at", nowISO)
    .neq("account_id", body.accountID);
  throwIfError(presenceRes.error, "select live_presence nearby");
  const candidates = (presenceRes.data ?? []) as LivePresenceRow[];
  if (candidates.length === 0) {
    return { presences: [] };
  }

  // 2. My connection list — used to decide which candidates I'm allowed to see.
  const connRes = await supabase
    .from("linkedin_connection")
    .select("connection_profile_id, first_name, last_name")
    .eq("account_id", body.accountID);
  throwIfError(connRes.error, "select linkedin_connection for matching");
  const myConnections = (connRes.data ?? []) as ConnectionRow[];

  const slugSet = new Set<string>();
  const nameSet = new Set<string>();
  for (const c of myConnections) {
    const slug = slugFromProfileID(c.connection_profile_id);
    if (slug) slugSet.add(slug);
    const name = normalizeKey(`${c.first_name ?? ""} ${c.last_name ?? ""}`);
    if (name) nameSet.add(name);
  }

  // 3. A candidate is visible if they're one of my connections — matched by
  //    their own LinkedIn slug, or (fallback) by normalized display name.
  const matched = candidates.filter((p) => {
    const slugMatch = p.linkedin_slug ? slugSet.has(p.linkedin_slug.toLowerCase()) : false;
    const nameMatch = nameSet.has(normalizeKey(p.display_name));
    return slugMatch || nameMatch;
  });

  return {
    presences: matched.map((p) => ({
      accountID: p.account_id,
      displayName: p.display_name,
      headline: p.headline,
      linkedInSlug: p.linkedin_slug,
      linkedInURL: p.linkedin_url,
      eventName: p.event_name,
      mapX: p.map_x,
      mapY: p.map_y,
      startedAt: p.started_at,
      expiresAt: p.expires_at,
    })),
  };
}

// "linkedin:in:some-slug" -> "some-slug". Returns null for non-slug profile ids.
function slugFromProfileID(profileID: string | null): string | null {
  if (!profileID) return null;
  const prefix = "linkedin:in:";
  if (profileID.toLowerCase().startsWith(prefix)) {
    return profileID.slice(prefix.length).toLowerCase();
  }
  return null;
}

// Lowercase, trim, collapse internal whitespace — used for event + name matching.
function normalizeKey(value: string): string {
  return value.trim().toLowerCase().replace(/\s+/g, " ");
}

function clamp01(value: number): number {
  if (Number.isNaN(value)) return 0.5;
  return Math.max(0, Math.min(1, value));
}

// Returns the value if it's a finite number inside [min, max], else null. Used
// for lat/lng/accuracy where an out-of-range value should be dropped rather
// than silently clamped to a misleading coordinate.
function rangedOrNull(value: number | null | undefined, min: number, max: number): number | null {
  if (value == null) return null;
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  if (value < min || value > max) return null;
  return value;
}

// ---------------------------------------------------------------------------
// Messaging (real cross-device DMs)
// ---------------------------------------------------------------------------

type ChatMessageRow = {
  id: string;
  thread_id: string;
  sender_account_id: string;
  recipient_account_id: string;
  body: string;
  sent_at: string;
  delivered_at: string | null;
  read_at: string | null;
};

function threadID(a: string, b: string): string {
  const aLow = a.toLowerCase();
  const bLow = b.toLowerCase();
  return aLow < bLow ? `${aLow}:${bLow}` : `${bLow}:${aLow}`;
}

function toChatMessageDTO(row: ChatMessageRow) {
  return {
    id: row.id,
    threadID: row.thread_id,
    senderAccountID: row.sender_account_id,
    recipientAccountID: row.recipient_account_id,
    body: row.body,
    sentAt: row.sent_at,
    deliveredAt: row.delivered_at,
    readAt: row.read_at,
  };
}

async function sendMessage(body: MessageSendRequest) {
  if (!body.senderAccountID || !isUUID(body.senderAccountID)) {
    throw new HTTPError("senderAccountID (UUID) is required", 400);
  }
  if (!body.recipientAccountID || !isUUID(body.recipientAccountID)) {
    throw new HTTPError("recipientAccountID (UUID) is required", 400);
  }
  if (body.senderAccountID === body.recipientAccountID) {
    throw new HTTPError("sender and recipient must differ", 400);
  }
  const text = (body.body ?? "").trim();
  if (!text) {
    throw new HTTPError("body is required", 400);
  }
  if (text.length > 4000) {
    throw new HTTPError("body exceeds 4000 characters", 400);
  }

  const supabase = serviceClient();
  const row = {
    thread_id: threadID(body.senderAccountID, body.recipientAccountID),
    sender_account_id: body.senderAccountID,
    recipient_account_id: body.recipientAccountID,
    body: text,
    // sent_at + delivered_at come from server defaults / trigger.
  };

  const res = await supabase.from("chat_message").insert(row).select("*").single();
  throwIfError(res.error, "insert chat_message");
  return { message: toChatMessageDTO(res.data as ChatMessageRow) };
}

async function pollMessages(body: MessagePollRequest) {
  if (!body.accountID || !isUUID(body.accountID)) {
    throw new HTTPError("accountID (UUID) is required", 400);
  }
  const supabase = serviceClient();
  let query = supabase
    .from("chat_message")
    .select("*")
    .or(`sender_account_id.eq.${body.accountID},recipient_account_id.eq.${body.accountID}`)
    .order("sent_at", { ascending: false })
    .limit(200);
  if (body.sinceISO) {
    query = query.gt("sent_at", body.sinceISO);
  }
  const res = await query;
  throwIfError(res.error, "select chat_message poll");
  const rows = (res.data ?? []) as ChatMessageRow[];
  return { messages: rows.map(toChatMessageDTO) };
}

async function listThreads(body: MessageThreadsRequest) {
  if (!body.accountID || !isUUID(body.accountID)) {
    throw new HTTPError("accountID (UUID) is required", 400);
  }
  const supabase = serviceClient();
  // Pull recent messages, then aggregate client-side in TS. 1000 covers any
  // reasonable Linkup user's history; switch to a SQL view if it ever grows.
  const res = await supabase
    .from("chat_message")
    .select("*")
    .or(`sender_account_id.eq.${body.accountID},recipient_account_id.eq.${body.accountID}`)
    .order("sent_at", { ascending: false })
    .limit(1000);
  throwIfError(res.error, "select chat_message threads");
  const rows = (res.data ?? []) as ChatMessageRow[];

  const byThread = new Map<string, {
    threadID: string;
    otherAccountID: string;
    lastBody: string;
    lastSentAt: string;
    lastSenderAccountID: string;
    unreadCount: number;
  }>();
  for (const r of rows) {
    if (byThread.has(r.thread_id)) {
      const t = byThread.get(r.thread_id)!;
      if (r.recipient_account_id === body.accountID && !r.read_at) {
        t.unreadCount += 1;
      }
      continue; // first row per thread is newest (rows are DESC sorted)
    }
    const other = r.sender_account_id === body.accountID
      ? r.recipient_account_id
      : r.sender_account_id;
    byThread.set(r.thread_id, {
      threadID: r.thread_id,
      otherAccountID: other,
      lastBody: r.body,
      lastSentAt: r.sent_at,
      lastSenderAccountID: r.sender_account_id,
      unreadCount: r.recipient_account_id === body.accountID && !r.read_at ? 1 : 0,
    });
  }

  return { threads: Array.from(byThread.values()) };
}

// ---------------------------------------------------------------------------
// Message deletion (single message or whole-thread-from-my-side)
// ---------------------------------------------------------------------------
//
// Two modes, distinguished by which optional fields are present:
//
//   { messageID, accountID }            — delete one row. The caller must be
//                                          the SENDER of that row. Recipients
//                                          can't delete content they didn't
//                                          author. 404 if the row doesn't
//                                          exist or sender doesn't match.
//
//   { accountID, otherAccountID }       — "delete the chat on my side": remove
//                                          every row in the canonical thread
//                                          whose sender is accountID. The
//                                          counterparty's outbound messages
//                                          stay (they own those rows). The
//                                          response notes this behavior.

async function deleteMessages(body: MessageDeleteRequest) {
  if (!body.accountID || !isUUID(body.accountID)) {
    throw new HTTPError("accountID (UUID) is required", 400);
  }

  const supabase = serviceClient();

  if (body.messageID) {
    if (!isUUID(body.messageID)) {
      throw new HTTPError("messageID must be a UUID", 400);
    }
    // Confirm the row exists AND that the caller is the sender. We do this in
    // two steps so we can return a tidy 404 / 403 rather than a silent zero-
    // row delete.
    const lookup = await supabase
      .from("chat_message")
      .select("id, sender_account_id")
      .eq("id", body.messageID)
      .maybeSingle();
    throwIfError(lookup.error, "lookup chat_message for delete");
    if (!lookup.data) {
      throw new HTTPError("message not found", 404);
    }
    if ((lookup.data as { sender_account_id: string }).sender_account_id !== body.accountID) {
      throw new HTTPError("only the sender can delete a message", 403);
    }
    const res = await supabase.from("chat_message").delete().eq("id", body.messageID);
    throwIfError(res.error, "delete chat_message single");
    return { ok: true, deleted: 1 };
  }

  if (body.otherAccountID) {
    if (!isUUID(body.otherAccountID)) {
      throw new HTTPError("otherAccountID must be a UUID", 400);
    }
    if (body.otherAccountID === body.accountID) {
      throw new HTTPError("accountID and otherAccountID must differ", 400);
    }
    const thread = threadID(body.accountID, body.otherAccountID);
    // One-sided thread delete: only the caller's own outbound messages go.
    // The other person's messages remain (they own those rows).
    const res = await supabase
      .from("chat_message")
      .delete({ count: "exact" })
      .eq("thread_id", thread)
      .eq("sender_account_id", body.accountID);
    throwIfError(res.error, "delete chat_message thread");
    return {
      ok: true,
      deleted: res.count ?? 0,
      note: "only messages sent by accountID were removed; counterparty messages remain",
    };
  }

  throw new HTTPError("provide messageID or otherAccountID", 400);
}

// ---------------------------------------------------------------------------
// Account deletion (Apple App Store §5.1.1(v))
// ---------------------------------------------------------------------------
//
// Wipes every row keyed to the account plus the auth.users row. Deletes are
// done explicitly (in FK-safe order) so the endpoint is correct regardless of
// whether each FK was declared with ON DELETE CASCADE. The auth.admin.deleteUser
// call at the end is best-effort: if the user is already gone we succeed.

async function deleteAccount(body: AccountDeleteRequest) {
  if (!body.accountID || !isUUID(body.accountID)) {
    throw new HTTPError("accountID (UUID) is required", 400);
  }

  const supabase = serviceClient();
  const accountID = body.accountID;

  // Resolve the auth user id BEFORE we delete the linkup_account row. Per
  // migration 0005 the two ids are normally equal, but we read auth_user_id
  // first in case the deployment used the divergent path.
  let authUserID: string = accountID;
  try {
    const lookup = await supabase
      .from("linkup_account")
      .select("auth_user_id")
      .eq("id", accountID)
      .maybeSingle();
    if (lookup.data && (lookup.data as { auth_user_id: string | null }).auth_user_id) {
      authUserID = (lookup.data as { auth_user_id: string }).auth_user_id;
    }
  } catch (error) {
    console.error("[linkedin-oauth] account-delete auth_user_id lookup failed (non-fatal)", {
      message: error instanceof Error ? error.message : String(error),
    });
  }

  // 1. chat_message — both directions.
  const msgRes = await supabase
    .from("chat_message")
    .delete({ count: "exact" })
    .or(`sender_account_id.eq.${accountID},recipient_account_id.eq.${accountID}`);
  throwIfError(msgRes.error, "delete chat_message for account");
  const messages = msgRes.count ?? 0;

  // 2. live_presence.
  const presRes = await supabase
    .from("live_presence")
    .delete({ count: "exact" })
    .eq("account_id", accountID);
  throwIfError(presRes.error, "delete live_presence for account");
  const presence = presRes.count ?? 0;

  // 3. linkedin_profile_observation.
  const obsRes = await supabase
    .from("linkedin_profile_observation")
    .delete({ count: "exact" })
    .eq("account_id", accountID);
  throwIfError(obsRes.error, "delete linkedin_profile_observation for account");
  const observations = obsRes.count ?? 0;

  // 4. linkedin_connection.
  const connRes = await supabase
    .from("linkedin_connection")
    .delete({ count: "exact" })
    .eq("account_id", accountID);
  throwIfError(connRes.error, "delete linkedin_connection for account");
  const connections = connRes.count ?? 0;

  // 5. linkedin_profile.
  const profRes = await supabase
    .from("linkedin_profile")
    .delete({ count: "exact" })
    .eq("account_id", accountID);
  throwIfError(profRes.error, "delete linkedin_profile for account");
  const profiles = profRes.count ?? 0;

  // 6. linkedin_import_record.
  const impRes = await supabase
    .from("linkedin_import_record")
    .delete({ count: "exact" })
    .eq("account_id", accountID);
  throwIfError(impRes.error, "delete linkedin_import_record for account");
  const imports = impRes.count ?? 0;

  // 7. linkup_account itself.
  const acctRes = await supabase
    .from("linkup_account")
    .delete({ count: "exact" })
    .eq("id", accountID);
  throwIfError(acctRes.error, "delete linkup_account");
  const account = acctRes.count ?? 0;

  // 8. Supabase Auth user. Best-effort — if the user is already gone (or auth
  //    isn't wired yet) we succeed silently. Apple just needs the data gone.
  try {
    const auth = (supabase as unknown as {
      auth: { admin: { deleteUser: (id: string) => Promise<{ error: { message: string } | null }> } };
    }).auth;
    const res = await auth.admin.deleteUser(authUserID);
    if (res.error && !/not.found|user.not.found/i.test(res.error.message)) {
      console.error("[linkedin-oauth] auth.admin.deleteUser non-fatal error", {
        message: res.error.message,
      });
    }
  } catch (error) {
    console.error("[linkedin-oauth] auth.admin.deleteUser threw (non-fatal)", {
      message: error instanceof Error ? error.message : String(error),
    });
  }

  return {
    ok: true,
    deleted: {
      messages,
      presence,
      observations,
      connections,
      profiles,
      imports,
      account,
    },
  };
}

// ---------------------------------------------------------------------------
// Archive upload (server-side CSV parse — port of LinkedInNetworkImportService)
// ---------------------------------------------------------------------------

type ParsedCSVRow = {
  firstName: string;
  lastName: string;
  url: string;
  emailAddress: string;
  company: string;
  position: string;
  connectedOn: string;
};

async function uploadArchive(request: Request) {
  const url = new URL(request.url);
  const accountID = url.searchParams.get("accountID") ?? "";
  if (!accountID || !isUUID(accountID)) {
    throw new HTTPError("accountID (UUID) query param is required", 400);
  }

  let csvText: string;
  const contentType = request.headers.get("content-type") ?? "";
  if (contentType.toLowerCase().includes("multipart/form-data")) {
    const form = await request.formData();
    const file = form.get("file");
    if (!file || typeof file === "string") {
      throw new HTTPError("multipart form must include a 'file' field", 400);
    }
    csvText = await (file as File).text();
  } else {
    csvText = await request.text();
  }
  if (!csvText) {
    throw new HTTPError("empty body — provide the Connections.csv contents", 400);
  }

  const rows = parseConnectionsCSV(csvText);
  const importedAt = isoNow();
  const importID = crypto.randomUUID();
  const fileHash = await sha256Hex(csvText);

  const profiles: SyncProfile[] = [];
  const connections: SyncConnection[] = [];
  const observations: SyncObservation[] = [];
  const seenProfileIDs = new Set<string>();

  for (const r of rows) {
    const { profileID, slug, normalizedURL } = deriveProfileIdentity(r.url, r.firstName, r.lastName);
    if (!profileID) continue;

    if (!seenProfileIDs.has(profileID)) {
      seenProfileIDs.add(profileID);
      profiles.push({
        id: profileID,
        normalizedURL,
        slug,
        firstName: r.firstName || null,
        lastName: r.lastName || null,
        company: r.company || null,
        position: r.position || null,
      });
    }

    connections.push({
      id: crypto.randomUUID(),
      accountID,
      connectionProfileID: profileID,
      importID,
      verificationState: "imported",
      confidenceScore: 0.8,
      fieldMask: {
        hasFirstName: !!r.firstName,
        hasLastName: !!r.lastName,
        hasCompany: !!r.company,
        hasPosition: !!r.position,
        hasEmail: !!r.emailAddress,
        hasConnectedOn: !!r.connectedOn,
      },
      firstName: r.firstName,
      lastName: r.lastName,
      profileURL: normalizedURL || r.url,
      emailHash: r.emailAddress ? await sha256Hex(r.emailAddress.toLowerCase()) : null,
      company: r.company || null,
      position: r.position || null,
      connectedOn: parseConnectedOn(r.connectedOn),
      importedAt,
    });

    observations.push({
      id: crypto.randomUUID(),
      profileID,
      importID,
      source: "linkedin_archive",
      observedAt: importedAt,
      firstName: r.firstName || null,
      lastName: r.lastName || null,
      company: r.company || null,
      position: r.position || null,
      rawURL: r.url,
      rawRowHash: await sha256Hex(JSON.stringify(r)),
    });
  }

  const syncResult = await syncArchive({
    accountID,
    importRecord: {
      id: importID,
      accountID,
      source: "linkedin_archive",
      importedAt,
      rowCount: rows.length,
      fileHash,
    },
    profiles,
    connections,
    profileObservations: observations,
  });

  return { ok: true, parsedRows: rows.length, ...syncResult };
}

// CSV parser — port of LinkedInNetworkImportService.swift.
// Handles: UTF-8 BOM, the LinkedIn "Notes:" preamble, CRLF/LF, quoted commas,
// escaped double-quotes (""). Headers are matched case-insensitively against
// the known LinkedIn export column names.
function parseConnectionsCSV(text: string): ParsedCSVRow[] {
  let body = text;
  if (body.charCodeAt(0) === 0xfeff) body = body.slice(1); // strip BOM
  body = body.replace(/\r\n/g, "\n");

  // Skip the "Notes:" preamble: walk lines until we hit one starting with
  // "First Name" (case-insensitively) or one that looks like a CSV header.
  const lines = body.split("\n");
  let headerIdx = -1;
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i].trim();
    if (!l) continue;
    if (/^"?first name"?,/i.test(l)) {
      headerIdx = i;
      break;
    }
  }
  if (headerIdx < 0) return [];

  const headerCells = splitCSVLine(lines[headerIdx]).map((c) => c.trim().toLowerCase());
  const idx = {
    firstName: headerCells.indexOf("first name"),
    lastName: headerCells.indexOf("last name"),
    url: headerCells.indexOf("url"),
    emailAddress: headerCells.indexOf("email address"),
    company: headerCells.indexOf("company"),
    position: headerCells.indexOf("position"),
    connectedOn: headerCells.indexOf("connected on"),
  };

  const out: ParsedCSVRow[] = [];
  // Re-join the rest into a single string and re-parse line-by-line, because
  // quoted fields may legitimately contain newlines.
  const rest = lines.slice(headerIdx + 1).join("\n");
  const records = splitCSVRecords(rest);
  for (const rec of records) {
    if (rec.length === 1 && rec[0].trim() === "") continue;
    out.push({
      firstName: idx.firstName >= 0 ? (rec[idx.firstName] ?? "").trim() : "",
      lastName: idx.lastName >= 0 ? (rec[idx.lastName] ?? "").trim() : "",
      url: idx.url >= 0 ? (rec[idx.url] ?? "").trim() : "",
      emailAddress: idx.emailAddress >= 0 ? (rec[idx.emailAddress] ?? "").trim() : "",
      company: idx.company >= 0 ? (rec[idx.company] ?? "").trim() : "",
      position: idx.position >= 0 ? (rec[idx.position] ?? "").trim() : "",
      connectedOn: idx.connectedOn >= 0 ? (rec[idx.connectedOn] ?? "").trim() : "",
    });
  }
  return out;
}

function splitCSVLine(line: string): string[] {
  return splitCSVRecords(line)[0] ?? [];
}

// Tokenises a CSV blob into records (rows), each an array of cells. Handles
// quoted fields with embedded newlines, commas, and "" escape sequences.
function splitCSVRecords(text: string): string[][] {
  const records: string[][] = [];
  let cur: string[] = [];
  let cell = "";
  let inQuotes = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') {
          cell += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        cell += ch;
      }
    } else {
      if (ch === '"') {
        inQuotes = true;
      } else if (ch === ",") {
        cur.push(cell);
        cell = "";
      } else if (ch === "\n") {
        cur.push(cell);
        records.push(cur);
        cur = [];
        cell = "";
      } else {
        cell += ch;
      }
    }
  }
  if (cell.length > 0 || cur.length > 0) {
    cur.push(cell);
    records.push(cur);
  }
  return records;
}

function deriveProfileIdentity(rawURL: string, firstName: string, lastName: string) {
  const url = (rawURL || "").trim();
  let slug: string | null = null;
  let normalizedURL = "";
  if (url) {
    // Match "/in/<slug>" anywhere in the URL.
    const m = url.match(/linkedin\.com\/in\/([^\/?#]+)/i);
    if (m) {
      slug = m[1].toLowerCase().replace(/\/+$/, "");
      normalizedURL = `https://www.linkedin.com/in/${slug}`;
    } else {
      normalizedURL = url;
    }
  }
  let profileID: string | null = null;
  if (slug) {
    profileID = `linkedin:in:${slug}`;
  } else if (firstName || lastName) {
    const synthetic = `${firstName} ${lastName}`.trim().toLowerCase().replace(/\s+/g, "-");
    if (synthetic) profileID = `linkedin:name:${synthetic}`;
  }
  return { profileID, slug, normalizedURL };
}

function parseConnectedOn(raw: string): string | null {
  if (!raw) return null;
  // LinkedIn exports "DD MMM YYYY" (e.g. "11 Apr 2026"). Try parsing.
  const months: Record<string, number> = {
    jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5,
    jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11,
  };
  const m = raw.trim().match(/^(\d{1,2})\s+([A-Za-z]{3,})\s+(\d{4})$/);
  if (m) {
    const day = parseInt(m[1], 10);
    const month = months[m[2].slice(0, 3).toLowerCase()];
    const year = parseInt(m[3], 10);
    if (!isNaN(day) && month !== undefined && !isNaN(year)) {
      return new Date(Date.UTC(year, month, day)).toISOString().replace(/\.\d{3}Z$/, "Z");
    }
  }
  // Fallback: let Date try.
  const d = new Date(raw);
  if (!isNaN(d.getTime())) return d.toISOString().replace(/\.\d{3}Z$/, "Z");
  return null;
}

// ---------------------------------------------------------------------------
// LinkedIn API helpers
// ---------------------------------------------------------------------------

async function exchangeAuthorizationCode(code: string, redirectURI: string, codeVerifier: string) {
  const params = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: redirectURI,
    client_id: requiredEnv("LINKEDIN_CLIENT_ID"),
    client_secret: requiredEnv("LINKEDIN_CLIENT_SECRET"),
    code_verifier: codeVerifier,
  });

  const response = await fetch(linkedInTokenURL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: params,
  });
  const text = await response.text();
  if (!response.ok) {
    console.error("[linkedin-oauth] token exchange failed", { status: response.status, body: text });
    throw new HTTPError(`LinkedIn token exchange failed: ${text}`, response.status);
  }

  const payload = JSON.parse(text) as { access_token?: string };
  if (!payload.access_token) {
    console.error("[linkedin-oauth] token exchange returned no access_token", { body: text });
    throw new HTTPError("LinkedIn did not return an access token", 502);
  }
  return payload.access_token;
}

async function fetchUserInfo(accessToken: string) {
  const response = await fetch(linkedInUserInfoURL, {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  const text = await response.text();
  if (!response.ok) {
    console.error("[linkedin-oauth] userinfo failed", { status: response.status, body: text });
    throw new HTTPError(`LinkedIn userinfo request failed: ${text}`, response.status);
  }
  return JSON.parse(text) as LinkedInUserInfo;
}

async function toImportPayload(accountID: string, member: LinkedInUserInfo) {
  const importedAt = isoNow();
  const importID = crypto.randomUUID();
  return {
    member: {
      subject: member.sub,
      name: member.name ?? null,
      givenName: member.given_name ?? null,
      familyName: member.family_name ?? null,
      email: member.email ?? null,
      picture: member.picture ?? null,
      profileURL: null,
      profileSlug: null,
      verifiedAt: importedAt,
    },
    importRecord: {
      id: importID,
      accountID,
      // Matches LinkedInImportSource.linkedinAPI in iOS. This endpoint only
      // verifies identity; connection rows still come from the CSV archive.
      source: "linkedin_api",
      importedAt,
      rowCount: 0,
      fileHash: await sha256Hex(`${member.sub}:${importedAt}`),
    },
    // Profiles / connections come from the CSV archive flow, not this endpoint.
    profiles: [],
    connections: [],
    profileObservations: [],
  };
}

// ---------------------------------------------------------------------------
// Supabase service client
// ---------------------------------------------------------------------------

let cachedClient: SupabaseClient | null = null;

function serviceClient(): SupabaseClient {
  if (cachedClient) return cachedClient;
  const supabaseURL = requiredEnv("SUPABASE_URL");
  const serviceRoleKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
  cachedClient = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return cachedClient;
}

function throwIfError(error: { message: string } | null, context: string) {
  if (error) {
    throw new HTTPError(`${context}: ${error.message}`, 500);
  }
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

async function readJSON<T>(request: Request): Promise<T> {
  try {
    return (await request.json()) as T;
  } catch {
    throw new HTTPError("Request body must be valid JSON", 400);
  }
}

const uuidPattern =
  /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

function isUUID(value: string): boolean {
  return uuidPattern.test(value);
}

async function sha256Hex(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function isoNow() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) {
    throw new HTTPError(`${name} is required`, 500);
  }
  return value;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

class HTTPError extends Error {
  constructor(message: string, public status: number) {
    super(message);
  }
}
