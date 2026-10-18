import Link from "next/link";
import { redirect } from "next/navigation";
import { logout } from "@/actions/auth";
import { BrandLogo } from "@/components/BrandLogo";
import { UserManager } from "@/components/UserManager";
import { getSession } from "@/lib/auth";
import { getStore } from "@/lib/store";
import { publicUser } from "@/lib/users";

export const dynamic = "force-dynamic";

export default async function SynorraHostPage() {
  const session = await getSession();
  if (!session || session.role !== "admin") redirect("/");

  const store = await getStore();
  const staff = store.users
    .filter((user) =>
      ![user.username, user.title, user.name, user.role].some((value) =>
        /^manager$/i.test(value.trim()),
      ) && user.role !== "barista",
    )
    .map(publicUser);

  return (
    <main className="min-h-svh overflow-x-hidden bg-neutral-100 text-black">
      <header className="relative z-40 flex min-h-[72px] items-center justify-between border-b border-neutral-200 bg-white px-4 py-3 sm:px-6">
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
          <h1 className="text-base font-medium">Staff</h1>
        </div>
        <div className="flex items-center gap-4">
          <form action={logout}>
            <button type="submit" className="text-sm font-medium text-neutral-600 hover:text-black">
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
        showBaristaRole={false}
      />
    </main>
  );
}
