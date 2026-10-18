import type { ReactNode } from "react";
import Image from "next/image";

export function BackOfficeAuthShell({
  eyebrow,
  children,
}: {
  eyebrow: string;
  children: ReactNode;
}) {
  return (
    <main className="relative flex min-h-svh flex-col items-center justify-center overflow-hidden bg-[#f5f8fd] px-4 py-8 sm:px-6 sm:py-12">
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -left-44 -top-56 h-[620px] w-[620px] rounded-full bg-[#dceeff]/85 blur-[90px]"
      />
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -bottom-[380px] -right-44 h-[760px] w-[760px] rounded-full bg-[#dfe3ff]/80 blur-[100px]"
      />
      <section className="relative z-10 w-full max-w-[620px] rounded-[26px] border border-white/80 bg-white/90 px-7 py-8 shadow-[0_24px_80px_rgba(51,91,143,0.14)] backdrop-blur-sm sm:px-10 sm:py-9">
        <header className="mb-7 flex flex-col items-center text-center">
          <Image
            src="/images/logo.png"
            alt="Synorra"
            width={360}
            height={360}
            priority
            className="h-[58px] w-[188px] object-cover"
          />
          <span className="mt-4 inline-flex items-center gap-2 rounded-full bg-[#eff4fa] px-4 py-2 text-[11px] font-semibold tracking-[0.12em] text-[#6683a1] uppercase">
            <svg
              aria-hidden="true"
              viewBox="0 0 20 20"
              className="h-4 w-4 fill-none stroke-current"
              strokeWidth="1.8"
            >
              <circle cx="10" cy="6" r="3" />
              <path
                d="M4 17c.4-3 2.5-4.6 6-4.6s5.6 1.6 6 4.6"
                strokeLinecap="round"
              />
            </svg>
            {eyebrow}
          </span>
        </header>
        {children}
      </section>
      <p className="relative z-10 mt-6 text-xs text-[#7f9bb9]">
        &copy; 2026 Synorra. All rights reserved.
      </p>
    </main>
  );
}
