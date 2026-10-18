import type { PaymentMethod } from "@/lib/types";

export const PAYMENT_METHODS = [
  { id: "cash" as const, label: "Cash" },
  { id: "gcash" as const, label: "GCash" },
  { id: "maya" as const, label: "Maya" },
];

export function parsePayment(value: string | null | undefined): PaymentMethod {
  if (value?.startsWith("split:")) return value as PaymentMethod;
  if (value === "gcash" || value === "maya") return value;
  return "cash";
}

export function paymentLabel(method?: PaymentMethod | string | null): string {
  if (method?.startsWith("split:")) {
    const parts = method.slice("split:".length).split(",").map((part) => part.split("=")[0]);
    const labels = parts.map((part) => part === "gcash" ? "GCash" : part === "maya" ? "Maya" : "Cash");
    return `Split (${labels.join(" + ")})`;
  }
  if (method === "gcash") return "GCash";
  if (method === "maya") return "Maya";
  return "Cash";
}
