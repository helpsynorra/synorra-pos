"use client";

import { useState, useEffect, useMemo, useTransition } from "react";
import { approveVoidRequest } from "@/actions/pos";
import { drinkDisplayName, formatMoney, orderItemTypes, orderLineListLabel, orderLineOptionsLabel } from "@/lib/menu";
import { phDateString, phDateTimeLabel, phPeriodBounds, phTimestamp, type PeriodRange } from "@/lib/datetime";
import { paymentLabel } from "@/lib/payments";
import { inferMenuCategoryType, menuCategoryTypeForName, menuCategoryTypeLabel, normalizeMenuCategoryType } from "@/lib/menu";
import { parseRole } from "@/lib/users";
import { pairLoginSessions } from "@/lib/staff-sessions";
import {
  bestSellers,
  cafeHours,
  categorySales,
  lowSellers,
  drinkProductStats,
} from "@/lib/analytics";
import type { Order, PaymentMethod, StoreData } from "@/lib/types";

type SalesSummary = {
  totals: { sales: number; orders: number; averageTicket: number };
  payments: { method: string; count: number; sales: number }[];
  days: { date: string; orders: number; sales: number; quantity: number }[];
  months: { month: string; orders: number; sales: number }[];
  hours: { hour: number; quantity: number }[];
  products: {
    id: string;
    name: string;
    category: string;
    categoryType: string;
    qty: number;
    sales: number;
    iced: number;
    hot: number;
  }[];
};

type RecentOrdersPage = {
  orders: Order[];
  page: number;
  hasMore: boolean;
  total: number;
};

const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

function isSalesSummary(value: unknown): value is SalesSummary {
  const isRecord = (entry: unknown): entry is Record<string, unknown> =>
    Boolean(entry && typeof entry === "object" && !Array.isArray(entry));
  const isNumber = (entry: unknown): entry is number =>
    typeof entry === "number" && Number.isFinite(entry);
  if (!isRecord(value)) return false;
  const summary = value;
  const totals = summary.totals;
  if (!isRecord(totals)) return false;
  const isPayment = (entry: unknown) =>
    isRecord(entry) &&
    typeof entry.method === "string" &&
    ["cash", "gcash", "maya", "cards", "grab", "foodpanda", "split"].includes(entry.method) &&
    isNumber(entry.count) &&
    isNumber(entry.sales);
  const isDay = (entry: unknown) =>
    isRecord(entry) &&
    typeof entry.date === "string" &&
    DATE_PATTERN.test(entry.date) &&
    isNumber(entry.orders) &&
    isNumber(entry.sales) &&
    isNumber(entry.quantity);
  const isMonth = (entry: unknown) =>
    isRecord(entry) &&
    typeof entry.month === "string" &&
    DATE_PATTERN.test(entry.month) &&
    isNumber(entry.orders) &&
    isNumber(entry.sales);
  const isHour = (entry: unknown) => {
    if (!isRecord(entry)) return false;
    const hour = entry.hour;
    return isNumber(hour) &&
      Number.isInteger(hour) &&
      hour >= 0 &&
      hour <= 23 &&
      isNumber(entry.quantity);
  };
  const isProduct = (entry: unknown) =>
    isRecord(entry) &&
    typeof entry.id === "string" &&
    typeof entry.name === "string" &&
    typeof entry.category === "string" &&
    typeof entry.categoryType === "string" &&
    isNumber(entry.qty) &&
    isNumber(entry.sales) &&
    isNumber(entry.iced) &&
    isNumber(entry.hot);

  return (
    isNumber(totals.sales) &&
    isNumber(totals.orders) &&
    isNumber(totals.averageTicket) &&
    Array.isArray(summary.payments) &&
    summary.payments.every(isPayment) &&
    Array.isArray(summary.days) &&
    summary.days.every(isDay) &&
    Array.isArray(summary.months) &&
    summary.months.every(isMonth) &&
    Array.isArray(summary.hours) &&
    summary.hours.every(isHour) &&
    Array.isArray(summary.products) &&
    summary.products.every(isProduct)
  );
}

function hourLabel(hour: number) {
  if (hour === 0) return "12 AM";
  if (hour < 12) return `${hour} AM`;
  if (hour === 12) return "12 PM";
  return `${hour - 12} PM`;
}

function summaryPaymentMethod(method: string): PaymentMethod {
  switch (method) {
    case "cash":
    case "gcash":
    case "maya":
    case "cards":
    case "grab":
    case "foodpanda":
    case "split":
      return method;
    default:
      throw new Error(`Unsupported payment method in sales summary: ${method}`);
  }
}

function isRecentOrdersPage(value: unknown): value is RecentOrdersPage {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const result = value as Record<string, unknown>;
  return (
    Array.isArray(result.orders) &&
    result.orders.every((order) => {
      if (!order || typeof order !== "object" || Array.isArray(order)) return false;
      const entry = order as Record<string, unknown>;
      return (
        typeof entry.id === "string" &&
        typeof entry.createdAt === "string" &&
        typeof entry.baristaName === "string" &&
        typeof entry.total === "number" &&
        Array.isArray(entry.items) &&
        entry.items.every((item) => {
          if (!item || typeof item !== "object" || Array.isArray(item)) return false;
          const line = item as Record<string, unknown>;
          return (
            typeof line.productId === "string" &&
            typeof line.name === "string" &&
            typeof line.qty === "number" &&
            typeof line.price === "number"
          );
        })
      );
    }) &&
    typeof result.page === "number" &&
    typeof result.hasMore === "boolean" &&
    typeof result.total === "number"
  );
}

function Metric({
  label,
  value,
  hint,
}: {
  label: string;
  value: string;
  hint?: string | null;
}) {
  return (
    <div className="min-w-0 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
      <p className="text-[10px] tracking-[0.2em] text-neutral-500 uppercase sm:text-xs sm:tracking-[0.25em]">
        {label}
      </p>
      <p className="mt-2 break-words text-xl font-semibold sm:mt-3 sm:text-3xl">{value}</p>
      {hint ? <p className="mt-2 text-xs leading-relaxed text-neutral-500">{hint}</p> : null}
    </div>
  );
}

function VerticalBars({
  items,
}: {
  items: { key: string; label: string; value: number; caption: string; display: string }[];
}) {
  const max = Math.max(...items.map((item) => item.value), 1);
  return (
    <div className="mt-6 flex h-64 items-end gap-2 pb-6 overflow-x-auto">
      {items.map((item, idx) => (
        <div key={`${item.key}-${idx}`} className="flex min-w-[32px] flex-1 flex-col items-center h-full justify-end">
          <p className="mb-2 text-[10px] text-neutral-400 whitespace-nowrap">{item.display}</p>
          <div className="flex w-full items-end flex-1">
            <div
              className="w-full bg-[#58789d]"
              style={{ height: `${Math.max((item.value / max) * 100, item.value > 0 ? 6 : 0)}%` }}
              title={item.display}
            />
          </div>
          <span className="mt-2 text-[11px] font-medium text-neutral-700 whitespace-nowrap truncate max-w-full">{item.label}</span>
          <span className="text-[10px] text-neutral-500 whitespace-nowrap">{item.caption}</span>
        </div>
      ))}
    </div>
  );
}

function HorizontalBars({
  items,
  empty,
}: {
  items: { key: string; label: string; value: number; left: string; right: string }[];
  empty: string;
}) {
  if (items.length === 0) {
    return <p className="mt-6 text-sm text-neutral-500">{empty}</p>;
  }
  const max = Math.max(...items.map((item) => item.value), 1);
  return (
    <ul className="mt-5 space-y-3">
      {items.map((item, idx) => (
        <li key={`${item.key}-${idx}`}>
          <div className="flex items-baseline justify-between gap-3 text-sm">
            <span className="truncate">{item.label}</span>
            <span className="shrink-0 text-neutral-500">{item.right}</span>
          </div>
          <div className="mt-1.5 h-2 bg-neutral-200">
            <div
              className="h-full bg-[#58789d]"
              style={{ width: `${Math.max((item.value / max) * 100, item.value > 0 ? 4 : 0)}%` }}
            />
          </div>
          <p className="mt-1 text-[11px] text-neutral-500">{item.left}</p>
        </li>
      ))}
    </ul>
  );
}

function formatDateStr(date: Date) {
  return date.toLocaleDateString("en-US", {
    timeZone: "Asia/Manila",
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

function toInputDateStr(date: Date) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Manila",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

function isVoided(order: Order) {
  return Boolean(order.voided) || Boolean(order.voidReason?.trim());
}

function voidStatusLabel(order: Order, users: StoreData["users"]) {
  const actor = users.find((user) => user.id === order.voidedBy);
  const snapshotName = order.voidedByName?.trim();
  // A stored name can still be a bad legacy snapshot of the cashier's ID.
  // Never display it unless the linked staff account is an admin.
  if (actor && parseRole(actor.title, actor.role) !== "admin") return "VOID";
  const accountName = actor?.name.trim();
  const username = actor?.username.trim();
  const isRoleLabel = /^(admin|cashier|barista|sale in charge)$/i;
  const personName = snapshotName || (accountName && isRoleLabel.test(accountName) && username
    ? username
    : accountName || username);
  return personName ? `VOID - ${personName.toUpperCase()}` : "VOID";
}

function orderIdLabel(order: Order) {
  if (order.ticketNo != null && String(order.ticketNo).trim() !== "") {
    const ticket = String(order.ticketNo).trim().replace(/^#/, "");
    return `Order #${ticket}`;
  }
  return `Order #${order.id}`;
}

function orderServiceMode(order: Order) {
  const mode = order.serviceMode ?? order.items.find((item) => item.serviceMode)?.serviceMode;
  if (mode === "dine-in") return "Dine-in";
  if (mode === "take-out") return "Take-out";
  return "—";
}

export function AdminDashboard({
  store,
  showPromoVoucher,
}: {
  store: StoreData;
  showPromoVoucher: boolean;
}) {
  const [isClient, setIsClient] = useState(false);
  const [filterDateStr, setFilterDateStr] = useState("");
  const [rangeType, setRangeType] = useState<string>("today");
  const [activeFilterMode, setActiveFilterMode] = useState<"range" | "date">("range");
  const [approvalMessage, setApprovalMessage] = useState<string | null>(null);
  const [approvalPending, startApprovalTransition] = useTransition();
  const [drinksOpen, setDrinksOpen] = useState(true);
  const [ordersOpen, setOrdersOpen] = useState(true);
  const [salesSummaryResult, setSalesSummaryResult] = useState<{
    rangeKey: string;
    summary: SalesSummary | null;
    error: string | null;
  } | null>(null);
  const [recentOrderPageSelection, setRecentOrderPageSelection] = useState({
    rangeKey: "",
    page: 1,
  });
  const [recentOrderPageResult, setRecentOrderPageResult] = useState<{
    rangeKey: string;
    page: number;
    result: RecentOrdersPage | null;
    error: string | null;
  } | null>(null);

  /* eslint-disable react-hooks/set-state-in-effect */
  useEffect(() => {
    setIsClient(true);
    setFilterDateStr(toInputDateStr(new Date()));
  }, []);
  /* eslint-enable react-hooks/set-state-in-effect */

  const todayStr = phDateString();
  const isTodaySelected = activeFilterMode === "date"
    ? filterDateStr === todayStr
    : rangeType === "today";
  const periodBounds = activeFilterMode === "date" && filterDateStr
    ? { from: filterDateStr, to: filterDateStr }
    : phPeriodBounds(rangeType as PeriodRange);
  const periodKey = `${periodBounds.from}:${periodBounds.to}`;
  const now = new Date(`${periodBounds.to}T23:59:59.999+08:00`);
  const recentOrderPage = recentOrderPageSelection.rangeKey === periodKey
    ? recentOrderPageSelection.page
    : 1;

  useEffect(() => {
    const controller = new AbortController();
    fetch(
      `/api/admin/sales-summary?from=${encodeURIComponent(periodBounds.from)}&to=${encodeURIComponent(periodBounds.to)}`,
      { signal: controller.signal },
    )
      .then(async (response) => {
        const result: unknown = await response.json();
        if (!response.ok) {
          const message =
            result && typeof result === "object" && "error" in result
              ? String(result.error)
              : "Unable to load sales summary.";
          throw new Error(message);
        }
        if (!isSalesSummary(result)) {
          throw new Error("Sales summary response was invalid.");
        }
        setSalesSummaryResult({ rangeKey: periodKey, summary: result, error: null });
      })
      .catch((error: unknown) => {
        if (error instanceof DOMException && error.name === "AbortError") return;
        setSalesSummaryResult({
          rangeKey: periodKey,
          summary: null,
          error: error instanceof Error ? error.message : "Unable to load sales summary.",
        });
      });

    return () => controller.abort();
  }, [periodBounds.from, periodBounds.to, periodKey]);

  useEffect(() => {
    const controller = new AbortController();
    fetch(
      `/api/admin/recent-orders?from=${encodeURIComponent(periodBounds.from)}&to=${encodeURIComponent(periodBounds.to)}&page=${recentOrderPage}`,
      { signal: controller.signal },
    )
      .then(async (response) => {
        const result: unknown = await response.json();
        if (!response.ok) {
          const message =
            result && typeof result === "object" && "error" in result
              ? String(result.error)
              : "Unable to load recent orders.";
          throw new Error(message);
        }
        if (!isRecentOrdersPage(result)) {
          throw new Error("Recent orders response was invalid.");
        }
        setRecentOrderPageResult({
          rangeKey: periodKey,
          page: recentOrderPage,
          result,
          error: null,
        });
      })
      .catch((error: unknown) => {
        if (error instanceof DOMException && error.name === "AbortError") return;
        setRecentOrderPageResult({
          rangeKey: periodKey,
          page: recentOrderPage,
          result: null,
          error: error instanceof Error ? error.message : "Unable to load recent orders.",
        });
      });

    return () => controller.abort();
  }, [periodBounds.from, periodBounds.to, periodKey, recentOrderPage]);

  const todayDateStr = formatDateStr(now);
  const salesSummary = salesSummaryResult?.rangeKey === periodKey
    ? salesSummaryResult.summary
    : null;
  const salesSummaryError = salesSummaryResult?.rangeKey === periodKey
    ? salesSummaryResult.error
    : null;
  const salesSummaryLoading = salesSummaryResult?.rangeKey !== periodKey;
  const currentRecentOrderPage =
    recentOrderPageResult?.rangeKey === periodKey &&
    recentOrderPageResult.page === recentOrderPage
      ? recentOrderPageResult.result
      : null;
  const recentOrderPageError =
    recentOrderPageResult?.rangeKey === periodKey &&
    recentOrderPageResult.page === recentOrderPage
      ? recentOrderPageResult.error
      : null;
  const recentOrdersLoading = !currentRecentOrderPage && !recentOrderPageError;
  const currentWeekStart = new Date(now.getTime() - 6 * 24 * 60 * 60 * 1000);
  const currentWeekRangeStr = `${formatDateStr(currentWeekStart)} – ${todayDateStr}`;
  const summary = salesSummary ?? {
    totals: { sales: 0, orders: 0, averageTicket: 0 },
    payments: [],
    days: [],
    months: [],
    hours: [],
    products: [],
  };

  let trackingItems: { key: string; label: string; value: number; caption: string; display: string }[] = [];
  let trackingTitle = "Sales tracking";
  let trackingSubtitle = "";

  if (rangeType === "month" || rangeType === "lastMonth") {
    trackingTitle = `Sales tracking · ${rangeType === "month" ? "This Month" : "Last Month"}`;
    trackingItems = summary.days.map((day) => ({
      key: day.date,
      label: new Intl.DateTimeFormat("en-US", { timeZone: "Asia/Manila", day: "numeric" })
        .format(new Date(`${day.date}T12:00:00+08:00`)),
      value: day.sales,
      display: formatMoney(day.sales),
      caption: `${day.orders} tix`,
    }));
  } else if (rangeType === "thisYear") {
    trackingTitle = "Sales tracking · This Year (Monthly)";
    trackingItems = summary.months.map((month) => ({
      key: month.month,
      label: new Intl.DateTimeFormat("en-US", { timeZone: "Asia/Manila", month: "short" })
        .format(new Date(`${month.month}T12:00:00+08:00`)),
      value: month.sales,
      display: month.sales > 0 ? formatMoney(month.sales) : "",
      caption: `${month.orders} tix`,
    }));
  } else if (rangeType === "lastYear") {
    trackingTitle = "Sales tracking · Last Year (Monthly)";
    trackingItems = summary.months.map((month) => ({
      key: month.month,
      label: new Intl.DateTimeFormat("en-US", { timeZone: "Asia/Manila", month: "short" })
        .format(new Date(`${month.month}T12:00:00+08:00`)),
      value: month.sales,
      display: month.sales > 0 ? formatMoney(month.sales) : "",
      caption: `${month.orders} tix`,
    }));
  } else if (rangeType === "week" || rangeType === "lastWeek") {
    trackingTitle = rangeType === "lastWeek" ? "Sales tracking · Last Week" : "Sales tracking · 7 days";
    trackingSubtitle = currentWeekRangeStr;
    trackingItems = summary.days.map((day) => ({
      key: day.date,
      label: new Intl.DateTimeFormat("en-US", { timeZone: "Asia/Manila", weekday: "short", month: "short", day: "numeric" })
        .format(new Date(`${day.date}T12:00:00+08:00`)),
      value: day.sales,
      display: formatMoney(day.sales),
      caption: `${day.orders} tix`,
    }));
  }

  const categoryTypeByName = new Map(
    Object.entries(store.categoryTypes ?? {}).map(([category, type]) => [
      category.trim().toLowerCase(),
      normalizeMenuCategoryType(type),
    ]),
  );
  const productStatsList = summary.products.map((product) => ({
    ...product,
    categoryType: menuCategoryTypeForName(
      product.category,
      categoryTypeByName.get(product.category.trim().toLowerCase()) ??
        product.categoryType ??
        inferMenuCategoryType(product.category),
    ),
  }));
  const productDetailsById = new Map(summary.products.map((product) => [product.id, product]));
  const best = bestSellers(productStatsList, 5);
  const low = lowSellers(productStatsList, 5);
  const drinkSoldRows = drinkProductStats(productStatsList)
    .filter((item) => item.qty > 0)
    .map((item) => ({
      ...item,
      iced: productDetailsById.get(item.id)?.iced ?? 0,
      hot: productDetailsById.get(item.id)?.hot ?? 0,
    }))
    .sort((a, b) => b.qty - a.qty || a.name.localeCompare(b.name));
  
  const categories = categorySales(drinkProductStats(productStatsList)).filter((item) => item.qty > 0);
  
  const hours = cafeHours(
    Array.from({ length: 24 }, (_, hour) => ({
      hour,
      label: hourLabel(hour),
      sales: 0,
      orders: summary.hours.find((entry) => entry.hour === hour)?.quantity ?? 0,
    })),
  );
  const peak = hours.reduce(
    (bestHour, slot) => (slot.orders > bestHour.orders ? slot : bestHour),
    hours[0],
  );

  const busy = summary.days.reduce(
    (bestDay, day) => (day.sales > bestDay.sales ? day : bestDay),
    summary.days[0],
  );
  
  const payments = summary.payments.map((entry) => ({
    ...entry,
    method: summaryPaymentMethod(entry.method),
    label: paymentLabel(summaryPaymentMethod(entry.method)),
  }));
  const totalSalesAmount = summary.totals.sales;
  const menuCategoryTypeByName = new Map(
    store.menu.map((item) => [
      item.category.trim().toLowerCase(),
      normalizeMenuCategoryType(
        categoryTypeByName.get(item.category.trim().toLowerCase()) ??
          item.categoryType ??
          inferMenuCategoryType(item.category),
      ),
    ]),
  );
  const getCategoryType = (category: string) => menuCategoryTypeForName(
    category,
    categoryTypeByName.get(category.trim().toLowerCase()) ??
      menuCategoryTypeByName.get(category.trim().toLowerCase()),
  );
  const menuCategoryTypeByProductId = new Map(
    store.menu.map((item) => [
      item.id,
      getCategoryType(item.category),
    ]),
  );
  const getProductCategoryType = (product: (typeof productStatsList)[number]) =>
    menuCategoryTypeByProductId.get(product.id) ??
    getCategoryType(product.category);
  const soldProductGroups = new Map<
    string,
    { type: string; quantity: number; sales: number }
  >();
  const configuredCategoryNames = new Set([
    ...store.categories,
    ...store.menu.map((item) => item.category),
    ...productStatsList.map((item) => item.category),
  ]);
  for (const category of configuredCategoryNames) {
    const type = getCategoryType(category);
    if (!soldProductGroups.has(type.toLowerCase())) {
      soldProductGroups.set(type.toLowerCase(), { type, quantity: 0, sales: 0 });
    }
  }
  for (const product of productStatsList) {
    const type = getProductCategoryType(product);
    const key = type.toLowerCase();
    const group = soldProductGroups.get(key) ?? { type, quantity: 0, sales: 0 };
    group.quantity += product.qty;
    group.sales += product.sales;
    soldProductGroups.set(key, group);
  }
  const soldProductSummary = [...soldProductGroups.values()].sort((a, b) =>
    a.type.localeCompare(b.type),
  );
  const totalSoldQty = soldProductSummary.reduce((sum, group) => sum + group.quantity, 0);
  const totalSoldSales = soldProductSummary.reduce((sum, group) => sum + group.sales, 0);
  const computedAverageTicket = summary.totals.averageTicket;

  const orderOwnerName = (order: Order) => {
    const owner = store.users.find(
      (user) => user.id === order.ownerId && user.role === "cashier",
    );
    return owner?.name || owner?.username || "—";
  };
  const pairedShifts = useMemo(
    () => pairLoginSessions(store.loginActivity ?? []).filter((s) => s.role === "barista" || s.role === "pos_cashier"),
    [store.loginActivity],
  );
  const orderCashierInCharge = (order: Order) => {
    if (order.baristaUserId) {
      const staff = store.users.find((u) => u.id === order.baristaUserId);
      if (staff?.role === "pos_cashier") {
        return staff.name || staff.username || "—";
      }
    }
    const orderTime = phTimestamp(order.createdAt);
    const activeCashier = pairedShifts
      .filter((session) =>
        session.role === "pos_cashier" &&
        session.loginAt != null &&
        phTimestamp(session.loginAt) <= orderTime &&
        (!session.logoutAt || phTimestamp(session.logoutAt) >= orderTime),
      )
      .sort((a, b) => phTimestamp(b.loginAt ?? "") - phTimestamp(a.loginAt ?? ""))[0];
    if (!activeCashier) return "—";
    const cashier = store.users.find((user) => user.id === activeCashier.userId);
    return cashier?.name || cashier?.username || activeCashier.name || "—";
  };
  const orderBaristaInCharge = (order: Order) => {
    if (order.baristaUserId) {
      const staff = store.users.find((u) => u.id === order.baristaUserId);
      if (staff && staff.role === "barista") {
        return staff.name || staff.username || order.baristaName || "—";
      }
    }
    const activeAtOrder = pairedShifts.filter((session) => {
      if (session.role !== "barista") return false;
      const started = session.loginAt ? session.loginAt <= order.createdAt : false;
      const ended = session.logoutAt ? session.logoutAt >= order.createdAt : true;
      return started && ended;
    });
    if (activeAtOrder.length > 0) {
      const names = Array.from(new Set(activeAtOrder.map((s) => s.name.trim()).filter(Boolean)));
      if (names.length > 0) return names.join(", ");
    }
    const orderDay = phDateString(order.createdAt);
    const sameDayBaristas = pairedShifts.filter(
      (s) => s.role === "barista" && s.loginAt && phDateString(s.loginAt) === orderDay,
    );
    if (sameDayBaristas.length > 0) {
      const names = Array.from(new Set(sameDayBaristas.map((s) => s.name.trim()).filter(Boolean)));
      if (names.length > 0) return names.join(", ");
    }
    return "—";
  };
  const recentOrderTotal = (order: Order) =>
    typeof order.subtotal === "number" && Number.isFinite(order.subtotal)
      ? Math.max(0, order.subtotal - (order.discount ?? 0))
      : order.total;
  const latest = currentRecentOrderPage?.orders ?? [];
  const pendingVoidRequests: typeof store.voidRequests = [];

  if (!isClient) {
    return <div className="p-8 text-center text-neutral-500">Loading dashboard...</div>;
  }
  if (salesSummaryLoading) {
    return <div className="p-8 text-center text-neutral-500">Loading sales summary...</div>;
  }
  if (salesSummaryError || !salesSummary) {
    return (
      <div role="alert" className="p-8 text-center text-sm text-red-700">
        {salesSummaryError ?? "Sales summary is unavailable."}
      </div>
    );
  }

  return (
    <div className="mx-auto min-w-0 max-w-[1760px] space-y-6 px-3 py-5 sm:space-y-8 sm:px-6 sm:py-7 xl:px-8 2xl:space-y-10 2xl:px-10 2xl:py-9">
      <div className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <p className="text-xs tracking-[0.3em] text-neutral-500 uppercase">
            Sales analysis
          </p>
          <h1 className="mt-2 text-2xl font-semibold sm:text-3xl">
            Track every ticket
          </h1>
        </div>

        <div className="flex w-full min-w-0 flex-col gap-2 sm:flex-row sm:flex-wrap sm:items-center lg:w-auto">
          <div 
            className={`flex min-w-0 items-center gap-2 rounded-lg border px-3 py-2 shadow-sm transition sm:py-1.5 ${
              activeFilterMode === "range" 
                ? "bg-white border-black ring-1 ring-black" 
                : "bg-white border-neutral-300 opacity-75"
            }`}
          >
            <span className="shrink-0 text-xs font-medium text-neutral-500">Range:</span>
            <select
              value={rangeType}
              onChange={(e) => {
                setRangeType(e.target.value);
                setActiveFilterMode("range");
              }}
              onClick={() => setActiveFilterMode("range")}
              className="min-w-0 flex-1 bg-transparent text-sm outline-none cursor-pointer"
            >
              <option value="today">Today</option>
              <option value="week">This Week</option>
              <option value="lastWeek">Last Week</option>
              <option value="month">This Month</option>
              <option value="lastMonth">Last Month</option>
              <option value="thisYear">This Year</option>
              <option value="lastYear">Last Year</option>
            </select>
          </div>

          <div 
            className={`flex min-w-0 items-center gap-2 rounded-lg border px-3 py-2 shadow-sm transition sm:py-1.5 ${
              activeFilterMode === "date" 
                ? "bg-white border-black ring-1 ring-black" 
                : "bg-white border-neutral-300 opacity-75"
            }`}
          >
            <span className="shrink-0 text-xs font-medium text-neutral-500">Date:</span>
            <input
              type="date"
              value={filterDateStr}
              onChange={(e) => {
                setFilterDateStr(e.target.value);
                setActiveFilterMode("date");
              }}
              onClick={() => setActiveFilterMode("date")}
              className="min-w-0 flex-1 bg-transparent text-sm outline-none cursor-pointer"
            />
          </div>

          <button
            type="button"
            onClick={() => window.print()}
            className="rounded-lg bg-[#101d37] px-4 py-2 text-xs font-medium text-white transition hover:bg-[#243a5e] shadow-sm"
          >
            Download PDF Sales
          </button>

        </div>
      </div>

      {pendingVoidRequests.length > 0 ? (
        <section className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
          <div className="flex flex-wrap items-end justify-between gap-2 border-b border-neutral-200 pb-3">
            <div>
              <p className="text-[10px] tracking-[0.2em] text-neutral-500 uppercase sm:text-xs sm:tracking-[0.25em]">
                Void approvals
              </p>
              <h2 className="mt-1 text-lg font-semibold">Requests waiting for admin</h2>
            </div>
            <span className="rounded-full bg-[#101d37] px-3 py-1 text-xs font-medium text-white">
              {pendingVoidRequests.length} pending
            </span>
          </div>

          {approvalMessage ? (
            <p className="mt-3 text-sm text-neutral-600">{approvalMessage}</p>
          ) : null}

          <div className="mt-4 grid gap-3 xl:grid-cols-2">
            {pendingVoidRequests.map((request) => (
              <article key={request.id} className="border border-neutral-200 bg-neutral-50 p-4">
                <div className="flex items-start justify-between gap-4">
                  <div className="min-w-0">
                    <p className="text-sm font-semibold">{request.requestedByName}</p>
                    <p className="mt-0.5 text-xs text-neutral-500">
                      {phDateTimeLabel(request.requestedAt)}
                      {request.orderId ? " · Existing ticket" : " · Current checkout"}
                    </p>
                  </div>
                  <p className="shrink-0 text-sm font-semibold">{formatMoney(request.total)}</p>
                </div>
                <p className="mt-3 text-sm text-neutral-700">
                  {request.items.map((item) => `${item.qty}× ${orderLineListLabel(item)}`).join(", ")}
                </p>
                <p className="mt-2 text-xs text-neutral-500">
                  Reason: {request.reason}
                </p>
                <button
                  type="button"
                  disabled={approvalPending}
                  onClick={() =>
                    startApprovalTransition(async () => {
                      const result = await approveVoidRequest(request.id);
                      if ("error" in result && result.error) {
                        setApprovalMessage(result.error);
                        return;
                      }
                      setApprovalMessage(`Void approved for ${request.requestedByName}.`);
                    })
                  }
                  className="mt-4 w-full rounded-lg bg-[#101d37] px-4 py-2.5 text-xs font-medium text-white transition hover:bg-[#243a5e] disabled:opacity-40"
                >
                  {approvalPending ? "Processing..." : "Approve void"}
                </button>
              </article>
            ))}
          </div>
        </section>
      ) : null}

      <section className="space-y-6">
        <div className="border-b border-neutral-200 pb-3">
          <h2 className="text-xs tracking-[0.25em] text-neutral-500 uppercase">
            Performance Overview
          </h2>
        </div>

        <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-5">
          {isTodaySelected ? (
            <>
              <Metric
                label="Today's Sales"
                value={formatMoney(summary.totals.sales)}
              />
              <Metric
                label="Today's Orders"
                value={String(summary.totals.orders)}
              />
            </>
          ) : (
            <>
              <Metric
                label="Period Sales"
                value={formatMoney(summary.totals.sales)}
              />
              <Metric
                label="Period Orders"
                value={String(summary.totals.orders)}
              />
            </>
          )}

          <Metric
            label="Average Ticket"
            value={formatMoney(computedAverageTicket)}
          />

          <div className="min-w-0 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
            <p className="text-[10px] tracking-[0.2em] text-neutral-500 uppercase sm:text-xs sm:tracking-[0.25em]">
              Sold Products
            </p>
            <div className="mt-3 space-y-3">
              {soldProductSummary.map((group) => (
                <div
                  key={group.type.toLowerCase()}
                  className="flex items-start justify-between gap-3"
                >
                  <div>
                    <p className="text-sm font-medium">
                      {menuCategoryTypeLabel(group.type).toUpperCase()}
                    </p>
                    <p className="text-xs text-neutral-500">{formatMoney(group.sales)}</p>
                  </div>
                  <p className="text-2xl font-semibold sm:text-3xl">{group.quantity}</p>
                </div>
              ))}
              <div className="flex items-center justify-between gap-3 border-t border-neutral-200 pt-3">
                <div>
                  <p className="text-sm font-semibold">Total Sold</p>
                  <p className="text-xs text-neutral-500">{formatMoney(totalSoldSales)}</p>
                </div>
                <p className="text-2xl font-semibold sm:text-3xl">{totalSoldQty}</p>
              </div>
            </div>
          </div>

          <Metric
            label="Peak Hour"
            value={peak && peak.orders > 0 ? peak.label : "—"}
          />

          {rangeType === "week" && (
            <Metric
              label="Busiest Day"
              value={busy
                ? new Intl.DateTimeFormat("en-US", { timeZone: "Asia/Manila", weekday: "short", month: "short", day: "numeric" })
                    .format(new Date(`${busy.date}T12:00:00+08:00`))
                : "—"}
            />
          )}
        </div>
      </section>

      <section className="grid gap-4 xl:grid-cols-2 2xl:gap-6">
        {!isTodaySelected && (
          <div className="min-w-0 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
            <div className="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
              <h2 className="text-[10px] tracking-[0.2em] text-neutral-500 uppercase sm:text-xs sm:tracking-[0.25em]">
                {trackingTitle}
              </h2>
              <span className="text-[11px] text-neutral-400">{trackingSubtitle}</span>
            </div>
            <VerticalBars items={trackingItems} />
          </div>
        )}

        <div className={`min-w-0 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5 ${isTodaySelected ? "xl:col-span-2" : ""}`}>
          <div className="flex flex-col gap-1 sm:flex-row sm:items-center sm:justify-between">
            <h2 className="text-[10px] tracking-[0.2em] text-neutral-500 uppercase sm:text-xs sm:tracking-[0.25em]">
              Peak hours <span className="hidden sm:inline">(by item volume) · 8:00 AM – 12:00 AM</span>
            </h2>
          </div>
          <div className="overflow-x-auto">
            <div className="min-w-[560px]">
              <VerticalBars
                items={hours.map((slot) => ({
                  key: String(slot.hour),
                  label: slot.label,
                  value: slot.orders,
                  display: slot.orders > 0 ? `${slot.orders} items` : "",
                  caption: "",
                }))}
              />
            </div>
          </div>
        </div>
      </section>

      <section className="grid gap-4 xl:grid-cols-2 2xl:gap-6">
        <div className="min-w-0 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
          <h2 className="text-[10px] tracking-[0.2em] text-neutral-500 uppercase sm:text-xs sm:tracking-[0.25em]">
            Best selling drinks
          </h2>
          
          <HorizontalBars
            empty="No drinks sold in this period."
            items={best.map((item) => ({
              key: item.id,
              label: item.name,
              value: item.qty,
              left: `${item.qty} sold`,
              right: formatMoney(item.sales),
            }))}
          />
        </div>

        <div className="min-w-0 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
          <h2 className="text-[10px] tracking-[0.2em] text-neutral-500 uppercase sm:text-xs sm:tracking-[0.25em]">
            Low selling drinks
          </h2>
          <HorizontalBars
            empty="No drinks found in menu."
            items={low.map((item) => ({
              key: item.id,
              label: item.name,
              value: item.qty,
              left: item.qty === 0 ? "No sales" : `${item.qty} sold`,
              right: formatMoney(item.sales),
            }))}
          />
        </div>
      </section>

      <section className="grid gap-4 xl:grid-cols-2 2xl:gap-6">
        <div className="min-w-0 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
          <h2 className="text-[10px] tracking-[0.2em] text-neutral-500 uppercase sm:text-xs sm:tracking-[0.25em]">
            Sales by Drinks category
          </h2>
          <HorizontalBars
            empty="No category sales in this period."
            items={categories
              .sort((a, b) => b.qty - a.qty)
              .map((item) => ({
                key: item.name,
                label: item.name,
                value: item.qty,
                left: `${item.qty} items`,
                right: item.sales ? formatMoney(item.sales) : '₱0.00',
              }))}
          />
        </div>

        <div className="min-w-0 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
          <h2 className="text-[10px] tracking-[0.2em] text-neutral-500 uppercase sm:text-xs sm:tracking-[0.25em]">
            Payment Types (Total Breakdown)
          </h2>
          <div className="mt-4 space-y-3">
            {payments.map((p, pIdx) => (
              <div key={`${p.method}-${pIdx}`} className="flex justify-between items-center text-sm border-b border-neutral-100 pb-2">
                <div>
                  <p className="font-medium">{p.label}</p>
                  <p className="text-xs text-neutral-500">{p.count} transactions</p>
                </div>
                <span className="font-semibold">{formatMoney(p.sales)}</span>
              </div>
            ))}
            <div className="flex justify-between items-center text-sm font-bold pt-2 border-t border-neutral-200">
              <span>Total Revenue:</span>
              <span>{formatMoney(totalSalesAmount)}</span>
            </div>
          </div>
        </div>
      </section>

      <section className="min-w-0 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <div className="flex items-center gap-3">
          <h2 className="text-[10px] tracking-[0.2em] text-neutral-500 uppercase sm:text-xs sm:tracking-[0.25em]">
            Drinks sold
          </h2>
          <button
            type="button"
            onClick={() => setDrinksOpen((open) => !open)}
            className="rounded border border-neutral-300 px-2 py-1 text-[10px] font-medium tracking-wide text-neutral-600 uppercase transition hover:border-black hover:text-black"
          >
            {drinksOpen ? "Minimize" : "Expand"}
          </button>
        </div>
        {drinksOpen ? (
          <>
            {drinkSoldRows.length === 0 ? (
              <p className="mt-4 py-6 text-center text-sm text-neutral-500">
                No drinks sold in this range.
              </p>
            ) : (
              <div className="mt-4">
                <div className="hidden grid-cols-5 gap-x-4 border-b border-neutral-200 pb-2 text-xs text-neutral-500 sm:grid">
                  <p className="min-w-0">Drink</p>
                  <p className="min-w-0 text-right">Iced</p>
                  <p className="min-w-0 text-right">Hot</p>
                  <p className="min-w-0 text-right">Sold</p>
                  <p className="min-w-0 text-right">Sales</p>
                </div>
                <div className="divide-y divide-neutral-200">
                  {drinkSoldRows.map((item) => (
                    <div
                      key={item.id}
                      className="grid grid-cols-1 gap-1 py-3 sm:grid-cols-5 sm:items-start sm:gap-x-4"
                    >
                      <p className="min-w-0 text-sm font-medium">{item.name}</p>
                      <p className="min-w-0 text-sm text-neutral-600 sm:text-right">
                        <span className="sm:hidden">Iced: </span>
                        {item.iced}
                      </p>
                      <p className="min-w-0 text-sm text-neutral-600 sm:text-right">
                        <span className="sm:hidden">Hot: </span>
                        {item.hot}
                      </p>
                      <p className="min-w-0 text-sm text-neutral-700 sm:text-right">{item.qty}</p>
                      <p className="min-w-0 text-sm font-semibold sm:text-right">
                        {formatMoney(item.sales)}
                      </p>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </>
        ) : null}
      </section>

      <section className="min-w-0 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <div className="flex items-center gap-3">
          <h2 className="text-[10px] tracking-[0.2em] text-neutral-500 uppercase sm:text-xs sm:tracking-[0.25em]">
            Recent orders
          </h2>
          <button
            type="button"
            onClick={() => setOrdersOpen((open) => !open)}
            className="rounded border border-neutral-300 px-2 py-1 text-[10px] font-medium tracking-wide text-neutral-600 uppercase transition hover:border-black hover:text-black"
          >
            {ordersOpen ? "Minimize" : "Expand"}
          </button>
        </div>
        {ordersOpen ? (
          recentOrdersLoading ? (
            <p className="mt-4 py-6 text-center text-sm text-neutral-500">
              Loading recent orders...
            </p>
          ) : recentOrderPageError ? (
            <p role="alert" className="mt-4 py-6 text-center text-sm text-red-700">
              {recentOrderPageError}
            </p>
          ) : latest.length === 0 ? (
            <p className="mt-4 py-6 text-center text-sm text-neutral-500">
              No recent orders found for the selected range.
            </p>
          ) : (
          <>
            <div className="mt-4 overflow-x-auto">
              <div className={showPromoVoucher ? "min-w-[1060px]" : "min-w-[970px]"}>
              <div className={`hidden gap-x-3 border-b border-neutral-200 pb-2 text-xs text-neutral-500 lg:grid ${showPromoVoucher ? "grid-cols-12" : "grid-cols-11"}`}>
                <p className="min-w-0">Time</p>
                <p className="min-w-0">Owner</p>
                <p className="min-w-0">Order #</p>
                <p className="min-w-0">Items</p>
                <p className="min-w-0">Type</p>
                <p className="min-w-0">Status</p>
                <p className="min-w-0">Cashier in Charge</p>
                <p className="min-w-0">Barista in Charge</p>
                {showPromoVoucher ? <p className="min-w-0">Promo voucher</p> : null}
                <p className="min-w-0">Payment</p>
                <p className="min-w-0">Service</p>
                <p className="min-w-0 text-right">Total</p>
              </div>
              <div className="grid gap-3 lg:block lg:divide-y lg:divide-neutral-200">
                {latest.map((order: Order, ordIdx: number) => (
                  <div
                    key={`${order.id}-${ordIdx}`}
                    className={`grid grid-cols-1 gap-2 rounded-2xl border border-slate-200 bg-slate-50/60 p-4 shadow-sm lg:items-start lg:gap-x-3 lg:rounded-none lg:border-0 lg:bg-transparent lg:px-0 lg:py-3 lg:shadow-none ${showPromoVoucher ? "lg:grid-cols-12" : "lg:grid-cols-11"}`}
                  >
                    <div className="min-w-0">
                      <p className="text-sm leading-5 text-neutral-700">
                        {phDateTimeLabel(order.createdAt)}
                      </p>
                      <p className="mt-0.5 text-xs text-neutral-500 lg:hidden">
                        Owner: {orderOwnerName(order)}
                      </p>
                      {isVoided(order) ? (
                        <p className="mt-0.5 text-sm font-medium text-neutral-400 line-through lg:hidden">
                          {orderIdLabel(order)}
                        </p>
                      ) : (
                        <p className="mt-0.5 text-sm font-medium lg:hidden">{orderIdLabel(order)}</p>
                      )}
                    </div>
                    <p className="hidden min-w-0 break-words text-sm text-neutral-700 lg:block">
                      {orderOwnerName(order)}
                    </p>
                    <p className="hidden min-w-0 text-sm font-medium lg:block">
                      {isVoided(order) ? (
                        <span className="text-neutral-400 line-through">{orderIdLabel(order)}</span>
                      ) : (
                        orderIdLabel(order)
                      )}
                    </p>
                    <ul className="min-w-0 list-disc space-y-1 pl-4 text-xs leading-relaxed text-neutral-600 lg:text-sm">
                      {order.items.map((item, itemIdx) => (
                        <li key={`${order.id}-${item.productId}-${itemIdx}`} className="break-words">
                          <p>
                            {item.qty}× {drinkDisplayName(item)}
                          </p>
                          {orderLineOptionsLabel(item) ? (
                            <p className="text-[11px] text-neutral-500">{orderLineOptionsLabel(item)}</p>
                          ) : null}
                        </li>
                      ))}
                    </ul>
                    <p className="min-w-0 break-words text-xs text-neutral-500 lg:text-sm">
                      <span className="lg:hidden">Type: </span>
                      {orderItemTypes(order.items, store.menu).join(", ") || "—"}
                    </p>
                    <div className="min-w-0">
                      <span
                        className={`inline-flex rounded px-2 py-0.5 text-[10px] font-medium lg:text-xs ${
                          isVoided(order)
                            ? "bg-red-100 text-red-700"
                            : "bg-black text-white"
                        }`}
                      >
                        {isVoided(order) ? voidStatusLabel(order, store.users) : "Completed"}
                      </span>
                    </div>
                    <p className="min-w-0 break-words text-xs text-neutral-500 lg:text-sm">
                      <span className="lg:hidden">Cashier in Charge: </span>
                      {orderCashierInCharge(order)}
                    </p>
                    <p className="min-w-0 break-words text-xs text-neutral-500 lg:text-sm">
                      <span className="lg:hidden">Barista in Charge: </span>
                      {orderBaristaInCharge(order)}
                    </p>
                    {showPromoVoucher ? (
                      <p className="min-w-0 break-words text-xs text-neutral-500 lg:text-sm">
                        <span className="lg:hidden">Promo voucher: </span>
                        {order.promoLabel?.trim() || "—"}
                      </p>
                    ) : null}
                    <p className="min-w-0 text-xs text-neutral-500 lg:text-sm">
                      <span className="lg:hidden">Payment: </span>
                      {paymentLabel(order.paymentMethod)}
                    </p>
                    <p className="min-w-0 text-xs text-neutral-500 lg:text-sm">
                      <span className="lg:hidden">Service: </span>
                      {orderServiceMode(order)}
                    </p>
                    <p className="min-w-0 text-sm font-semibold lg:text-right">
                      <span className="font-normal text-neutral-500 lg:hidden">Total: </span>
                      {formatMoney(recentOrderTotal(order))}
                    </p>
                  </div>
                ))}
              </div>
            </div>
            </div>
            {currentRecentOrderPage ? (
              <div className="mt-4 flex flex-wrap items-center justify-between gap-3 border-t border-neutral-200 pt-3">
                <p className="text-xs text-neutral-500">
                  Showing {(recentOrderPage - 1) * 50 + 1}–
                  {Math.min(recentOrderPage * 50, currentRecentOrderPage.total)} of{" "}
                  {currentRecentOrderPage.total} orders
                </p>
                <div className="flex gap-2">
                  <button
                    type="button"
                    disabled={recentOrderPage <= 1}
                    onClick={() =>
                      setRecentOrderPageSelection({ rangeKey: periodKey, page: recentOrderPage - 1 })
                    }
                    className="rounded border border-neutral-300 px-3 py-1.5 text-xs disabled:opacity-40"
                  >
                    Previous
                  </button>
                  <button
                    type="button"
                    disabled={!currentRecentOrderPage.hasMore}
                    onClick={() =>
                      setRecentOrderPageSelection({ rangeKey: periodKey, page: recentOrderPage + 1 })
                    }
                    className="rounded border border-neutral-300 px-3 py-1.5 text-xs disabled:opacity-40"
                  >
                    Next
                  </button>
                </div>
              </div>
            ) : null}
          </>
          )
        ) : null}
      </section>
    </div>
  );
}
