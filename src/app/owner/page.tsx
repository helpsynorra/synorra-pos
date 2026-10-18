import { redirect } from "next/navigation";
import { AdminDashboard } from "@/components/AdminDashboard";
import { AdminShell } from "@/components/AdminShell";
import { getSession } from "@/lib/auth";
import { getAdminLedgerEntries, getStore } from "@/lib/store";
import { publicUser } from "@/lib/users";

export const dynamic = "force-dynamic";

export default async function AdminPage() {
  const session = await getSession();
  if (!session || session.role !== "cashier") {
    
    redirect("/");
  }

  
  let store: Awaited<ReturnType<typeof getStore>>;
  let ledger: Awaited<ReturnType<typeof getAdminLedgerEntries>>;
  try {
    [store, ledger] = await Promise.all([getStore(), getAdminLedgerEntries()]);
  } catch (error) {
    // React's production Server Component error (#441) hides the useful
    // Supabase/PostgREST message. Keep the details in server logs and show
    // the owner the actionable setup hint without falling back to shared data.
    console.error("Unable to load Owner workspace", error);
    return (
      <main className="min-h-svh bg-neutral-100 p-6 text-black">
        <section className="mx-auto mt-12 max-w-2xl rounded-xl border border-red-200 bg-white p-6">
          <h1 className="text-lg font-semibold">Hindi ma-load ang Owner workspace</h1>
          <p className="mt-2 text-sm text-neutral-600">
            I-apply ang latest Supabase migrations, kasama ang
            <code className="mx-1 rounded bg-neutral-100 px-1">20261018001600_owner_data_isolation.sql</code>,
            pagkatapos ay i-refresh ang page. Walang shared-data fallback para
            hindi mahalo ang records ng bawat Owner.
          </p>
        </section>
      </main>
    );
  }

  return (
    <main className="min-h-svh overflow-x-hidden bg-neutral-100 text-black">
      <AdminShell session={session} users={store.users.map(publicUser)} store={store}>
        <AdminDashboard
          store={store}
          initialExpenses={ledger.expenses}
          initialCredits={ledger.credits}
          initialLedgerError={ledger.error ?? null}
        />
      </AdminShell>
    </main>
  );
}
