"use client";

import { useActionState, useState } from "react";
import {
  login,
  requestOwnerPasswordReset,
  type LoginState,
  type PasswordResetRequestState,
} from "@/actions/auth";

const initial: LoginState = {};

const field =
  "w-full rounded-none border border-white/30 bg-transparent px-4 py-3 text-white outline-none focus:border-white";

export function LoginForm({ role }: { role: "admin" | "cashier" }) {
  const [state, action, pending] = useActionState(login, initial);
  const [showPasswordReset, setShowPasswordReset] = useState(false);
  const isCashier = role === "cashier";

  if (isCashier && showPasswordReset) {
    return <PasswordResetRequest onBack={() => setShowPasswordReset(false)} />;
  }

  return (
    <form action={action} className="w-full max-w-md space-y-6">
      <input type="hidden" name="role" value={role} />

      {isCashier ? (
        <label className="block text-left text-sm">
          <span className="mb-2 block tracking-wide text-neutral-400 uppercase">
            Owner email
          </span>
          <input
            name="email"
            type="email"
            autoComplete="email"
            className={field}
            required
          />
        </label>
      ) : null}

      {!isCashier ? (
        <label className="block text-left text-sm">
          <span className="mb-2 block tracking-wide text-neutral-400 uppercase">
            Username
          </span>
          <input
            name="username"
            autoComplete="username"
            autoFocus
            className={field}
            required
          />
        </label>
      ) : null}

      <label className="block text-left text-sm">
        <span className="mb-2 block tracking-wide text-neutral-400 uppercase">
          Password
        </span>
        <input
          name="password"
          type="password"
          autoComplete="current-password"
          required
          className={field}
        />
      </label>

      {state?.error ? (
        <p className="text-sm text-red-300">{state.error}</p>
      ) : null}

      <button
        type="submit"
        disabled={pending}
        className="w-full rounded-full bg-white py-3 text-sm font-medium text-black transition hover:bg-neutral-200 disabled:opacity-60"
      >
        {pending ? "Signing in..." : "Enter Synorra"}
      </button>
      {isCashier ? (
        <button
          type="button"
          onClick={() => setShowPasswordReset(true)}
          className="w-full text-sm text-neutral-300 underline underline-offset-4 hover:text-white"
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
      <section className="w-full max-w-md space-y-6 text-left text-white">
        <h1 className="text-2xl font-medium">Reset password</h1>
        <p className="text-sm leading-6 text-neutral-300">
          If an account exists with that email address, you will receive an email with instructions to reset your password.
        </p>
        <button
          type="button"
          onClick={onBack}
          className="text-sm text-neutral-300 underline underline-offset-4 hover:text-white"
        >
          Back to Sign In form
        </button>
      </section>
    );
  }

  return (
    <form action={action} className="w-full max-w-md space-y-6 text-left text-white">
      <div className="space-y-2">
        <h1 className="text-2xl font-medium">Reset password</h1>
        <p className="text-sm leading-6 text-neutral-300">
          Enter your email to receive instructions to reset your password
        </p>
      </div>
      <label className="block text-sm">
        <span className="mb-2 block tracking-wide text-neutral-400">Email</span>
        <input
          name="email"
          type="email"
          autoComplete="email"
          autoFocus
          required
          className={field}
        />
      </label>
      {state.error ? <p className="text-sm text-red-300">{state.error}</p> : null}
      <button
        type="submit"
        disabled={pending}
        className="w-full rounded-full bg-white py-3 text-sm font-medium text-black transition hover:bg-neutral-200 disabled:opacity-60"
      >
        {pending ? "Sending..." : "Continue"}
      </button>
      <button
        type="button"
        onClick={onBack}
        className="w-full text-sm text-neutral-300 underline underline-offset-4 hover:text-white"
      >
        Back to Sign In form
      </button>
    </form>
  );
}
