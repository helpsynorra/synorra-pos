import { BrandLogo } from "@/components/BrandLogo";
import { ResetOwnerPasswordForm } from "@/components/ResetOwnerPasswordForm";

export const dynamic = "force-dynamic";

export default async function OwnerPasswordResetPage({
  searchParams,
}: {
  searchParams: Promise<{ token?: string }>;
}) {
  const { token = "" } = await searchParams;

  return (
    <main className="relative flex min-h-svh items-center justify-center overflow-hidden px-4 py-12 sm:px-6 sm:py-16">
      <div
        className="absolute inset-0 bg-cover bg-center"
        style={{ backgroundImage: "url(/images/hero-wide.jpg)" }}
      />
      <div className="absolute inset-0 bg-black/75" />
      <div className="relative z-10 flex w-full flex-col items-center text-center">
        <div className="relative -top-10">
          <BrandLogo size="md" showTagline />
        </div>
        <p className="mt-6 mb-10 text-xs tracking-[0.3em] text-neutral-300 uppercase">
          Owner password recovery
        </p>
        <ResetOwnerPasswordForm token={token} />
      </div>
    </main>
  );
}
