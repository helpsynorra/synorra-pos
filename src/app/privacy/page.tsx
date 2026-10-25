import type { Metadata } from "next";
import { LegalDocumentPage } from "@/components/LegalDocumentPage";

export const metadata: Metadata = {
  title: "Privacy Policy & Cookie Policy | Synorra POS",
  description: "How Synorra POS handles personal information and website cookies.",
};

export default function PrivacyPage() {
  return <LegalDocumentPage kind="privacy" />;
}
