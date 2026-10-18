import { BrandLogo } from "@/components/BrandLogo";
import { LoginForm } from "@/components/LoginForm";

export function StaffLogin({ role = "admin" }: { role?: "admin" | "cashier" }) {
  const isCashier = role === "cashier";
  return (
    <main className="relative flex min-h-svh items-center justify-center overflow-hidden px-4 py-12 sm:px-6 sm:py-16">
      <div
        className="absolute inset-0 bg-cover bg-center"
        style={{ backgroundImage: "url(/images/hero-wide.jpg)" }}
      />
      <div className="absolute inset-0 bg-black/75" />
      <div className="relative z-10 flex w-full max-w-md flex-col items-center text-center">
        <div className="relative -top-10">
          <BrandLogo size="md" showTagline />
        </div>
        <p className="mt-6 mb-10 text-xs tracking-[0.3em] text-neutral-300 uppercase">
          {isCashier ? "Owner back-office login" : "Admin login"}
        </p>
        <LoginForm role={role} />
      </div>
    </main>
  );
}
