"use server";

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/auth";
import { phTimestamp } from "@/lib/datetime";
import { workShiftInterval } from "@/lib/shift-reports";
import {
  closeWorkShiftRecord,
  createWorkShiftRecord,
  deleteWorkShiftRecord,
  getAdminLedgerEntries,
  getFreshStore,
} from "@/lib/store";
import { pairLoginSessions } from "@/lib/staff-sessions";
import type { WorkShift } from "@/lib/types";

async function requireOwner() {
  const session = await getSession();
  if (!session || (session.role !== "admin" && session.role !== "cashier")) {
    throw new Error("Only the Owner or admin can manage work shifts.");
  }
  return session;
}

function validDate(value: string) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value) &&
    Number.isFinite(Date.parse(`${value}T12:00:00+08:00`)) &&
    new Date(`${value}T12:00:00+08:00`).toISOString().startsWith(value);
}

export async function createWorkShift(input: {
  name: string;
  date: string;
  startTime: string;
  endTime: string;
  openingFloat: number;
  staffUserIds: string[];
}): Promise<void> {
  const session = await requireOwner();
  if (!input || typeof input.name !== "string" || !Array.isArray(input.staffUserIds)) {
    throw new Error("Enter valid shift details.");
  }
  const name = input.name.trim();
  const staffUserIds = [...new Set(input.staffUserIds.filter((id) => typeof id === "string" && id.trim()).map((id) => id.trim()))];
  if (
    !name ||
    name.length > 50 ||
    !validDate(input.date) ||
    !/^([01]\d|2[0-3]):[0-5]\d$/.test(input.startTime) ||
    !/^([01]\d|2[0-3]):[0-5]\d$/.test(input.endTime) ||
    input.startTime === input.endTime ||
    !Number.isFinite(input.openingFloat) ||
    input.openingFloat < 0 ||
    input.openingFloat > 9_999_999_999.99 ||
    staffUserIds.length === 0
  ) {
    throw new Error("Enter a shift name, date, different start and end times, non-negative opening float, and at least one staff member.");
  }

  const store = await getFreshStore();
  if (store.workShiftError) throw new Error(store.workShiftError);
  const validStaffIds = new Set(store.users
    .filter((user) => user.role === "barista" || user.role === "pos_cashier")
    .map((user) => user.id));
  if (staffUserIds.some((id) => !validStaffIds.has(id))) {
    throw new Error("Only active Barista and Cashier staff can be assigned to a shift.");
  }

  const shift: WorkShift = {
    id: randomUUID(),
    name,
    date: input.date,
    startTime: input.startTime,
    endTime: input.endTime,
    openingFloat: Math.round(input.openingFloat * 100) / 100,
    staffUserIds,
    createdAt: new Date().toISOString(),
  };
  const interval = workShiftInterval(shift);
  if (!Number.isFinite(interval.start) || !Number.isFinite(interval.end)) {
    throw new Error("The selected date or shift hours are invalid.");
  }
  const overlapsExistingShift = store.workShifts.some((existing) => {
    const other = workShiftInterval(existing);
    return interval.start < other.end && other.start < interval.end;
  });
  if (overlapsExistingShift) {
    throw new Error("Shift hours cannot overlap another scheduled shift. This keeps sales and cash totals assigned to exactly one shift.");
  }

  await createWorkShiftRecord(shift, session.userId);
  revalidatePath("/owner");
}

export async function deleteWorkShift(shiftId: string): Promise<void> {
  await requireOwner();
  const store = await getFreshStore();
  if (store.workShiftError) throw new Error(store.workShiftError);
  const shift = store.workShifts.find((entry) => entry.id === shiftId);
  if (!shift) throw new Error("Shift was not found.");
  if (shift.closedAt) throw new Error("A shift with a closing report cannot be deleted.");
  const ledger = await getAdminLedgerEntries();
  if (ledger.error) throw new Error(ledger.error);
  if (ledger.expenses.some((entry) => entry.workShiftId === shiftId)) {
    throw new Error("This shift has cash expenses assigned and cannot be deleted.");
  }

  const interval = workShiftInterval(shift);
  const assignedIds = new Set(shift.staffUserIds);
  const hasAttendance = pairLoginSessions(store.loginActivity ?? []).some((entry) => {
    if (!assignedIds.has(entry.userId) || !entry.loginAt) return false;
    const login = phTimestamp(entry.loginAt);
    const logout = entry.logoutAt ? phTimestamp(entry.logoutAt) : Date.now();
    return login < interval.end && logout > interval.start;
  });
  if (hasAttendance) throw new Error("This shift has attendance records and cannot be deleted.");

  await deleteWorkShiftRecord(shift.id);
  revalidatePath("/owner");
}

export async function closeWorkShift(shiftId: string, closingCash: number): Promise<void> {
  const session = await requireOwner();
  if (!shiftId || !Number.isFinite(closingCash) || closingCash < 0 || closingCash > 9_999_999_999.99) {
    throw new Error("Enter the actual non-negative closing cash count.");
  }
  const store = await getFreshStore();
  if (store.workShiftError) throw new Error(store.workShiftError);
  const shift = store.workShifts.find((entry) => entry.id === shiftId);
  if (!shift) throw new Error("Shift was not found.");
  if (shift.closedAt) throw new Error("This shift already has a closing report.");
  const { start } = workShiftInterval(shift);
  if (Date.now() < start) throw new Error("A shift cannot be closed before its scheduled start.");

  await closeWorkShiftRecord(shift.id, Math.round(closingCash * 100) / 100, session.userId);
  revalidatePath("/owner");
}
