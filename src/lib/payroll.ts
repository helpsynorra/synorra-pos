import type { StaffUser } from "@/lib/types";
import type { StaffSession } from "@/lib/staff-sessions";
import { phTimestamp } from "@/lib/datetime";

export function calculatePayrollHours(
  staffId: string,
  sessions: StaffSession[],
  periodStart: string,
  periodEnd: string,
  now = Date.now(),
) {
  const start = phTimestamp(`${periodStart}T00:00:00+08:00`);
  const end = Math.min(phTimestamp(`${periodEnd}T23:59:59.999+08:00`), now);
  let hours = 0;
  let regularHours = 0;
  let overtimeHours = 0;

  for (const session of sessions) {
    if (session.userId !== staffId || !session.loginAt) continue;
    const login = phTimestamp(session.loginAt);
    const logout = session.logoutAt ? phTimestamp(session.logoutAt) : now;
    const overlapStart = Math.max(login, start);
    const overlapEnd = Math.min(logout, end);
    const duration = Math.max(0, overlapEnd - overlapStart) / 3_600_000;
    if (duration <= 0) continue;
    hours += duration;
    const shiftHoursBeforePeriod = Math.max(0, overlapStart - login) / 3_600_000;
    const regularInOverlap = Math.max(0, Math.min(duration, 8 - shiftHoursBeforePeriod));
    regularHours += regularInOverlap;
    overtimeHours += duration - regularInOverlap;
  }
  return { hours, regularHours, overtimeHours };
}

export function calculatePayrollHoursBetween(
  staffId: string,
  sessions: StaffSession[],
  start: number,
  end: number,
  now = Date.now(),
) {
  const boundedEnd = Math.min(end, now);
  let hours = 0;
  let regularHours = 0;
  let overtimeHours = 0;

  for (const session of sessions) {
    if (session.userId !== staffId || !session.loginAt) continue;
    const login = phTimestamp(session.loginAt);
    const logout = session.logoutAt ? phTimestamp(session.logoutAt) : now;
    const overlapStart = Math.max(login, start);
    const overlapEnd = Math.min(logout, boundedEnd);
    const duration = Math.max(0, overlapEnd - overlapStart) / 3_600_000;
    if (duration <= 0) continue;
    hours += duration;
    const hoursBeforeRange = Math.max(0, overlapStart - login) / 3_600_000;
    const regularInRange = Math.max(0, Math.min(duration, 8 - hoursBeforeRange));
    regularHours += regularInRange;
    overtimeHours += duration - regularInRange;
  }
  return { hours, regularHours, overtimeHours };
}

export function calculateGrossPay(
  staff: Pick<StaffUser, "hourlyRate" | "dailyRate" | "overtimeRate">,
  hours: { regularHours: number; overtimeHours: number },
) {
  const hourlyRate = staff.hourlyRate ?? (staff.dailyRate ?? 0) / 8;
  const overtimeRate = staff.overtimeRate ?? 1.5;
  return Math.round(
    (hours.regularHours * hourlyRate +
      hours.overtimeHours * hourlyRate * overtimeRate) * 100,
  ) / 100;
}
