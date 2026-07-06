# VS Contract Reviewer

Versus Studio's internal tool for intake, AI-powered review, and institutional
storage of MSAs, SOWs, and related contracts. Built from
`VS-Contract-Reviewer-Project-Brief.docx` (July 2026).

## Stack

Next.js 14 (App Router) · Firebase Auth + Firestore · Firebase Hosting ·
Google Drive API · Gmail API · Anthropic Claude API (`claude-sonnet-4-6`).

## Local setup

```bash
npm install
cp .env.local.example .env.local
# fill in GOOGLE_CLIENT_SECRET, GOOGLE_DOCO_REFRESH_TOKEN, ANTHROPIC_API_KEY,
# and the FIREBASE_ADMIN_* service-account values — none of these are
# committed, and .env.local is gitignored.
npm run dev
```

### Getting the values `.env.local.example` doesn't include

- **Firebase Admin service account** — Firebase Console → Project settings →
  Service accounts → Generate new private key. Use its `client_email` and
  `private_key` for `FIREBASE_ADMIN_CLIENT_EMAIL` / `FIREBASE_ADMIN_PRIVATE_KEY`
  (keep the `\n` escapes in the private key as-is).
- **`GOOGLE_DOCO_REFRESH_TOKEN`** — a one-time OAuth consent flow run as
  `doco@vsnyc.tv` against the `vs-contract-drive` Google Cloud project, with
  Drive + Gmail send scopes. Store the resulting refresh token as a secret;
  it's what lets the server send Drive/Gmail requests without a browser
  session.
- **`ANTHROPIC_API_KEY`** — from the Anthropic Console.

## Auth flow

Google sign-in is restricted to `@vsnyc.tv` accounts (checked client-side via
`isAllowedDomainEmail` and again server-side when minting the session cookie
in `/api/auth/session`, since the client check alone isn't a trust boundary).
On first sign-in a `users/{uid}` doc is created with `role: "reviewer"`.
Promote admins manually in the Firestore console — the brief specifies this
as a deliberate manual step, not a self-service one.

Route protection is layered:
1. `src/middleware.ts` redirects to `/login` if there's no session cookie at
   all, for `/`, `/library`, `/settings`.
2. Admin-only routes (`/library`, `/settings`) additionally check `role` via
   `AuthGuard` client-side (hides the UI entirely — not just disables it) and
   should be paired with a server-side `requireAdmin()` check
   (`src/lib/firebase/session.ts`) in any data-fetching you add to those
   pages, since Firestore security rules are the real enforcement boundary
   (`firestore.rules`).

## Data model

See `src/lib/types.ts` for the full TypeScript mirror of the Firestore schema
(`users`, `clients`, `contracts`, `contracts/{id}/versions`,
`.../issueThreads`) and `firestore.rules` for security rules — both transcribed
directly from the project brief §6 and §8.

## The eight standing concerns

Defined once in `src/lib/types.ts` (`EIGHT_CONCERNS`) and consumed by the
prompt builder in `src/lib/claude/prompts.ts`, so the concern list and the
prompt can't drift apart.

## Deployment

```bash
npm install -g firebase-tools
firebase experiments:enable webframeworks
firebase login                 # as kathryn@vsnyc.tv
firebase init hosting          # select vs-contracts, detect Next.js
firebase functions:secrets:set GOOGLE_CLIENT_SECRET
firebase functions:secrets:set ANTHROPIC_API_KEY
firebase functions:secrets:set GOOGLE_DOCO_REFRESH_TOKEN
firebase deploy
```

Confirm `vs-contracts.web.app` is in Firebase Console → Authentication →
Settings → Authorized domains after the first deploy.

### Post-deploy checklist (brief §10)

- Visit `vs-contracts.web.app` → should redirect to `/login`.
- Sign in with `kathryn@vsnyc.tv` → should land on the reviewer view.
- In the Firestore console, set `users/{uid}.role = "admin"` for yourself.
- Upload a real contract → confirm a Drive folder is created under
  `Contract Reviews/{Client}/{Project (Number)}/` and the file lands there.
- Run a full review and confirm findings render against the eight concerns.
- Verify the email notification fires once `NOTIFY_EMAIL_SECONDARY` is
  uncommented for `samantha@vsnyc.tv`.
- Visit `/library` and confirm the client you just created appears.

## What's stubbed vs. real

Everything is real, working code against the documented APIs — but a few
things need production wiring before they're load-bearing:

- **Drive OAuth refresh token** — needs the one-time consent flow described
  above; there's no interactive "connect Drive" UI in v1 per the brief.
- **Client library merge** (Settings → "Merge & delete duplicate") — the UI
  is in place; the actual reassignment should run through a Cloud Function
  for atomicity rather than client-side batched writes, noted inline in
  `ClientLibraryManagement.tsx`.
- **Governing-MSA standing-positions panel** and **version delta summaries**
  — the UI slots exist (`ClientDetailView`, `deltaFromPrevious` field) but
  the extraction step itself is Phase 2 (brief §11).

## Phase 2 (brief §11, not built)

Asana task creation on review complete · Claude-drafted version-to-version
delta summaries · governing-MSA standing-position extraction and reuse ·
custom domain (`contracts.vsnyc.tv`) · PDF export of the report · mobile/
tablet responsive pass.
