"use client";

import { useActionState } from "react";
import { changeCashierPassword, type PasswordChangeState } from "@/actions/auth";

const initial: PasswordChangeState = {};
const field = "w-full rounded-none border border-white/30 bg-transparent px-4 py-3 text-white outline-none focus:border-white";

export function CashierPasswordChangeForm({ username }: { username: string }) {
  const [state, action, pending] = useActionState(changeCashierPassword, initial);

  return (
    <form action={action} className="w-full max-w-md space-y-5 text-left">
      <label className="block text-sm">
        <span className="mb-2 block tracking-wide text-neutral-400 uppercase">Username</span>
        <input name="username" defaultValue={username} autoComplete="username" required className={field} />
      </label>
      <label className="block text-sm">
        <span className="mb-2 block tracking-wide text-neutral-400 uppercase">Current Owner password</span>
        <input name="password" type="password" autoComplete="current-password" required className={field} />
      </label>
      <label className="block text-sm">
        <span className="mb-2 block tracking-wide text-neutral-400 uppercase">New password</span>
        <input name="newPassword" type="password" autoComplete="new-password" minLength={8} required className={field} />
      </label>
      {state.error ? <p className="text-sm text-red-300">{state.error}</p> : null}
      <button type="submit" disabled={pending} className="w-full rounded-full bg-white py-3 text-sm font-medium text-black transition hover:bg-neutral-200 disabled:opacity-60">
        {pending ? "Saving..." : "Save new password"}
      </button>
    </form>
  );
}
