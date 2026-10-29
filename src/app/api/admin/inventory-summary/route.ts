import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { supabaseAdmin } from "@/lib/store";

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

  const from = request.nextUrl.searchParams.get("from") ?? "";
  const to = request.nextUrl.searchParams.get("to") ?? "";
  if (!isValidDate(from) || !isValidDate(to) || from > to) {
    return NextResponse.json(
      { error: "Provide a valid inclusive from/to date range." },
      { status: 400 },
    );
  }

  const { data, error } = await supabaseAdmin().rpc("admin_inventory_summary", {
    p_owner_id: session.userId,
    p_from: from,
    p_to: to,
  });
  if (error) {
    const schemaMissing = error.code === "PGRST202" ||
      /admin_inventory_summary.*does not exist|could not find the function.*admin_inventory_summary/i.test(error.message);
    return NextResponse.json(
      {
        error: schemaMissing
          ? "Inventory summary is not installed. Apply supabase/migrations/20261029000900_admin_inventory_summary.sql and reload the Supabase schema cache."
          : `Unable to load inventory summary: ${error.message}`,
      },
      { status: schemaMissing ? 503 : 500, headers: { "Cache-Control": "private, no-store" } },
    );
  }

  return NextResponse.json(data, {
    headers: { "Cache-Control": "private, no-store" },
  });
}
