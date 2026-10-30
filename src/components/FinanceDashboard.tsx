"use client";

import { useEffect, useMemo, useState, type FormEvent } from "react";
import {
  createAdminLedgerEntry,
  deleteAdminLedgerEntry,
  savePayrollDraft,
  setAdminLedgerEntryStatus,
} from "@/actions/admin-ledger";
import { getAttendancePhotoUrl } from "@/actions/attendance";
import { formatMoney } from "@/lib/menu";
import { calculateGrossPay, calculatePayrollHours, calculatePayrollHoursBetween } from "@/lib/payroll";
import { pairLoginSessions } from "@/lib/staff-sessions";
import { shiftAttendanceStatus, workShiftInterval } from "@/lib/shift-reports";
import { liveOrders, paymentStats, sumSales } from "@/lib/analytics";
import { paymentLabel } from "@/lib/payments";
import { phDateString, phDateTimeLabel, phDateRangeUtcBounds, phPeriodBounds, phTimestamp, type PeriodRange } from "@/lib/datetime";
import type {
  AdminLedgerCategory,
  AdminLedgerEntry,
  AdminLedgerKind,
  LedgerPaymentSource,
  LoginActivity,
  Order,
  PayrollRecord,
  StoreData,
  WorkShift,
} from "@/lib/types";

function attendanceEventLabel(type: LoginActivity["type"]) {
  switch (type) {
    case "break_start":
      return "Break start";
    case "break_end":
      return "Break end";
    case "logout":
      return "Clock-out";
    default:
      return "Clock-in";
  }
}

const expenseCategories: { id: AdminLedgerCategory; label: string }[] = [
  { id: "supplies", label: "Supplies" },
  { id: "utilities", label: "Utilities" },
  { id: "petty_cash", label: "Petty Cash" },
  { id: "restock", label: "Restock Expense" },
  { id: "payroll", label: "Payroll Expense" },
  { id: "other", label: "Other" },
];

function Card({ label, value, hint }: { label: string; value: number; hint?: string }) {
  return (
    <article className="min-w-0 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
      <p className="text-[10px] tracking-[0.2em] text-neutral-500 uppercase">{label}</p>
      <p className="mt-2 break-words text-xl font-semibold sm:text-2xl">{formatMoney(value)}</p>
      {hint ? <p className="mt-1 text-xs text-neutral-500">{hint}</p> : null}
    </article>
  );
}

function inPeriod(date: string, start: number, endExclusive: number) {
  const time = phTimestamp(date);
  return time >= start && time < endExclusive;
}

async function loadAdminHistoryPages<T>(
  urlForPage: (page: number) => string,
  key: "orders" | "activity",
): Promise<T[]> {
  const rows: T[] = [];
  for (let page = 1; page <= 2000; page += 1) {
    const response = await fetch(urlForPage(page), { cache: "no-store" });
    const result = await response.json() as {
      orders?: T[];
      activity?: T[];
      hasMore?: boolean;
      error?: string;
    };
    if (!response.ok) throw new Error(result.error || "Unable to load Finance history.");
    const pageRows = key === "orders" ? result.orders : result.activity;
    if (!Array.isArray(pageRows) || typeof result.hasMore !== "boolean") {
      throw new Error("Finance history response was incomplete.");
    }
    rows.push(...pageRows);
    if (!result.hasMore) return rows;
  }
  throw new Error("Finance history exceeds the supported page limit.");
}

type PaymentSummaryRow = { method: string; count: number; sales: number };

function isPaymentSummary(value: unknown): value is { payments: PaymentSummaryRow[]; totals: { sales: number } } {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const summary = value as Record<string, unknown>;
  if (!summary.totals || typeof summary.totals !== "object" || Array.isArray(summary.totals)) return false;
  const totals = summary.totals as Record<string, unknown>;
  return typeof totals.sales === "number" &&
    Number.isFinite(totals.sales) &&
    Array.isArray(summary.payments) &&
    summary.payments.every((entry) =>
      Boolean(entry) &&
      typeof entry === "object" &&
      !Array.isArray(entry) &&
      typeof (entry as Record<string, unknown>).method === "string" &&
      typeof (entry as Record<string, unknown>).count === "number" &&
      Number.isFinite((entry as Record<string, unknown>).count) &&
      typeof (entry as Record<string, unknown>).sales === "number" &&
      Number.isFinite((entry as Record<string, unknown>).sales),
    );
}

function LedgerCard({
  kind,
  entries,
  total,
  canEdit,
  pending,
  onAdd,
  onDelete,
  onStatusChange,
  workShifts,
}: {
  kind: AdminLedgerKind;
  entries: AdminLedgerEntry[];
  total: number;
  canEdit: boolean;
  pending: boolean;
  onAdd: (event: FormEvent<HTMLFormElement>, data: { title: string; reason: string; amount: string; category: AdminLedgerCategory; counterparty: string; paymentSource: LedgerPaymentSource; date: string; workShiftId: string }) => void;
  onDelete: (entry: AdminLedgerEntry) => void;
  onStatusChange: (entry: AdminLedgerEntry) => void;
  workShifts: WorkShift[];
}) {
  const [title, setTitle] = useState("");
  const [reason, setReason] = useState("");
  const [amount, setAmount] = useState("");
  const [date, setDate] = useState(phDateString());
  const [category, setCategory] = useState<AdminLedgerCategory>("supplies");
  const [counterparty, setCounterparty] = useState("");
  const [paymentSource, setPaymentSource] = useState<LedgerPaymentSource>("cash");
  const [workShiftId, setWorkShiftId] = useState("");
  const expense = kind === "expense";
  const expenseDayStart = phTimestamp(`${date}T00:00:00+08:00`);
  const expenseShifts = workShifts.filter((shift) => {
    const interval = workShiftInterval(shift);
    return !shift.closedAt && interval.start < expenseDayStart + 24 * 60 * 60 * 1000 && interval.end > expenseDayStart;
  });

  return (
    <section className="min-w-0 space-y-4 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
      <div>
        <h2 className="text-xs tracking-[0.25em] text-neutral-500 uppercase">
          {expense ? "Expense Manager" : "Credit / Receivables"}
        </h2>
        <p className="mt-1 text-sm font-semibold">
          {expense ? "Total expenses" : "Outstanding"}: {formatMoney(total)}
        </p>
      </div>
      {canEdit ? (
        <form
          onSubmit={(event) => onAdd(event, { title, reason, amount, category, counterparty, paymentSource, date, workShiftId })}
          className="grid gap-2 border-t border-neutral-100 pt-3 sm:grid-cols-2"
        >
          <input value={title} onChange={(event) => setTitle(event.target.value)} placeholder={expense ? "Expense title" : "Credit / receivable title"} required className="min-w-0 rounded border border-neutral-300 px-3 py-2 text-sm" />
          {!expense ? <input value={counterparty} onChange={(event) => setCounterparty(event.target.value)} placeholder="internal / partner" required className="min-w-0 rounded border border-neutral-300 px-3 py-2 text-sm" /> : null}
          {expense ? (
            <select value={category} onChange={(event) => setCategory(event.target.value as AdminLedgerCategory)} className="min-w-0 rounded border border-neutral-300 bg-white px-3 py-2 text-sm">
              {expenseCategories.map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}
            </select>
          ) : null}
          <input value={reason} onChange={(event) => setReason(event.target.value)} placeholder="Reason / notes" className="min-w-0 rounded border border-neutral-300 px-3 py-2 text-sm" />
          <input type="number" min="0.01" step="0.01" value={amount} onChange={(event) => setAmount(event.target.value)} placeholder="Amount (₱)" required className="min-w-0 rounded border border-neutral-300 px-3 py-2 text-sm" />
          <label className="flex items-center gap-2 text-xs text-neutral-500">Date <input type="date" value={date} onChange={(event) => { setDate(event.target.value); setWorkShiftId(""); }} required className="min-w-0 rounded border border-neutral-300 px-2 py-2 text-sm text-neutral-900" /></label>
          {expense ? (
            <select value={paymentSource} onChange={(event) => { setPaymentSource(event.target.value as LedgerPaymentSource); setWorkShiftId(""); }} aria-label="Expense paid from" className="min-w-0 rounded border border-neutral-300 bg-white px-3 py-2 text-sm">
              <option value="cash">Paid from cash drawer</option>
              <option value="non_cash">Paid electronically / card</option>
              <option value="unassigned">Not yet paid / unspecified</option>
            </select>
          ) : null}
          {expense && paymentSource === "cash" && expenseShifts.length > 0 ? (
            <select value={workShiftId} onChange={(event) => setWorkShiftId(event.target.value)} aria-label="Cash expense shift" required className="min-w-0 rounded border border-neutral-300 bg-white px-3 py-2 text-sm">
              <option value="">Assign to shift</option>
              {expenseShifts.map((shift) => <option key={shift.id} value={shift.id}>{shift.name} ({shift.startTime}–{shift.endTime})</option>)}
            </select>
          ) : null}
          <button type="submit" disabled={pending} className="rounded bg-[#101d37] px-3 py-2 text-sm font-medium text-white disabled:opacity-50 sm:col-span-2">
            {pending ? "Saving..." : expense ? "Add expense" : "Add receivable"}
          </button>
        </form>
      ) : null}
      <div className={entries.length > 0 ? "overflow-x-auto" : "overflow-hidden"}>
        <table className={`w-full text-left text-sm ${entries.length > 0 ? "min-w-[640px]" : ""}`}>
          <thead className="border-b border-neutral-100 text-xs text-neutral-400">
            <tr>
              <th className="py-2">Title / Party</th>
              <th className="py-2">Category / Notes</th>
              <th className="py-2 text-right">Amount</th>
              <th className="py-2">Status / Payment</th>
              <th className="py-2 text-right">Action</th>
            </tr>
          </thead>
          <tbody>
            {entries.length === 0 ? <tr><td colSpan={5} className="py-5 text-center text-xs text-neutral-400">No entries in this range.</td></tr> : entries.map((entry, index) => (
              <tr key={`${entry.id}-${index}`} className="border-b border-neutral-50 text-xs">
                <td className="py-2">
                  <p className="font-medium">{entry.title}</p>
                  <p className="text-[11px] text-neutral-400">{entry.date}</p>
                  {!expense && entry.counterparty ? <p className="text-neutral-500">{entry.counterparty}</p> : null}
                </td>
                <td className="py-2 text-neutral-500">
                  {expense ? expenseCategories.find((item) => item.id === entry.category)?.label ?? "Other" : entry.reason || "—"}
                  {expense && entry.reason ? <p>{entry.reason}</p> : null}
                  {expense && entry.workShiftId ? <p>Shift: {workShifts.find((shift) => shift.id === entry.workShiftId)?.name ?? "Former shift"}</p> : null}
                </td>
                <td className="py-2 text-right font-medium">{formatMoney(entry.amount)}</td>
                <td className="py-2">
                  {expense
                    ? entry.paymentSource === "cash" ? "Paid · Cash" : entry.paymentSource === "non_cash" ? "Paid · E-wallet/Card" : "Unassigned"
                    : entry.status === "settled" ? "Settled" : "Unpaid"}
                </td>
                <td className="py-2 text-right">
                  {!expense ? (
                    <button type="button" disabled={!canEdit || pending} onClick={() => onStatusChange(entry)} className="font-medium text-[#243a5e] disabled:text-neutral-300">
                      {entry.status === "settled" ? "Mark unpaid" : "Settle"}
                    </button>
                  ) : canEdit && entry.category !== "restock" && entry.category !== "payroll" && entry.date === phDateString() ? (
                    <button type="button" disabled={pending} onClick={() => onDelete(entry)} className="font-medium text-red-500">Delete</button>
                  ) : <span className="text-neutral-300">—</span>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

export function FinanceDashboard({
  store,
  initialExpenses,
  initialCredits,
  initialLedgerError,
  payrollRecords,
  payrollError,
  remoteHistory = false,
}: {
  store: StoreData;
  initialExpenses: AdminLedgerEntry[];
  initialCredits: AdminLedgerEntry[];
  initialLedgerError: string | null;
  payrollRecords: PayrollRecord[];
  payrollError: string | null;
  remoteHistory?: boolean;
}) {
  const today = phDateString();
  const [rangeType, setRangeType] = useState<"today" | "week" | "month" | "custom">("today");
  const [customStart, setCustomStart] = useState(today);
  const [customEnd, setCustomEnd] = useState(today);
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [selectedShiftId, setSelectedShiftId] = useState("all");
  const [attendancePhotoPage, setAttendancePhotoPage] = useState(0);
  const [viewingAttendancePhoto, setViewingAttendancePhoto] = useState<{
    url: string;
    name: string;
    type: LoginActivity["type"];
    at: string;
  } | null>(null);
  const [remoteOrders, setRemoteOrders] = useState<Order[]>(store.orders);
  const [remoteLoginActivity, setRemoteLoginActivity] = useState<LoginActivity[]>(store.loginActivity ?? []);
  const [remotePayments, setRemotePayments] = useState<{ rangeKey: string; payments: PaymentSummaryRow[]; totalSales: number } | null>(null);
  const [historyLoading, setHistoryLoading] = useState(remoteHistory);
  const [historyError, setHistoryError] = useState<string | null>(null);
  const activity = remoteHistory ? remoteLoginActivity : store.loginActivity ?? [];
  const financeOrders = remoteHistory ? remoteOrders : store.orders;
  const sessions = useMemo(() => pairLoginSessions(activity), [activity]);
  const attendancePhotos = activity
    .filter((entry) => Boolean(entry.photoPath))
    .sort((left, right) => phTimestamp(right.at) - phTimestamp(left.at));
  const attendancePhotoPageCount = Math.max(1, Math.ceil(attendancePhotos.length / 20));
  const safeAttendancePhotoPage = Math.min(attendancePhotoPage, attendancePhotoPageCount - 1);
  const attendancePhotoRows = attendancePhotos.slice(safeAttendancePhotoPage * 20, safeAttendancePhotoPage * 20 + 20);
  const period = rangeType === "custom"
    ? { from: customStart, to: customEnd }
    : phPeriodBounds(rangeType as PeriodRange);
  const periodBounds = useMemo(
    () => phDateRangeUtcBounds(period.from, period.to),
    [period.from, period.to],
  );
  const start = periodBounds ? phTimestamp(periodBounds.start) : 0;
  const endExclusive = periodBounds ? phTimestamp(periodBounds.endExclusive) : 0;
  const periodKey = `${period.from}:${period.to}`;
  const allLiveOrders = liveOrders(financeOrders);
  const periodOrders = allLiveOrders.filter((order) => inPeriod(order.createdAt, start, endExclusive));
  const expenses = initialExpenses.filter((entry) => inPeriod(entry.date, start, endExclusive));
  const credits = initialCredits.filter((entry) => inPeriod(entry.date, start, endExclusive));
  const totalRevenue = sumSales(periodOrders);
  const totalExpenses = expenses.reduce((sum, entry) => sum + entry.amount, 0);
  const outstandingCredits = credits.filter((entry) => entry.status !== "settled").reduce((sum, entry) => sum + entry.amount, 0);
  useEffect(() => {
    if (!remoteHistory || !periodBounds) return;
    let active = true;
    const query = new URLSearchParams({ from: period.from, to: period.to });
    const load = async () => {
      try {
        const [orders, activity, paymentResponse] = await Promise.all([
          loadAdminHistoryPages<Order>(
            (page) => `/api/admin/history?${new URLSearchParams({ ...Object.fromEntries(query), kind: "transactions", page: String(page), includeActivity: "false" })}`,
            "orders",
          ),
          loadAdminHistoryPages<LoginActivity>(
            (page) => `/api/admin/login-activity?${new URLSearchParams({ ...Object.fromEntries(query), page: String(page) })}`,
            "activity",
          ),
          fetch(`/api/admin/sales-summary?${query}`, { cache: "no-store" }),
        ]);
        const paymentSummary: unknown = await paymentResponse.json();
        if (!paymentResponse.ok) {
          const errorMessage = paymentSummary && typeof paymentSummary === "object" && "error" in paymentSummary
            ? String(paymentSummary.error)
            : "Unable to load payment breakdown.";
          throw new Error(errorMessage);
        }
        if (!isPaymentSummary(paymentSummary)) throw new Error("Payment breakdown response was invalid.");
        if (!active) return;
        setRemoteOrders(orders);
        setRemoteLoginActivity(activity);
        setRemotePayments({
          rangeKey: periodKey,
          payments: paymentSummary.payments,
          totalSales: paymentSummary.totals.sales,
        });
      } catch (error) {
        if (active) setHistoryError(error instanceof Error ? error.message : "Unable to load Finance history.");
      } finally {
        if (active) setHistoryLoading(false);
      }
    };
    void load();
    return () => { active = false; };
  }, [period.from, period.to, periodBounds, periodKey, remoteHistory]);

  function prepareHistoryReload() {
    if (!remoteHistory) return;
    setHistoryLoading(true);
    setHistoryError(null);
    setRemoteOrders([]);
    setRemoteLoginActivity([]);
    setAttendancePhotoPage(0);
  }

  const localPaymentStats = paymentStats(periodOrders);
  const paymentSummary = remoteHistory && remotePayments?.rangeKey === periodKey
    ? remotePayments
    : null;
  const paymentBreakdown = remoteHistory
    ? (paymentSummary?.payments ?? []).map((payment) => ({
        label: paymentLabel(payment.method),
        count: payment.count,
        amount: payment.sales,
      }))
    : localPaymentStats.map((payment) => ({
        label: payment.label,
        count: payment.count,
        amount: payment.sales,
      }));
  const paymentTotal = paymentSummary?.totalSales ?? paymentBreakdown.reduce((sum, payment) => sum + payment.amount, 0);

  const itemSoldRows = (() => {
    const totals = new Map<string, { quantity: number; sales: number }>();
    for (const order of periodOrders) {
      const orderGross = order.items.reduce((sum, line) => sum + line.price * line.qty, 0);
      for (const line of order.items) {
        const name = line.name.trim() || line.productId;
        const current = totals.get(name) ?? { quantity: 0, sales: 0 };
        current.quantity += line.qty;
        current.sales += orderGross > 0 ? order.total * line.price * line.qty / orderGross : 0;
        totals.set(name, current);
      }
    }
    return Array.from(totals, ([name, values]) => ({ name, ...values }))
      .sort((a, b) => b.sales - a.sales);
  })();
  const canEdit = !initialLedgerError;
  const staff = store.users.filter((user) => user.role === "barista" || user.role === "pos_cashier");
  const periodShifts = (store.workShifts ?? []).filter((shift) => shift.date >= period.from && shift.date <= period.to);
  const activeShiftFilter = periodShifts.some((shift) => shift.id === selectedShiftId) ? selectedShiftId : "all";
  const shiftIntervals = periodShifts.map((shift) => ({
    shift,
    interval: workShiftInterval(shift),
  }));
  const orderShiftAssignments = new Map<string, string>();
  for (const order of allLiveOrders) {
    const createdAt = phTimestamp(order.createdAt);
    const matchingShifts = shiftIntervals
      .filter(({ interval }) => createdAt >= interval.start && createdAt < interval.end)
      .sort((left, right) =>
        right.interval.start - left.interval.start ||
        left.shift.id.localeCompare(right.shift.id),
      );
    if (matchingShifts[0]) orderShiftAssignments.set(order.id, matchingShifts[0].shift.id);
  }
  const allShiftReports = periodShifts.map((shift) => {
    const interval = workShiftInterval(shift);
    const shiftOrders = allLiveOrders.filter((order) => orderShiftAssignments.get(order.id) === shift.id);
    const sales = shiftOrders.reduce((sum, order) => sum + order.total, 0);
    const byPayment = { cash: 0, eWallet: 0, card: 0 };
    for (const order of shiftOrders) {
      const method = order.paymentMethod ?? "cash";
      if (method === "cash") byPayment.cash += order.total;
      else if (method === "gcash" || method === "maya") byPayment.eWallet += order.total;
      else if (method.startsWith("split:")) {
        for (const [key, label] of [["cash", "cash"], ["gcash", "eWallet"], ["maya", "eWallet"], ["card", "card"]] as const) {
          const amount = new RegExp("(?:^|,)" + key + "=([0-9.]+)").exec(method)?.[1];
          if (amount) byPayment[label] += Number(amount) || 0;
        }
      }
    }
    const attendanceRows = shift.staffUserIds.flatMap((userId) => {
      const user = staff.find((entry) => entry.id === userId);
      if (!user) return [];
      const hours = calculatePayrollHoursBetween(userId, sessions, interval.start, interval.end);
      return [{
        user,
        status: shiftAttendanceStatus(userId, shift, sessions),
        hours: hours.hours,
        grossPay: calculateGrossPay(user, hours),
      }];
    });
    return {
      shift,
      interval,
      sales,
      byPayment,
      attendanceRows,
      attendanceCounts: attendanceRows.reduce(
        (counts, row) => {
          if (row.status === "Present") counts.present += 1;
          if (row.status === "Absent") counts.absent += 1;
          if (row.status === "Late") counts.late += 1;
          return counts;
        },
        { present: 0, absent: 0, late: 0 },
      ),
      workedHours: attendanceRows.reduce((sum, row) => sum + row.hours, 0),
      grossPayroll: attendanceRows.reduce((sum, row) => sum + row.grossPay, 0),
    };
  });
  const shiftReports = allShiftReports.filter(({ shift }) => activeShiftFilter === "all" || shift.id === activeShiftFilter);
  const todayShiftAttendance = (store.workShifts ?? [])
    .filter((shift) => shift.date === today && (activeShiftFilter === "all" || shift.id === activeShiftFilter))
    .flatMap((shift) => shift.staffUserIds.flatMap((userId) =>
      staff.some((user) => user.id === userId)
        ? [{ userId, status: shiftAttendanceStatus(userId, shift, sessions) }]
        : [],
    ));
  const attendanceByStaff = staff.map((user) => {
    const rows = shiftReports.flatMap((report) => report.attendanceRows.filter((row) => row.user.id === user.id));
    const counts = rows.reduce(
      (value, row) => {
        if (row.status === "Present") value.present += 1;
        if (row.status === "Absent") value.absent += 1;
        if (row.status === "Late") value.late += 1;
        return value;
      },
      { present: 0, absent: 0, late: 0 },
    );
    const todaysRows = todayShiftAttendance.filter((row) => row.userId === user.id);
    const todayStatus = todaysRows.find((row) => row.status !== "Not started")?.status ?? (todaysRows.length ? "Not started" : "Not scheduled");
    return { staff: user, ...counts, todayStatus };
  });
  const todayAttendance = todayShiftAttendance.reduce(
    (counts, row) => {
      if (row.status === "Present") counts.present += 1;
      if (row.status === "Absent") counts.absent += 1;
      if (row.status === "Late") counts.late += 1;
      return counts;
    },
    { present: 0, absent: 0, late: 0 },
  );
  const payrollForStaff = (userId: string) => payrollRecords.find((record) =>
    record.userId === userId && record.periodStart === period.from && record.periodEnd === period.to,
  );

  async function perform(action: () => Promise<void>, success?: string) {
    setPending(true);
    setMessage(null);
    try {
      await action();
      setMessage(success ?? "Saved.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Finance update failed.");
    } finally {
      setPending(false);
    }
  }

  async function viewAttendancePhoto(entry: (typeof attendancePhotoRows)[number]) {
    await perform(async () => {
      const url = await getAttendancePhotoUrl(entry.id);
      setViewingAttendancePhoto({
        url,
        name: entry.name,
        type: entry.type,
        at: entry.at,
      });
    });
  }

  async function addEntry(
    event: FormEvent<HTMLFormElement>,
    kind: AdminLedgerKind,
    data: { title: string; reason: string; amount: string; category: AdminLedgerCategory; counterparty: string; paymentSource: LedgerPaymentSource; date: string; workShiftId: string },
  ) {
    event.preventDefault();
    const amount = Number(data.amount);
    if (!data.title.trim() || !Number.isFinite(amount) || amount <= 0) {
      setMessage("Enter a title and a valid amount greater than zero.");
      return;
    }
    if (kind === "credit" && !data.counterparty.trim()) {
      setMessage("Enter the internal or partner who owes the balance.");
      return;
    }
    await perform(() => createAdminLedgerEntry(kind, data.title, data.reason, amount, {
      category: kind === "expense" ? data.category : "other",
      counterparty: kind === "credit" ? data.counterparty : undefined,
      paymentSource: kind === "expense" ? data.paymentSource : "unassigned",
      date: data.date,
      workShiftId: data.workShiftId || undefined,
    }));
  }

  function updatePayrollDraft(userId: string) {
    const form = document.querySelector<HTMLFormElement>(`form[data-payroll-user="${CSS.escape(userId)}"]`);
    if (!form) return;
    const advance = Number(new FormData(form).get("advance") ?? 0);
    const tardy = Number(new FormData(form).get("tardy") ?? 0);
    if (!Number.isFinite(advance) || advance < 0 || !Number.isFinite(tardy) || tardy < 0) {
      setMessage("Enter valid non-negative payroll deductions.");
      return;
    }

    void perform(() => savePayrollDraft({
      userId,
      periodStart: period.from,
      periodEnd: period.to,
      cashAdvance: advance,
      tardinessDeduction: tardy,
    }), "Payroll saved.");
  }

  function downloadAttendanceCsv() {
    const escapeCsv = (value: string | number) => {
      const text = String(value).replace(/^[\t\r ]*[=+\-@]/, "'$&");
      return `"${text.replaceAll('"', '""')}"`;
    };
    const rows = [
      ["Staff", "Role", "Live status today", "Assigned shifts", "Present", "Absent", "Late", "Shift details"],
      ...attendanceByStaff.map(({ staff: user, todayStatus, present, absent, late }) => [
        user.name,
        user.role === "barista" ? "Barista" : "Cashier",
        todayStatus,
        shiftReports.filter((report) => report.shift.staffUserIds.includes(user.id)).length,
        present,
        absent,
        late,
        shiftReports.filter((report) => report.shift.staffUserIds.includes(user.id))
          .map((report) => `${report.shift.date} ${report.shift.name}: ${report.attendanceRows.find((row) => row.user.id === user.id)?.status ?? "—"}`)
          .join("; "),
      ]),
    ];
    const csv = `\uFEFF${rows.map((row) => row.map(escapeCsv).join(",")).join("\r\n")}`;
    const url = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
    const link = document.createElement("a");
    link.href = url;
    link.download = `attendance-${period.from}-to-${period.to}.csv`;
    link.click();
    URL.revokeObjectURL(url);
  }

  return (
    <main className="mx-auto min-w-0 max-w-[1760px] space-y-6 px-3 py-5 sm:px-6 sm:py-7 xl:px-8 2xl:px-10">
      {remoteHistory && historyLoading ? <p role="status" className="text-sm text-neutral-500">Loading Finance history for {period.from}–{period.to}…</p> : null}
      {remoteHistory && historyError ? <p role="alert" className="text-sm text-red-600">{historyError}</p> : null}
      <header className="flex flex-col gap-4 lg:flex-row lg:items-end lg:justify-between">
        <div>
          <p className="text-xs tracking-[0.3em] text-neutral-500 uppercase">Finance</p>
          <h1 className="mt-2 text-2xl font-semibold sm:text-3xl">Finance, Payroll & Valuation</h1>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          <label className="flex items-center gap-2 rounded-lg border border-neutral-300 bg-white px-3 py-2 text-xs">
            <span className="text-neutral-500">Range</span>
            <select value={rangeType} onChange={(event) => { prepareHistoryReload(); setRangeType(event.target.value as typeof rangeType); }} className="bg-transparent text-sm">
              <option value="today">Today</option>
              <option value="week">This Week</option>
              <option value="month">This Month</option>
              <option value="custom">Custom</option>
            </select>
          </label>
          {rangeType === "custom" ? (
            <>
              <label className="text-xs text-neutral-600">From <input type="date" value={customStart} onChange={(event) => {
                const next = event.target.value;
                setCustomStart(next);
                if (!next || next > customEnd) {
                  setRemoteOrders([]);
                  setRemoteLoginActivity([]);
                  setHistoryLoading(false);
                  setHistoryError(next ? "The start date must be on or before the end date." : "Select a valid start date.");
                } else prepareHistoryReload();
              }} className="rounded border border-neutral-300 bg-white p-2" /></label>
              <label className="text-xs text-neutral-600">To <input type="date" value={customEnd} onChange={(event) => {
                const next = event.target.value;
                setCustomEnd(next);
                if (!next || customStart > next) {
                  setRemoteOrders([]);
                  setRemoteLoginActivity([]);
                  setHistoryLoading(false);
                  setHistoryError(next ? "The end date must be on or after the start date." : "Select a valid end date.");
                } else prepareHistoryReload();
              }} className="rounded border border-neutral-300 bg-white p-2" /></label>
            </>
          ) : null}
        </div>
      </header>

      {message || initialLedgerError || payrollError || store.workShiftError ? <p role="alert" className={`border p-3 text-sm ${initialLedgerError || payrollError || store.workShiftError || message?.toLowerCase().includes("could not") || message?.toLowerCase().includes("unable") ? "border-red-200 bg-red-50 text-red-700" : "border-emerald-200 bg-emerald-50 text-emerald-800"}`}>{message ?? initialLedgerError ?? payrollError ?? store.workShiftError}</p> : null}

      <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <Card label="Gross Sales / Revenue" value={totalRevenue} />
        <Card label="Total Expenses" value={totalExpenses} hint="Includes restocks and released payroll" />
        <Card label="Outstanding Receivables" value={outstandingCredits} />
        <Card label="Net Profit" value={totalRevenue - totalExpenses} hint="Revenue minus expenses" />
      </section>

      <section>
        <div className="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
          <h2 className="text-xs tracking-[0.2em] text-neutral-500 uppercase">Revenue by payment method</h2>
          <div className="mt-3 divide-y divide-slate-100">
            {paymentBreakdown.map((item) => (
              <div key={item.label} className="flex items-center justify-between gap-4 py-2.5 text-sm">
                <div>
                  <p className="font-medium text-slate-800">{item.label}</p>
                  <p className="text-xs text-neutral-500">{item.count} transactions</p>
                </div>
                <p className="shrink-0 font-semibold">{formatMoney(item.amount)}</p>
              </div>
            ))}
            {remoteHistory && !paymentSummary ? (
              <p role={historyLoading ? "status" : "alert"} className="py-3 text-sm text-neutral-500">
                {historyLoading ? "Loading payment breakdown…" : historyError ?? "Payment breakdown unavailable."}
              </p>
            ) : null}
            <div className="flex items-center justify-between gap-4 border-t border-slate-200 pt-3 text-sm font-bold">
              <span>Total Revenue</span>
              <span>{formatMoney(paymentTotal)}</span>
            </div>
          </div>
        </div>
      </section>

      <section className="grid gap-4 xl:grid-cols-2">
        <LedgerCard kind="expense" entries={expenses.filter((entry) => entry.kind === "expense")} total={totalExpenses} canEdit={canEdit} pending={pending} workShifts={store.workShifts ?? []} onAdd={(event, data) => void addEntry(event, "expense", data)} onDelete={(entry) => void perform(() => deleteAdminLedgerEntry(entry.id, "expense"))} onStatusChange={(entry) => void perform(() => setAdminLedgerEntryStatus(entry.id, entry.status === "settled" ? "unpaid" : "settled"))} />
        <LedgerCard kind="credit" entries={credits.filter((entry) => entry.kind === "credit")} total={outstandingCredits} canEdit={canEdit} pending={pending} workShifts={[]} onAdd={(event, data) => void addEntry(event, "credit", data)} onDelete={(entry) => void perform(() => deleteAdminLedgerEntry(entry.id, "credit"))} onStatusChange={(entry) => void perform(() => setAdminLedgerEntryStatus(entry.id, entry.status === "settled" ? "unpaid" : "settled"))} />
      </section>

      <section className="space-y-4 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <div>
          <h2 className="text-xs tracking-[0.2em] text-neutral-500 uppercase">Shift sales & attendance</h2>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[850px] table-fixed text-left text-sm">
            <thead className="border-b border-neutral-100 text-xs text-neutral-500">
              <tr><th className="w-[150px] px-3 py-2">Shift</th><th className="w-[230px] px-3 py-2">Assigned staff / attendance</th><th className="w-[160px] px-3 py-2 text-right">Sales</th><th className="w-[150px] px-3 py-2 text-right">Cash sales</th><th className="w-[190px] px-3 py-2 text-right">Worked hours / gross payroll</th></tr>
            </thead>
            <tbody>
              {shiftReports.map((report) => {
                return (
                  <tr key={report.shift.id} className="border-b border-neutral-50 align-top">
                    <td className="px-3 py-3"><p className="font-semibold">{report.shift.name}</p><p className="text-xs text-neutral-500">{report.shift.date} · {report.shift.startTime}–{report.shift.endTime}</p></td>
                    <td className="px-3 py-3">
                      {report.attendanceRows.length === 0 ? <span className="text-xs text-neutral-400">No active staff assigned</span> : report.attendanceRows.map((row) => (
                        <p key={row.user.id} className="text-xs"><span className="font-medium">{row.user.name}</span><span className="ml-2 text-slate-500">{row.status}</span></p>
                      ))}
                    </td>
                    <td className="px-3 py-3 text-right font-medium">{formatMoney(report.sales)}<span className="block text-[11px] text-neutral-400">e-wallet/card {formatMoney(report.byPayment.eWallet + report.byPayment.card)}</span></td>
                    <td className="px-3 py-3 text-right">{formatMoney(report.byPayment.cash)}</td>
                    <td className="whitespace-nowrap px-3 py-3 text-right">{report.workedHours.toFixed(2)} hrs<span className="block text-xs text-neutral-500">{formatMoney(report.grossPayroll)}</span></td>
                  </tr>
                );
              })}
              {shiftReports.length === 0 ? <tr><td colSpan={5} className="py-6 text-center text-xs text-neutral-400">No assigned shifts in this date range.</td></tr> : null}
            </tbody>
          </table>
        </div>
      </section>

      <section className="space-y-4 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 className="text-xs tracking-[0.2em] text-neutral-500 uppercase">Live staff attendance</h2>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <label className="flex items-center gap-2 rounded-lg border border-neutral-300 bg-white px-3 py-2 text-xs">
              <span className="text-neutral-500">Shift</span>
              <select value={activeShiftFilter} onChange={(event) => setSelectedShiftId(event.target.value)} className="max-w-64 bg-transparent text-sm">
                <option value="all">All shifts</option>
                {periodShifts.map((shift) => <option key={shift.id} value={shift.id}>{shift.date} · {shift.name}</option>)}
              </select>
            </label>
            <button type="button" onClick={downloadAttendanceCsv} disabled={attendanceByStaff.length === 0} className="rounded-lg border border-slate-300 px-3 py-2 text-sm font-medium text-slate-700 disabled:opacity-40">Download CSV</button>
          </div>
        </div>
        <div className="grid gap-2 sm:grid-cols-3">
          <div className="rounded-xl bg-emerald-50 p-3"><p className="text-xs text-emerald-800">Present today</p><p className="mt-1 text-xl font-semibold text-emerald-900">{todayAttendance.present}</p></div>
          <div className="rounded-xl bg-amber-50 p-3"><p className="text-xs text-amber-800">Late today</p><p className="mt-1 text-xl font-semibold text-amber-900">{todayAttendance.late}</p></div>
          <div className="rounded-xl bg-red-50 p-3"><p className="text-xs text-red-800">Absent today</p><p className="mt-1 text-xl font-semibold text-red-900">{todayAttendance.absent}</p></div>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full min-w-[700px] text-left text-sm">
            <thead className="border-b border-neutral-100 text-xs text-neutral-500"><tr><th className="py-2">Staff</th><th className="py-2">Today</th><th className="py-2 text-right">Present</th><th className="py-2 text-right">Absent</th><th className="py-2 text-right">Late</th></tr></thead>
            <tbody>{attendanceByStaff.map(({ staff: user, todayStatus, present, absent, late }) => (
              <tr key={user.id} className="border-b border-neutral-50">
                <td className="py-2"><span className="font-medium">{user.name}</span><span className="ml-2 text-xs text-neutral-500">{user.role === "barista" ? "Barista" : "Cashier"}</span></td>
                <td className="py-2">
                  <span className="inline-flex items-center gap-2">
                    <span
                      aria-hidden="true"
                      className={`size-2.5 rounded-full ${
                        todayStatus === "Present" || todayStatus === "Late"
                          ? "bg-emerald-500"
                          : todayStatus === "Absent"
                            ? "bg-red-500"
                            : "bg-neutral-400"
                      }`}
                    />
                    {todayStatus}
                  </span>
                </td>
                <td className="py-2 text-right">{present}</td>
                <td className="py-2 text-right">{absent}</td>
                <td className="py-2 text-right">{late}</td>
              </tr>
            ))}{attendanceByStaff.length === 0 ? <tr><td colSpan={5} className="py-5 text-center text-xs text-neutral-400">No attendance staff profiles found.</td></tr> : null}</tbody>
          </table>
        </div>
        <div className="border-t border-slate-100 pt-4">
          <div className="mb-3">
            <h3 className="text-xs font-semibold tracking-[0.15em] text-neutral-600 uppercase">Attendance photo log</h3>
          </div>
          {attendancePhotos.length === 0 ? (
            <p className="rounded-lg bg-slate-50 px-3 py-4 text-center text-xs text-neutral-500">No attendance photos recorded yet.</p>
          ) : (
            <>
              <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                {attendancePhotoRows.map((entry) => (
                  <div key={entry.id} className="flex items-center justify-between gap-3 rounded-lg border border-slate-200 p-3">
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium text-slate-800">{entry.name}</p>
                      <p className="text-xs text-slate-500">{attendanceEventLabel(entry.type)} · {phDateTimeLabel(entry.at)}</p>
                    </div>
                    <button
                      type="button"
                      disabled={pending}
                      onClick={() => void viewAttendancePhoto(entry)}
                      className="shrink-0 rounded-lg border border-slate-300 px-3 py-2 text-xs font-medium text-slate-700 disabled:opacity-40"
                    >
                      View photo
                    </button>
                  </div>
                ))}
              </div>
              <div className="mt-3 flex items-center justify-between text-xs text-neutral-500">
                <span>Showing {safeAttendancePhotoPage * 20 + 1}–{Math.min((safeAttendancePhotoPage + 1) * 20, attendancePhotos.length)} of {attendancePhotos.length}</span>
                <div className="flex gap-2">
                  <button
                    type="button"
                    disabled={safeAttendancePhotoPage === 0}
                    onClick={() => setAttendancePhotoPage((page) => Math.max(0, page - 1))}
                    className="rounded border border-slate-300 px-3 py-1.5 disabled:opacity-40"
                  >
                    Newer
                  </button>
                  <button
                    type="button"
                    disabled={safeAttendancePhotoPage >= attendancePhotoPageCount - 1}
                    onClick={() => setAttendancePhotoPage((page) => Math.min(attendancePhotoPageCount - 1, page + 1))}
                    className="rounded border border-slate-300 px-3 py-1.5 disabled:opacity-40"
                  >
                    Older
                  </button>
                </div>
              </div>
            </>
          )}
        </div>
      </section>


      <section className="space-y-4 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:p-5">
        <div className="overflow-x-auto"><table className="w-full min-w-[420px] text-left text-sm"><thead className="border-b border-neutral-100 text-xs text-neutral-500"><tr><th className="py-2">Item sold</th><th className="py-2 text-right">Qty</th><th className="py-2 text-right">Sales</th></tr></thead><tbody>{itemSoldRows.length === 0 ? <tr><td colSpan={3} className="py-5 text-center text-xs text-neutral-400">No sales in this range.</td></tr> : itemSoldRows.map((row) => <tr key={row.name} className="border-b border-neutral-50 text-xs"><td className="py-2 font-medium">{row.name}</td><td className="py-2 text-right">{row.quantity}</td><td className="py-2 text-right">{formatMoney(row.sales)}</td></tr>)}</tbody></table></div>
      </section>
      {viewingAttendancePhoto ? (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-slate-950/70 p-4"
          role="dialog"
          aria-modal="true"
          aria-label={`${attendanceEventLabel(viewingAttendancePhoto.type)} photo for ${viewingAttendancePhoto.name}`}
          onClick={() => setViewingAttendancePhoto(null)}
        >
          <div className="w-full max-w-xl rounded-2xl bg-white p-4 shadow-2xl" onClick={(event) => event.stopPropagation()}>
            <div className="mb-3 flex items-start justify-between gap-3">
              <div>
                <p className="font-semibold text-slate-900">{viewingAttendancePhoto.name} · {attendanceEventLabel(viewingAttendancePhoto.type)}</p>
                <p className="text-xs text-slate-500">{phDateTimeLabel(viewingAttendancePhoto.at)}</p>
              </div>
              <button type="button" onClick={() => setViewingAttendancePhoto(null)} className="rounded-lg border border-slate-300 px-3 py-1.5 text-sm">Close</button>
            </div>
            <img src={viewingAttendancePhoto.url} alt={`Attendance photo for ${viewingAttendancePhoto.name}`} loading="lazy" decoding="async" className="max-h-[70vh] w-full rounded-xl bg-slate-100 object-contain" />
          </div>
        </div>
      ) : null}
    </main>
  );
}
