<!--
  DRAFT — NOT LEGAL ADVICE.
  This privacy policy was drafted by an engineering agent from the codebase's
  actual data flows. A qualified attorney must review it before Linkup ships
  to the App Store or any production user. Anywhere the document references
  jurisdiction, retention windows, or rights, double-check against your real
  business posture and applicable law (GDPR, CCPA/CPRA, COPPA, etc.).

  Placeholders to fill in before publishing:
    - support@linkup.app  (replace with the real support inbox)
    - Effective date     (currently 2026-06-09)
-->

# Linkup Privacy Policy

**Effective date:** June 9, 2026
**Version:** 1.0

Linkup ("we", "us", "the app") helps you find your LinkedIn 1st-degree
connections at the same conference or event in real time. Privacy is a core
product requirement, not an afterthought — this policy explains exactly what we
collect, why, where it's stored, and how to remove it.

If you have questions or want to exercise any of the rights below, email us at
**support@linkup.app**.

---

## 1. Who this applies to

This policy applies to the Linkup iOS app and the Linkup backend services it
talks to. Linkup is intended for users **age 13 and older**. We do not
knowingly collect data from children under 13. If you believe a child has
created an account, contact us and we will delete it.

---

## 2. What we collect

We only collect what the app needs to do its job. Specifically:

### 2.1 Account information
- **Full name** (you provide this on signup, or it comes from Apple / Google /
  LinkedIn sign-in).
- **Email address** (same sources as above).
- **Password hash** — only if you sign up with email and password. We store a
  one-way hash; we never see or store your plain-text password.
- **Apple subject identifier** — the opaque `sub` claim from Sign in with
  Apple, used to recognize your account on subsequent sign-ins.
- **Google subject identifier** — the equivalent opaque identifier from Sign
  in with Google.
- **Last-signed-in timestamp.**

### 2.2 LinkedIn data (only if you connect LinkedIn)
- Your **LinkedIn member ID**, **public profile URL**, **profile slug**,
  **display name**, **headline**, and **profile picture URL**, retrieved
  through LinkedIn's OpenID Connect flow when you choose "Continue with
  LinkedIn" or use the "Connect with LinkedIn" option in Settings.
- Your **imported 1st-degree LinkedIn connections** — name, public profile
  URL, current company, current position, and a one-way SHA-256 hash of any
  email address LinkedIn includes in the export. Linkup imports this list
  only when you explicitly upload your LinkedIn data export (`Connections.csv`)
  via Settings.

### 2.3 Location
- **Live location (latitude / longitude)** while a share session is active.
  Sharing is opt-in per session, time-boxed (you choose 1–12 hours), and ends
  automatically when the session expires or when you tap "Stop sharing".
- We do **not** collect background location and we do **not** have an
  "always-on" mode.

### 2.4 In-app messages
- **Direct messages** you send to mutual LinkedIn connections inside Linkup —
  message body, sender, recipient, and timestamps.

### 2.5 Device identifiers
- **Apple Push Notification service (APNs) token** for delivering push
  notifications you've opted into.

We do **not** collect: contacts, photos, microphone, camera, advertising
identifiers (IDFA), fingerprinting signals, or any data we do not need to
operate the features described above.

---

## 3. How we use what we collect

| Data | Purpose |
|---|---|
| Name, email, auth identifiers, password hash | Create your account, sign you in, recover your session |
| LinkedIn profile fields | Show your profile in the app, match you to connections by LinkedIn slug |
| Imported LinkedIn connections | Power the core feature — finding which of your 1st-degree connections are at the same event |
| Live location during share sessions | Show you on the map to the 1st-degree connections you've chosen to share with |
| In-app messages | Deliver the message and show conversation history |
| APNs token | Send the push notifications you've enabled in Settings (new message, connection arrival, expiry warning) |
| Last-signed-in timestamp | Operational debugging and detecting stale sessions |

We do **not** sell your data, and we do **not** use it for advertising or
cross-app tracking.

---

## 4. Where your data is stored

All Linkup data is stored in **Supabase** (a managed Postgres service)
operated by Supabase Inc., in their **US** region, under our project named
"Linkup" inside our Supabase organization "Forge AI Advisory". Database
access is enforced via Supabase Row Level Security (RLS) — in production,
each row is only accessible to the authenticated user it belongs to.
Writes from our server-side functions use a service role that is never
exposed to the iOS app.

---

## 5. How long we keep it

| Data | Retention |
|---|---|
| Live location (lat / lng) | Deleted from active presence records when your share session expires (max 12 hours after it starts) |
| Account info, LinkedIn profile, imported connections | Kept until you delete your account or disconnect LinkedIn |
| In-app chat messages | **Retained indefinitely** unless you delete your account. See §7 to delete them earlier. |
| APNs token | Refreshed by iOS automatically; deleted when you sign out or delete the app |
| Backend logs | Standard Supabase platform logs (operational, not analytical) |

---

## 6. Third parties we share with

Linkup uses a small, specific set of third parties — and only for the features
you trigger. We do **not** use analytics SDKs, advertising networks, or
tracking SDKs of any kind.

- **Apple** — when you use *Sign in with Apple*, Apple authenticates you and
  returns an opaque identifier to Linkup. Subject to Apple's privacy policy.
- **Google** — when you use *Sign in with Google*, Google authenticates you
  and returns an identifier and email. Subject to Google's privacy policy.
- **LinkedIn** — when you use *Continue with LinkedIn* or *Connect with
  LinkedIn*, LinkedIn authenticates you and returns the profile fields listed
  in §2.2. Subject to LinkedIn's privacy policy. Connections you import via
  your LinkedIn data export originate from LinkedIn but are uploaded by you
  directly into Linkup.
- **Supabase Inc.** — our backend hosting provider (see §4).
- **Apple Push Notification service (APNs)** — used to deliver push
  notifications.

We do not share your data with any other third party.

---

## 7. Your rights

You can, at any time:

- **Export your data.** Email **support@linkup.app** to request a copy.
- **Delete your account and all associated data.** Email
  **support@linkup.app** or use the in-app delete-account option when
  available. Deletion removes your account row, imported connections,
  messages, and any active share session.
- **Disconnect LinkedIn.** In the app, open *Settings → LinkedIn → Disconnect*.
  This removes your imported connections and unlinks your LinkedIn profile from
  your Linkup account.
- **Sign out.** *Settings → Sign out* clears your local session.
- **Stop sharing immediately.** *Discover tab → Stop sharing* ends any
  active session and removes your location from the server.
- **Manage notifications.** Use iOS Settings or *Linkup Settings →
  Notifications* to control which pushes you receive.

Depending on where you live (e.g., the EU/EEA or California), you may have
additional rights under GDPR, CCPA/CPRA, or similar laws — including the right
to object to or restrict processing, the right to portability, and the right
to lodge a complaint with a supervisory authority. To exercise any of those
rights, email **support@linkup.app**.

---

## 8. Security

- Passwords are never stored in plain text; we store a one-way hash.
- iOS session tokens are stored in the device Keychain.
- Backend access is gated by Supabase RLS and a service-role secret that is
  never shipped inside the iOS app.
- Live location is removed when your share session expires.

No system is perfectly secure, but we design defensively and minimize what we
collect.

---

## 9. Children

Linkup is for users 13 and older. We do not knowingly collect data from
children under 13. If you are a parent or guardian and believe a child has
given us information, contact **support@linkup.app** and we will delete it.

---

## 10. Changes to this policy

We may update this policy as Linkup evolves. When we make a material change
we will update the **Effective date** at the top and notify you in-app or by
email before the change takes effect.

---

## 11. Contact

**Email:** support@linkup.app
