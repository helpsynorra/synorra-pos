import { parsePayment, paymentLabel } from "@/lib/payments";
import { addonExtra, menuCategoryTypeForName } from "@/lib/menu";
import type { Order, PaymentMethod } from "@/lib/types";

function getPhDateString(date: Date): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Manila",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

function getPhTimeDetails(date: Date) {
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Manila",
    hour: "numeric",
    minute: "numeric",
    second: "numeric",
    hour12: false,
  });
  const parts = formatter.formatToParts(date);
  let hour = 0;
  for (const part of parts) {
    if (part.type === "hour") {
      hour = parseInt(part.value, 10);
      if (hour === 24) hour = 0;
    }
  }
  return { hour };
}

function startOfDayPH(date: Date): Date {
  const phDateStr = getPhDateString(date);
  return new Date(`${phDateStr}T00:00:00+08:00`);
}

export function isWasteOrder(order: Partial<Order>): boolean {
  return order.recordType?.toLowerCase() === "waste" ||
    order.paymentMethod?.toLowerCase() === "waste" ||
    (order.id ? order.id.trim().toLowerCase().startsWith("waste-") : false) ||
    (order.ticketNo ? order.ticketNo.trim().toLowerCase().startsWith("w-") : false) ||
    Boolean(order.wasteReason);
}

export function liveOrders(orders: Order[]): Order[] {
  return orders.filter((order) =>
    !order.voided &&
    !order.deletedAt &&
    !isWasteOrder(order),
  );
}

export function sumSales(orders: Order[]): number {
  return liveOrders(orders).reduce((sum, order) => sum + order.total, 0);
}

export function averageTicket(orders: Order[]): number {
  const live = liveOrders(orders);
  if (live.length === 0) return 0;
  return sumSales(live) / live.length;
}

export function ordersOnDay(orders: Order[], day: Date): Order[] {
  const start = startOfDayPH(day).getTime();
  const end = start + 24 * 60 * 60 * 1000;
  return liveOrders(orders).filter((order) => {
    const time = new Date(order.createdAt).getTime();
    return time >= start && time < end;
  });
}

export function lastNDays(orders: Order[], days: number, now = new Date()) {
  return Array.from({ length: days }, (_, index) => {
    const date = new Date(now);
    date.setDate(now.getDate() - (days - 1 - index));
    const dayOrders = ordersOnDay(orders, date);
    return {
      label: new Intl.DateTimeFormat("en-US", { timeZone: "Asia/Manila", weekday: "short", month: "short", day: "numeric" }).format(date),
      shortDay: new Intl.DateTimeFormat("en-US", { timeZone: "Asia/Manila", weekday: "short" }).format(date),
      date: getPhDateString(date),
      orders: dayOrders.length,
      sales: sumSales(dayOrders),
    };
  });
}

export function salesByYearMonths(orders: Order[], targetYear?: number) {
  const now = new Date();
  const yearNum = targetYear ?? parseInt(new Intl.DateTimeFormat("en-US", { timeZone: "Asia/Manila", year: "numeric" }).format(now), 10);

  return Array.from({ length: 12 }, (_, monthIndex) => {
    const monthStart = new Date(Date.UTC(yearNum, monthIndex, 1, 0, 0, 0));
    monthStart.setHours(monthStart.getHours() - 8);
    
    const monthEnd = new Date(Date.UTC(yearNum, monthIndex + 1, 0, 23, 59, 59));
    monthEnd.setHours(monthEnd.getHours() - 8);

    const monthOrders = liveOrders(orders).filter((order) => {
      const time = new Date(order.createdAt).getTime();
      return time >= monthStart.getTime() && time <= monthEnd.getTime();
    });

    const monthName = new Intl.DateTimeFormat("en-US", { timeZone: "Asia/Manila", month: "short" }).format(new Date(yearNum, monthIndex, 1));

    return {
      key: `${yearNum}-${monthIndex}`,
      label: monthName,
      date: monthName,
      orders: monthOrders.length,
      sales: sumSales(monthOrders),
    };
  });
}

export type ProductStat = {
  id: string;
  name: string;
  category: string;
  categoryType?: string;
  qty: number;
  sales: number;
};

export function productStats(
  orders: Order[],
  menu: { id: string; name: string; category: string; categoryType?: string }[] = [],
): ProductStat[] {
  const map = new Map<string, ProductStat>();

  for (const item of menu) {
    map.set(item.id, {
      id: item.id,
      name: item.name,
      category: item.category,
      categoryType: item.categoryType,
      qty: 0,
      sales: 0,
    });
  }

  for (const order of liveOrders(orders)) {
    const lineBaseAmounts = order.items.map((line) => line.qty * line.price);
    const baseSubtotal = lineBaseAmounts.reduce((sum, amount) => sum + amount, 0);
    const addonSubtotal = order.items.reduce(
      (sum, line) => sum + addonExtra(line.addons) * line.qty,
      0,
    );
    // Web orders may already have add-ons folded into line.price, while Flutter
    // orders keep the base price and store add-ons separately. Compare both
    // representations with the persisted subtotal to include add-ons once.
    const expectedSubtotal = order.subtotal && order.subtotal > 0
      ? order.subtotal
      : order.total + (order.discount ?? 0);
    const baseOnlyDiff = Math.abs(expectedSubtotal - baseSubtotal);
    const withAddonsDiff = Math.abs(expectedSubtotal - (baseSubtotal + addonSubtotal));
    const includeSeparateAddons = withAddonsDiff < baseOnlyDiff;
    const grossSubtotal = baseSubtotal + (includeSeparateAddons ? addonSubtotal : 0);
    // Allocate order-level discounts/adjustments proportionally so product
    // sales sum to the order total shown in revenue metrics.
    const revenueFactor = grossSubtotal > 0 ? order.total / grossSubtotal : 0;

    for (const [lineIndex, line] of order.items.entries()) {
      const matchingMenuItem = map.get(line.productId) ?? menu.find((item) => item.name.trim().toLowerCase() === line.name.trim().toLowerCase());
      const current = map.get(line.productId) ?? {
        id: line.productId,
        name: line.name,
        category: line.category ?? matchingMenuItem?.category ?? "Other",
        categoryType: line.categoryType ?? matchingMenuItem?.categoryType,
        qty: 0,
        sales: 0,
      };
      current.qty += line.qty;
      const separateAddonAmount = includeSeparateAddons ? addonExtra(line.addons) : 0;
      current.sales += (lineBaseAmounts[lineIndex] + separateAddonAmount * line.qty) * revenueFactor;
      current.name = line.name;
      map.set(line.productId, current);
    }
  }

  return [...map.values()];
}

// Helper para i-filter ang Drinks lang
export function drinkProductStats(stats: ProductStat[]): ProductStat[] {
  return stats.filter((item) => {
    const type = menuCategoryTypeForName(item.category, item.categoryType).trim().toLowerCase();
    return type.includes("drink");
  });
}

export function bestSellers(stats: ProductStat[], limit = 5): ProductStat[] {
  const drinksOnly = drinkProductStats(stats);
  return [...drinksOnly]
    .sort((a, b) => b.qty - a.qty || b.sales - a.sales)
    .slice(0, limit);
}

// Ibinigay ulit ang topProducts export para mawala ang build error sa PosDrawer
export function topProducts(orders: Order[], menu: { id: string; name: string; category: string }[] = [], limit = 5) {
  return bestSellers(productStats(orders, menu), limit).map((item) => ({
    name: item.name,
    qty: item.qty,
    sales: item.sales,
  }));
}

export function lowSellers(stats: ProductStat[], limit = 5): ProductStat[] {
  const drinksOnly = drinkProductStats(stats);
  return [...drinksOnly]
    .sort((a, b) => a.qty - b.qty || a.sales - b.sales)
    .slice(0, limit);
}

export function unitsSold(stats: ProductStat[]): number {
  return drinkProductStats(stats).reduce((sum, item) => sum + item.qty, 0);
}

export function categorySales(stats: ProductStat[]) {
  const map = new Map<string, { name: string; qty: number; sales: number }>();
  for (const item of stats) {
    const current = map.get(item.category) ?? {
      name: item.category,
      qty: 0,
      sales: 0,
    };
    current.qty += item.qty;
    current.sales += item.sales;
    map.set(item.category, current);
  }
  return [...map.values()].sort((a, b) => b.sales - a.sales);
}

export function salesByHour(orders: Order[], now = new Date(), days = 7) {
  const start = startOfDayPH(now);
  start.setDate(start.getDate() - (days - 1));
  
  const buckets = Array.from({ length: 24 }, (_, hour) => {
    let label = "";
    if (hour === 0) {
      label = "12 AM";
    } else if (hour < 12) {
      label = `${hour} AM`;
    } else if (hour === 12) {
      label = "12 PM";
    } else {
      label = `${hour - 12} PM`;
    }

    return {
      hour,
      label,
      sales: 0,
      orders: 0,
    };
  });

  for (const order of liveOrders(orders)) {
    const time = new Date(order.createdAt);
    if (time.getTime() < start.getTime()) continue;
    
    const { hour } = getPhTimeDetails(time);
    buckets[hour].sales += order.total;
    buckets[hour].orders += 1;
  }

  return buckets;
}

export function cafeHours(buckets: ReturnType<typeof salesByHour>) {
  const open = buckets.filter((slot) => slot.hour >= 8 && slot.hour <= 23);
  const midnight = buckets.find((slot) => slot.hour === 0);
  return midnight ? [...open, midnight] : open;
}

export function changePercent(current: number, previous: number): number | null {
  if (previous === 0 && current === 0) return 0;
  if (previous === 0) return current > 0 ? 100 : 0;
  return Math.round(((current - previous) / previous) * 100);
}

export function totalDiscount(orders: Order[]): number {
  return liveOrders(orders).reduce((sum, order) => sum + (order.discount ?? 0), 0);
}

export function paymentStats(orders: Order[]) {
  const buckets: Record<
    Exclude<PaymentMethod, `split:${string}` | "split" | "waste">,
    { method: PaymentMethod; label: string; count: number; sales: number }
  > = {
    cash: { method: "cash", label: paymentLabel("cash"), count: 0, sales: 0 },
    gcash: { method: "gcash", label: paymentLabel("gcash"), count: 0, sales: 0 },
    maya: { method: "maya", label: paymentLabel("maya"), count: 0, sales: 0 },
    cards: { method: "cards", label: paymentLabel("cards"), count: 0, sales: 0 },
    grab: { method: "grab", label: paymentLabel("grab"), count: 0, sales: 0 },
    foodpanda: { method: "foodpanda", label: paymentLabel("foodpanda"), count: 0, sales: 0 },
  };
  const splitBucket = {
    method: "split" as PaymentMethod,
    label: "Split",
    count: 0,
    sales: 0,
  };
  for (const order of liveOrders(orders)) {
    const method = parsePayment(order.paymentMethod);
    if (
      method === "cash" ||
      method === "gcash" ||
      method === "maya" ||
      method === "cards" ||
      method === "grab" ||
      method === "foodpanda"
    ) {
      buckets[method].count += 1;
      buckets[method].sales += order.total;
    } else {
      splitBucket.count += 1;
      splitBucket.sales += order.total;
    }
  }
  return [
    ...Object.values(buckets),
    ...(splitBucket.count ? [splitBucket] : []),
  ];
}

export function promoStats(orders: Order[]) {
  const map = new Map<string, { label: string; count: number; discount: number }>();
  for (const order of liveOrders(orders)) {
    if (!order.promoLabel || !order.discount) continue;
    const current = map.get(order.promoLabel) ?? {
      label: order.promoLabel,
      count: 0,
      discount: 0,
    };
    current.count += 1;
    current.discount += order.discount;
    map.set(order.promoLabel, current);
  }
  return [...map.values()].sort((a, b) => b.count - a.count);
}

export function busiestDay(days: ReturnType<typeof lastNDays>) {
  return days.reduce(
    (best, day) => (day.sales > best.sales ? day : best),
    days[0],
  );
}
