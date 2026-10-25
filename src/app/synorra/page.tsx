import { redirect } from "next/navigation";
import { StaffLogin } from "@/components/StaffLogin";
import { getSession } from "@/lib/auth";

export const dynamic = "force-dynamic";

export default async function SynorraAliasPage() {
  const session = await getSession();
  if (session?.role === "admin") redirect("/synorra-host");

  return <StaffLogin role="admin" />;
}
