import Link from "next/link";
import { redirect } from "next/navigation";
import { logout } from "@/actions/auth";
import { BrandLogo } from "@/components/BrandLogo";
import { UserManager } from "@/components/UserManager";
import { getSession } from "@/lib/auth";
import { getOwnerAccounts, getStore } from "@/lib/store";
import { publicUser } from "@/lib/users";

export const dynamic = "force-dynamic";

export default async function SynorraHostPage() {
  const session = await getSession();
  if (!session || session.role !== "admin") redirect("/");

  const [store, owners] = await Promise.all([getStore(), getOwnerAccounts()]);
  const staff = owners
    .filter((user) => ![user.username, user.title, user.name, user.role].some((value) => /^manager$/i.test(value.trim())))
    .map(publicUser);

  return (
    <main className="min-h-svh overflow-x-hidden bg-[#f5f8fc] text-[#17243e]">
      <header className="relative z-40 flex min-h-[68px] items-center justify-between border-b border-[#e7edf5] bg-white px-4 py-3 sm:px-6">
        <div className="flex items-center gap-4">
          <Link
            href="/"
            aria-label="Back to website"
            className="flex h-10 w-10 items-center justify-center rounded-full border border-neutral-300 text-neutral-700 transition hover:border-black hover:bg-black hover:text-white"
          >
            <svg viewBox="0 0 24 24" className="h-4 w-4 stroke-current" fill="none">
              <path d="M15 18 9 12l6-6M9 12h11" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </Link>
          <BrandLogo size="sm" align="start" />
          <span className="hidden h-7 w-px bg-[#e5ebf4] sm:block" />
          <h1 className="text-sm font-semibold tracking-tight text-[#263b5d]">Admin Console</h1>
        </div>
        <div className="flex items-center gap-4">
          <div className="hidden text-right sm:block">
            <p className="text-xs font-semibold text-[#263b5d]">{session.name}</p>
            <p className="text-[10px] text-[#8a9ab0]">Administrator</p>
          </div>
          <form action={logout}>
            <button type="submit" className="rounded-full border border-[#dce5f2] px-3.5 py-2 text-xs font-semibold text-[#536783] transition hover:border-[#4353ff] hover:text-[#4353ff]">
              Log out
            </button>
          </form>
        </div>
      </header>
      <UserManager
        users={staff}
        session={session}
        loginActivity={store.loginActivity ?? []}
        offRequests={store.offRequests ?? []}
        showShiftTabs={false}
        showAdminRole={false}
        showOwnerRole={true}
        showBaristaRole={false}
        showEditStaffButton={false}
        showDeleteStaffButton={true}
        showViewPermissionsButton={false}
        adminLoginPath={store.loginGates.admin}
        printButtonHidden={store.pos.printButtonHidden}
        inventoryFeaturesEnabled={store.pos.inventoryFeaturesEnabled}
        showPrintButtonToggle={true}
      />
      <footer className="border-t border-[#e7edf5] bg-white px-4 py-4 sm:px-6">
        <nav aria-label="Legal" className="mx-auto flex max-w-7xl flex-wrap gap-x-5 gap-y-2 text-xs text-[#65758b]">
          <Link href="/terms" target="_blank" rel="noreferrer" className="hover:text-[#263b5d]">Terms of Use</Link>
          <Link href="/privacy" target="_blank" rel="noreferrer" className="hover:text-[#263b5d]">Privacy &amp; Cookie Policy</Link>
        </nav>
      </footer>
    </main>
  );
}
