type PushRequest = {
  deviceToken: string;
  eventName?: string;
  message?: string;
  senderName?: string;
  muted?: boolean;
};

const encoder = new TextEncoder();

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const url = new URL(request.url);
  const body = await request.json() as PushRequest;

  if (!body.deviceToken) {
    return json({ error: "deviceToken is required" }, 400);
  }

  if (url.pathname.endsWith("/message")) {
    if (body.muted) {
      return json({ skipped: true, reason: "recipient muted sender" });
    }
    return send(body.deviceToken, {
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

  if (url.pathname.endsWith("/share-expiring")) {
    return send(body.deviceToken, {
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

  if (url.pathname.endsWith("/share-expired")) {
    return send(body.deviceToken, {
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

  return json({ error: "Unknown endpoint" }, 404);
});

async function send(deviceToken: string, payload: Record<string, unknown>) {
  const topic = requiredEnv("APNS_BUNDLE_ID");
  const jwt = await apnsJWT();
  const env = Deno.env.get("APNS_ENV") === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";

  const response = await fetch(`https://${env}/3/device/${deviceToken}`, {
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
  return json({ ok: response.ok, status: response.status, response: responseBody }, response.ok ? 200 : response.status);
}

async function apnsJWT() {
  const keyID = requiredEnv("APNS_KEY_ID");
  const teamID = requiredEnv("APNS_TEAM_ID");
  const privateKey = requiredEnv("APNS_PRIVATE_KEY");
  const header = { alg: "ES256", kid: keyID };
  const claims = { iss: teamID, iat: Math.floor(Date.now() / 1000) };
  const signingInput = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(claims))}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(signingInput));
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) {
    throw new Error(`${name} is required`);
  }
  return value;
}

function pemToArrayBuffer(pem: string) {
  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0)).buffer;
}

function base64url(value: string | Uint8Array) {
  const bytes = typeof value === "string" ? encoder.encode(value) : value;
  let binary = "";
  bytes.forEach((byte) => {
    binary += String.fromCharCode(byte);
  });
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}
