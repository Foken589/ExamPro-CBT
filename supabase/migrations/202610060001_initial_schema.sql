create extension if not exists pgcrypto;
create type public.user_role as enum ('ADMIN','TEACHER','STUDENT');
create type public.question_kind as enum ('MULTIPLE_CHOICE');
create type public.difficulty_level as enum ('EASY','MEDIUM','HARD');
create type public.exam_status as enum ('DRAFT','SCHEDULED','ACTIVE','COMPLETED','ARCHIVED');
create type public.attempt_status as enum ('IN_PROGRESS','SUBMITTED','AUTO_SUBMITTED','ABANDONED');
create table public.profiles(id uuid primary key references auth.users(id) on delete cascade,full_name text not null default '',email text not null default '',role public.user_role not null default 'STUDENT',phone text,institution text,avatar_url text,is_active boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$ begin insert into public.profiles(id,email,full_name) values(new.id,new.email,coalesce(new.raw_user_meta_data->>'full_name','')); return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();
create function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$ select exists(select 1 from public.profiles where id=auth.uid() and role='ADMIN' and is_active) $$;
create table public.subjects(id uuid primary key default gen_random_uuid(),name text not null,code text,description text,teacher_id uuid not null references public.profiles(id),is_active boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.question_banks(id uuid primary key default gen_random_uuid(),subject_id uuid not null references public.subjects(id) on delete cascade,teacher_id uuid not null references public.profiles(id),name text not null,description text,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.questions(id uuid primary key default gen_random_uuid(),question_bank_id uuid not null references public.question_banks(id) on delete cascade,subject_id uuid not null references public.subjects(id) on delete cascade,teacher_id uuid not null references public.profiles(id),question_text text not null,question_type public.question_kind not null default 'MULTIPLE_CHOICE',marks numeric(8,2) not null default 1 check(marks>0),explanation text,difficulty public.difficulty_level not null default 'MEDIUM',is_active boolean not null default true,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.question_options(id uuid primary key default gen_random_uuid(),question_id uuid not null references public.questions(id) on delete cascade,option_text text not null,option_order integer not null, is_correct boolean not null default false,created_at timestamptz not null default now(),unique(question_id,option_order));
create unique index question_one_correct_option on public.question_options(question_id) where is_correct;
create table public.exams(id uuid primary key default gen_random_uuid(),teacher_id uuid not null references public.profiles(id),subject_id uuid not null references public.subjects(id),title text not null,description text,instructions text,duration_minutes integer not null check(duration_minutes>0),total_questions integer not null check(total_questions>0),questions_to_answer integer not null check(questions_to_answer>0 and questions_to_answer<=total_questions),total_marks numeric(9,2) not null check(total_marks>0),start_at timestamptz not null,end_at timestamptz not null,status public.exam_status not null default 'DRAFT',randomize_questions boolean not null default false,randomize_options boolean not null default false,allow_navigation boolean not null default true,allow_question_flagging boolean not null default true,show_result_after_submission boolean not null default false,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),check(end_at>start_at));
create table public.exam_questions(id uuid primary key default gen_random_uuid(),exam_id uuid not null references public.exams(id) on delete cascade,question_id uuid not null references public.questions(id),question_order integer not null,marks numeric(8,2) not null check(marks>0),created_at timestamptz not null default now(),unique(exam_id,question_id),unique(exam_id,question_order));
create table public.exam_attempts(id uuid primary key default gen_random_uuid(),exam_id uuid not null references public.exams(id),student_id uuid not null references public.profiles(id),started_at timestamptz not null default now(),expires_at timestamptz not null,submitted_at timestamptz,status public.attempt_status not null default 'IN_PROGRESS',score numeric(9,2),total_marks numeric(9,2),percentage numeric(6,2),questions_answered integer not null default 0,questions_unanswered integer not null default 0,auto_submitted boolean not null default false,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create unique index one_live_attempt_per_student_exam on public.exam_attempts(exam_id,student_id) where status='IN_PROGRESS';
create table public.attempt_questions(attempt_id uuid not null references public.exam_attempts(id) on delete cascade,question_id uuid not null references public.questions(id),question_order integer not null,marks numeric(8,2) not null,primary key(attempt_id,question_id),unique(attempt_id,question_order));
create table public.student_answers(id uuid primary key default gen_random_uuid(),attempt_id uuid not null references public.exam_attempts(id) on delete cascade,question_id uuid not null,selected_option_id uuid references public.question_options(id),is_correct boolean,marks_awarded numeric(8,2),answered_at timestamptz,updated_at timestamptz not null default now(),unique(attempt_id,question_id),foreign key(attempt_id,question_id) references public.attempt_questions(attempt_id,question_id));
create table public.exam_flags(id uuid primary key default gen_random_uuid(),attempt_id uuid not null references public.exam_attempts(id) on delete cascade,question_id uuid not null,created_at timestamptz not null default now(),unique(attempt_id,question_id),foreign key(attempt_id,question_id) references public.attempt_questions(attempt_id,question_id));
create table public.audit_logs(id uuid primary key default gen_random_uuid(),user_id uuid references public.profiles(id),action text not null,entity_type text not null,entity_id uuid,metadata jsonb not null default '{}',created_at timestamptz not null default now());
create index questions_bank_active_idx on public.questions(question_bank_id,is_active);
create index exams_window_idx on public.exams(status,start_at,end_at);
create index attempts_student_idx on public.exam_attempts(student_id,created_at desc);
create index attempts_exam_idx on public.exam_attempts(exam_id,status);
create index answers_attempt_idx on public.student_answers(attempt_id);
create or replace function public.start_exam(p_exam_id uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare v_user uuid:=auth.uid(); v_exam public.exams; v_attempt uuid; v_count integer;
begin
 if v_user is null or not exists(select 1 from public.profiles where id=v_user and role='STUDENT' and is_active) then raise exception 'Student account required'; end if;
 select * into v_exam from public.exams where id=p_exam_id for share;
 if not found or v_exam.status not in ('ACTIVE','SCHEDULED') or now()<v_exam.start_at or now()>v_exam.end_at then raise exception 'Exam is not available'; end if;
 if v_exam.status='SCHEDULED' then update public.exams set status='ACTIVE',updated_at=now() where id=p_exam_id;end if;
 perform pg_advisory_xact_lock(hashtextextended(p_exam_id::text||v_user::text,0));
 select id into v_attempt from public.exam_attempts where exam_id=p_exam_id and student_id=v_user and status='IN_PROGRESS' for update;
 if v_attempt is not null then return v_attempt; end if;
 if v_exam.randomize_questions then
  select count(*) into v_count from public.questions where subject_id=v_exam.subject_id and is_active;
  if v_count<v_exam.questions_to_answer then raise exception 'Not enough questions are available'; end if;
 else
  select count(*) into v_count from public.exam_questions where exam_id=p_exam_id;
  if v_count<v_exam.questions_to_answer then raise exception 'Exam question set is incomplete'; end if;
 end if;
 insert into public.exam_attempts(exam_id,student_id,expires_at,questions_unanswered) values(p_exam_id,v_user,least(now()+make_interval(mins=>v_exam.duration_minutes),v_exam.end_at),v_exam.questions_to_answer) returning id into v_attempt;
 if v_exam.randomize_questions then
  insert into public.attempt_questions(attempt_id,question_id,question_order,marks) select v_attempt,q.id,row_number() over(order by random())::int,q.marks from (select id,marks from public.questions where subject_id=v_exam.subject_id and is_active order by random() limit v_exam.questions_to_answer) q;
 else
  insert into public.attempt_questions(attempt_id,question_id,question_order,marks) select v_attempt,question_id,question_order,marks from public.exam_questions where exam_id=p_exam_id order by question_order limit v_exam.questions_to_answer;
 end if;
 update public.exam_attempts set total_marks=(select coalesce(sum(marks),0) from public.attempt_questions where attempt_id=v_attempt) where id=v_attempt;
 insert into public.audit_logs(user_id,action,entity_type,entity_id) values(v_user,'attempt_started','exam_attempts',v_attempt);
 return v_attempt;
end $$;
create or replace function public.save_answer(p_attempt_id uuid,p_question_id uuid,p_option_id uuid) returns void language plpgsql security definer set search_path=public as $$
declare v_attempt public.exam_attempts;
begin
 select * into v_attempt from public.exam_attempts where id=p_attempt_id and student_id=auth.uid() for update;
 if not found or v_attempt.status<>'IN_PROGRESS' or v_attempt.expires_at<=now() then raise exception 'Attempt is no longer editable'; end if;
 if not exists(select 1 from public.attempt_questions where attempt_id=p_attempt_id and question_id=p_question_id) then raise exception 'Question is not part of this attempt'; end if;
 if not exists(select 1 from public.question_options where id=p_option_id and question_id=p_question_id) then raise exception 'Invalid option'; end if;
 insert into public.student_answers(attempt_id,question_id,selected_option_id,answered_at,updated_at) values(p_attempt_id,p_question_id,p_option_id,now(),now()) on conflict(attempt_id,question_id) do update set selected_option_id=excluded.selected_option_id,answered_at=now(),updated_at=now();
end $$;
create or replace function public.submit_exam(p_attempt_id uuid,p_auto boolean default false) returns public.exam_attempts language plpgsql security definer set search_path=public as $$
declare v public.exam_attempts; v_total numeric; v_score numeric; v_answered integer;
begin
 select * into v from public.exam_attempts where id=p_attempt_id and student_id=auth.uid() for update;
 if not found then raise exception 'Attempt not found'; end if;
 if v.status<>'IN_PROGRESS' then return v; end if;
 if now()<v.expires_at and p_auto then raise exception 'Attempt has not expired'; end if;
 select coalesce(sum(a.marks_awarded),0),count(a.id) filter(where a.selected_option_id is not null),coalesce(sum(aq.marks),0) into v_score,v_answered,v_total from public.attempt_questions aq left join public.student_answers a on a.attempt_id=aq.attempt_id and a.question_id=aq.question_id where aq.attempt_id=p_attempt_id;
 update public.student_answers a set is_correct=o.is_correct,marks_awarded=case when o.is_correct then aq.marks else 0 end from public.attempt_questions aq,public.question_options o where a.attempt_id=p_attempt_id and aq.attempt_id=a.attempt_id and aq.question_id=a.question_id and o.id=a.selected_option_id;
 select coalesce(sum(marks_awarded),0) into v_score from public.student_answers where attempt_id=p_attempt_id;
 update public.exam_attempts set status=case when p_auto or expires_at<=now() then 'AUTO_SUBMITTED'::public.attempt_status else 'SUBMITTED'::public.attempt_status end,auto_submitted=(p_auto or expires_at<=now()),submitted_at=now(),score=v_score,percentage=case when v_total=0 then 0 else round(v_score/v_total*100,2) end,questions_answered=v_answered,questions_unanswered=(select count(*) from public.attempt_questions where attempt_id=p_attempt_id)-v_answered,updated_at=now() where id=p_attempt_id returning * into v;
 insert into public.audit_logs(user_id,action,entity_type,entity_id) values(auth.uid(),case when v.auto_submitted then 'attempt_auto_submitted' else 'attempt_submitted' end,'exam_attempts',p_attempt_id);
 return v;
end $$;
alter table public.profiles enable row level security;
alter table public.subjects enable row level security;
alter table public.question_banks enable row level security;
alter table public.questions enable row level security;
alter table public.question_options enable row level security;
alter table public.exams enable row level security;
alter table public.exam_questions enable row level security;
alter table public.exam_attempts enable row level security;
alter table public.attempt_questions enable row level security;
alter table public.student_answers enable row level security;
alter table public.exam_flags enable row level security;
alter table public.audit_logs enable row level security;
create policy profile_read on public.profiles for select using(id=auth.uid() or public.is_admin());
create policy teacher_read_attempt_students on public.profiles for select using(exists(select 1 from public.exam_attempts a join public.exams e on e.id=a.exam_id where a.student_id=profiles.id and e.teacher_id=auth.uid()));
create policy profile_update on public.profiles for update using(id=auth.uid() or public.is_admin()) with check(id=auth.uid() or public.is_admin());
create policy subject_read on public.subjects for select using(is_active or teacher_id=auth.uid() or public.is_admin());
create policy subject_write on public.subjects for all using(teacher_id=auth.uid() or public.is_admin()) with check((teacher_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in ('TEACHER','ADMIN'))) or public.is_admin());
create policy bank_owner_all on public.question_banks for all using(teacher_id=auth.uid() or public.is_admin()) with check(((teacher_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in ('TEACHER','ADMIN'))) or public.is_admin()) and exists(select 1 from public.subjects s where s.id=subject_id and (s.teacher_id=auth.uid() or public.is_admin())));
create policy question_select on public.questions for select using(teacher_id=auth.uid() or public.is_admin() or exists(select 1 from public.attempt_questions aq join public.exam_attempts a on a.id=aq.attempt_id where aq.question_id=id and a.student_id=auth.uid()));
create policy question_write on public.questions for all using(teacher_id=auth.uid() or public.is_admin()) with check(((teacher_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in ('TEACHER','ADMIN'))) or public.is_admin()) and exists(select 1 from public.question_banks b where b.id=question_bank_id and b.subject_id=questions.subject_id and (b.teacher_id=auth.uid() or public.is_admin())));
create policy options_visible_to_owner_or_attempt on public.question_options for select using(exists(select 1 from public.questions q where q.id=question_id and (q.teacher_id=auth.uid() or public.is_admin())) or exists(select 1 from public.attempt_questions aq join public.exam_attempts a on a.id=aq.attempt_id where aq.question_id=question_id and a.student_id=auth.uid() and (a.status<>'IN_PROGRESS' or exists(select 1 from public.student_answers sa where sa.attempt_id=a.id and sa.question_id=question_options.question_id))));
drop policy options_visible_to_owner_or_attempt on public.question_options;
create policy options_visible_to_owner_or_attempt on public.question_options for select using(exists(select 1 from public.questions q where q.id=question_id and (q.teacher_id=auth.uid() or public.is_admin())) or exists(select 1 from public.attempt_questions aq join public.exam_attempts a on a.id=aq.attempt_id where aq.question_id=question_id and a.student_id=auth.uid()));
create policy exam_read on public.exams for select using(teacher_id=auth.uid() or public.is_admin() or (status in ('ACTIVE','SCHEDULED','COMPLETED') and exists(select 1 from public.subjects s where s.id=subject_id and s.is_active)));
create policy exam_write on public.exams for all using(teacher_id=auth.uid() or public.is_admin()) with check((teacher_id=auth.uid() and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role in ('TEACHER','ADMIN'))) or public.is_admin());
create policy exam_questions_teacher on public.exam_questions for all using(exists(select 1 from public.exams e where e.id=exam_id and (e.teacher_id=auth.uid() or public.is_admin()))) with check(exists(select 1 from public.exams e join public.questions q on q.id=question_id where e.id=exam_id and q.subject_id=e.subject_id and (e.teacher_id=auth.uid() or public.is_admin()) and (q.teacher_id=auth.uid() or public.is_admin())));
create policy attempts_read on public.exam_attempts for select using(student_id=auth.uid() or exists(select 1 from public.exams e where e.id=exam_id and e.teacher_id=auth.uid()) or public.is_admin());
create policy attempt_questions_read on public.attempt_questions for select using(exists(select 1 from public.exam_attempts a where a.id=attempt_id and (a.student_id=auth.uid() or public.is_admin() or exists(select 1 from public.exams e where e.id=a.exam_id and e.teacher_id=auth.uid()))));
create policy answers_read on public.student_answers for select using(exists(select 1 from public.exam_attempts a where a.id=attempt_id and (a.student_id=auth.uid() or public.is_admin() or exists(select 1 from public.exams e where e.id=a.exam_id and e.teacher_id=auth.uid()))));
create policy flags_read on public.exam_flags for select using(exists(select 1 from public.exam_attempts a where a.id=attempt_id and a.student_id=auth.uid()));
create policy audit_admin_read on public.audit_logs for select using(public.is_admin());
create policy attempt_flags_insert on public.exam_flags for insert with check(exists(select 1 from public.exam_attempts a where a.id=attempt_id and a.student_id=auth.uid() and a.status='IN_PROGRESS' and a.expires_at>now()) and exists(select 1 from public.attempt_questions q where q.attempt_id=attempt_id and q.question_id=exam_flags.question_id));
create policy attempt_flags_delete on public.exam_flags for delete using(exists(select 1 from public.exam_attempts a where a.id=attempt_id and a.student_id=auth.uid() and a.status='IN_PROGRESS' and a.expires_at>now()));
-- Column grants prevent students from reading is_correct even though they can read answer text.
revoke all on public.question_options from anon,authenticated;
grant select(id,question_id,option_text,option_order,created_at) on public.question_options to authenticated;
grant select,insert,update,delete on public.profiles,public.subjects,public.question_banks,public.questions,public.exams,public.exam_questions,public.exam_flags to authenticated;
grant select on public.question_options,public.exam_attempts,public.attempt_questions,public.student_answers to authenticated;
create or replace function public.protect_profile_role() returns trigger language plpgsql security definer set search_path=public as $$ begin if (new.role is distinct from old.role or new.is_active is distinct from old.is_active) and not public.is_admin() then raise exception 'Only administrators can change roles or account status'; end if; return new; end $$;
create trigger protect_profile_role before update on public.profiles for each row execute procedure public.protect_profile_role();
grant execute on function public.start_exam(uuid) to authenticated;
grant execute on function public.save_answer(uuid,uuid,uuid) to authenticated;
grant execute on function public.submit_exam(uuid,boolean) to authenticated;
create or replace function public.create_question(p_bank uuid,p_text text,p_marks numeric,p_difficulty public.difficulty_level,p_explanation text,p_options jsonb) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_bank public.question_banks;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role in ('TEACHER','ADMIN') and is_active) then raise exception 'Teacher account required'; end if;
 select * into v_bank from public.question_banks where id=p_bank and (teacher_id=auth.uid() or public.is_admin());
 if not found then raise exception 'Question bank not found'; end if;
 if jsonb_typeof(p_options)<>'array' or jsonb_array_length(p_options)<2 or (select count(*) from jsonb_array_elements(p_options) x where (x->>'is_correct')::boolean)=1 is not true then raise exception 'Provide at least two options and exactly one correct answer'; end if;
 insert into public.questions(question_bank_id,subject_id,teacher_id,question_text,marks,difficulty,explanation) values(p_bank,v_bank.subject_id,auth.uid(),p_text,p_marks,p_difficulty,p_explanation) returning id into v_id;
 insert into public.question_options(question_id,option_text,option_order,is_correct) select v_id,x->>'text',ord::int,(x->>'is_correct')::boolean from jsonb_array_elements(p_options) with ordinality as q(x,ord);
 insert into public.audit_logs(user_id,action,entity_type,entity_id) values(auth.uid(),'question_created','questions',v_id);
 return v_id;
end $$;
create or replace function public.create_exam(p_data jsonb,p_question_ids uuid[] default '{}') returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_teacher uuid:=auth.uid(); v_count int; v_question uuid; v_idx int:=0;
begin
 if not exists(select 1 from public.profiles where id=v_teacher and role in ('TEACHER','ADMIN') and is_active) then raise exception 'Teacher account required'; end if;
 if not exists(select 1 from public.subjects where id=(p_data->>'subject_id')::uuid and (teacher_id=v_teacher or public.is_admin())) then raise exception 'Subject not found'; end if;
 if coalesce((p_data->>'duration_minutes')::int,0)<=0 or coalesce((p_data->>'questions_to_answer')::int,0)<=0 or (p_data->>'end_at')::timestamptz<=(p_data->>'start_at')::timestamptz then raise exception 'Invalid exam settings'; end if;
 if coalesce((p_data->>'randomize_questions')::boolean,false) then
   select count(*) into v_count from public.questions where subject_id=(p_data->>'subject_id')::uuid and is_active;
 else v_count:=coalesce(array_length(p_question_ids,1),0); end if;
 if v_count<(p_data->>'questions_to_answer')::int then raise exception 'Not enough questions selected'; end if;
 insert into public.exams(teacher_id,subject_id,title,description,instructions,duration_minutes,total_questions,questions_to_answer,total_marks,start_at,end_at,status,randomize_questions,randomize_options,allow_navigation,allow_question_flagging,show_result_after_submission)
 values(v_teacher,(p_data->>'subject_id')::uuid,p_data->>'title',p_data->>'description',p_data->>'instructions',(p_data->>'duration_minutes')::int,v_count,(p_data->>'questions_to_answer')::int,(p_data->>'total_marks')::numeric,(p_data->>'start_at')::timestamptz,(p_data->>'end_at')::timestamptz,case when not coalesce((p_data->>'publish')::boolean,false) then 'DRAFT'::public.exam_status when (p_data->>'start_at')::timestamptz>now() then 'SCHEDULED'::public.exam_status when (p_data->>'end_at')::timestamptz<=now() then 'COMPLETED'::public.exam_status else 'ACTIVE'::public.exam_status end,coalesce((p_data->>'randomize_questions')::boolean,false),coalesce((p_data->>'randomize_options')::boolean,false),coalesce((p_data->>'allow_navigation')::boolean,true),coalesce((p_data->>'allow_question_flagging')::boolean,true),coalesce((p_data->>'show_result_after_submission')::boolean,false)) returning id into v_id;
 if not coalesce((p_data->>'randomize_questions')::boolean,false) then
  foreach v_question in array p_question_ids loop v_idx:=v_idx+1; if not exists(select 1 from public.questions q where q.id=v_question and q.subject_id=(p_data->>'subject_id')::uuid and q.teacher_id=v_teacher and q.is_active) then raise exception 'Invalid question selection'; end if; insert into public.exam_questions(exam_id,question_id,question_order,marks) select v_id,q.id,v_idx,q.marks from public.questions q where q.id=v_question; end loop;
 end if;
 insert into public.audit_logs(user_id,action,entity_type,entity_id) values(v_teacher,case when coalesce((p_data->>'publish')::boolean,false) then 'exam_published' else 'exam_created' end,'exams',v_id);
 return v_id;
end $$;
grant execute on function public.create_question(uuid,text,numeric,public.difficulty_level,text,jsonb) to authenticated;
grant execute on function public.create_exam(jsonb,uuid[]) to authenticated;
create or replace function public.set_exam_status(p_exam_id uuid,p_status public.exam_status) returns public.exam_status language plpgsql security definer set search_path=public as $$
declare v_exam public.exams; v_pool integer;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role in ('TEACHER','ADMIN') and is_active) then raise exception 'Teacher account required';end if;
 select * into v_exam from public.exams where id=p_exam_id and (teacher_id=auth.uid() or public.is_admin()) for update;
 if not found then raise exception 'Exam not found';end if;
 if p_status in ('ACTIVE','SCHEDULED') then
  if v_exam.randomize_questions then select count(*) into v_pool from public.questions where subject_id=v_exam.subject_id and is_active;
  else select count(*) into v_pool from public.exam_questions where exam_id=p_exam_id;end if;
  if v_pool<v_exam.questions_to_answer then raise exception 'Not enough questions are available';end if;
  if p_status='ACTIVE' and (now()<v_exam.start_at or now()>v_exam.end_at) then raise exception 'Exam is outside its schedule';end if;
  if p_status='SCHEDULED' and now()>=v_exam.start_at then raise exception 'Exam schedule has already started';end if;
 end if;
 update public.exams set status=p_status,updated_at=now() where id=p_exam_id;
 insert into public.audit_logs(user_id,action,entity_type,entity_id,metadata) values(auth.uid(),'exam_status_changed','exams',p_exam_id,jsonb_build_object('status',p_status));
 return p_status;
end $$;
grant execute on function public.set_exam_status(uuid,public.exam_status) to authenticated;
create or replace function public.import_questions(p_bank uuid,p_questions jsonb) returns integer language plpgsql security definer set search_path=public as $$
declare v_bank public.question_banks; v_row jsonb; v_id uuid; v_count int:=0;
begin
 if not exists(select 1 from public.profiles where id=auth.uid() and role in ('TEACHER','ADMIN') and is_active) then raise exception 'Teacher account required'; end if;
 select * into v_bank from public.question_banks where id=p_bank and (teacher_id=auth.uid() or public.is_admin());
 if not found then raise exception 'Question bank not found'; end if;
 if jsonb_typeof(p_questions)<>'array' or jsonb_array_length(p_questions)=0 or jsonb_array_length(p_questions)>1000 then raise exception 'Import must contain between 1 and 1000 rows'; end if;
 for v_row in select value from jsonb_array_elements(p_questions) loop
  if coalesce(v_row->>'question_text','')='' or jsonb_typeof(v_row->'options')<>'array' or jsonb_array_length(v_row->'options')<2 or (select count(*) from jsonb_array_elements(v_row->'options') o where (o->>'is_correct')::boolean)=1 is not true then raise exception 'Invalid question row'; end if;
  if coalesce((v_row->>'marks')::numeric,0)<=0 or upper(coalesce(v_row->>'difficulty','')) not in ('EASY','MEDIUM','HARD') then raise exception 'Invalid question fields'; end if;
  insert into public.questions(question_bank_id,subject_id,teacher_id,question_text,marks,difficulty,explanation) values(p_bank,v_bank.subject_id,auth.uid(),v_row->>'question_text',(v_row->>'marks')::numeric,upper(v_row->>'difficulty')::public.difficulty_level,v_row->>'explanation') returning id into v_id;
  insert into public.question_options(question_id,option_text,option_order,is_correct) select v_id,o->>'text',ord::int,(o->>'is_correct')::boolean from jsonb_array_elements(v_row->'options') with ordinality as t(o,ord);
  v_count:=v_count+1;
 end loop;
 insert into public.audit_logs(user_id,action,entity_type,metadata) values(auth.uid(),'bulk_question_import','question_banks',jsonb_build_object('bank_id',p_bank,'question_count',v_count));
 return v_count;
end $$;
grant execute on function public.import_questions(uuid,jsonb) to authenticated;
revoke select on public.exam_attempts from authenticated;
grant select(id,exam_id,student_id,started_at,expires_at,submitted_at,status,questions_answered,questions_unanswered,auto_submitted,created_at,updated_at) on public.exam_attempts to authenticated;
revoke select on public.student_answers from authenticated;
grant select(id,attempt_id,question_id,selected_option_id,answered_at,updated_at) on public.student_answers to authenticated;
create or replace function public.get_permitted_results(p_attempt_id uuid default null) returns table(attempt_id uuid,student_id uuid,student_name text,student_email text,exam_id uuid,exam_title text,subject_name text,score numeric,total_marks numeric,percentage numeric,status public.attempt_status,started_at timestamptz,submitted_at timestamptz,auto_submitted boolean,questions_answered integer,questions_unanswered integer) language sql stable security definer set search_path=public as $$
 select a.id,a.student_id,p.full_name,p.email,a.exam_id,e.title,s.name,a.score,a.total_marks,a.percentage,a.status,a.started_at,a.submitted_at,a.auto_submitted,a.questions_answered,a.questions_unanswered
 from public.exam_attempts a join public.exams e on e.id=a.exam_id join public.subjects s on s.id=e.subject_id join public.profiles p on p.id=a.student_id
 where a.status<>'IN_PROGRESS' and (p_attempt_id is null or a.id=p_attempt_id) and (a.student_id=auth.uid() and e.show_result_after_submission or e.teacher_id=auth.uid() or public.is_admin())
 order by a.submitted_at desc limit 5000
$$;
grant execute on function public.get_permitted_results(uuid) to authenticated;
create or replace function public.finalize_expired_attempts() returns integer language plpgsql security definer set search_path=public as $$
declare v public.exam_attempts; v_score numeric; v_total numeric; v_answered integer; v_count integer:=0;
begin
 if auth.role()<>'service_role' then raise exception 'Service role required'; end if;
 for v in select * from public.exam_attempts where status='IN_PROGRESS' and expires_at<=now() order by expires_at limit 500 for update skip locked loop
  update public.student_answers a set is_correct=o.is_correct,marks_awarded=case when o.is_correct then aq.marks else 0 end from public.attempt_questions aq,public.question_options o where a.attempt_id=v.id and aq.attempt_id=a.attempt_id and aq.question_id=a.question_id and o.id=a.selected_option_id;
  select coalesce(sum(marks_awarded),0) into v_score from public.student_answers where attempt_id=v.id;
  select coalesce(sum(marks),0) into v_total from public.attempt_questions where attempt_id=v.id;
  select count(*) into v_answered from public.student_answers where attempt_id=v.id and selected_option_id is not null;
  update public.exam_attempts set status='AUTO_SUBMITTED',auto_submitted=true,submitted_at=now(),score=v_score,total_marks=v_total,percentage=case when v_total=0 then 0 else round(v_score/v_total*100,2) end,questions_answered=v_answered,questions_unanswered=(select count(*) from public.attempt_questions where attempt_id=v.id)-v_answered,updated_at=now() where id=v.id and status='IN_PROGRESS';
  if found then insert into public.audit_logs(user_id,action,entity_type,entity_id) values(v.student_id,'attempt_auto_submitted','exam_attempts',v.id);v_count:=v_count+1;end if;
 end loop;
 return v_count;
end $$;
revoke all on function public.finalize_expired_attempts() from public,anon,authenticated;
grant execute on function public.finalize_expired_attempts() to service_role;
