import { redirect } from "next/navigation";
import { AdminDashboard } from "@/components/AdminDashboard";
import { AdminShell } from "@/components/AdminShell";
import { FinanceDashboard } from "@/components/FinanceDashboard";
import { getSession } from "@/lib/auth";
import { getAdminLedgerEntries, getPayrollRecords, getStore } from "@/lib/store";
import { publicUser } from "@/lib/users";

export const dynamic = "force-dynamic";

export default async function AdminPage() {
  const session = await getSession();
  if (!session || session.role !== "cashier") {
    
    redirect("/");
  }

  
  const [store, ledger, payrollRecords] = await Promise.all([
    getStore({ includeAdminHistory: false, includeInventory: false }),
    getAdminLedgerEntries(),
    getPayrollRecords(),
  ]);

  return (
    <main className="min-h-svh overflow-x-clip bg-slate-50 text-slate-950">
      <AdminShell
        session={session}
        users={store.users.map(publicUser)}
        store={store}
        attendanceSettings={store.pos}
        financeContent={
          <FinanceDashboard
            key="finance-dashboard"
            store={store}
            initialExpenses={ledger.expenses}
            initialCredits={ledger.credits}
            initialLedgerError={ledger.error ?? null}
            payrollRecords={payrollRecords.records}
            payrollError={payrollRecords.error ?? null}
            remoteHistory
          />
        }
      >
        <AdminDashboard
          store={store}
          showPromoVoucher={
            session.permissions?.promotionsEnabled === true &&
            session.permissions?.promotionDiscount === true
          }
        />
      </AdminShell>
    </main>
  );
}
