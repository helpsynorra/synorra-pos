"use server";

import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/auth";
import { getStore, supabaseAdmin, updateStore } from "@/lib/store";
import type { AttendanceAuthMode } from "@/lib/types";

const authModes: AttendanceAuthMode[] = [
  "username_password",
  "photo_username_password",
  "photo_full_name_pin",
];

export async function saveAttendanceSettings(input: {
  authMode: AttendanceAuthMode;
}): Promise<void> {
  const session = await getSession();
  if (!session || (session.role !== "admin" && session.role !== "cashier")) {
    throw new Error("Only the Owner or admin can manage attendance settings.");
  }
  if (!input || typeof input.authMode !== "string") {
    throw new Error("Attendance settings are invalid.");
  }
  if (!authModes.includes(input.authMode)) {
    throw new Error("Select a valid attendance login method.");
  }

  await updateStore((store) => {
    store.pos.attendanceAuthMode = input.authMode;
  });
  revalidatePath("/owner");
}

export async function getAttendancePhotoUrl(activityId: string): Promise<string> {
  const session = await getSession();
  if (!session || session.role !== "cashier") {
    throw new Error("Only Owner/Finance users can view attendance photos.");
  }
  if (typeof activityId !== "string" || !activityId.trim()) {
    throw new Error("Select a valid attendance record.");
  }

  const store = await getStore();
  const activity = store.loginActivity.find((entry) => entry.id === activityId);
  if (!activity?.photoPath) {
    throw new Error("No attendance photo is available for this record.");
  }

  const { data, error } = await supabaseAdmin()
    .storage
    .from("attendance-photos")
    .createSignedUrl(activity.photoPath, 5 * 60);
  if (error) {
    throw new Error(`Unable to open attendance photo: ${error.message}`);
  }
  if (!data?.signedUrl) {
    throw new Error("Unable to open attendance photo: no secure link was returned.");
  }
  return data.signedUrl;
}

export async function getStaffAvatarUrl(staffUserId: string): Promise<string | null> {
  const session = await getSession();
  if (!session || (session.role !== "admin" && session.role !== "cashier")) {
    throw new Error("Only the Owner or admin can view staff photos.");
  }
  if (typeof staffUserId !== "string" || !staffUserId.trim()) {
    throw new Error("Select a valid staff account.");
  }

  const { data: user, error: userError } = await supabaseAdmin()
    .from("staff_users")
    .select("id, owner_id, avatar_path")
    .eq("id", staffUserId)
    .maybeSingle();
  if (userError) {
    throw new Error(`Unable to load staff photo details: ${userError.message}`);
  }
  if (!user || (session.role === "cashier" && user.owner_id !== session.userId)) {
    throw new Error("Staff account not found in your workspace.");
  }
  if (!user.avatar_path) return null;

  const { data, error } = await supabaseAdmin()
    .storage
    .from("staff-avatars")
    .createSignedUrl(user.avatar_path, 60 * 60);
  if (error) {
    throw new Error(`Unable to open staff photo: ${error.message}`);
  }
  if (!data?.signedUrl) {
    throw new Error("Unable to open staff photo: no secure link was returned.");
  }
  return data.signedUrl;
}
