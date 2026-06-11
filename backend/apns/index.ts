// Linkup APNs Edge Function — production push sender.
//
// Routes (all POST):
//   /apns/send             body { deviceToken, title, body, payload? }
//   /apns/message          legacy compatibility — body { deviceToken, eventName?, message?, senderName?, muted? }
//   /apns/share-expiring   legacy compatibility — body { deviceToken, eventName? }
//   /apns/share-expired    legacy compatibility — body { deviceToken, eventName? }
//   GET /health            -> { ok: true }
//   GET /version           -> { version: BUILD_VERSION }
//
// Signs a short-lived ES256 JWT per request and POSTs the alert to Apple's
// HTTP/2 endpoint. Environment:
//   APNS_KEY_ID         — Apple APNs key id (the .p8 filename minus prefix/suffix)
//   APNS_TEAM_ID        — Apple Developer Team id
//   APNS_PRIVATE_KEY    — PEM contents of the .p8 file (BEGIN/END PRIVATE KEY)
//   APNS_TOPIC          — iOS bundle id (default: com.linkup.app)
//   APNS_ENVIRONMENT    — "sandbox" | "production" (default: production)
//
// JWTs are cached in-memory for ~50 minutes (Apple rejects tokens > 1h old).

const BUILD_VERSION = "linkup-apns@2026-06-09-v1";

const encoder = new TextEncoder();

type SendRequest = {
  deviceToken: string;
  title: string;
  body: string;
  payload?: Record<string, unknown>;
};

type LegacyMessageRequest = {
  deviceToken: string;
  eventName?: string;
  message?: string;
  senderName?: string;
  muted?: boolean;
};

type LegacyShareRequest = {
  deviceToken: string;
  eventName?: string;
};

// Supabase serves this function at /functions/v1/apns/<route>, and the worker
// sees the function name as the first pathname segment ("/apns/send"). Some
// callers (the pg_net trigger GUC, legacy clients) also write the route with
// its own "/apns" prefix, producing "/apns/apns/send" once deployed. Strip the
// deployment prefix and up to two "/apns" segments so every spelling routes.
function routePath(rawPathname: string): string {
  let p = rawPathname;
  if (p.startsWith("/functions/v1/")) p = p.slice("/functions/v1".length);
  for (let i = 0; i < 2 && (p === "/apns" || p.startsWith("/apns/")); i++) {
    p = p.slice("/apns".length);
    if (p === "") p = "/";
  }
  return p;
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

  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    if (pathname === "/send") {
      const body = await readJSON<SendRequest>(request);
      return await handleSend(body);
    }
    if (pathname === "/message" || pathname.endsWith("/message")) {
      const body = await readJSON<LegacyMessageRequest>(request);
      return await handleLegacyMessage(body);
    }
    if (pathname === "/share-expiring" || pathname.endsWith("/share-expiring")) {
      const body = await readJSON<LegacyShareRequest>(request);
      return await handleShareExpiring(body);
    }
    if (pathname === "/share-expired" || pathname.endsWith("/share-expired")) {
      const body = await readJSON<LegacyShareRequest>(request);
      return await handleShareExpired(body);
    }
  } catch (error) {
    const status = error instanceof HTTPError ? error.status : 500;
    const message = error instanceof Error ? error.message : "apns request failed";
    console.error("[apns] request failed", { status, message, path: url.pathname });
    return json({ error: message }, status);
  }

  return json({ error: "Unknown endpoint" }, 404);
});

// ---------------------------------------------------------------------------
// Route handlers
// ---------------------------------------------------------------------------

async function handleSend(body: SendRequest) {
  if (!body?.deviceToken) throw new HTTPError("deviceToken is required", 400);
  if (!body?.title) throw new HTTPError("title is required", 400);
  if (!body?.body) throw new HTTPError("body is required", 400);

  return await send(body.deviceToken, {
    aps: {
      alert: { title: body.title, body: body.body.slice(0, 240) },
      sound: "default",
    },
    ...(body.payload ?? {}),
  });
}

async function handleLegacyMessage(body: LegacyMessageRequest) {
  if (!body?.deviceToken) throw new HTTPError("deviceToken is required", 400);
  if (body.muted) {
    return json({ skipped: true, reason: "recipient muted sender" });
  }
  return await send(body.deviceToken, {
    aps: {
      alert: {
        title: body.eventName
          ? `${body.senderName ?? "Someone"} is here at ${body.eventName}`
          : `${body.senderName ?? "Someone"} sent a message`,
        body: (body.message ?? "").slice(0, 140),
      },
      sound: "default",
    },
    type: "message",
    senderName: body.senderName,
    eventName: body.eventName,
    message: body.message,
  });
}

async function handleShareExpiring(body: LegacyShareRequest) {
  if (!body?.deviceToken) throw new HTTPError("deviceToken is required", 400);
  return await send(body.deviceToken, {
    aps: {
      alert: {
        title: "30 minutes left",
        body: `Your location is still live${body.eventName ? ` at ${body.eventName}` : ""}.`,
      },
      sound: "default",
    },
    type: "share_expiring",
    eventName: body.eventName,
  });
}

async function handleShareExpired(body: LegacyShareRequest) {
  if (!body?.deviceToken) throw new HTTPError("deviceToken is required", 400);
  return await send(body.deviceToken, {
    aps: {
      alert: {
        title: "Location no longer live",
        body: `Your location sharing${body.eventName ? ` at ${body.eventName}` : ""} has ended.`,
      },
      sound: "default",
    },
    type: "share_expired",
    eventName: body.eventName,
  });
}

// ---------------------------------------------------------------------------
// APNs HTTP/2 send + JWT
// ---------------------------------------------------------------------------

async function send(deviceToken: string, payload: Record<string, unknown>) {
  const topic = Deno.env.get("APNS_TOPIC") ?? "com.linkup.app";
  const jwt = await apnsJWT();
  const environment = (Deno.env.get("APNS_ENVIRONMENT") ?? "production").toLowerCase();
  const host = environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";

  const response = await fetch(`https://${host}/3/device/${deviceToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  const responseBody = await response.text();
  if (!response.ok) {
    console.error("[apns] push failed", { status: response.status, body: responseBody });
  }
  return json(
    { ok: response.ok, status: response.status, response: responseBody },
    response.ok ? 200 : response.status,
  );
}

// JWTs are valid for up to 1h; cache for 50m to avoid signing per-request.
let cachedJWT: { token: string; expiresAt: number } | null = null;

async function apnsJWT(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJWT && cachedJWT.expiresAt > now + 60) {
    return cachedJWT.token;
  }
  const keyID = requiredEnv("APNS_KEY_ID");
  const teamID = requiredEnv("APNS_TEAM_ID");
  const privateKey = requiredEnv("APNS_PRIVATE_KEY");

  const header = { alg: "ES256", kid: keyID };
  const claims = { iss: teamID, iat: now };
  const signingInput = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(claims))}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(signingInput),
  );
  const token = `${signingInput}.${base64url(new Uint8Array(signature))}`;
  cachedJWT = { token, expiresAt: now + 50 * 60 };
  return token;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  return Uint8Array.from(atob(base64), (ch) => ch.charCodeAt(0)).buffer;
}

function base64url(value: string | Uint8Array): string {
  const bytes = typeof value === "string" ? encoder.encode(value) : value;
  let binary = "";
  bytes.forEach((byte) => {
    binary += String.fromCharCode(byte);
  });
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
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

function requiredEnv(name: string): string {
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
