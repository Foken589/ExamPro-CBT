import { NextResponse } from "next/server";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";

const inputSchema = z.object({ bankId: z.string().uuid(), level: z.string().trim().min(2).max(100), count: z.number().int().min(1).max(25) });
const outputSchema = {
  type: "object",
  properties: { questions: { type: "array", items: { type: "object", properties: {
    question_text: { type: "string" }, option_a: { type: "string" }, option_b: { type: "string" },
    option_c: { type: "string" }, option_d: { type: "string" }, correct_option: { type: "string", enum: ["A", "B", "C", "D"] },
    difficulty: { type: "string", enum: ["EASY", "MEDIUM", "HARD"] }, marks: { type: "number" }, explanation: { type: "string" },
  }, required: ["question_text", "option_a", "option_b", "option_c", "option_d", "correct_option", "difficulty", "marks", "explanation"], additionalProperties: false } } },
  required: ["questions"], additionalProperties: false,
};

export async function POST(request: Request) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Sign in as a teacher to generate questions." }, { status: 401 });
  const { data: profile } = await supabase.from("profiles").select("role,is_active").eq("id", user.id).maybeSingle();
  if (!profile?.is_active || !["TEACHER", "ADMIN"].includes(profile.role)) return NextResponse.json({ error: "Teacher access required." }, { status: 403 });
  const parsed = inputSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) return NextResponse.json({ error: "Choose a valid question bank and level." }, { status: 400 });
  const { data: bank } = await supabase.from("question_banks").select("id,name,subjects(name)").eq("id", parsed.data.bankId).maybeSingle();
  if (!bank) return NextResponse.json({ error: "Question bank not found." }, { status: 404 });
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) return NextResponse.json({ error: "Question generation is not configured. Add OPENAI_API_KEY to the server environment." }, { status: 503 });

  const { error: limitError } = await supabase.rpc("reserve_question_generation");
  if (limitError) return NextResponse.json({ error: "Generation limit reached. Please wait before requesting another batch." }, { status: 429 });
  const joinedSubjects = bank.subjects as unknown as { name: string } | { name: string }[] | null;
  const subjectName = Array.isArray(joinedSubjects) ? joinedSubjects[0]?.name : joinedSubjects?.name;
  const subject = subjectName || bank.name;
  const model = process.env.OPENAI_QUESTION_MODEL || "gpt-4o-mini";

  try {
    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST", headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      signal: AbortSignal.timeout(55_000),
      body: JSON.stringify({
        model, store: false, max_output_tokens: 12000,
        input: [
          { role: "system", content: `You write accurate, original multiple-choice assessment questions. Return exactly ${parsed.data.count} distinct questions. Each must have four plausible options, exactly one correct answer, an unambiguous question, and a concise explanation. Avoid duplicates and avoid requiring facts beyond the stated level. Output only the requested structured data.` },
          { role: "user", content: `Create exactly ${parsed.data.count} original, varied ${subject} multiple-choice questions for ${parsed.data.level}. Mix topics and difficulty. Marks should be 1 unless a calculation reasonably needs more. For maths/science, ensure the marked answer is actually correct and explanations show a brief check. Do not include copyrighted exam questions. This is a teacher-review draft.` },
        ],
        text: { format: { type: "json_schema", name: "question_batch", strict: true, schema: outputSchema } },
      }),
    });
    const result = await response.json();
    if (!response.ok) return NextResponse.json({ error: response.status === 429 ? "The generation provider is busy; try again shortly." : "Question generation failed. Check the server configuration and try again." }, { status: response.status === 429 ? 503 : 502 });
    const text = result.output?.flatMap((item: { type?: string; content?: { type?: string; text?: string }[] }) => item.type === "message" ? (item.content ?? []).filter((part) => part.type === "output_text").map((part) => part.text ?? "") : []).join("");
    if (!text) return NextResponse.json({ error: "The provider returned no question data. Please try again." }, { status: 502 });
    const batch = z.object({ questions: z.array(z.object({ question_text: z.string().min(8).max(2000), option_a: z.string().min(1), option_b: z.string().min(1), option_c: z.string().min(1), option_d: z.string().min(1), correct_option: z.enum(["A", "B", "C", "D"]), difficulty: z.enum(["EASY", "MEDIUM", "HARD"]), marks: z.number().positive().max(100), explanation: z.string().max(2000) })) }).safeParse(JSON.parse(text));
    if (!batch.success || batch.data.questions.length !== parsed.data.count) return NextResponse.json({ error: "The generated batch was incomplete or invalid. Please generate it again." }, { status: 502 });
    const questions = batch.data.questions.map((question) => ({
      question_text: question.question_text, marks: question.marks, difficulty: question.difficulty, explanation: question.explanation,
      options: [question.option_a, question.option_b, question.option_c, question.option_d].map((text, index) => ({ text, is_correct: question.correct_option === String.fromCharCode(65 + index) })),
    }));
    return NextResponse.json({ questions }, { headers: { "Cache-Control": "private, no-store" } });
  } catch {
    return NextResponse.json({ error: "Question generation timed out or could not reach the provider. Please try again." }, { status: 504 });
  }
}
