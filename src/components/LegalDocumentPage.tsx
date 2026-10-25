import Link from "next/link";
import {
  cookieCategories,
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
      ? "Terms & Conditions (Terms of Service)"
      : kind === "privacy"
        ? "Privacy & Cookie Policy"
        : "Cookie Policy";
  const sections: LegalSection[] =
    kind === "terms"
      ? termsOfUse
      : kind === "privacy"
        ? [...privacyPolicy, ...cookiePolicy]
        : cookiePolicy;
  const relatedDocument =
    kind === "terms"
      ? { href: "/privacy", label: "Privacy & Cookie Policy" }
      : kind === "privacy"
        ? { href: "/terms", label: "Terms of Use" }
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
          Last updated October 25, 2026
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
          {(kind === "privacy" || kind === "cookies") && (
            <section>
              <h2 className="text-lg font-semibold">Cookie categories</h2>
              <div className="mt-3 overflow-x-auto rounded-xl border border-[#e4e8ef]">
                <table className="w-full min-w-[620px] border-collapse text-left text-sm">
                  <thead className="bg-[#f5f6f8] text-[#18263e]">
                    <tr>
                      <th scope="col" className="px-4 py-3 font-semibold">Category</th>
                      <th scope="col" className="px-4 py-3 font-semibold">Purpose</th>
                      <th scope="col" className="px-4 py-3 font-semibold">Current use</th>
                    </tr>
                  </thead>
                  <tbody>
                    {cookieCategories.map((cookie) => (
                      <tr key={cookie.category} className="border-t border-[#e4e8ef] align-top text-[#53627f]">
                        <th scope="row" className="px-4 py-3 font-semibold text-[#18263e]">{cookie.category}</th>
                        <td className="px-4 py-3 leading-6">{cookie.purpose}</td>
                        <td className="px-4 py-3 leading-6">{cookie.currentUse}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </section>
          )}
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
