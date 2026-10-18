import type { Metadata } from "next";
import { SiteFooter } from "@/components/SiteFooter";
import { CAFE } from "@/lib/cafe";

export const metadata: Metadata = {
  title: `Follow Us | ${CAFE.name}`,
  description: `Follow ${CAFE.name} on Facebook, Instagram, and TikTok.`,
};

const socialDetails = {
  facebook: {
    action: "Visit our Facebook page",
    accent: "group-hover:border-blue-400/50 group-hover:bg-blue-950/30",
  },
  instagram: {
    action: "Follow us on Instagram",
    accent: "group-hover:border-pink-400/50 group-hover:bg-pink-950/20",
  },
  tiktok: {
    action: "Find us on TikTok",
    accent: "group-hover:border-cyan-300/50 group-hover:bg-cyan-950/20",
  },
} as const;

export default function FollowPage() {
  return (
    <>
      <main className="relative flex min-h-[72vh] flex-col overflow-hidden bg-[radial-gradient(ellipse_at_50%_0%,rgba(120,85,55,0.22),transparent_55%),#0a0a0a] px-5 pb-20 pt-12 text-white sm:px-8 sm:pt-16">
        <div className="mx-auto w-full max-w-5xl flex-1">
          <p className="text-center font-script text-3xl text-amber-100/75 sm:text-4xl">
            Synorra
          </p>
          <div className="mx-auto mt-12 max-w-2xl text-center sm:mt-16">
            <h1 className="mt-2 font-serif text-4xl italic sm:text-6xl">
              Follow Synorra.
            </h1>
          </div>

          <div className="mx-auto mt-12 grid max-w-4xl gap-4 md:grid-cols-3">
            {CAFE.socials.map((social) => {
              const details = socialDetails[social.id];

              return (
                <a
                  key={social.id}
                  href={social.href}
                  target="_blank"
                  rel="noopener noreferrer"
                  className={`group rounded-3xl border border-white/10 bg-white/[0.035] p-6 transition duration-300 hover:-translate-y-1 hover:bg-white/[0.07] sm:p-7 ${details.accent}`}
                >
                  <span className="flex h-12 w-12 items-center justify-center rounded-2xl border border-white/10 bg-white/[0.06] font-serif text-xl text-white">
                    {social.id === "facebook" ? "f" : social.id === "instagram" ? "◎" : "♪"}
                  </span>
                  <h2 className="mt-2 font-serif text-2xl">{social.label}</h2>
                  <span className="mt-6 inline-flex items-center gap-2 text-xs text-neutral-300 transition group-hover:text-white">
                    {details.action}
                    <span aria-hidden="true" className="transition group-hover:translate-x-1">→</span>
                  </span>
                </a>
              );
            })}
          </div>
        </div>
      </main>
      <SiteFooter />
    </>
  );
}
