import type { WorkShift } from "@/lib/types";
import type { StaffSession } from "@/lib/staff-sessions";
import { phTimestamp } from "@/lib/datetime";

export type ShiftAttendanceStatus = "Present" | "Late" | "Absent" | "Not started";

export function workShiftInterval(shift: Pick<WorkShift, "date" | "startTime" | "endTime">) {
  const start = phTimestamp(`${shift.date}T${shift.startTime}:00+08:00`);
  let end = phTimestamp(`${shift.date}T${shift.endTime}:00+08:00`);
  if (end <= start) end += 24 * 60 * 60 * 1000;
  return { start, end };
}

export function shiftAttendanceStatus(
  userId: string,
  shift: WorkShift,
  sessions: StaffSession[],
  now = Date.now(),
): ShiftAttendanceStatus {
  const { start, end } = workShiftInterval(shift);
  if (now < start) return "Not started";

  const assignedSessions = sessions.filter((session) => session.userId === userId && session.loginAt);
  const presentAtStart = assignedSessions.some((session) => {
    const login = phTimestamp(session.loginAt!);
    const logout = session.logoutAt ? phTimestamp(session.logoutAt) : now;
    return login <= start && logout >= start;
  });
  if (presentAtStart) return "Present";

  const lateLogin = assignedSessions.some((session) => {
    const login = phTimestamp(session.loginAt!);
    const logout = session.logoutAt ? phTimestamp(session.logoutAt) : now;
    return login > start && login < end && logout > login;
  });
  if (lateLogin) return "Late";
  return "Absent";
}
