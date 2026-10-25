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
    <main className="relative grid min-h-svh grid-cols-1 place-items-center overflow-hidden bg-[#f5f8fd] px-4 py-8 sm:px-6 sm:py-12 md:grid-cols-[minmax(0,0.95fr)_minmax(0,1.05fr)] md:place-items-stretch md:gap-4 md:px-5 md:py-6 lg:gap-8 lg:px-8 lg:py-8 xl:grid-cols-[minmax(0,1.1fr)_minmax(460px,0.9fr)] xl:gap-12 xl:px-12 xl:py-10 2xl:gap-20 2xl:px-20">
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -left-44 -top-56 h-[620px] w-[620px] rounded-full bg-[#dceeff]/85 blur-[90px]"
      />
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -bottom-[380px] -right-44 h-[760px] w-[760px] rounded-full bg-[#dfe3ff]/80 blur-[100px]"
      />
      <div aria-hidden="true" className="relative z-10 mb-5 hidden h-28 w-56 items-end justify-center sm:flex md:hidden">
        <div className="absolute bottom-3 h-5 w-48 -skew-x-12 rounded-full bg-[#b7c9df]/45 blur-md" />
        <div className="relative z-10 h-20 w-40 -skew-y-6 rounded-2xl border border-white bg-gradient-to-br from-white to-[#dbe6f2] p-2.5 shadow-[10px_14px_25px_rgba(47,72,107,0.18)]">
          <div className="h-full rounded-xl border border-[#d8e2ef] bg-white p-2">
            <div className="flex items-center justify-between border-b border-[#e7edf5] pb-1.5 text-[8px] font-bold tracking-wide text-[#243958]">
              <span>REGISTER</span><span className="text-emerald-600">READY</span>
            </div>
            <div className="mt-2 grid grid-cols-3 gap-1"><span className="h-4 rounded bg-[#edf2f8]" /><span className="h-4 rounded bg-[#edf2f8]" /><span className="h-4 rounded bg-[#edf2f8]" /></div>
          </div>
        </div>
        <div className="absolute bottom-1 h-3 w-36 -skew-x-12 rounded-b-lg bg-[#aebfd3]" />
      </div>
      <section className="relative z-10 hidden min-h-[min(760px,calc(100svh-80px))] w-full flex-col justify-center md:flex md:min-h-0 md:justify-start md:pt-3 xl:min-h-[min(760px,calc(100svh-80px))] xl:justify-center xl:py-0">
        <Image src="/images/logo-transparent.png" alt="Synorra POS" width={360} height={360} priority className="h-[58px] w-[188px] object-cover object-left" />
        <p className="mt-8 text-[10px] font-bold tracking-[0.2em] text-[#6c83a0] uppercase lg:mt-12 lg:text-xs lg:tracking-[0.25em]">Point of sale · inventory · team</p>
        <h1 className="mt-3 max-w-xl text-3xl font-semibold leading-[1.08] tracking-tight text-[#17243e] lg:mt-4 lg:text-5xl 2xl:text-6xl">A smoother day starts at the counter.</h1>
        <p className="mt-4 max-w-lg text-sm leading-6 text-[#7086a1] lg:mt-5 lg:text-base lg:leading-7">Sign in to manage your shop, serve internals, and keep every order moving.</p>
        <div aria-hidden="true" className="relative mt-4 h-[260px] w-full max-w-[650px]">
          <div className="absolute bottom-7 left-10 right-8 h-14 -skew-x-12 rounded-full bg-[#b7c9df]/45 blur-xl" />
          <div className="relative z-10 ml-8 mt-10 h-52 w-[min(72%,420px)] rounded-[28px] border border-white bg-gradient-to-br from-white via-[#edf3fa] to-[#dbe6f2] p-4 shadow-[18px_24px_50px_rgba(47,72,107,0.2)] lg:p-5">
            <div className="h-full rounded-2xl border border-[#d8e2ef] bg-white p-3 shadow-inner lg:p-4">
              <div className="flex items-center justify-between border-b border-[#e7edf5] pb-3">
                <span className="text-xs font-bold tracking-wide text-[#243958]">REGISTER</span>
                <span className="flex items-center gap-1.5 text-[10px] text-[#54836f]"><span className="size-2 rounded-full bg-emerald-500" /> READY</span>
              </div>
              <div className="mt-4 grid grid-cols-3 gap-2">
                <span className="h-9 rounded-xl bg-[#f1f5fa]" /><span className="h-9 rounded-xl bg-[#f1f5fa]" /><span className="h-9 rounded-xl bg-[#f1f5fa]" />
                <span className="h-9 rounded-xl bg-[#f1f5fa]" /><span className="h-9 rounded-xl bg-[#f1f5fa]" /><span className="h-9 rounded-xl bg-[#1d2b45]" />
              </div>
            </div>
          </div>
          <div className="absolute bottom-4 left-[20%] h-12 w-[58%] -skew-x-12 rounded-b-[22px] border border-[#cbd7e6] bg-gradient-to-r from-[#d4dfec] via-white to-[#c5d3e4] shadow-[12px_16px_25px_rgba(47,72,107,0.16)]" />
          <div className="absolute bottom-0 left-[29%] h-5 w-[40%] -skew-x-12 rounded-b-xl bg-[#aebfd3]" />
        </div>
      </section>
      <section className="relative z-10 w-full max-w-[620px] rounded-[26px] border border-white/80 bg-white/95 px-6 py-7 shadow-[0_24px_80px_rgba(51,91,143,0.14)] backdrop-blur-sm sm:px-10 sm:py-9 md:mx-auto md:h-fit md:max-w-[560px] md:self-center md:px-6 md:py-7 lg:px-8 xl:max-w-[560px] xl:px-10 xl:py-9">
        <header className="mb-7 flex flex-col items-center text-center">
          <Image
            src="/images/logo-transparent.png"
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

    </main>
  );
}
