"use client";

import Link from "next/link";
import { useActionState } from "react";
import { resetOwnerPassword, type PasswordResetState } from "@/actions/auth";

const initial: PasswordResetState = {};
const field =
  "w-full rounded-xl border border-slate-200 bg-white px-4 py-3 text-slate-900 outline-none transition focus:border-slate-500 focus:ring-4 focus:ring-slate-100";

export function ResetOwnerPasswordForm({ token }: { token: string }) {
  const [state, action, pending] = useActionState(resetOwnerPassword, initial);

  if (!token) {
    return (
      <section className="w-full space-y-5 text-left text-slate-900">
        <h1 className="text-2xl font-semibold tracking-tight">Reset password</h1>
        <p className="text-sm leading-6 text-slate-500">
          This reset link is invalid or expired. Request another reset.
        </p>
        <Link
          href="/back-office"
          className="text-sm font-medium text-slate-600 underline underline-offset-4 hover:text-slate-900"
        >
          Back to Sign In form
        </Link>
      </section>
    );
  }

  if (state.reset) {
    return (
      <section className="w-full space-y-5 text-left text-slate-900">
        <h1 className="text-2xl font-semibold tracking-tight">Password reset</h1>
        <p className="text-sm leading-6 text-slate-500">
          Your password has been reset. You can now sign in with your new password.
        </p>
        <Link
          href="/back-office"
          className="inline-block text-sm font-medium text-slate-600 underline underline-offset-4 hover:text-slate-900"
        >
          Back to Sign In form
        </Link>
      </section>
    );
  }

  return (
    <form action={action} className="w-full space-y-5 text-left text-slate-900">
      <input type="hidden" name="token" value={token} />
      <div className="space-y-2">
        <h1 className="text-2xl font-semibold tracking-tight">Reset password</h1>
        <p className="text-sm leading-6 text-slate-500">
          Enter a new password for your Owner account.
        </p>
      </div>
      <label className="block text-sm">
        <span className="mb-2 block font-medium text-slate-600">New password</span>
        <input
          name="password"
          type="password"
          autoComplete="new-password"
          minLength={8}
          maxLength={128}
          required
          className={field}
        />
      </label>
      <label className="block text-sm">
        <span className="mb-2 block font-medium text-slate-600">Confirm new password</span>
        <input
          name="confirmPassword"
          type="password"
          autoComplete="new-password"
          minLength={8}
          maxLength={128}
          required
          className={field}
        />
      </label>
      {state.error ? <p className="text-sm text-red-600">{state.error}</p> : null}
      <button
        type="submit"
        disabled={pending || !token}
        className="w-full rounded-xl bg-slate-900 py-3.5 text-sm font-semibold text-white shadow-sm transition hover:bg-slate-700 disabled:opacity-60"
      >
        {pending ? "Resetting..." : "Reset password"}
      </button>
      <Link
        href="/back-office"
        className="block text-center text-sm font-medium text-slate-600 underline underline-offset-4 hover:text-slate-900"
      >
        Back to Sign In form
      </Link>
    </form>
  );
}
