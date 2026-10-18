import { redirect } from "next/navigation";
import { CashierPasswordChangeForm } from "@/components/CashierPasswordChangeForm";
import { getSession } from "@/lib/auth";
import { BrandLogo } from "@/components/BrandLogo";
import { getStore } from "@/lib/store";

export const dynamic = "force-dynamic";

export default async function ChangeCashierPasswordPage() {
  const session = await getSession();
  if (!session || session.role !== "cashier" || !session.mustChangePassword) {
    redirect("/");
  }
  const store = await getStore();
  const owner = store.users.find((user) => user.id === session.userId && user.role === "cashier");
  if (!owner) redirect("/");

  return (
    <main className="relative flex min-h-svh items-center justify-center overflow-hidden px-4 py-12 sm:px-6 sm:py-16">
      <div className="absolute inset-0 bg-cover bg-center" style={{ backgroundImage: "url(/images/hero-wide.jpg)" }} />
      <div className="absolute inset-0 bg-black/80" />
      <section className="relative z-10 flex w-full max-w-md flex-col items-center text-center">
        <BrandLogo size="md" showTagline />
        <h1 className="mt-8 mb-3 text-xl font-semibold text-white">Set your new password</h1>
        <p className="mb-8 text-sm text-neutral-300">This is required once for your Owner account.</p>
        <CashierPasswordChangeForm email={owner.email ?? ""} />
      </section>
    </main>
  );
}
