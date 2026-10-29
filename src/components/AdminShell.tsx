"use client";

import { useState, useEffect, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { StaffHeader, type AdminPanel } from "@/components/StaffHeader";
import { UserManager } from "@/components/UserManager";
import { SalePurchaseTransactions } from "@/components/SalePurchaseTransactions";
import type { PublicStaffUser } from "@/lib/users";
import type { Session, StoreData } from "@/lib/types";

type AdminShellProps = {
  session: Session;
  users: PublicStaffUser[];
  store: StoreData;
  children: ReactNode;
  financeContent: ReactNode;
  attendanceSettings: StoreData["pos"];
};

function readSavedPanel(): AdminPanel {
  const savedPanel = window.localStorage.getItem("admin_activePanel");
  const savedSection = window.localStorage.getItem("admin_section");
  if (savedPanel === "staff" || savedSection === "staff") return "sales";
  if (savedPanel === "transactions" || savedPanel === "finance") {
    return savedPanel;
  }
  return "sales";
}

export function AdminShell({ session, users, store, children, financeContent, attendanceSettings }: AdminShellProps) {
  const [panel, setPanel] = useState<AdminPanel>("sales");
  const [isMounted, setIsMounted] = useState(false);
  const [loginActivity, setLoginActivity] = useState<StoreData["loginActivity"]>([]);
  const [loginActivityPage, setLoginActivityPage] = useState(0);
  const [loginActivityHasMore, setLoginActivityHasMore] = useState(false);
  const [loginActivityLoading, setLoginActivityLoading] = useState(false);
  const [loginActivityError, setLoginActivityError] = useState<string | null>(null);
  const router = useRouter();
  const currentPanel = isMounted ? panel : "sales";

  useEffect(() => {
    if (panel !== "transactions" && panel !== "sales" && panel !== "staff" && panel !== "finance") return;
    // Keep Admin lookups reasonably fresh without polling every 5 seconds.
    const refreshTimer = window.setInterval(() => router.refresh(), 60000);
    return () => window.clearInterval(refreshTimer);
  }, [panel, router]);

  /* eslint-disable react-hooks/set-state-in-effect */
  useEffect(() => {
    setPanel(readSavedPanel());
    setIsMounted(true);
  }, []);
  /* eslint-enable react-hooks/set-state-in-effect */

  useEffect(() => {
    if (currentPanel !== "staff") return;
    let active = true;
    fetch("/api/admin/login-activity?page=1", { cache: "no-store" })
      .then(async (response) => {
        const result = await response.json();
        if (!response.ok) throw new Error(result.error || "Unable to load staff activity.");
        if (!active) return;
        setLoginActivity(result.activity);
        setLoginActivityPage(result.page);
        setLoginActivityHasMore(result.hasMore);
      })
      .catch((error: unknown) => {
        if (active) setLoginActivityError(error instanceof Error ? error.message : "Unable to load staff activity.");
      })
      .finally(() => {
        if (active) setLoginActivityLoading(false);
      });
    return () => { active = false; };
  }, [currentPanel]);

  function handlePanelChange(next: AdminPanel) {
    setPanel(next);
    if (next === "staff") {
      setLoginActivityLoading(true);
      setLoginActivityError(null);
    }
    window.localStorage.setItem("admin_activePanel", next);
    window.localStorage.setItem("admin_section", next === "staff" ? "staff" : "admin");
  }

  async function loadMoreLoginActivity() {
    if (loginActivityLoading || !loginActivityHasMore) return;
    setLoginActivityLoading(true);
    setLoginActivityError(null);
    try {
      const response = await fetch(`/api/admin/login-activity?page=${loginActivityPage + 1}`, { cache: "no-store" });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || "Unable to load staff activity.");
      setLoginActivity((current) => [...current, ...result.activity]);
      setLoginActivityPage(result.page);
      setLoginActivityHasMore(result.hasMore);
    } catch (error) {
      setLoginActivityError(error instanceof Error ? error.message : "Unable to load staff activity.");
    } finally {
      setLoginActivityLoading(false);
    }
  }

  const current = currentPanel;

  return (
    <>
      <StaffHeader session={session} panel={current} onPanelChange={handlePanelChange} />

      <div className="min-w-0 xl:pl-60">
        <div className="mx-auto min-h-[calc(100svh-65px)] w-full max-w-[1920px] min-w-0">
          {current === "staff" ? (
            <>
            <UserManager
              users={users.filter((user) => user.role !== "admin")}
              session={session}
              loginActivity={loginActivity}
              offRequests={store.offRequests ?? []}
              showAdminRole={false}
              showOwnerRole={false}
              showBaristaRole={true}
              showCashierRole={true}
              showBaristasOnly={false}
              showEditStaffButton={session.role === "cashier"}
              baristaOnlyStaffActions={true}
              printButtonHidden={store.pos.printButtonHidden}
              showLoginLinksTab={session.role !== "cashier"}
              showPrintButtonToggle={session.role !== "cashier"}
              showViewPermissionsButton={session.role !== "cashier"}
              adminLoginPath={store.loginGates.admin}
              attendanceSettings={attendanceSettings}
              workShifts={store.workShifts}
              workShiftError={store.workShiftError}
              showAttendanceSettings={session.role === "cashier"}
              showScheduleTab={session.role === "cashier"}
            />
            <div className="mx-auto max-w-[1920px] px-4 pb-6">
              {loginActivityLoading && loginActivity.length === 0 ? <p role="status" className="mb-2 text-sm text-neutral-500">Loading staff activity…</p> : null}
              {loginActivityError ? <p role="alert" className="mb-2 text-sm text-red-600">{loginActivityError}</p> : null}
              {loginActivityHasMore ? (
                <button
                  type="button"
                  onClick={() => void loadMoreLoginActivity()}
                  disabled={loginActivityLoading}
                  className="rounded border border-neutral-300 bg-white px-4 py-2 text-sm font-medium disabled:opacity-50"
                >
                  {loginActivityLoading ? "Loading activity…" : "Load older activity"}
                </button>
              ) : null}
            </div>
            </>
          ) : null}
          {current === "sales" ? children : null}
          {current === "transactions" ? <SalePurchaseTransactions store={store} remoteHistory remoteInventory /> : null}
          {current === "finance" ? financeContent : null}
        </div>
      </div>
    </>
  );
}
