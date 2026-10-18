"use client";

import { useActionState, useState } from "react";
import {
  login,
  requestOwnerPasswordReset,
  type LoginState,
  type PasswordResetRequestState,
} from "@/actions/auth";

const initial: LoginState = {};
const ownerField =
  "h-[58px] w-full rounded-[17px] border border-[#dce5f0] bg-white/80 pl-12 pr-12 text-[15px] text-[#17243e] outline-none transition placeholder:text-[#afbed1] focus:border-[#748eac] focus:ring-4 focus:ring-[#eaf1f8]";
const ownerLabel =
  "mb-2 block text-[11px] font-bold tracking-[0.12em] text-[#6e89a6] uppercase";

export function LoginForm({ role }: { role: "admin" | "cashier" }) {
  const [state, action, pending] = useActionState(login, initial);
  const [showPasswordReset, setShowPasswordReset] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const isCashier = role === "cashier";

  if (isCashier && showPasswordReset) {
    return <PasswordResetRequest onBack={() => setShowPasswordReset(false)} />;
  }

  return (
    <form action={action} className={`w-full ${isCashier ? "space-y-6" : "space-y-5"}`}>
      <input type="hidden" name="role" value={role} />
      {isCashier ? (
        <div className="mb-1 text-center">
          <p className="mt-2 text-[15px] leading-6 text-[#7892af]">
            Sign in with your Email and Password.
          </p>
        </div>
      ) : null}

      {isCashier ? (
        <label className="block text-left">
          <span className={ownerLabel}>Email</span>
          <div className="relative">
            <FieldIcon kind="email" />
            <input
              name="email"
              type="email"
              autoComplete="email"
              placeholder="you@gmail.com"
              className={ownerField}
              required
            />
          </div>
        </label>
      ) : (
        <label className="block text-left text-sm">
          <span className="mb-2 block tracking-wide text-neutral-400 uppercase">
            Username
          </span>
          <input
            name="username"
            autoComplete="username"
            autoFocus
            className="w-full rounded-none border border-white/30 bg-transparent px-4 py-3 text-white outline-none focus:border-white"
            required
          />
        </label>
      )}

      <label className="block text-left">
        <span className={isCashier ? ownerLabel : "mb-2 block text-sm text-neutral-400"}>
          Password
        </span>
        <div className={isCashier ? "relative" : undefined}>
          {isCashier ? <FieldIcon kind="password" /> : null}
          <input
            name="password"
            type={isCashier && showPassword ? "text" : "password"}
            autoComplete="current-password"
            placeholder={isCashier ? "Enter your password" : undefined}
            required
            className={
              isCashier
                ? ownerField
                : "w-full rounded-none border border-white/30 bg-transparent px-4 py-3 text-white outline-none focus:border-white"
            }
          />
          {isCashier ? (
            <button
              type="button"
              aria-label={showPassword ? "Hide password" : "Show password"}
              onClick={() => setShowPassword((visible) => !visible)}
              className="absolute inset-y-0 right-3 flex items-center text-[#758ca8] hover:text-[#263b5c]"
            >
              <FieldIcon kind={showPassword ? "hide" : "show"} />
            </button>
          ) : null}
        </div>
      </label>

      {state?.error ? (
        <p className={`text-sm ${isCashier ? "text-red-600" : "text-red-300"}`}>
          {state.error}
        </p>
      ) : null}

      <button
        type="submit"
        disabled={pending}
        className={`w-full text-sm font-semibold transition disabled:cursor-wait disabled:opacity-60 ${
          isCashier
            ? "flex h-[60px] items-center justify-center gap-3 rounded-[17px] bg-[#101d37] text-white shadow-[0_12px_25px_rgba(20,38,70,0.2)] hover:bg-[#1b2c50]"
            : "rounded-full bg-white py-3.5 text-black hover:bg-neutral-200"
        }`}
      >
        {pending ? "Signing in..." : isCashier ? "Enter Synorra" : "Sign in"}
        {!pending && isCashier ? <ArrowIcon /> : null}
      </button>
      {isCashier ? (
        <button
          type="button"
          onClick={() => setShowPasswordReset(true)}
          className="w-full text-center text-sm font-medium text-[#243958] underline underline-offset-4 hover:text-[#536f91]"
        >
          Forgot password?
        </button>
      ) : null}
    </form>
  );
}

function PasswordResetRequest({ onBack }: { onBack: () => void }) {
  const [state, action, pending] = useActionState<
    PasswordResetRequestState,
    FormData
  >(requestOwnerPasswordReset, {});

  if (state.sent) {
    return (
      <section className="w-full space-y-5 text-center text-[#17243e]">
        <div className="mb-2 text-center">
          <h1 className="text-[26px] font-bold tracking-tight">Check your email</h1>
          <p className="mt-2 text-[15px] leading-6 text-[#7892af]">
            If an account exists with that email address, you will receive an email with instructions to reset your password.
          </p>
        </div>
        <button
          type="button"
          onClick={onBack}
          className="text-sm font-medium text-[#243958] underline underline-offset-4 hover:text-[#536f91]"
        >
          Back to Sign In
        </button>
      </section>
    );
  }

  return (
    <form action={action} className="w-full space-y-6 text-left text-[#17243e]">
      <div className="mb-1 text-center">
        <h1 className="text-[26px] font-bold tracking-tight">Forgot password?</h1>
        <p className="mt-2 text-[15px] leading-6 text-[#7892af]">
          Enter your email and we’ll send you a secure reset link.
        </p>
      </div>
      <label className="block text-sm">
        <span className={ownerLabel}>Email</span>
        <div className="relative">
          <FieldIcon kind="email" />
          <input
            name="email"
            type="email"
            autoComplete="email"
            autoFocus
            placeholder="you@gmail.com"
            required
            className={ownerField}
          />
        </div>
      </label>
      {state.error ? <p className="text-sm text-red-600">{state.error}</p> : null}
      <button
        type="submit"
        disabled={pending}
        className="flex h-[60px] w-full items-center justify-center gap-3 rounded-[17px] bg-[#101d37] text-sm font-semibold text-white shadow-[0_12px_25px_rgba(20,38,70,0.2)] transition hover:bg-[#1b2c50] disabled:cursor-wait disabled:opacity-60"
      >
        {pending ? "Sending..." : "Send reset link"}
        {!pending ? <ArrowIcon /> : null}
      </button>
      <button
        type="button"
        onClick={onBack}
        className="w-full text-center text-sm font-medium text-[#243958] underline underline-offset-4 hover:text-[#536f91]"
      >
        Back to Sign In
      </button>
    </form>
  );
}

function FieldIcon({ kind }: { kind: "email" | "password" | "show" | "hide" }) {
  const common = {
    className: "h-5 w-5 fill-none stroke-current",
    viewBox: "0 0 24 24",
    strokeWidth: 1.8,
    strokeLinecap: "round" as const,
    strokeLinejoin: "round" as const,
    "aria-hidden": true as const,
  };
  const icon = {
    email: <><rect x="3" y="5" width="18" height="14" rx="2" /><path d="m4 7 8 6 8-6" /></>,
    password: <><rect x="5" y="10" width="14" height="11" rx="2" /><path d="M8 10V7a4 4 0 1 1 8 0v3M12 14v3" /></>,
    show: <><path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6-10-6-10-6Z" /><circle cx="12" cy="12" r="3" /></>,
    hide: <><path d="m3 3 18 18M10.6 10.6a2 2 0 0 0 2.8 2.8M9.9 5.2A11.2 11.2 0 0 1 12 5c6.5 0 10 7 10 7a16 16 0 0 1-3.1 3.7M6.2 6.3C3.5 8.1 2 12 2 12s3.5 7 10 7c1 0 1.9-.2 2.7-.5" /></>,
  }[kind];

  if (kind === "show" || kind === "hide") {
    return <svg {...common}>{icon}</svg>;
  }

  return (
    <svg {...common} className={`${common.className} absolute left-4 top-1/2 -translate-y-1/2 text-[#7792af]`}>
      {icon}
    </svg>
  );
}

function ArrowIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24" className="h-5 w-5 fill-none stroke-current" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M5 12h14M13 6l6 6-6 6" />
    </svg>
  );
}
