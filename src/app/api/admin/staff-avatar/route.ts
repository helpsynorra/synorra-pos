import { randomUUID } from "node:crypto";
import { NextRequest, NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { supabaseAdmin } from "@/lib/store";

const MAX_AVATAR_BYTES = 153_600;
const allowedTypes = new Set(["image/jpeg", "image/png", "image/webp"]);

export async function POST(request: NextRequest) {
  const session = await getSession();
  if (!session || (session.role !== "admin" && session.role !== "cashier")) {
    return NextResponse.json({ error: "Only an Owner or admin can upload staff photos." }, { status: 403 });
  }

  const formData = await request.formData();
  const file = formData.get("avatar");
  if (!(file instanceof File) || !allowedTypes.has(file.type)) {
    return NextResponse.json({ error: "Choose a JPEG, PNG, or WebP photo." }, { status: 400 });
  }
  if (file.size === 0 || file.size > MAX_AVATAR_BYTES) {
    return NextResponse.json({ error: "The compressed photo must be 150 KB or smaller." }, { status: 413 });
  }

  const extension = file.type === "image/webp" ? "webp" : file.type === "image/png" ? "png" : "jpg";
  const path = `${session.userId}/${randomUUID()}.${extension}`;
  const { error } = await supabaseAdmin()
    .storage
    .from("staff-avatars")
    .upload(path, new Uint8Array(await file.arrayBuffer()), {
      contentType: file.type,
      cacheControl: "31536000",
      upsert: false,
    });

  if (error) {
    return NextResponse.json({ error: `Unable to upload staff photo: ${error.message}` }, { status: 500 });
  }
  return NextResponse.json({ path });
}

export async function DELETE(request: NextRequest) {
  const session = await getSession();
  if (!session || (session.role !== "admin" && session.role !== "cashier")) {
    return NextResponse.json({ error: "Only an Owner or admin can remove staff photos." }, { status: 403 });
  }

  const body: unknown = await request.json();
  const path = body && typeof body === "object" && "path" in body && typeof body.path === "string"
    ? body.path
    : "";
  if ((session.role === "cashier" && !path.startsWith(`${session.userId}/`)) || path.includes("..")) {
    return NextResponse.json({ error: "The photo path is invalid." }, { status: 400 });
  }

  const { error } = await supabaseAdmin().storage.from("staff-avatars").remove([path]);
  if (error) {
    return NextResponse.json({ error: `Unable to remove the previous staff photo: ${error.message}` }, { status: 500 });
  }
  return NextResponse.json({ ok: true });
}
