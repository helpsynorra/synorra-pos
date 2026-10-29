import type { PaymentMethod } from "@/lib/types";

export const PAYMENT_METHODS = [
  { id: "cash" as const, label: "Cash" },
  { id: "gcash" as const, label: "GCash" },
  { id: "maya" as const, label: "Maya" },
];

export function parsePayment(value: string | null | undefined): PaymentMethod {
  const method = value?.trim().toLowerCase();
  if (method === "waste") return "waste";
  if (method === "split") return "split";
  if (method?.startsWith("split:")) return method as PaymentMethod;
  if (
    method === "gcash" ||
    method === "maya" ||
    method === "cards" ||
    method === "grab" ||
    method === "foodpanda"
  ) {
    return method;
  }
  return "cash";
}

export function paymentLabel(method?: PaymentMethod | string | null): string {
  const normalized = method?.trim().toLowerCase();
  if (normalized === "waste") return "Waste";
  if (normalized === "split") return "Split";
  if (normalized?.startsWith("split:")) {
    const parts = normalized.slice("split:".length).split(",").map((part) => part.split("=")[0]);
    const labels = parts.map((part) => {
      if (part === "gcash") return "GCash";
      if (part === "maya") return "Maya";
      if (part === "cards") return "Cards";
      if (part === "grab") return "Grab";
      if (part === "foodpanda") return "Foodpanda";
      return "Cash";
    });
    return `Split (${labels.join(" + ")})`;
  }
  if (normalized === "gcash") return "GCash";
  if (normalized === "maya") return "Maya";
  if (normalized === "cards") return "Cards";
  if (normalized === "grab") return "Grab";
  if (normalized === "foodpanda") return "Foodpanda";
  return "Cash";
}
