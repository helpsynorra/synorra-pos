"use client";

import { useState, useEffect, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { StaffHeader, type AdminPanel } from "@/components/StaffHeader";
import { UserManager } from "@/components/UserManager";
import { SalePurchaseTransactions } from "@/components/SalePurchaseTransactions";
import { MenuCatalog } from "@/components/MenuCatalog";
import type { PublicStaffUser } from "@/lib/users";
import type { Session, StoreData } from "@/lib/types";

type AdminShellProps = {
  session: Session;
  users: PublicStaffUser[];
  store: StoreData;
  children: ReactNode;
};

function readSavedPanel(): AdminPanel {
  const savedPanel = window.localStorage.getItem("admin_activePanel");
  const savedSection = window.localStorage.getItem("admin_section");
  if (savedPanel === "staff" || savedSection === "staff") return "sales";
  if (savedPanel === "menu" || savedPanel === "transactions") {
    return savedPanel;
  }
  return "sales";
}

export function AdminShell({ session, users, store, children }: AdminShellProps) {
  const [panel, setPanel] = useState<AdminPanel>("sales");
  const [isMounted, setIsMounted] = useState(false);
  const router = useRouter();

  useEffect(() => {
    if (panel !== "transactions" && panel !== "sales" && panel !== "staff") return;
    const refreshTimer = window.setInterval(() => router.refresh(), 5000);
    return () => window.clearInterval(refreshTimer);
  }, [panel, router]);

  useEffect(() => {
    setPanel(readSavedPanel());
    setIsMounted(true);
  }, []);

  function handlePanelChange(next: AdminPanel) {
    setPanel(next);
    window.localStorage.setItem("admin_activePanel", next);
    window.localStorage.setItem("admin_section", next === "staff" ? "staff" : "admin");
  }

  const current = isMounted ? panel : "sales";

  return (
    <>
      <StaffHeader session={session} panel={current} onPanelChange={handlePanelChange} />

      {current === "staff" ? (
        <UserManager
          users={users.filter((user) => user.role !== "admin")}
          session={session}
          loginActivity={store.loginActivity ?? []}
          offRequests={store.offRequests ?? []}
          showAdminRole={false}
          showOwnerRole={false}
          showBaristaRole={true}
          showBaristasOnly={false}
          showEditStaffButton={false}
          baristaOnlyStaffActions={true}
          printButtonHidden={store.pos.printButtonHidden}
          showLoginLinksTab={session.role !== "cashier"}
          showPrintButtonToggle={session.role !== "cashier"}
          showViewPermissionsButton={session.role !== "cashier"}
          adminLoginPath={store.loginGates.admin}
        />
      ) : null}
      {current === "sales" ? children : null}
      {current === "menu" ? (
        <MenuCatalog
          menu={store.menu}
          categories={store.categories}
          categoryTypes={store.categoryTypes ?? {}}
          inventory={store.inventory}
        />
      ) : null}
      {current === "transactions" ? <SalePurchaseTransactions store={store} /> : null}
    </>
  );
}
