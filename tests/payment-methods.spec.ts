import { expect, test } from "@playwright/test";
import { cafeHours, salesByHour } from "../src/lib/analytics";
import { parsePayment, paymentLabel } from "../src/lib/payments";
import type { Order } from "../src/lib/types";

test("peak hours chart covers 8 AM through midnight", () => {
  const buckets = salesByHour(
    [] as Order[],
    new Date("2026-10-29T04:00:00.000Z"),
    1,
  );
  const hours = cafeHours(buckets);
  expect(hours.map((slot) => slot.hour)).toEqual([
    8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 0,
  ]);
});

test("preserves supported payment methods and their Admin Sales labels", () => {
  for (const [value, label] of [
    ["cash", "Cash"],
    ["cards", "Cards"],
    ["grab", "Grab"],
    ["foodpanda", "Foodpanda"],
    ["gcash", "GCash"],
    ["maya", "Maya"],
  ] as const) {
    const method = parsePayment(value);
    expect(method).toBe(value);
    expect(paymentLabel(method)).toBe(label);
  }
});

test("preserves split-payment details and legacy cash fallbacks", () => {
  const split = "split:cash=500,gcash=250";
  expect(parsePayment(split)).toBe(split);
  expect(paymentLabel(parsePayment(split))).toBe("Split (Cash + GCash)");
  expect(parsePayment("unknown-method")).toBe("cash");
  expect(parsePayment(undefined)).toBe("cash");
});
