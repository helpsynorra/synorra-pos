"use client";

import Link from "next/link";
import { useActionState, useState } from "react";
import { resetOwnerPassword, type PasswordResetState } from "@/actions/auth";

const initial: PasswordResetState = {};
const field =
  "h-[58px] w-full rounded-[17px] border border-[#dce5f0] bg-white/80 pl-12 pr-12 text-[15px] text-[#17243e] outline-none transition placeholder:text-[#afbed1] focus:border-[#748eac] focus:ring-4 focus:ring-[#eaf1f8]";
const label =
  "mb-2 block text-[11px] font-bold tracking-[0.12em] text-[#6e89a6] uppercase";

export function ResetOwnerPasswordForm({ token }: { token: string }) {
  const [state, action, pending] = useActionState(resetOwnerPassword, initial);
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);

  if (!token || state.error?.toLowerCase().includes("invalid or expired")) {
    return (
      <section className="w-full space-y-5 text-center text-[#17243e]">
        <div className="mb-1">
          <h1 className="text-[26px] font-bold tracking-tight">Reset link expired</h1>
          <p className="mt-2 text-[15px] leading-6 text-[#7892af]">
            This reset link is invalid or expired. Request another reset to continue.
          </p>
        </div>
        <Link
          href="/back-office"
          className="inline-block text-sm font-medium text-[#243958] underline underline-offset-4 hover:text-[#536f91]"
        >
          Back to Sign In
        </Link>
      </section>
    );
  }

  if (state.reset) {
    return (
      <section className="w-full space-y-5 text-center text-[#17243e]">
        <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-[#edf5ef] text-2xl text-[#4f8a68]">
          ✓
        </div>
        <div>
          <h1 className="text-[26px] font-bold tracking-tight">Password updated</h1>
          <p className="mt-2 text-[15px] leading-6 text-[#7892af]">
            Your password has been reset. You can now sign in with your new password.
          </p>
        </div>
        <Link
          href="/back-office"
          className="inline-flex h-[58px] w-full items-center justify-center gap-3 rounded-[17px] bg-[#101d37] text-sm font-semibold text-white shadow-[0_12px_25px_rgba(20,38,70,0.2)] transition hover:bg-[#1b2c50]"
        >
          Back to Sign In <ArrowIcon />
        </Link>
      </section>
    );
  }

  return (
    <form action={action} className="w-full space-y-5 text-left text-[#17243e]">
      <input type="hidden" name="token" value={token} />
      <div className="mb-1 text-center">
        <h1 className="text-[26px] font-bold tracking-tight">Create a new password</h1>
        <p className="mt-2 text-[15px] leading-6 text-[#7892af]">
          Choose a strong password with at least 8 characters.
        </p>
      </div>
      <PasswordField
        name="password"
        label="New password"
        autoComplete="new-password"
        visible={showPassword}
        onToggle={() => setShowPassword((visible) => !visible)}
      />
      <PasswordField
        name="confirmPassword"
        label="Confirm new password"
        autoComplete="new-password"
        visible={showConfirmPassword}
        onToggle={() => setShowConfirmPassword((visible) => !visible)}
      />
      {state.error ? <p className="text-sm text-red-600">{state.error}</p> : null}
      <button
        type="submit"
        disabled={pending}
        className="flex h-[60px] w-full items-center justify-center gap-3 rounded-[17px] bg-[#101d37] text-sm font-semibold text-white shadow-[0_12px_25px_rgba(20,38,70,0.2)] transition hover:bg-[#1b2c50] disabled:cursor-wait disabled:opacity-60"
      >
        {pending ? "Updating password..." : "Reset password"}
        {!pending ? <ArrowIcon /> : null}
      </button>
      <Link
        href="/back-office"
        className="block text-center text-sm font-medium text-[#243958] underline underline-offset-4 hover:text-[#536f91]"
      >
        Back to Sign In
      </Link>
    </form>
  );
}

function PasswordField({
  name,
  label: fieldLabel,
  autoComplete,
  visible,
  onToggle,
}: {
  name: string;
  label: string;
  autoComplete: string;
  visible: boolean;
  onToggle: () => void;
}) {
  return (
    <label className="block text-sm">
      <span className={label}>{fieldLabel}</span>
      <span className="relative block">
        <svg
          aria-hidden="true"
          viewBox="0 0 24 24"
          className="absolute left-4 top-1/2 h-5 w-5 -translate-y-1/2 fill-none stroke-[#7792af]"
          strokeWidth="1.8"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <rect x="5" y="10" width="14" height="11" rx="2" />
          <path d="M8 10V7a4 4 0 1 1 8 0v3M12 14v3" />
        </svg>
        <input
          name={name}
          type={visible ? "text" : "password"}
          autoComplete={autoComplete}
          minLength={8}
          maxLength={128}
          placeholder="Enter your password"
          required
          className={field}
        />
        <button
          type="button"
          aria-label={visible ? "Hide password" : "Show password"}
          onClick={onToggle}
          className="absolute inset-y-0 right-3 flex items-center text-[#758ca8] hover:text-[#263b5c]"
        >
          <svg
            aria-hidden="true"
            viewBox="0 0 24 24"
            className="h-5 w-5 fill-none stroke-current"
            strokeWidth="1.8"
            strokeLinecap="round"
            strokeLinejoin="round"
          >
            {visible ? (
              <>
                <path d="m3 3 18 18M10.6 10.6a2 2 0 0 0 2.8 2.8M9.9 5.2A11.2 11.2 0 0 1 12 5c6.5 0 10 7 10 7a16 16 0 0 1-3.1 3.7M6.2 6.3C3.5 8.1 2 12 2 12s3.5 7 10 7c1 0 1.9-.2 2.7-.5" />
              </>
            ) : (
              <>
                <path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6-10-6-10-6Z" />
                <circle cx="12" cy="12" r="3" />
              </>
            )}
          </svg>
        </button>
      </span>
    </label>
  );
}

function ArrowIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24" className="h-5 w-5 fill-none stroke-current" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <path d="M5 12h14M13 6l6 6-6 6" />
    </svg>
  );
}
