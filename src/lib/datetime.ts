const PH_TZ = "Asia/Manila";

function dateFromValue(value: string | Date): Date {
  if (value instanceof Date) return value;

  const trimmed = value.trim();
  const localDateTime = /^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?)$/;
  if (localDateTime.test(trimmed)) {
    return new Date(`${trimmed.replace(" ", "T")}+08:00`);
  }

  return new Date(trimmed);
}

function partsOf(date: Date) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: PH_TZ,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  }).formatToParts(date);
  const pick = (type: Intl.DateTimeFormatPartTypes) =>
    parts.find((part) => part.type === type)?.value ?? "00";
  return {
    year: pick("year"),
    month: pick("month"),
    day: pick("day"),
    hour: pick("hour") === "24" ? "00" : pick("hour"),
    minute: pick("minute"),
    second: pick("second"),
  };
}

export function phDateString(value: string | Date = new Date()): string {
  if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value.trim())) {
    return value.trim();
  }

  const date = dateFromValue(value);
  if (Number.isNaN(date.getTime())) {
    const match = String(value).match(/^(\d{4}-\d{2}-\d{2})/);
    return match?.[1] ?? "";
  }

  const { year, month, day } = partsOf(date);
  return `${year}-${month}-${day}`;
}

export function phDateTimeLabel(value: string | Date): string {
  if (typeof value === "string" && /^\d{4}-\d{2}-\d{2}$/.test(value.trim())) {
    const date = new Date(`${value.trim()}T12:00:00+08:00`);
    return new Intl.DateTimeFormat("en-US", {
      timeZone: PH_TZ,
      month: "short",
      day: "numeric",
      year: "numeric",
    }).format(date);
  }

  const date = dateFromValue(value);
  if (Number.isNaN(date.getTime())) {
    return phDateString(value);
  }

  return new Intl.DateTimeFormat("en-US", {
    timeZone: PH_TZ,
    month: "short",
    day: "numeric",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  }).format(date);
}

export function phDateTimeInputValue(value: string | Date): string {
  const date = dateFromValue(value);
  if (Number.isNaN(date.getTime())) return "";

  const { year, month, day, hour, minute } = partsOf(date);
  return `${year}-${month}-${day}T${hour}:${minute}`;
}

export function phIsoFromDateTimeInput(value: string): string {
  const input = value.trim();
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(input)) return "";

  const date = new Date(`${input}:00+08:00`);
  if (Number.isNaN(date.getTime()) || phDateTimeInputValue(date) !== input) {
    return "";
  }

  return date.toISOString();
}

export function phNowDateTime(value: Date = new Date()): string {
  const { year, month, day, hour, minute, second } = partsOf(value);
  return `${year}-${month}-${day} ${hour}:${minute}:${second}`;
}

export function phIsoFromDate(dateStr: string, previousIso?: string): string {
  if (previousIso && phDateString(previousIso) === dateStr) {
    return previousIso;
  }

  const today = phDateString();
  const time = dateStr === today ? phNowDateTime().slice(11) : "12:00:00";
  return `${dateStr}T${time}+08:00`;
}

export function previousPhDate(dateStr: string): string {
  const date = new Date(`${dateStr}T12:00:00+08:00`);
  date.setTime(date.getTime() - 24 * 60 * 60 * 1000);
  return phDateString(date);
}

export function phTimestamp(value: string | Date): number {
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? 0 : value.getTime();
  }

  const trimmed = String(value).trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
    return new Date(`${trimmed}T12:00:00+08:00`).getTime();
  }
  if (/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(trimmed)) {
    return new Date(`${trimmed.replace(" ", "T")}+08:00`).getTime();
  }

  const date = dateFromValue(trimmed);
  return Number.isNaN(date.getTime()) ? 0 : date.getTime();
}

export function phIsoTimestamp(value: string | Date): string {
  const timestamp = phTimestamp(value);
  return timestamp ? new Date(timestamp).toISOString() : "";
}

export type PeriodRange =
  | "today"
  | "week"
  | "lastWeek"
  | "month"
  | "lastMonth"
  | "thisYear"
  | "lastYear";

function ymd(year: number, month: number, day: number) {
  const date = new Date(Date.UTC(year, month - 1, day));
  return [
    date.getUTCFullYear(),
    String(date.getUTCMonth() + 1).padStart(2, "0"),
    String(date.getUTCDate()).padStart(2, "0"),
  ].join("-");
}

export function phPeriodBounds(range: PeriodRange, now: Date = new Date()): { from: string; to: string } {
  const today = phDateString(now);
  const [year, month, day] = today.split("-").map(Number);

  if (range === "today") return { from: today, to: today };
  if (range === "week") {
    const weekday = new Date(Date.UTC(year, month - 1, day)).getUTCDay();
    const start = new Date(Date.UTC(year, month - 1, day - weekday));
    return { from: ymd(start.getUTCFullYear(), start.getUTCMonth() + 1, start.getUTCDate()), to: today };
  }
  if (range === "lastWeek") {
    const weekday = new Date(Date.UTC(year, month - 1, day)).getUTCDay();
    const daysFromMonday = weekday === 0 ? 6 : weekday - 1;
    const lastMonday = day - daysFromMonday - 7;
    const start = new Date(Date.UTC(year, month - 1, lastMonday));
    const end = new Date(Date.UTC(year, month - 1, lastMonday + 6));
    return {
      from: ymd(start.getUTCFullYear(), start.getUTCMonth() + 1, start.getUTCDate()),
      to: ymd(end.getUTCFullYear(), end.getUTCMonth() + 1, end.getUTCDate()),
    };
  }
  if (range === "month") return { from: ymd(year, month, 1), to: today };
  if (range === "lastMonth") {
    const end = new Date(Date.UTC(year, month - 1, 0));
    const endYear = end.getUTCFullYear();
    const endMonth = end.getUTCMonth() + 1;
    return { from: ymd(endYear, endMonth, 1), to: ymd(endYear, endMonth, end.getUTCDate()) };
  }
  if (range === "thisYear") return { from: ymd(year, 1, 1), to: today };
  return { from: ymd(year - 1, 1, 1), to: ymd(year - 1, 12, 31) };
}

export function phDateRangeUtcBounds(from: string, to: string): { start: string; endExclusive: string } | null {
  const isValidDate = (value: string) => {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
    const date = new Date(`${value}T00:00:00+08:00`);
    return !Number.isNaN(date.getTime()) && phDateString(date) === value;
  };
  if (!isValidDate(from) || !isValidDate(to) || from > to) return null;

  const [year, month, day] = to.split("-").map(Number);
  const nextDay = new Date(Date.UTC(year, month - 1, day + 1));
  const nextDate = ymd(nextDay.getUTCFullYear(), nextDay.getUTCMonth() + 1, nextDay.getUTCDate());
  return {
    start: new Date(`${from}T00:00:00+08:00`).toISOString(),
    endExclusive: new Date(`${nextDate}T00:00:00+08:00`).toISOString(),
  };
}
