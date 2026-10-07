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
OPENAI_API_KEY=YOUR_SERVER_ONLY_OPENAI_API_KEY
OPENAI_QUESTION_MODEL=gpt-4o-mini
```

The service-role key is used only by the protected timeout-finalization job. `CRON_SECRET` protects that endpoint. Question generation uses the server-only OpenAI key; never prefix secrets with `NEXT_PUBLIC_`.

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
2. Set `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`, `OPENAI_API_KEY`, and `OPENAI_QUESTION_MODEL` in Vercel project settings. Add `SUPABASE_SERVICE_ROLE_KEY` and `CRON_SECRET` for timeout finalization.
3. Deploy using the standard Next.js build (`npm run build`).
4. Set `CRON_SECRET` and the Supabase Site URL to the production domain, then add production auth callback/reset URLs. Vercel schedules expired-attempt finalization using `vercel.json`.
5. Verify signup/confirmation, login, role redirects and the assessment operations against the configured database.

## Deployment: AfeesHost Node.js

Use a Linux plan that explicitly supports Node.js application hosting. PHP-only hosting cannot run this application. Configure application root as the repository root, Node.js 20.9+, build command `npm ci && npm run build`, and start command `npm run start`. Set the same server environment variables in the host panel, bind the assigned port as supported by the host, connect the domain, enable SSL, then restart the Node application after deployments or environment changes. Keep the Supabase service-role value server-side only. Supabase Auth Site URL and redirect allowlist must include the public domain.

The application currently uses standard Next.js server rendering and `next start`; it does not rely on Vercel-only APIs. Confirm the host's current Next.js process and port configuration with its Node.js application panel when provisioning.

## Current implementation boundary

The repository includes the main authentication, teacher authoring, student exam-taking, results/export and administrator workflows. The student dashboard shows available and scheduled exams, resume links, completion counts, released-result averages, and in-app exam notifications. New scheduled or published exams notify active student accounts; dashboard data refreshes every minute. Migrations provision a standard subject catalog and a question bank for each subject for teacher and administrator accounts (Mathematics, English Language, English Literature, Physics, Chemistry, Biology, Computer Science, History, Geography, Business Studies, Economics and Further Mathematics).

Teachers can upload questions from **Teacher dashboard → Questions & import**. Create or choose the destination question bank, then upload a CSV with the columns `question_text, option_a, option_b, option_c, option_d, correct_option, marks, difficulty, explanation`. The importer validates rows, supports up to 1,000 questions per file, and offers an error report. The same page has **Generate a question batch**: choose the subject bank and level, generate 25 questions at a time, review/remove drafts, then save them. Four batches give about 100 questions for a subject; generation is limited to 8 batches per teacher per hour. Generated questions are drafts for teacher review and are not automatically attached to or published in an exam. Add `OPENAI_API_KEY` server-side to enable generation.

Teachers create exams from **Teacher dashboard → Create exam**. Set the start and end date/time, duration in minutes, question count and marks, select a question source, then choose **Publish immediately** to make it available on schedule. To keep an exam unpublished, leave that option unchecked. Students see active and scheduled exams and their notifications in the student dashboard.

Email/push notification delivery, demo seed data, complete editing/deletion flows, and automated end-to-end/security coverage remain future work. Before production, apply and review all Supabase migrations, configure authentication and deployment secrets (including the OpenAI key if question generation is enabled), and verify the workflows against a live Supabase project.
