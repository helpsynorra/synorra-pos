import { phDateString, phTimestamp } from "@/lib/datetime";
import type { LoginActivity, StaffUser } from "@/lib/types";

export type AttendanceCounts = {
  staff: Pick<StaffUser, "id" | "name" | "role">;
  present: number;
  absent: number;
  late: number;
  todayStatus: "Present" | "Absent" | "Late" | "Not scheduled" | "Not started";
};

function dateAfter(date: string): string {
  const [year, month, day] = date.split("-").map(Number);
  const next = new Date(Date.UTC(year, month - 1, day + 1));
  return next.toISOString().slice(0, 10);
}

function isoWeekday(date: string): number {
  const [year, month, day] = date.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, day)).getUTCDay() || 7;
}

function firstLoginByStaffAndDay(records: LoginActivity[]): Map<string, number> {
  const firstLogin = new Map<string, number>();
  for (const record of records) {
    if (record.type !== "login") continue;
    const date = phDateString(record.at);
    const timestamp = phTimestamp(record.at);
    if (!timestamp) continue;
    const key = `${record.userId}\u0000${date}`;
    const previous = firstLogin.get(key);
    if (previous === undefined || timestamp < previous) firstLogin.set(key, timestamp);
  }
  return firstLogin;
}

function shiftStart(date: string, startTime: string): number {
  return phTimestamp(`${date}T${startTime}:00+08:00`);
}

export function attendanceCountsForRange({
  staff,
  records,
  from,
  to,
  workdays,
  startTime,
  now = new Date(),
}: {
  staff: Pick<StaffUser, "id" | "name" | "role">[];
  records: LoginActivity[];
  from: string;
  to: string;
  workdays: number[];
  startTime: string;
  now?: Date;
}): AttendanceCounts[] {
  const today = phDateString(now);
  const nowTimestamp = now.getTime();
  const firstLogins = firstLoginByStaffAndDay(records);
  const scheduledDays = new Set(workdays);
  const counts = new Map(staff.map((user) => [
    user.id,
    { staff: user, present: 0, absent: 0, late: 0, todayStatus: "Not scheduled" as AttendanceCounts["todayStatus"] },
  ]));

  for (let date = from; date <= to && date <= today; date = dateAfter(date)) {
    const scheduled = scheduledDays.has(isoWeekday(date));
    const expectedStart = shiftStart(date, startTime);
    const attendanceDue = date < today || nowTimestamp >= expectedStart;
    for (const entry of counts.values()) {
      const loginAt = firstLogins.get(`${entry.staff.id}\u0000${date}`) ?? null;
      if (!scheduled || !attendanceDue) continue;
      if (loginAt === null) entry.absent += 1;
      else if (loginAt > expectedStart) entry.late += 1;
      else entry.present += 1;
    }
  }

  for (const entry of counts.values()) {
    if (!scheduledDays.has(isoWeekday(today))) {
      entry.todayStatus = "Not scheduled";
      continue;
    }
    const expectedStart = shiftStart(today, startTime);
    if (nowTimestamp < expectedStart) {
      entry.todayStatus = "Not started";
      continue;
    }
    const loginAt = firstLogins.get(`${entry.staff.id}\u0000${today}`) ?? null;
    entry.todayStatus = loginAt === null
      ? "Absent"
      : loginAt > expectedStart ? "Late" : "Present";
  }
  return Array.from(counts.values()).sort((a, b) => a.staff.name.localeCompare(b.staff.name));
}
