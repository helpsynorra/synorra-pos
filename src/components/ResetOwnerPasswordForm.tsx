"use client";

import Link from "next/link";
import { useActionState } from "react";
import { resetOwnerPassword, type PasswordResetState } from "@/actions/auth";

const initial: PasswordResetState = {};
const field =
  "w-full rounded-none border border-white/30 bg-transparent px-4 py-3 text-white outline-none focus:border-white";

export function ResetOwnerPasswordForm({ token }: { token: string }) {
  const [state, action, pending] = useActionState(resetOwnerPassword, initial);

  if (!token) {
    return (
      <section className="w-full max-w-md space-y-6 text-left text-white">
        <h1 className="text-2xl font-medium">Reset password</h1>
        <p className="text-sm leading-6 text-neutral-300">
          This reset link is invalid or expired. Request another reset.
        </p>
        <Link
          href="/back-office"
          className="text-sm text-neutral-300 underline underline-offset-4 hover:text-white"
        >
          Back to Sign In form
        </Link>
      </section>
    );
  }

  if (state.reset) {
    return (
      <section className="w-full max-w-md space-y-6 text-left text-white">
        <h1 className="text-2xl font-medium">Password reset</h1>
        <p className="text-sm leading-6 text-neutral-300">
          Your password has been reset. You can now sign in with your new password.
        </p>
        <Link
          href="/back-office"
          className="inline-block text-sm text-neutral-300 underline underline-offset-4 hover:text-white"
        >
          Back to Sign In form
        </Link>
      </section>
    );
  }

  return (
    <form action={action} className="w-full max-w-md space-y-6 text-left text-white">
      <input type="hidden" name="token" value={token} />
      <div className="space-y-2">
        <h1 className="text-2xl font-medium">Reset password</h1>
        <p className="text-sm leading-6 text-neutral-300">
          Enter a new password for your Owner account.
        </p>
      </div>
      <label className="block text-sm">
        <span className="mb-2 block text-neutral-400">New password</span>
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
        <span className="mb-2 block text-neutral-400">Confirm new password</span>
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
      {state.error ? <p className="text-sm text-red-300">{state.error}</p> : null}
      <button
        type="submit"
        disabled={pending || !token}
        className="w-full rounded-full bg-white py-3 text-sm font-medium text-black transition hover:bg-neutral-200 disabled:opacity-60"
      >
        {pending ? "Resetting..." : "Reset password"}
      </button>
      <Link
        href="/back-office"
        className="block text-center text-sm text-neutral-300 underline underline-offset-4 hover:text-white"
      >
        Back to Sign In form
      </Link>
    </form>
  );
}
