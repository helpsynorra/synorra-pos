import Image from "next/image";
import Link from "next/link";
import { CAFE } from "@/lib/cafe";

type BrandLogoProps = {
  href?: string;
  size?: "sm" | "md" | "lg";
  showTagline?: boolean;
  align?: "center" | "start";
};

const sizes = {
  sm: { box: "h-10 w-10", type: "text-[10px]" },
  md: { box: "h-24 w-24", type: "text-xs" },
  lg: { box: "h-32 w-32", type: "text-sm" },
};

export function BrandLogo({
  href = "/",
  size = "md",
  showTagline = false,
  align = "center",
}: BrandLogoProps) {
  const scale = sizes[size];

  return (
    <Link
      href={href}
      className={`inline-flex flex-col ${align === "center" ? "items-center" : "items-start"}`}
    >
      <Image
        src="/images/logo.png"
        alt={CAFE.name}
        width={320}
        height={320}
        className={`${scale.box} rounded-full object-cover`}
        priority={size !== "sm"}
      />
      {showTagline ? (
        <span className={`mt-3 tracking-[0.28em] uppercase text-white/70 ${scale.type}`}>
          {CAFE.tagline}
        </span>
      ) : null}
    </Link>
  );
}
