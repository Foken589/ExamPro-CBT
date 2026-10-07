import Link from "next/link";
import { notFound } from "next/navigation";
import { requireRole } from "@/lib/auth/guards";
import { StartExam } from "@/components/student-exam";

export default async function Page({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const { sb, user } = await requireRole(["STUDENT"]);

  const { data: exam } = await sb
    .from("exams")
    .select(
      "id,title,description,instructions,status,start_at,end_at,duration_minutes,questions_to_answer,subjects(name)"
    )
    .eq("id", id)
    .maybeSingle();

  if (!exam) {
    notFound();
  }

  const { data: attempt } = await sb
    .from("exam_attempts")
    .select("id,status")
    .eq("exam_id", id)
    .eq("student_id", user.id)
    .eq("status", "IN_PROGRESS")
    .maybeSingle();

  const available =
    (exam.status === "ACTIVE" || exam.status === "SCHEDULED") &&
    Date.now() >= new Date(exam.start_at).getTime() &&
    Date.now() <= new Date(exam.end_at).getTime();

  const subjectName = exam.subjects?.[0]?.name ?? "Subject";

  return (
    <main className="shell dashmain">
      <Link href="/student">← Student dashboard</Link>

      <section className="panel">
        <span className="badge">{exam.status}</span>

        <h1>{exam.title}</h1>

        <p className="subtle">
          {subjectName} · {exam.duration_minutes} minutes ·{" "}
          {exam.questions_to_answer} questions
        </p>

        {exam.description && <p>{exam.description}</p>}

        <h2>Instructions</h2>

        <p style={{ whiteSpace: "pre-wrap", lineHeight: 1.6 }}>
          {exam.instructions ||
            "Read each question carefully. Your answers save automatically. You may review questions before submitting."}
        </p>

        {available ? (
          <StartExam
            examId={exam.id}
            attemptId={attempt?.id ?? null}
          />
        ) : (
          <p className="subtle">
            This exam is not currently available to start.
          </p>
        )}
      </section>
    </main>
  );
}