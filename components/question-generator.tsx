"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/browser";

type Bank = { id: string; name: string; subject_id: string; subjects: { name: string } | { name: string }[] | null };
type Generated = { question_text: string; marks: number; difficulty: "EASY" | "MEDIUM" | "HARD"; explanation: string; options: { text: string; is_correct: boolean }[] };
const subject = (bank: Bank) => Array.isArray(bank.subjects) ? bank.subjects[0]?.name ?? bank.name : bank.subjects?.name ?? bank.name;

export function QuestionGenerator({ banks }: { banks: Bank[] }) {
  const [bankId, setBankId] = useState("");
  const [level, setLevel] = useState("General secondary / GCSE-style");
  const [questions, setQuestions] = useState<Generated[]>([]);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const selectedBank = banks.find((bank) => bank.id === bankId);

  async function generateBatch() {
    if (!selectedBank || busy) return;
    setBusy(true);
    setMessage("Generating a 25-question draft batch…");
    try {
      const response = await fetch("/api/teacher/questions/generate", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ bankId, level, count: Math.min(25, 100 - questions.length) }),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error ?? "Question generation failed.");
      setQuestions((previous) => [...previous, ...result.questions]);
      setMessage(`Added ${result.questions.length} draft questions. Generate four batches for about 100, then review and save them.`);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Question generation failed.");
    } finally { setBusy(false); }
  }

  async function saveDrafts() {
    if (!selectedBank || !questions.length || busy) return;
    setBusy(true);
    setMessage("Saving reviewed questions…");
    const { data, error } = await createClient().rpc("import_questions", { p_bank: bankId, p_questions: questions });
    setBusy(false);
    if (error) { setMessage("Could not save questions. Please retry; no partial import was made."); return; }
    setMessage(`${data} questions saved in ${selectedBank.name}.`);
    setQuestions([]);
  }

  function removeQuestion(index: number) { setQuestions((previous) => previous.filter((_, itemIndex) => itemIndex !== index)); }

  return <section className="panel question-generator">
    <h2>Generate a question batch</h2>
    <p className="subtle">Create original four-option questions for a subject. Generated questions stay in this preview until a teacher saves them. Review accuracy and suitability before using them in a live exam.</p>
    <div className="generator-controls">
      <div className="field"><label htmlFor="generator-bank">Question bank</label><select id="generator-bank" value={bankId} onChange={(event) => { setBankId(event.target.value); setQuestions([]); }}><option value="">Choose a subject bank</option>{banks.map((item) => <option key={item.id} value={item.id}>{subject(item)} · {item.name}</option>)}</select></div>
      <div className="field"><label htmlFor="generator-level">Level / curriculum</label><input id="generator-level" value={level} maxLength={100} onChange={(event) => setLevel(event.target.value)} /></div>
    </div>
    <div className="generator-actions"><button type="button" className="btn" onClick={() => void generateBatch()} disabled={!selectedBank || !level.trim() || busy || questions.length >= 100}>{busy ? "Working…" : `Generate 25${questions.length ? ` more (${questions.length}/100)` : ""}`}</button><button type="button" className="btn primary" onClick={() => void saveDrafts()} disabled={!questions.length || busy}>Save {questions.length} reviewed questions</button><span className="subtle">{questions.length} in draft</span></div>
    {message && <p className={message.startsWith("Could") || message.includes("failed") ? "error" : "subtle"} role="status">{message}</p>}
    {questions.length > 0 && <div className="generated-preview"><h3>Review generated questions</h3>{questions.map((item, index) => <article key={`${index}:${item.question_text}`}><div><b>{index + 1}. {item.question_text}</b><ol type="A">{item.options.map((option, optionIndex) => <li key={optionIndex}>{option.text}{option.is_correct && <strong> · Answer</strong>}</li>)}</ol><small>{item.difficulty} · {item.marks} mark{item.marks === 1 ? "" : "s"}{item.explanation ? ` · ${item.explanation}` : ""}</small></div><button type="button" className="notification-read" onClick={() => removeQuestion(index)} aria-label={`Remove question ${index + 1}`}>Remove</button></article>)}</div>}
  </section>;
}
