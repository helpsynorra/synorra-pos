"use server";

import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/auth";
import { phDateString, phTimestamp } from "@/lib/datetime";
import { calculateGrossPay, calculatePayrollHours } from "@/lib/payroll";
import { pairLoginSessions } from "@/lib/staff-sessions";
import { workShiftInterval } from "@/lib/shift-reports";
import {
  deleteAdminLedgerEntryRecord,
  getAdminLedgerEntries,
  getFreshStore,
  getPayrollRecords,
  importAdminLedgerEntries,
  insertAdminLedgerEntryRecord,
  savePayrollRecord,
  setAdminLedgerEntryStatusRecord,
  updateStore,
} from "@/lib/store";
import type { AdminLedgerCategory, AdminLedgerEntry, AdminLedgerKind, LedgerPaymentSource, PayrollRecord } from "@/lib/types";

async function requireAdmin() {
  const session = await getSession();
  if (!session || (session.role !== "admin" && session.role !== "cashier")) {
    throw new Error("Only an Owner or admin can manage finance entries.");
  }
}

function validateEntry(entry: AdminLedgerEntry): AdminLedgerEntry {
  const categories: AdminLedgerCategory[] = ["supplies", "utilities", "petty_cash", "restock", "payroll", "other"];
  const paymentSources: LedgerPaymentSource[] = ["cash", "non_cash", "unassigned"];
  const dateIsValid =
    typeof entry?.date === "string" &&
    /^\d{4}-\d{2}-\d{2}$/.test(entry.date) &&
    !Number.isNaN(Date.parse(`${entry.date}T00:00:00Z`)) &&
    new Date(`${entry.date}T00:00:00Z`).toISOString().slice(0, 10) === entry.date;
  if (
    !entry ||
    typeof entry.id !== "string" ||
    entry.id.length === 0 ||
    entry.id.length > 100 ||
    (entry.kind !== "expense" && entry.kind !== "credit") ||
    typeof entry.title !== "string" ||
    entry.title.trim().length === 0 ||
    entry.title.trim().length > 120 ||
    typeof entry.reason !== "string" ||
    entry.reason.length > 500 ||
    (entry.category !== undefined && !categories.includes(entry.category)) ||
    (entry.paymentSource !== undefined && !paymentSources.includes(entry.paymentSource)) ||
    (entry.counterparty !== undefined && (typeof entry.counterparty !== "string" || entry.counterparty.length > 120)) ||
    !Number.isFinite(entry.amount) ||
    entry.amount < 0.01 ||
    entry.amount > 9_999_999_999.99 ||
    !dateIsValid
  ) {
    throw new Error("Invalid ledger entry.");
  }
  return {
    ...entry,
    title: entry.title.trim(),
    reason: entry.reason.trim(),
    amount: Math.round(entry.amount * 100) / 100,
    category: entry.category ?? "other",
    paymentSource: entry.paymentSource ?? "unassigned",
    counterparty: entry.counterparty?.trim() || undefined,
  };
}

export async function createAdminLedgerEntry(
  kind: AdminLedgerKind,
  title: string,
  reason: string,
  amount: number,
  details: {
    category?: AdminLedgerCategory;
    counterparty?: string;
    paymentSource?: LedgerPaymentSource;
    date?: string;
    workShiftId?: string;
  } = {},
): Promise<void> {
  await requireAdmin();
  if (details.workShiftId) {
    const store = await getFreshStore();
    const shift = store.workShifts.find((entry) => entry.id === details.workShiftId);
    const entryDate = details.date ?? phDateString();
    const dayStart = validPeriod(entryDate, entryDate) ? phTimestamp(`${entryDate}T00:00:00+08:00`) : 0;
    const shiftInterval = shift ? workShiftInterval(shift) : null;
    if (
      kind !== "expense" ||
      details.paymentSource !== "cash" ||
      !shift ||
      Boolean(shift.closedAt) ||
      !shiftInterval ||
      !dayStart ||
      shiftInterval.start >= dayStart + 24 * 60 * 60 * 1000 ||
      shiftInterval.end <= dayStart
    ) {
      throw new Error("Select a scheduled shift that overlaps this date for the cash expense.");
    }
  }
  const entry = validateEntry({
    id: crypto.randomUUID(),
    kind,
    title,
    reason,
    amount,
    date: details.date ?? phDateString(),
    category: details.category ?? "other",
    counterparty: details.counterparty?.trim() || undefined,
    paymentSource: details.paymentSource ?? "unassigned",
    workShiftId: details.workShiftId,
    status: kind === "credit" ? "unpaid" : "settled",
  });
  await insertAdminLedgerEntryRecord(entry);
  revalidatePath("/owner");
}

export async function setAdminLedgerEntryStatus(
  id: string,
  status: "unpaid" | "settled",
): Promise<void> {
  await requireAdmin();
  if (!id || id.length > 150) throw new Error("Invalid Finance entry.");
  await setAdminLedgerEntryStatusRecord(id, "credit", status);
  revalidatePath("/owner");
}

export async function setCashDrawerOpeningFloat(amount: number): Promise<void> {
  await requireAdmin();
  if (!Number.isFinite(amount) || amount < 0 || amount > 9_999_999_999.99) {
    throw new Error("Enter a valid opening cash float.");
  }
  await updateStore((store) => {
    store.pos.cashDrawerOpeningFloat = Math.round(amount * 100) / 100;
  });
  revalidatePath("/owner");
}

function validPeriod(start: string, end: string) {
  const valid = (value: string) =>
    /^\d{4}-\d{2}-\d{2}$/.test(value) &&
    !Number.isNaN(Date.parse(`${value}T00:00:00Z`)) &&
    new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value;
  return valid(start) && valid(end) && start <= end;
}

export async function savePayrollDraft(input: {
  userId: string;
  periodStart: string;
  periodEnd: string;
  cashAdvance: number;
  tardinessDeduction: number;
}): Promise<void> {
  await requireAdmin();
  if (!input.userId || input.userId.length > 150 || !validPeriod(input.periodStart, input.periodEnd)) {
    throw new Error("Select a staff member and a valid payroll date range.");
  }
  for (const amount of [input.cashAdvance, input.tardinessDeduction]) {
    if (!Number.isFinite(amount) || amount < 0 || amount > 9_999_999_999.99) {
      throw new Error("Enter valid non-negative deductions.");
    }
  }

  const [store, payrollResult] = await Promise.all([getFreshStore(), getPayrollRecords()]);
  if (payrollResult.error) throw new Error(payrollResult.error);
  const staff = store.users.find(
    (user) => user.id === input.userId && (user.role === "barista" || user.role === "pos_cashier"),
  );
  if (!staff) throw new Error("Staff member was not found.");
  const existing = payrollResult.records.find((record) =>
    record.userId === input.userId &&
    record.periodStart === input.periodStart &&
    record.periodEnd === input.periodEnd,
  );
  if (existing?.status === "paid") throw new Error("This payroll has already been paid.");

  const sessions = pairLoginSessions(store.loginActivity);
  const hours = calculatePayrollHours(
    staff.id,
    sessions,
    input.periodStart,
    input.periodEnd,
  );
  const grossPay = calculateGrossPay(staff, hours);
  const netPay = Math.max(0, grossPay - input.cashAdvance - input.tardinessDeduction);
  const record: PayrollRecord = {
    id: existing?.id ?? `payroll-${crypto.randomUUID()}`,
    userId: staff.id,
    staffName: staff.name,
    periodStart: input.periodStart,
    periodEnd: input.periodEnd,
    hours: Math.round(hours.hours * 100) / 100,
    grossPay,
    cashAdvance: Math.round(input.cashAdvance * 100) / 100,
    tardinessDeduction: Math.round(input.tardinessDeduction * 100) / 100,
    netPay: Math.round(netPay * 100) / 100,
    status: "unpaid",
  };
  await savePayrollRecord(record);
  revalidatePath("/owner");
}

export async function releasePayroll(recordId: string): Promise<void> {
  await requireAdmin();
  if (!recordId || recordId.length > 200) throw new Error("Invalid payroll record.");
  const payrollResult = await getPayrollRecords();
  if (payrollResult.error) throw new Error(payrollResult.error);
  const record = payrollResult.records.find((entry) => entry.id === recordId);
  if (!record) throw new Error("Payroll record was not found.");
  if (record.status === "paid") return;

  const relatedRecordId = `payroll:${record.id}`;
  const ledger = await getAdminLedgerEntries();
  if (ledger.error) throw new Error(ledger.error);
  const existingExpense = ledger.expenses.find((entry) => entry.relatedRecordId === relatedRecordId);
  const payoutLedgerId = existingExpense?.id ?? `payroll-expense-${record.id}`;
  if (!existingExpense && record.netPay > 0) {
    try {
      await insertAdminLedgerEntryRecord({
        id: payoutLedgerId,
        kind: "expense",
        title: `Payroll: ${record.staffName}`,
        reason: `Salary for ${record.periodStart} to ${record.periodEnd}`,
        amount: record.netPay,
        category: "payroll",
        paymentSource: "cash",
        relatedRecordId,
        status: "settled",
      });
    } catch (error) {
      const refreshed = await getAdminLedgerEntries();
      if (!refreshed.expenses.some((entry) => entry.relatedRecordId === relatedRecordId)) {
        throw error;
      }
    }
  }
  await savePayrollRecord({
    ...record,
    status: "paid",
    payoutLedgerId: record.netPay > 0 ? payoutLedgerId : undefined,
    paidAt: new Date().toISOString(),
  });
  revalidatePath("/owner");
}

export async function deleteAdminLedgerEntry(
  id: string,
  kind: AdminLedgerKind,
): Promise<void> {
  await requireAdmin();
  if (!id || id.length > 100 || (kind !== "expense" && kind !== "credit")) {
    throw new Error("Invalid ledger entry.");
  }
  if (kind === "expense") {
    const [ledger, store] = await Promise.all([getAdminLedgerEntries(), getFreshStore()]);
    if (ledger.error) throw new Error(ledger.error);
    const entry = ledger.expenses.find((row) => row.id === id);
    if (entry?.workShiftId && store.workShifts.some((shift) => shift.id === entry.workShiftId && shift.closedAt)) {
      throw new Error("A cash expense assigned to a closed shift cannot be deleted.");
    }
  }
  await deleteAdminLedgerEntryRecord(id, kind);
  revalidatePath("/owner");
}

export async function importLegacyAdminLedgerEntries(
  untrustedEntries: AdminLedgerEntry[],
): Promise<void> {
  await requireAdmin();
  if (!Array.isArray(untrustedEntries)) {
    throw new Error("Invalid legacy ledger data.");
  }
  const entries = untrustedEntries.map(validateEntry);
  await importAdminLedgerEntries(entries);
  revalidatePath("/owner");
}
