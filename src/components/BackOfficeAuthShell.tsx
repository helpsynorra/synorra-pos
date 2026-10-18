import type { ReactNode } from "react";
import { BrandLogo } from "@/components/BrandLogo";

export function BackOfficeAuthShell({
  eyebrow,
  children,
}: {
  eyebrow: string;
  children: ReactNode;
}) {
  return (
    <main className="relative flex min-h-svh flex-col items-center justify-center overflow-x-hidden bg-slate-50 px-4 py-10 sm:px-6">
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -top-40 left-1/2 h-96 w-96 -translate-x-1/2 rounded-full bg-amber-100/70 blur-3xl"
      />
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -bottom-48 -right-32 h-96 w-96 rounded-full bg-slate-200/70 blur-3xl"
      />
      <section className="relative w-full max-w-md rounded-3xl border border-slate-200 bg-white p-7 shadow-xl shadow-slate-900/5 sm:p-9">
        <header className="mb-8 flex flex-col items-center text-center">
          <BrandLogo size="sm" />
          <span className="mt-2 text-[10px] font-semibold tracking-[0.3em] text-slate-500 uppercase">
            Synorra POS
          </span>
          <span className="mt-6 rounded-full bg-slate-100 px-3 py-1 text-[10px] font-semibold tracking-[0.18em] text-slate-500 uppercase">
            {eyebrow}
          </span>
        </header>
        {children}
      </section>
      <p className="relative mt-6 text-xs text-slate-400">
        &copy; 2026 Synorra. All rights reserved.
      </p>
    </main>
  );
}
