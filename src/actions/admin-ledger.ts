"use server";

import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/auth";
import { phDateString } from "@/lib/datetime";
import {
  deleteAdminLedgerEntryRecord,
  importAdminLedgerEntries,
  insertAdminLedgerEntryRecord,
} from "@/lib/store";
import type { AdminLedgerEntry, AdminLedgerKind } from "@/lib/types";

async function requireAdmin() {
  const session = await getSession();
  if (!session || session.role !== "admin") {
    throw new Error("Only an admin can manage sales ledger entries.");
  }
}

function validateEntry(entry: AdminLedgerEntry): AdminLedgerEntry {
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
  };
}

export async function createAdminLedgerEntry(
  kind: AdminLedgerKind,
  title: string,
  reason: string,
  amount: number,
): Promise<void> {
  await requireAdmin();
  const entry = validateEntry({
    id: crypto.randomUUID(),
    kind,
    title,
    reason,
    amount,
    date: phDateString(),
  });
  await insertAdminLedgerEntryRecord(entry);
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
