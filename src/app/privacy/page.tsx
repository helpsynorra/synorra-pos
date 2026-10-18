import type { Metadata } from "next";
import { LegalDocumentPage } from "@/components/LegalDocumentPage";

export const metadata: Metadata = {
  title: "Privacy Policy | Synorra POS",
  description: "How Synorra POS handles account and store information.",
};

export default function PrivacyPage() {
  return <LegalDocumentPage kind="privacy" />;
}
