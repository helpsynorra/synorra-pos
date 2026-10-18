import Link from "next/link";
import {
  cookiePolicy,
  privacyPolicy,
  termsOfUse,
  type LegalSection,
} from "@/lib/legal";

type LegalDocumentPageProps = {
  kind: "terms" | "privacy" | "cookies";
};

export function LegalDocumentPage({ kind }: LegalDocumentPageProps) {
  const title =
    kind === "terms"
      ? "Terms of Use"
      : kind === "privacy"
        ? "Privacy Policy"
        : "Cookie Policy";
  const sections: LegalSection[] =
    kind === "terms"
      ? termsOfUse
      : kind === "privacy"
        ? privacyPolicy
        : cookiePolicy;
  const relatedDocument =
    kind === "terms"
      ? { href: "/privacy", label: "Privacy Policy" }
      : kind === "privacy"
        ? { href: "/cookies", label: "Cookie Policy" }
        : { href: "/terms", label: "Terms of Use" };

  return (
    <main className="min-h-screen bg-[#f5f6f8] px-5 py-10 text-[#18263e] sm:px-8 sm:py-16">
      <article className="mx-auto max-w-3xl rounded-3xl border border-[#e4e8ef] bg-white px-6 py-8 shadow-sm sm:px-12 sm:py-12">
        <Link
          href="/"
          className="text-sm font-semibold text-[#53627f] hover:text-[#b6404b]"
        >
          ← Back to Synorra
        </Link>
        <p className="mt-10 text-xs font-semibold uppercase tracking-[0.2em] text-[#b6404b]">
          Synorra POS
        </p>
        <h1 className="mt-3 text-4xl font-semibold tracking-tight">{title}</h1>
        <p className="mt-3 text-sm text-[#667085]">
          Last updated October 19, 2026
        </p>
        <p className="mt-8 rounded-2xl bg-[#f5f6f8] p-5 text-sm leading-6 text-[#53627f]">
          This document describes the current Synorra POS app behavior. It is
          provided for product information and should be reviewed by qualified
          counsel against your business operations and applicable requirements
          before publication.
        </p>
        <div className="mt-8 space-y-8">
          {sections.map((section) => (
            <section key={section.heading}>
              <h2 className="text-lg font-semibold">{section.heading}</h2>
              <p className="mt-2 leading-7 text-[#53627f]">{section.body}</p>
            </section>
          ))}
        </div>
        <div className="mt-10 border-t border-[#e4e8ef] pt-6 text-sm text-[#667085]">
          Questions? Email{" "}
          <a
            className="font-semibold text-[#29476f] underline underline-offset-4"
            href="mailto:help.synorra@gmail.com"
          >
            help.synorra@gmail.com
          </a>
          . Read our{" "}
          <Link
            className="font-semibold text-[#29476f] underline underline-offset-4"
            href={relatedDocument.href}
          >
            {relatedDocument.label}
          </Link>
          .
        </div>
      </article>
    </main>
  );
}
