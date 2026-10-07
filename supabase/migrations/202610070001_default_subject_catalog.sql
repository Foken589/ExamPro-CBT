-- Give every teacher a useful starting subject catalog. Subjects remain owned
-- by the teacher so the existing RLS and question-bank model stays intact.
create or replace function public.seed_default_subjects(p_teacher_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_subject record;
begin
  for v_subject in
    select * from (values
      ('Mathematics', 'MATH', 'Mathematics and quantitative reasoning'),
      ('English Language', 'ENG-L', 'Reading, writing and language skills'),
      ('English Literature', 'ENG-LIT', 'Literary texts and critical analysis'),
      ('Physics', 'PHYS', 'Matter, energy and the physical world'),
      ('Chemistry', 'CHEM', 'Materials, reactions and chemical principles'),
      ('Biology', 'BIO', 'Living systems and life sciences'),
      ('Computer Science', 'CS', 'Computing, programming and digital systems'),
      ('History', 'HIST', 'Historical periods, people and events'),
      ('Geography', 'GEOG', 'Places, environments and human geography'),
      ('Business Studies', 'BUS', 'Business operations and enterprise'),
      ('Economics', 'ECON', 'Markets, resources and economic systems'),
      ('Further Mathematics', 'F-MATH', 'Advanced mathematical topics')
    ) as catalog(name, code, description)
  loop
    if not exists (
      select 1 from public.subjects s
      where s.teacher_id = p_teacher_id and lower(s.name) = lower(v_subject.name)
    ) then
      insert into public.subjects(teacher_id, name, code, description)
      values (p_teacher_id, v_subject.name, v_subject.code, v_subject.description);
    end if;
  end loop;
end;
$$;
revoke all on function public.seed_default_subjects(uuid) from public, anon, authenticated;

create or replace function public.provision_teacher_subjects()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role in ('TEACHER', 'ADMIN') and new.is_active then
    perform public.seed_default_subjects(new.id);
  end if;
  return new;
end;
$$;
revoke all on function public.provision_teacher_subjects() from public, anon, authenticated;

create trigger provision_subject_catalog
after insert or update of role on public.profiles
for each row execute function public.provision_teacher_subjects();

-- Provision existing teaching and admin accounts as part of the migration.
do $$
declare v_profile record;
begin
  for v_profile in select id from public.profiles where role in ('TEACHER', 'ADMIN') and is_active loop
    perform public.seed_default_subjects(v_profile.id);
  end loop;
end;
$$;
