"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { ArrowRight, Bell, BookOpenCheck, CalendarClock, ChartNoAxesCombined, Clock3, Play, Search } from "lucide-react";
import { createClient } from "@/lib/supabase/browser";

type Exam = {
  id: string; title: string; status: string; start_at: string; end_at: string;
  duration_minutes: number; questions_to_answer: number; subjects: { name: string } | { name: string }[] | null;
};
type Attempt = { id: string; exam_id: string; expires_at: string };
type Notification = { id: string; title: string; message: string; created_at: string; read_at: string | null; exam_id: string | null };
const subjectName = (subjects: Exam["subjects"]) => Array.isArray(subjects) ? subjects[0]?.name ?? "General" : subjects?.name ?? "General";

export function StudentDashboard({ name, exams, attempts, completed, average, notifications }: {
  name: string; exams: Exam[]; attempts: Attempt[]; completed: number; average: number | null; notifications: Notification[];
}) {
  const router = useRouter();
  const [marking, setMarking] = useState<string | null>(null);
  useEffect(() => {
    const timer = window.setInterval(() => router.refresh(), 60_000);
    return () => window.clearInterval(timer);
  }, [router]);
  async function markRead(id: string) {
    setMarking(id);
    await createClient().from("notifications").update({ read_at: new Date().toISOString() }).eq("id", id).is("read_at", null);
    router.refresh();
    setMarking(null);
  }
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState("All exams");
  const attemptByExam = useMemo(() => new Map(attempts.map((attempt) => [attempt.exam_id, attempt])), [attempts]);
  const now = Date.now();
  const available = exams.filter((exam) => new Date(exam.start_at).getTime() <= now && new Date(exam.end_at).getTime() >= now);
  const upcoming = exams.filter((exam) => new Date(exam.start_at).getTime() > now);
  const activeAttempt = attempts.find((attempt) => new Date(attempt.expires_at).getTime() > now);
  const visibleExams = exams.filter((exam) => {
    const matchesText = `${exam.title} ${subjectName(exam.subjects)}`.toLowerCase().includes(query.toLowerCase());
    const matchesFilter = filter === "All exams" || (filter === "Available" && available.includes(exam)) || (filter === "Upcoming" && upcoming.includes(exam)) || (filter === "In progress" && attemptByExam.has(exam.id));
    return matchesText && matchesFilter;
  });

  return <div className="student-home">
    <header className="student-header">
      <Link className="brand" href="/"><span className="brandmark"><BookOpenCheck size={17}/></span>ExamPro CBT</Link>
      <div className="student-header-actions"><span className="subtle">Signed in as {name}</span><Link className="btn" href="/student/results">My results</Link></div>
    </header>
    <main className="shell student-main">
      <section className="student-welcome">
        <div><span className="eyebrow">Your learning space</span><h1>Welcome back, {name.split(" ")[0]}</h1><p>See what’s coming up, pick up an exam, and keep track of your progress.</p></div>
        <div className="welcome-mark"><BookOpenCheck size={34}/></div>
      </section>
      <section className="student-stats" aria-label="Your exam summary">
        <article><span><CalendarClock size={16}/>Available now</span><strong>{available.length}</strong><small>Exams open to start</small></article>
        <article><span><Clock3 size={16}/>Coming up</span><strong>{upcoming.length}</strong><small>Scheduled exams</small></article>
        <article><span><ChartNoAxesCombined size={16}/>Completed</span><strong>{completed}</strong><small>Submitted exams</small></article>
        <article><span><ChartNoAxesCombined size={16}/>Average score</span><strong>{average === null ? "—" : `${average}%`}</strong><small>{average === null ? "Your results will appear here" : "Across released results"}</small></article>
      </section>
      <section className="student-notifications" aria-labelledby="notification-heading">
        <div className="student-notifications-heading"><h2 id="notification-heading"><Bell size={18}/> Notifications</h2><span>{notifications.filter((item) => !item.read_at).length} new</span></div>
        {notifications.length ? <div className="student-notification-list">{notifications.map((item) => <article className={`student-notification ${item.read_at ? "is-read" : "is-unread"}`} key={item.id}>
          <div className="notification-copy"><strong>{item.title}</strong><p>{item.message}</p><time dateTime={item.created_at}>{new Date(item.created_at).toLocaleString([], { dateStyle: "medium", timeStyle: "short" })}</time></div>
          {item.exam_id && <Link className="btn" href={`/student/exams/${item.exam_id}`}>View exam</Link>}
          {!item.read_at && <button className="notification-read" disabled={marking === item.id} onClick={() => void markRead(item.id)}>{marking === item.id ? "Saving…" : "Mark read"}</button>}
        </article>)}</div> : <p className="student-notification-empty">You’re all caught up. New published or scheduled exams will appear here.</p>}
      </section>
      {activeAttempt && <section className="resume-card"><div className="resume-icon"><Play size={19}/></div><div><span className="eyebrow">Pick up where you left off</span><h2>You have an exam in progress</h2><p>Your saved answers are waiting for you. The exam timer continues while you’re away.</p></div><Link className="btn primary" href={`/student/attempt/${activeAttempt.id}`}>Resume exam <ArrowRight size={16}/></Link></section>}
      <section className="exam-browser">
        <div className="exam-browser-heading"><div><h2>Your exams</h2><p>Choose an available exam or check what’s scheduled next.</p></div><Link href="/student/results" className="text-link">View results <ArrowRight size={15}/></Link></div>
        <div className="exam-tools"><label className="searchbox"><Search size={17}/><input aria-label="Search exams" placeholder="Search by exam or subject" value={query} onChange={(event) => setQuery(event.target.value)}/></label><div className="exam-filters" role="group" aria-label="Filter exams">{["All exams", "Available", "Upcoming", "In progress"].map((item) => <button key={item} className={filter === item ? "selected" : ""} onClick={() => setFilter(item)}>{item}</button>)}</div></div>
        {visibleExams.length ? <div className="student-exam-list">{visibleExams.map((exam) => {
          const attempt = attemptByExam.get(exam.id);
          const starts = new Date(exam.start_at).getTime();
          const ends = new Date(exam.end_at).getTime();
          const isAvailable = starts <= now && ends >= now;
          const isClosed = ends < now;
          const status = attempt ? "In progress" : isAvailable ? "Available" : isClosed ? "Closed" : "Upcoming";
          return <article className="student-exam-card" key={exam.id}>
            <div className="subject-icon">{subjectName(exam.subjects).slice(0, 1).toUpperCase()}</div>
            <div className="student-exam-info"><div className="student-exam-title"><span className="subject-name">{subjectName(exam.subjects)}</span><span className={`exam-status ${status === "Available" ? "is-open" : status === "In progress" ? "is-progress" : status === "Closed" ? "is-closed" : "is-upcoming"}`}>{status}</span></div><h3>{exam.title}</h3><div className="exam-meta"><span><Clock3 size={14}/>{exam.duration_minutes} minutes</span><span><BookOpenCheck size={14}/>{exam.questions_to_answer} questions</span><span><CalendarClock size={14}/>{isAvailable ? `Closes ${new Date(exam.end_at).toLocaleString([], { dateStyle: "medium", timeStyle: "short" })}` : isClosed ? `Closed ${new Date(exam.end_at).toLocaleString([], { dateStyle: "medium", timeStyle: "short" })}` : `Starts ${new Date(exam.start_at).toLocaleString([], { dateStyle: "medium", timeStyle: "short" })}`}</span></div></div>
            <Link className={`btn ${isAvailable || attempt ? "primary" : ""}`} href={attempt ? `/student/attempt/${attempt.id}` : `/student/exams/${exam.id}`}>{attempt ? "Resume" : isAvailable ? "View exam" : isClosed ? "Closed" : "Details"}<ArrowRight size={15}/></Link>
          </article>;
        })}</div> : <div className="student-empty"><span className="empty-icon"><BookOpenCheck size={22}/></span><h3>{exams.length ? "No exams match your search" : "Your exam space is ready"}</h3><p>{exams.length ? "Try another search or filter." : "When your teacher publishes an exam, it will appear here with its subject, schedule and instructions."}</p>{exams.length > 0 && <button className="btn" onClick={() => { setQuery(""); setFilter("All exams"); }}>Clear filters</button>}</div>}
      </section>
      <footer className="student-footer"><span>Need help? Contact your teacher or school administrator.</span><Link href="/student/results">Review your exam history</Link></footer>
    </main>
  </div>;
}
