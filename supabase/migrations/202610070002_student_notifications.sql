create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  exam_id uuid references public.exams(id) on delete cascade,
  title text not null,
  message text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists notifications_student_created_idx
  on public.notifications(student_id, created_at desc);

alter table public.notifications enable row level security;
grant select on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;

create policy notifications_read_own
  on public.notifications for select
  using (student_id = auth.uid());

create policy notifications_update_own
  on public.notifications for update
  using (student_id = auth.uid())
  with check (student_id = auth.uid());

create or replace function public.notify_students_exam_published()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_title text;
  v_message text;
begin
  if new.status not in ('ACTIVE', 'SCHEDULED') then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.status in ('ACTIVE', 'SCHEDULED')
     and old.start_at is not distinct from new.start_at
     and old.end_at is not distinct from new.end_at then
    return new;
  end if;

  v_title := case when new.status = 'SCHEDULED' then 'New exam scheduled' else 'New exam available' end;
  v_message := format('%s · %s minutes · starts %s', new.title, new.duration_minutes,
                      to_char(new.start_at at time zone 'UTC', 'Mon DD, YYYY HH24:MI') || ' UTC');

  insert into public.notifications(student_id, exam_id, title, message)
  select p.id, new.id, v_title, v_message
  from public.profiles p
  where p.role = 'STUDENT' and p.is_active;

  return new;
end;
$$;

revoke all on function public.notify_students_exam_published() from public, anon, authenticated;

drop trigger if exists notify_students_exam_published on public.exams;
create trigger notify_students_exam_published
after insert or update of status, start_at, end_at on public.exams
for each row execute function public.notify_students_exam_published();

-- Make the dashboard useful immediately for exams that were already published.
insert into public.notifications(student_id, exam_id, title, message)
select p.id, e.id,
       case when e.status = 'SCHEDULED' then 'Upcoming exam' else 'Exam available' end,
       format('%s · %s minutes · starts %s', e.title, e.duration_minutes,
              to_char(e.start_at at time zone 'UTC', 'Mon DD, YYYY HH24:MI') || ' UTC')
from public.profiles p
cross join public.exams e
where p.role = 'STUDENT' and p.is_active and e.status in ('ACTIVE', 'SCHEDULED');

-- Each catalog subject gets a ready-to-use bank for manual, CSV, or generated questions.
insert into public.question_banks(subject_id, teacher_id, name, description)
select s.id, s.teacher_id, s.name || ' Question Bank', 'Starter bank for teacher-authored and generated practice questions.'
from public.subjects s
join public.profiles p on p.id = s.teacher_id and p.role in ('TEACHER', 'ADMIN') and p.is_active
where s.name in ('Mathematics', 'English Language', 'English Literature', 'Physics', 'Chemistry', 'Biology',
                 'Computer Science', 'History', 'Geography', 'Business Studies', 'Economics', 'Further Mathematics')
  and not exists (select 1 from public.question_banks b where b.subject_id = s.id and b.teacher_id = s.teacher_id);

create or replace function public.provision_default_question_bank()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.name in ('Mathematics', 'English Language', 'English Literature', 'Physics', 'Chemistry', 'Biology',
                  'Computer Science', 'History', 'Geography', 'Business Studies', 'Economics', 'Further Mathematics')
     and not exists (select 1 from public.question_banks b where b.subject_id = new.id and b.teacher_id = new.teacher_id) then
    insert into public.question_banks(subject_id, teacher_id, name, description)
    values (new.id, new.teacher_id, new.name || ' Question Bank', 'Starter bank for teacher-authored and generated practice questions.');
  end if;
  return new;
end;
$$;
revoke all on function public.provision_default_question_bank() from public, anon, authenticated;
drop trigger if exists provision_default_question_bank on public.subjects;
create trigger provision_default_question_bank
after insert on public.subjects for each row execute function public.provision_default_question_bank();

create table if not exists public.question_generation_requests (
  id bigint generated always as identity primary key,
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists question_generation_requests_teacher_time_idx
  on public.question_generation_requests(teacher_id, created_at desc);
alter table public.question_generation_requests enable row level security;
revoke all on public.question_generation_requests from public, anon, authenticated;

create or replace function public.reserve_question_generation()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_teacher uuid := auth.uid();
  v_recent integer;
begin
  if v_teacher is null or not exists (
    select 1 from public.profiles where id = v_teacher and role in ('TEACHER', 'ADMIN') and is_active
  ) then raise exception 'Teacher access required'; end if;

  perform pg_advisory_xact_lock(hashtextextended(v_teacher::text, 0));
  delete from public.question_generation_requests where created_at < now() - interval '30 days';
  select count(*) into v_recent from public.question_generation_requests
    where teacher_id = v_teacher and created_at > now() - interval '1 hour';
  if v_recent >= 8 then raise exception 'Hourly generation limit reached'; end if;
  insert into public.question_generation_requests(teacher_id) values(v_teacher);
end;
$$;
revoke all on function public.reserve_question_generation() from public, anon;
grant execute on function public.reserve_question_generation() to authenticated;
