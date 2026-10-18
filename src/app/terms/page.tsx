import type { Metadata } from "next";
import { LegalDocumentPage } from "@/components/LegalDocumentPage";

export const metadata: Metadata = {
  title: "Terms of Use | Synorra POS",
  description: "Terms for authorized use of Synorra POS.",
};

export default function TermsPage() {
  return <LegalDocumentPage kind="terms" />;
}
