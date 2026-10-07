import { requireRole } from "@/lib/auth/guards";
import { StudentDashboard } from "@/components/student-dashboard";

export default async function Page() {
  const { sb, user, profile } = await requireRole(["STUDENT"]);
  const [{ data: exams }, { data: attempts }, { data: results }, { data: notifications }] = await Promise.all([
    sb.from("exams").select("id,title,status,start_at,end_at,duration_minutes,questions_to_answer,subjects(name)").in("status", ["ACTIVE", "SCHEDULED"]).order("start_at").limit(100),
    sb.from("exam_attempts").select("id,exam_id,status,expires_at").eq("student_id", user.id).eq("status", "IN_PROGRESS"),
    sb.rpc("get_permitted_results", { p_attempt_id: null }),
    sb.from("notifications").select("id,title,message,created_at,read_at,exam_id").eq("student_id", user.id).order("created_at", { ascending: false }).limit(10),
  ]);
  const completed = (results ?? []) as { percentage: number | null }[];
  const average = completed.length
    ? Math.round(completed.reduce((sum, result) => sum + Number(result.percentage ?? 0), 0) / completed.length)
    : null;
  return <StudentDashboard name={profile.full_name || user.email || "Student"} exams={exams ?? []} attempts={attempts ?? []} completed={completed.length} average={average} notifications={notifications ?? []} />;
}
