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

  
  const [store, ledger] = await Promise.all([getStore(), getAdminLedgerEntries()]);

  return (
    <main className="min-h-svh overflow-x-clip bg-slate-50 text-slate-950">
      <AdminShell session={session} users={store.users.map(publicUser)} store={store}>
        <AdminDashboard
          store={store}
          showPromoVoucher={
            session.permissions?.promotionsEnabled === true &&
            session.permissions?.promotionDiscount === true
          }
          initialExpenses={ledger.expenses}
          initialCredits={ledger.credits}
          initialLedgerError={ledger.error ?? null}
        />
      </AdminShell>
    </main>
  );
}
