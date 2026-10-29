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

  try {
    const { data, error } = await supabaseAdmin().rpc("admin_sales_summary", {
      p_owner_id: session.userId,
      p_from: from,
      p_to: to,
    });
    if (error) {
      if (
        error.code === "PGRST202" ||
        /could not find the function.*admin_sales_summary|admin_sales_summary.*does not exist/i.test(error.message)
      ) {
        return NextResponse.json(
          {
            error:
              "The sales-summary database function is not installed or the Supabase schema cache is stale. Apply supabase/migrations/20261029000500_admin_sales_summary.sql, then reload the PostgREST schema cache.",
          },
          { status: 503 },
        );
      }
      throw new Error(`Unable to load sales summary: ${error.message}`);
    }

    return NextResponse.json(data, {
      headers: { "Cache-Control": "private, no-store" },
    });
  } catch (error) {
    return NextResponse.json(
      {
        error: error instanceof Error ? error.message : "Unable to load sales summary.",
      },
      { status: 500 },
    );
  }
}
