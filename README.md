# ExamPro CBT

ExamPro CBT is a Next.js App Router application foundation for secure online assessments. It includes the public marketing page, Supabase Auth screens, role-protected dashboards, a PostgreSQL migration with RLS, and server-authoritative RPCs for starting, saving and scoring an attempt.

## Stack and architecture

- Next.js App Router and React with TypeScript
- Supabase Auth, PostgreSQL, SSR cookie sessions and Row Level Security
- Zod validation on sensitive attempt endpoints
- SQL functions for atomic attempt creation, answer saving and submission/scoring
- Tailwind CSS v4 setup and responsive custom styling

Server components are the default. Supabase service-role credentials are not used in the browser. Student answers are written through security-definer SQL operations. Correct-answer columns are excluded from authenticated column-level `SELECT` grants.

## Local setup

Requirements: Node.js 20.9 or later and npm. Create a Supabase project, then copy `.env.example` to `.env.local` and set:

```env
NEXT_PUBLIC_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
NEXT_PUBLIC_SITE_URL=http://localhost:3000
SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVER_ONLY_SERVICE_ROLE_KEY
```

The service-role key is used only by the protected timeout-finalization job. `CRON_SECRET` protects that endpoint. Never prefix either secret with `NEXT_PUBLIC_`.

```bash
npm install
npm run dev
```

Open http://localhost:3000. Scripts: `npm run dev`, `npm run build`, `npm run start`, `npm run lint`, `npm run typecheck`, `npm run test`, `npm run test:e2e`.

## Supabase setup

1. Install the Supabase CLI and run `supabase login`.
2. Link the project with `supabase link --project-ref YOUR_PROJECT_REF`.
3. Apply the schema with `supabase db push` (or `npm run db:push`).
4. In Authentication → URL Configuration set the local Site URL to `http://localhost:3000` and add `http://localhost:3000/auth/confirm` and `http://localhost:3000/auth/reset-password` to redirect URLs. Set equivalent production URLs after deployment.
5. Configure email confirmation in Supabase Auth. Registration sets a new account to STUDENT; elevated roles must be granted by a trusted administrator through the database, never from registration metadata.

The initial migration is `supabase/migrations/202610060001_initial_schema.sql`. No production demo credentials are checked into source control. To bootstrap the first administrator, verify an account, then have a trusted project owner set that profile's role to `ADMIN` in the Supabase SQL editor.

## Deployment: Vercel

1. Push the repository to GitHub and import it into Vercel.
2. Set `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` in Vercel project settings. Add the service-role key only if a future server-only admin function requires it.
3. Deploy using the standard Next.js build (`npm run build`).
4. Set `CRON_SECRET` and the Supabase Site URL to the production domain, then add production auth callback/reset URLs. Vercel schedules expired-attempt finalization using `vercel.json`.
5. Verify signup/confirmation, login, role redirects and the assessment operations against the configured database.

## Deployment: AfeesHost Node.js

Use a Linux plan that explicitly supports Node.js application hosting. PHP-only hosting cannot run this application. Configure application root as the repository root, Node.js 20.9+, build command `npm ci && npm run build`, and start command `npm run start`. Set the same server environment variables in the host panel, bind the assigned port as supported by the host, connect the domain, enable SSL, then restart the Node application after deployments or environment changes. Keep the Supabase service-role value server-side only. Supabase Auth Site URL and redirect allowlist must include the public domain.

The application currently uses standard Next.js server rendering and `next start`; it does not rely on Vercel-only APIs. Confirm the host's current Next.js process and port configuration with its Node.js application panel when provisioning.

## Current implementation boundary

This repository is a working foundation, not yet the full product described in the build specification. Full question bank editing/import, exam authoring/publishing, the interactive timed exam room, result review/export, admin user-management screens, notification delivery, a demo seed and automated end-to-end/security tests still need implementation. The schema includes the core domain objects and critical attempt RPCs, but a production release needs migration review and live Supabase verification.
