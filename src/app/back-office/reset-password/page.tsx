import { BackOfficeAuthShell } from "@/components/BackOfficeAuthShell";
import { ResetOwnerPasswordForm } from "@/components/ResetOwnerPasswordForm";

export const dynamic = "force-dynamic";

export default async function OwnerPasswordResetPage({
  searchParams,
}: {
  searchParams: Promise<{ token?: string }>;
}) {
  const { token = "" } = await searchParams;

  return (
    <BackOfficeAuthShell eyebrow="Owner password recovery">
      <ResetOwnerPasswordForm token={token} />
    </BackOfficeAuthShell>
  );
}
