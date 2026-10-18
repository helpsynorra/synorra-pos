import type { Metadata } from "next";
import { LegalDocumentPage } from "@/components/LegalDocumentPage";

export const metadata: Metadata = {
  title: "Cookie Policy | Synorra POS",
  description: "How Synorra POS uses essential website cookies.",
};

export default function CookiesPage() {
  return <LegalDocumentPage kind="cookies" />;
}
