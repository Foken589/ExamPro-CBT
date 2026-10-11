import type { Metadata } from "next";
import { Analytics } from "@vercel/analytics/next";
import "./globals.css";

export const metadata: Metadata = {
  title: {
    default: "ExamPro CBT | Modern online examinations",
    template: "%s | ExamPro CBT",
  },
  description: "Modern online examinations, built for speed, security and scale.",
  openGraph: {
    title: "ExamPro CBT",
    description: "Modern online examinations, built for speed, security and scale.",
    type: "website",
  },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>
        {children}
        <Analytics />
      </body>
    </html>
  );
}
