import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { supabaseAdmin } from "@/lib/store";
import type { LoginActivity } from "@/lib/types";

const PAGE_SIZE = 50;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

function isValidDate(value: string) {
  if (!DATE_PATTERN.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00.000Z`);
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

export async function GET(request: NextRequest) {
  const session = await getSession();
  if (!session || session.role !== "cashier") {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const page = Number(request.nextUrl.searchParams.get("page") ?? "1");
  const from = request.nextUrl.searchParams.get("from");
  const to = request.nextUrl.searchParams.get("to");
  if ((from === null) !== (to === null) || (from !== null && to !== null && (!isValidDate(from) || !isValidDate(to) || from > to))) {
    return NextResponse.json({ error: "Provide a valid inclusive from/to date range." }, { status: 400 });
  }
  if (!Number.isSafeInteger(page) || page < 1 || (page - 1) * PAGE_SIZE > Number.MAX_SAFE_INTEGER) {
    return NextResponse.json({ error: "Provide a positive page number." }, { status: 400 });
  }

  try {
    const startRow = (page - 1) * PAGE_SIZE;
    let query = supabaseAdmin()
      .from("login_activity")
      .select("id, owner_id, user_id, username, name, role, type, at, photo_path", { count: "exact" })
      .eq("owner_id", session.userId);
    if (from && to) {
      query = query
        .gte("at", `${from}T00:00:00+08:00`)
        .lte("at", `${to}T23:59:59.999+08:00`);
    }
    const { data, error, count } = await query
      .order("at", { ascending: false })
      .range(startRow, startRow + PAGE_SIZE - 1);
    if (error) throw new Error(`Unable to load staff activity: ${error.message}`);

    const activity: LoginActivity[] = (data ?? []).map((row) => ({
      id: row.id,
      ownerId: row.owner_id ?? undefined,
      userId: row.user_id ?? row.id,
      username: row.username,
      name: row.name,
      role: row.role,
      type: row.type,
      at: row.at,
      photoPath: row.photo_path ?? undefined,
    }));
    const total = count ?? 0;
    return NextResponse.json({
      activity,
      page,
      pageSize: PAGE_SIZE,
      total,
      hasMore: startRow + activity.length < total,
    }, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Unable to load staff activity." },
      { status: 500, headers: { "Cache-Control": "private, no-store" } },
    );
  }
}
