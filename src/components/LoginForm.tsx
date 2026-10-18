"use client";

import { useActionState, useState } from "react";
import {
  login,
  requestOwnerPasswordReset,
  type LoginState,
  type PasswordResetRequestState,
} from "@/actions/auth";

const initial: LoginState = {};

const darkField =
  "w-full rounded-none border border-white/30 bg-transparent px-4 py-3 text-white outline-none focus:border-white";
const lightField =
  "w-full rounded-xl border border-slate-200 bg-white px-4 py-3 text-slate-900 outline-none transition placeholder:text-slate-400 focus:border-slate-500 focus:ring-4 focus:ring-slate-100";

export function LoginForm({ role }: { role: "admin" | "cashier" }) {
  const [state, action, pending] = useActionState(login, initial);
  const [showPasswordReset, setShowPasswordReset] = useState(false);
  const isCashier = role === "cashier";
  const field = isCashier ? lightField : darkField;
  const labelColor = isCashier ? "text-slate-600" : "text-neutral-400";

  if (isCashier && showPasswordReset) {
    return (
      <PasswordResetRequest onBack={() => setShowPasswordReset(false)} />
    );
  }

  return (
    <form action={action} className="w-full space-y-5">
      <input type="hidden" name="role" value={role} />
      {isCashier ? (
        <div className="mb-2 text-center">
          <h1 className="text-2xl font-semibold tracking-tight text-slate-900">
            Welcome back
          </h1>
          <p className="mt-2 text-sm leading-6 text-slate-500">
            Sign in with your Email and Password.
          </p>
        </div>
      ) : null}

      {isCashier ? (
        <label className="block text-left text-sm">
          <span className={`mb-2 block tracking-wide uppercase ${labelColor}`}>
            Email
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
          <span className={`mb-2 block tracking-wide uppercase ${labelColor}`}>
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
        <span className={`mb-2 block tracking-wide uppercase ${labelColor}`}>
            {isCashier ? "Password" : "Password"}
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
        <p className={`text-sm ${isCashier ? "text-red-600" : "text-red-300"}`}>
          {state.error}
        </p>
      ) : null}

      <button
        type="submit"
        disabled={pending}
        className={`w-full py-3.5 text-sm font-semibold transition disabled:opacity-60 ${
          isCashier
            ? "rounded-xl bg-slate-900 text-white shadow-sm hover:bg-slate-700"
            : "rounded-full bg-white text-black hover:bg-neutral-200"
        }`}
      >
        {pending ? "Signing in..." : "Enter Synorra"}
      </button>
      {isCashier ? (
        <button
          type="button"
          onClick={() => setShowPasswordReset(true)}
          className="w-full text-sm font-medium text-slate-600 underline underline-offset-4 hover:text-slate-900"
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
      <section className="w-full space-y-5 text-left text-slate-900">
        <h1 className="text-2xl font-semibold tracking-tight">Reset password</h1>
        <p className="text-sm leading-6 text-slate-500">
          If an account exists with that email address, you will receive an email with instructions to reset your password.
        </p>
        <button
          type="button"
          onClick={onBack}
          className="text-sm font-medium text-slate-600 underline underline-offset-4 hover:text-slate-900"
        >
          Back to Sign In form
        </button>
      </section>
    );
  }

  return (
    <form action={action} className="w-full space-y-5 text-left text-slate-900">
      <div className="space-y-2">
        <h1 className="text-2xl font-semibold tracking-tight">Reset password</h1>
        <p className="text-sm leading-6 text-slate-500">
          Enter your email to receive instructions to reset your password
        </p>
      </div>
      <label className="block text-sm">
        <span className="mb-2 block font-medium text-slate-600">Email</span>
        <input
          name="email"
          type="email"
          autoComplete="email"
          autoFocus
          required
          className={lightField}
        />
      </label>
      {state.error ? <p className="text-sm text-red-600">{state.error}</p> : null}
      <button
        type="submit"
        disabled={pending}
        className="w-full rounded-xl bg-slate-900 py-3.5 text-sm font-semibold text-white shadow-sm transition hover:bg-slate-700 disabled:opacity-60"
      >
        {pending ? "Sending..." : "Continue"}
      </button>
      <button
        type="button"
        onClick={onBack}
        className="w-full text-sm font-medium text-slate-600 underline underline-offset-4 hover:text-slate-900"
      >
        Back to Sign In form
      </button>
    </form>
  );
}
