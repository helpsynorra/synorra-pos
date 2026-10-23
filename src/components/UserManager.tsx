"use client";

import { useEffect, useMemo, useState, useTransition } from "react";
import {
  createOffRequest,
  createStaffUser,
  deleteCommunePromotionCode,
  endCommunePromotionEvent,
  deleteOffRequest,
  deleteOwnerPromotionCode,
  deleteStaffUser,
  punchStaff,
  setOffRequestStatus,
  updateStaffSessionTimes,
  deleteStaffSession,
  generateCommunePromotionCodes,
  getCommunePromotionDiscountSummary,
  updateCommunePromotionBatchPaymentStatus,
  updateOwnerPermissions,
  generateOwnerPromotionCode,
  getCommunePromotionCodes,
  updateStaffUser,
  updateStaffPassword,
  updateLoginGates,
} from "@/actions/users";
import type { PublicStaffUser } from "@/lib/users";
import { DEFAULT_STAFF_PERMISSIONS } from "@/lib/users";
import { phDateString, phDateTimeInputValue, phDateTimeLabel } from "@/lib/datetime";
import { isAttendanceStaffRole, pairLoginSessions, type StaffSession } from "@/lib/staff-sessions";
import type { LoginActivity, OffRequest, Order, PromotionCode, Session, StaffPermissions } from "@/lib/types";
import { formatMoney } from "@/lib/menu";

const field =
  "w-full rounded-xl border border-neutral-200 bg-white px-3.5 py-2.5 text-sm text-neutral-900 outline-none transition-all focus:border-neutral-900 focus:ring-1 focus:ring-neutral-900";
const staffField =
  "w-full rounded-xl border border-slate-200 bg-slate-50/70 px-4 py-3 text-sm text-slate-900 outline-none transition placeholder:text-slate-400 focus:border-[#58789d] focus:bg-white focus:ring-4 focus:ring-[#e8f0fa]";
const adminField =
  "h-12 w-full min-w-0 rounded-xl border border-[#dce6f4] bg-white px-3.5 text-sm text-[#243a5e] outline-none transition focus:border-[#58789d] focus:ring-2 focus:ring-[#e8f0fa]";

type UserManagerProps = {
  users: PublicStaffUser[];
  session: Session;
  loginActivity: LoginActivity[];
  offRequests: OffRequest[];
  showShiftTabs?: boolean;
  showAdminRole?: boolean;
  showOwnerRole?: boolean;
  showBaristaRole?: boolean;
  showCashierRole?: boolean;
  showBaristasOnly?: boolean;
  showEditStaffButton?: boolean;
  showDeleteStaffButton?: boolean;
  baristaOnlyStaffActions?: boolean;
  printButtonHidden?: boolean;
  inventoryFeaturesEnabled?: boolean;
  showLoginLinksTab?: boolean;
  showPrintButtonToggle?: boolean;
  showViewPermissionsButton?: boolean;
  adminLoginPath: string;
};

type SubTab = "staff" | "inout" | "off" | "gates" | "settings" | "customWebsitePromo";
type StaffRole = "Admin" | "Barista" | "Cashier" | "Owner";

type PermissionFlag = Exclude<keyof StaffPermissions, "promoCodes">;

function isPromotionExpired(promo: PromotionCode): boolean {
  if (!promo.expiresAt) return false;
  const expiry = Date.parse(promo.expiresAt);
  return !Number.isFinite(expiry) || expiry <= Date.now();
}

const permissionOptions: { key: PermissionFlag; label: string }[] = [
  { key: "stockInventory", label: "Stock inventory" },
  { key: "restockInventory", label: "Restock inventory" },
  { key: "connectLabels", label: "Connect labels" },
  { key: "connectReceipt", label: "Connect receipt" },
  { key: "printButton", label: "Print button" },
  { key: "customerReceipt", label: "Customer receipt" },
  { key: "cupLabels", label: "Cup labels" },
  { key: "dineIn", label: "Dine in" },
  { key: "takeOut", label: "Take out" },
  { key: "promotionDiscount", label: "Promotion discounts in POS" },
  { key: "promotionsEnabled", label: "Promotions enabled" },
];

const adminPermissionGroups: {
  title: string;
  description: string;
  icon: "inventory" | "operations" | "customer";
  permissions: PermissionFlag[];
}[] = [
  {
    title: "Inventory & Sales",
    description: "Manage products, stock and sales operations.",
    icon: "inventory",
    permissions: ["stockInventory", "connectReceipt", "cupLabels", "promotionDiscount"],
  },
  {
    title: "Operations",
    description: "Handle daily operations and customer flow.",
    icon: "operations",
    permissions: ["restockInventory", "printButton", "dineIn", "promotionsEnabled"],
  },
  {
    title: "Customer & Labels",
    description: "Manage customer data and label printing.",
    icon: "customer",
    permissions: ["connectLabels", "customerReceipt", "takeOut"],
  },
];

export function UserManager({ users, session, loginActivity, offRequests, showShiftTabs = true, showAdminRole = true, showOwnerRole = true, showBaristaRole = true, showCashierRole = false, showBaristasOnly = false, showEditStaffButton = true, showDeleteStaffButton = true, baristaOnlyStaffActions = false, showLoginLinksTab = true, showPrintButtonToggle = true, showViewPermissionsButton = true, adminLoginPath }: UserManagerProps) {
  const defaultStaffRole: StaffRole = showBaristasOnly || (!showOwnerRole && showBaristaRole)
    ? "Barista"
    : !showOwnerRole && showCashierRole
      ? "Cashier"
      : showOwnerRole
        ? "Owner"
        : "Admin";
  const [tab, setTab] = useState<SubTab>("staff");
  const [editingId, setEditingId] = useState<string | "new" | null>(null);
  const [name, setName] = useState("");
  const [username, setUsername] = useState("");
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<StaffRole>(defaultStaffRole);
  const [password, setPassword] = useState("");
  const [changingPasswordId, setChangingPasswordId] = useState<string | null>(null);
  const [staffPasswordDraft, setStaffPasswordDraft] = useState("");
  const [notice, setNotice] = useState<string | null>(null);
  const [adminPath, setAdminPath] = useState(adminLoginPath);
  const [permissionState, setPermissionState] = useState<Record<string, StaffPermissions>>(
    () => Object.fromEntries(users.map((user) => [user.id, { ...DEFAULT_STAFF_PERMISSIONS, ...user.permissions }])),
  );
  const [selectedPermissionOwnerId, setSelectedPermissionOwnerId] = useState<string | null>(null);
  const [communePromoCodes, setCommunePromoCodes] = useState<PromotionCode[]>([]);
  const [communePromoCollapsed, setCommunePromoCollapsed] = useState(false);
  const [selectedVoucherHost, setSelectedVoucherHost] = useState<string | null>(null);
  const [communeDiscountSummary, setCommuneDiscountSummary] = useState<{
    totalDiscountGiven: number;
    orders: Pick<Order, "id" | "ticketNo" | "promoLabel" | "discount" | "createdAt" | "items">[];
  } | null>(null);
  const [communeDiscountSummaryError, setCommuneDiscountSummaryError] = useState<string | null>(null);
  const [communeDiscountSummaryLoading, setCommuneDiscountSummaryLoading] = useState(false);
  const [promoCodeRecords, setPromoCodeRecords] = useState<Record<string, PromotionCode[]>>(
    () => Object.fromEntries(users.map((user) => [user.id, user.permissions?.promoCodes ?? []])),
  );
  const [promoValueDrafts, setPromoValueDrafts] = useState<Record<string, number>>({});
  const [promoTypeDrafts, setPromoTypeDrafts] = useState<Record<string, PromotionCode["discountType"]>>({});
  const [promoItemCountDrafts, setPromoItemCountDrafts] = useState<Record<string, number>>({});
  const [promoPrefixDrafts, setPromoPrefixDrafts] = useState<Record<string, string>>({});
  const [communeEventHost, setCommuneEventHost] = useState("");
  const [promoExpiryDrafts, setPromoExpiryDrafts] = useState<Record<string, string>>({});
  const [promoCountModes, setPromoCountModes] = useState<Record<string, string>>({});
  const [promoCustomCounts, setPromoCustomCounts] = useState<Record<string, string>>({});
  const [pending, startTransition] = useTransition();
  const [punchUserId, setPunchUserId] = useState("");
  const [editingSessionId, setEditingSessionId] = useState<string | null>(null);
  const [editLoginAt, setEditLoginAt] = useState("");
  const [editLogoutAt, setEditLogoutAt] = useState("");
  const [offUserId, setOffUserId] = useState("");
  const [offDate, setOffDate] = useState(phDateString());
  const [offReason, setOffReason] = useState("");

  useEffect(() => {
    setPromoCodeRecords(Object.fromEntries(users.map((user) => [user.id, user.permissions?.promoCodes ?? []])));
  }, [users]);

  useEffect(() => {
    if (session.role !== "admin") return;
    let cancelled = false;
    void getCommunePromotionCodes().then((result) => {
      if (cancelled) return;
      if ("error" in result && result.error) {
        setNotice(result.error);
        return;
      }
      setCommunePromoCodes(result.promos ?? []);
    });
    return () => { cancelled = true; };
  }, [session.role]);

  useEffect(() => {
    if (session.role !== "admin") return;
    let cancelled = false;
    setCommuneDiscountSummaryLoading(true);
    void getCommunePromotionDiscountSummary()
      .then((result) => {
        if (cancelled) return;
        if ("error" in result) {
          setCommuneDiscountSummaryError(result.error);
          setCommuneDiscountSummary(null);
        } else {
          setCommuneDiscountSummaryError(null);
          setCommuneDiscountSummary(result);
        }
        setCommuneDiscountSummaryLoading(false);
      })
      .catch((error: unknown) => {
        if (cancelled) return;
        setCommuneDiscountSummaryError(error instanceof Error ? error.message : "Could not load Commune's promo discount total.");
        setCommuneDiscountSummary(null);
        setCommuneDiscountSummaryLoading(false);
      });
    return () => { cancelled = true; };
  }, [session.role]);
  
  // Global filter/display date state for In / Out
  const [selectedDate, setSelectedDate] = useState(phDateString());

  // Global filter/display date state for Request off
  const [offSelectedDate, setOffSelectedDate] = useState(phDateString());

  const uniqueUsers = useMemo(
    () => Array.from(new Map(users.map((user) => [user.id, user])).values()),
    [users],
  );
  const visibleUsers = showBaristasOnly
    ? uniqueUsers.filter((user) => user.role === "barista" || user.role === "pos_cashier")
    : uniqueUsers;
  const ownerUsers = visibleUsers.filter((user) => user.role === "cashier");
  const isAdminConsole = session.role === "admin";
  const communeVoucherOrderBreakdown = useMemo(() => {
    return (communeDiscountSummary?.orders ?? []).map((order) => {
        const items = order.items.map((item) => {
          const addonsTotal = (item.addons ?? []).reduce((sum, addon) => sum + addon.price * Math.max(1, Number(addon.qty) || 1), 0);
          return { ...item, lineTotal: item.qty * (item.price + addonsTotal) };
        });
        return {
          order,
          voucherCode: order.promoLabel!,
          items,
          itemsTotal: items.reduce((sum, item) => sum + item.lineTotal, 0),
        };
      });
  }, [communeDiscountSummary]);
  const editing = visibleUsers.find((user) => user.id === editingId) ?? null;
  const floorStaff = visibleUsers.filter((user) => isAttendanceStaffRole(user.role));
  const allSessions = useMemo(
    () => pairLoginSessions(loginActivity).filter((row) => isAttendanceStaffRole(row.role)),
    [loginActivity],
  );
  const selectedStaffIsOnShift = allSessions.some(
    (shift) => shift.userId === punchUserId && !shift.logoutAt,
  );

  // Filter sessions based on selectedDate
  const sessions = useMemo(() => {
    if (!selectedDate) return allSessions;
    return allSessions.filter((row) => {
      const loginDateStr = row.loginAt ? new Date(row.loginAt).toISOString().split("T")[0] : "";
      const logoutDateStr = row.logoutAt ? new Date(row.logoutAt).toISOString().split("T")[0] : "";
      return loginDateStr === selectedDate || logoutDateStr === selectedDate;
    });
  }, [allSessions, selectedDate]);

  // Filter off requests based on offSelectedDate
  const requests = useMemo(() => {
    const sorted = [...offRequests].sort((a, b) => b.date.localeCompare(a.date) || b.createdAt.localeCompare(a.createdAt));
    if (!offSelectedDate) return sorted;
    return sorted.filter((req) => {
      const reqDateStr = req.date ? new Date(req.date).toISOString().split("T")[0] : "";
      return reqDateStr === offSelectedDate;
    });
  }, [offRequests, offSelectedDate]);

  function startCreate() {
    setEditingId("new");
    setName("");
    setUsername("");
    setEmail("");
    setRole(defaultStaffRole);
    setPassword("");
    setNotice(null);
    setTab("staff");
  }

  function startEdit(user: PublicStaffUser) {
    setEditingId(user.id);
    setName(user.name);
    setUsername(user.username);
    setEmail(user.email ?? "");
    const lowerRole = user.role.toLowerCase();
    setRole(
      lowerRole === "admin"
        ? "Admin"
        : lowerRole === "cashier"
            ? "Owner"
            : lowerRole === "pos_cashier" || user.title?.toLowerCase() === "cashier"
              ? "Cashier"
            : "Barista",
    );
    setPassword("");
    setNotice(null);
  }

  function resetForm() {
    setEditingId(null);
    setPassword("");
  }

  function startSessionEdit(row: StaffSession) {
    setEditingSessionId(row.id);
    setEditLoginAt(row.loginAt ? phDateTimeInputValue(row.loginAt) : "");
    setEditLogoutAt(row.logoutAt ? phDateTimeInputValue(row.logoutAt) : "");
    setNotice(null);
  }

  return (
    <div className="min-h-[calc(100svh-65px)] min-w-0 space-y-5 bg-slate-50/70 p-3 sm:space-y-6 sm:p-5 xl:p-7 2xl:p-9">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between border-b border-neutral-400 pb-3">
        <div className="flex w-fit max-w-full gap-1.5 overflow-x-auto rounded-2xl border border-slate-200 bg-white p-1.5 shadow-sm">
          {(
            [
              { id: "staff", label: "Staff" },
              { id: "inout", label: "In / Out" },
              { id: "off", label: "Request off" },
              { id: "gates", label: "Login links" },
              ...(showPrintButtonToggle ? [{ id: "settings" as const, label: "Settings" }] : []),
              ...(isAdminConsole ? [{ id: "customWebsitePromo" as const, label: "Custom Website Promo" }] : []),
            ] as const
          )
            .filter((entry) => (showShiftTabs || (entry.id !== "inout" && entry.id !== "off")) && (showLoginLinksTab || entry.id !== "gates"))
            .map((entry) => (
            <button
              key={entry.id}
              type="button"
              onClick={() => {
                setTab(entry.id);
                setNotice(null);
              }}
              className={`shrink-0 rounded-xl px-4 py-2.5 text-xs font-bold uppercase transition ${
                isAdminConsole
                  ? tab === entry.id
                    ? "bg-[#101d37] text-white shadow-[0_4px_12px_rgba(16,29,55,0.2)]"
                    : "text-[#536783] hover:bg-[#f2f5ff]"
                  : tab === entry.id
                    ? "bg-slate-900 text-white shadow-sm"
                    : "text-slate-600 hover:bg-slate-100 hover:text-slate-950"
              } rounded-xl`}
            >
              {entry.label}
            </button>
          ))}
        </div>
      </div>

      <div className="w-full space-y-5">
        {notice ? <p className="text-sm text-neutral-600">{notice}</p> : null}

        {tab === "staff" ? (
          <>
            <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
              <div>
                <p className="text-[11px] font-bold tracking-[0.2em] text-[#58789d] uppercase">Team management</p>
                <h1 className="mt-1 text-2xl font-bold tracking-tight text-slate-900">Staff</h1>
                <p className="mt-1 text-sm text-slate-500">Manage team accounts and POS access.</p>
              </div>
              <button
                type="button"
                onClick={startCreate}
                className="inline-flex items-center justify-center gap-2 rounded-xl bg-[#b90c0c] px-5 py-3 text-sm font-semibold text-white shadow-lg shadow-red-900/10 transition hover:-translate-y-0.5 hover:bg-[#970909]"
              >
                <svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" aria-hidden="true"><path d="M12 5v14M5 12h14" strokeWidth="2" strokeLinecap="round" /></svg>
                Add staff
              </button>
            </div>

            {editingId ? (
              <form
                className="overflow-hidden rounded-3xl border border-slate-200 bg-white shadow-[0_18px_50px_rgba(15,23,42,0.07)]"
                onSubmit={(event) => {
                  event.preventDefault();
                  const submittedPassword = password;
                  setPassword("");
                  startTransition(async () => {
                    const payload = {
                      name,
                      username,
                      email,
                      title: role,
                      role: role === "Owner" ? "cashier" : role === "Cashier" ? "pos_cashier" : role.toLowerCase(),
                      password: submittedPassword,
                    };
                    const result =
                      editingId === "new"
                        ? await createStaffUser(payload)
                        : await updateStaffUser({ id: editingId, ...payload });
                    if (result && "error" in result && result.error) {
                      setNotice(typeof result.error === "string" ? result.error : "Could not save.");
                      return;
                    }
                    if (editingId === "new") {
                      startCreate();
                      setEditingId(null);
                      setNotice(null);
                      return;
                    }
                    resetForm();
                    setNotice(null);
                  });
                }}
              >
                <div className="flex items-center justify-between gap-4 border-b border-slate-100 bg-gradient-to-r from-[#edf4fc] via-white to-white px-5 py-5 sm:px-7">
                  <div>
                    <p className="text-[11px] font-bold tracking-[0.18em] text-[#58789d] uppercase">Team account</p>
                    <h2 className="mt-1 text-lg font-bold text-slate-900">{editingId === "new" ? "Add a team member" : `Edit ${editing?.name ?? "staff"}`}</h2>
                  </div>
                  <button type="button" onClick={resetForm} className="rounded-lg px-3 py-2 text-sm font-semibold text-slate-500 transition hover:bg-white hover:text-slate-900">
                    Cancel
                  </button>
                </div>
                <div className="grid gap-5 p-4 min-[600px]:gap-6 min-[600px]:p-6 md:grid-cols-[1.1fr_0.9fr] xl:p-7">
                  <section className="space-y-4">
                    <div>
                      <h3 className="text-sm font-bold text-slate-800">Account details</h3>
                      <p className="mt-1 text-xs text-slate-500">Set the name and sign-in details for this account.</p>
                    </div>
                    <div className="grid gap-4 min-[600px]:grid-cols-2">
                      <label className="space-y-1.5 text-xs font-semibold text-slate-600">
                        <span className="block">Full name</span>
                        <input value={name} onChange={(event) => setName(event.target.value)} className={staffField} placeholder="e.g. Alex Santos" required />
                      </label>
                      <label className="space-y-1.5 text-xs font-semibold text-slate-600">
                        <span className="block">Username</span>
                        <input value={username} onChange={(event) => setUsername(event.target.value)} className={staffField} placeholder="e.g. alex" required />
                      </label>
                      {role === "Owner" && editingId !== "new" ? (
                        <label className="space-y-1.5 text-xs font-semibold text-slate-600 sm:col-span-2">
                          <span className="block">Email</span>
                          <input type="email" value={email} onChange={(event) => setEmail(event.target.value)} className={staffField} placeholder="name@example.com" />
                        </label>
                      ) : null}
                      <label className="space-y-1.5 text-xs font-semibold text-slate-600 sm:col-span-2">
                        <span className="block">Password</span>
                        <input
                          type="password"
                          value={password}
                          onChange={(event) => setPassword(event.target.value)}
                          className={staffField}
                          required={editingId === "new"}
                          placeholder={editingId === "new" ? "Create a password" : "Leave blank to keep current"}
                        />
                      </label>
                    </div>
                  </section>

                  <section className="rounded-2xl border border-slate-200 bg-slate-50/80 p-4 sm:p-5">
                    <div className="mb-4">
                      <h3 className="text-sm font-bold text-slate-800">Choose a role</h3>
                      <p className="mt-1 text-xs text-slate-500">Select what this person can do in the store.</p>
                    </div>
                    <div className="grid gap-3 min-[600px]:grid-cols-2">
                      {([...(showAdminRole ? ["Admin" as const] : []), ...(showOwnerRole ? ["Owner" as const] : []), ...(showBaristaRole ? ["Barista" as const] : []), ...(showCashierRole ? ["Cashier" as const] : [])] as const).map((id) => {
                        const selected = role === id;
                        const description = id === "Barista"
                          ? "Clock in and out for shifts."
                          : id === "Cashier"
                            ? "Handle POS sales and track shifts."
                            : id === "Owner"
                              ? "Manage this store and use the POS."
                              : "Manage Synorra settings and staff.";
                        return (
                          <button
                            key={id}
                            type="button"
                            aria-pressed={selected}
                            onClick={() => setRole(id)}
                            className={`group flex min-h-24 items-start gap-3 rounded-2xl border p-3 text-left transition ${selected ? "border-[#58789d] bg-white shadow-md shadow-[#dce8f7] ring-2 ring-[#e8f0fa]" : "border-slate-200 bg-white/70 hover:border-slate-300 hover:bg-white"}`}
                          >
                            <span className={`flex size-10 shrink-0 items-center justify-center rounded-xl text-sm font-bold ${selected ? "bg-[#101d37] text-white" : "bg-slate-100 text-slate-500 group-hover:bg-[#edf4fc] group-hover:text-[#243a5e]"}`}>
                              {id === "Barista" ? "B" : id === "Cashier" ? "₱" : id === "Owner" ? "O" : "A"}
                            </span>
                            <span className="min-w-0">
                              <span className="block text-sm font-bold text-slate-800">{id}</span>
                              <span className="mt-1 block text-[11px] leading-4 text-slate-500">{description}</span>
                            </span>
                          </button>
                        );
                      })}
                    </div>
                    <p className="mt-4 rounded-xl border-l-2 border-[#d64646] bg-[#edf4fc] px-3.5 py-3 text-xs leading-5 text-[#344f73]">
                      {role === "Owner"
                        ? "The Owner can sign in to POS with this username and password."
                        : role === "Admin"
                          ? "Admins can manage Synorra settings and staff."
                          : `${role}s use this username and password to clock in and out on POS.`}
                    </p>
                  </section>
                </div>
                <div className="flex justify-end border-t border-slate-100 bg-slate-50/70 px-5 py-4 sm:px-7">
                  <button
                    type="submit"
                    disabled={pending}
                    className="inline-flex items-center gap-2 rounded-xl bg-[#b90c0c] px-6 py-3 text-sm font-bold text-white shadow-lg shadow-red-900/10 transition hover:bg-[#970909] disabled:cursor-wait disabled:opacity-50"
                  >
                    {pending ? "Saving…" : editingId === "new" ? "Add staff member" : "Save changes"}
                    {!pending ? <svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" aria-hidden="true"><path d="m9 18 6-6-6-6" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" /></svg> : null}
                  </button>
                </div>
              </form>
            ) : null}

            <div className="grid gap-3 min-[1025px]:grid-cols-2">
              {visibleUsers.map((user) => (
                <div key={user.id} className="group rounded-2xl border border-slate-200 bg-white p-4 shadow-sm transition hover:-translate-y-0.5 hover:border-[#b8cce4] hover:shadow-lg hover:shadow-slate-900/5 sm:p-5">
                  <div className="flex items-center justify-between gap-3">
                  <div className="flex min-w-0 items-center gap-3.5">
                    <div className="flex size-12 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-[#101d37] to-[#58789d] text-base font-bold text-white shadow-md shadow-[#dce8f7]">
                      {user.name.trim().charAt(0).toUpperCase() || "S"}
                    </div>
                    <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <p className="truncate text-sm font-bold text-slate-900">{user.name}</p>
                      {user.id === session.userId ? (
                        <span className="rounded-full bg-[#fff0f0] px-2 py-0.5 text-[10px] font-bold tracking-wide text-[#c63d3d] uppercase">
                          you
                        </span>
                      ) : null}
                    </div>
                    <p className="mt-1 truncate text-xs text-slate-500">@{user.username}</p>
                    <span className="mt-2 inline-flex rounded-full bg-slate-100 px-2.5 py-1 text-[10px] font-bold tracking-wide text-slate-600 uppercase">
                      {user.role === "admin" ? "Admin" : user.role === "cashier" ? "Owner" : user.role === "pos_cashier" ? "Cashier" : user.title || "Barista"}
                    </span>
                    </div>
                  </div>
                  <div className="flex items-center gap-1">
                    {session.role === "cashier" && (user.role === "barista" || user.role === "pos_cashier") ? (
                      <button
                        type="button"
                        onClick={() => {
                          setChangingPasswordId((current) => current === user.id ? null : user.id);
                          setStaffPasswordDraft("");
                          setNotice(null);
                        }}
                        className="rounded-lg px-2.5 py-2 text-xs font-semibold text-[#58789d] transition hover:bg-[#edf4fc] hover:text-[#243a5e]"
                      >
                        {changingPasswordId === user.id ? "Cancel" : "Change password"}
                      </button>
                    ) : null}
                    {user.role === "cashier" && showViewPermissionsButton ? (
                      <button
                        type="button"
                        onClick={() => {
                          setSelectedPermissionOwnerId(user.id);
                          setTab("settings");
                        }}
                        className="rounded-full border border-neutral-300 px-3 py-2 text-xs font-medium text-neutral-700 hover:border-black hover:text-black"
                      >
                        View Permissions
                      </button>
                    ) : null}
                    {showEditStaffButton && (!baristaOnlyStaffActions || user.role === "barista" || user.role === "pos_cashier") ? <button
                      type="button"
                      aria-label={`Edit ${user.name}`}
                      onClick={() => startEdit(user)}
                      className="inline-flex h-9 items-center justify-center gap-1.5 rounded-xl px-2.5 text-xs font-semibold text-[#58789d] transition hover:bg-[#edf4fc] hover:text-[#243a5e]"
                    >
                      <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor">
                        <path d="M4 20h4l10.5-10.5a2.1 2.1 0 0 0-3-3L5 17v3Z" strokeWidth="1.7" strokeLinejoin="round" />
                        <path d="M13.5 6.5l3 3" strokeWidth="1.7" />
                      </svg>
                      Edit
                    </button> : null}
                    {showDeleteStaffButton && (!baristaOnlyStaffActions || user.role === "barista" || user.role === "pos_cashier") ? <button
                      type="button"
                      aria-label={`Delete ${user.name}`}
                      disabled={pending || user.id === session.userId}
                      onClick={() => {
                        const confirmation = user.role === "cashier"
                          ? `Delete ${user.name}'s Owner account and all of its store data? This cannot be undone.`
                          : `Delete ${user.name}'s staff account?`;
                        if (!window.confirm(confirmation)) return;
                        startTransition(async () => {
                          const result = await deleteStaffUser(user.id);
                          if (result && "error" in result && result.error) {
                            setNotice(typeof result.error === "string" ? result.error : "Could not delete.");
                            return;
                          }
                          if (editingId === user.id) resetForm();
                          setNotice(null);
                        });
                      }}
                      className="flex h-9 w-9 items-center justify-center rounded-xl text-neutral-400 hover:bg-red-50 hover:text-red-600 disabled:opacity-30"
                    >
                      <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor">
                        <path d="M5 7h14M10 7V5h4v2M8 7l1 12h6l1-12" strokeWidth="1.7" />
                      </svg>
                    </button> : null}
                  </div>
                </div>
                  {changingPasswordId === user.id ? (
                    <form
                      className="mt-4 flex flex-col gap-2 border-t border-slate-100 pt-4 sm:flex-row sm:items-end"
                      onSubmit={(event) => {
                        event.preventDefault();
                        const nextPassword = staffPasswordDraft;
                        startTransition(async () => {
                          const result = await updateStaffPassword(user.id, nextPassword);
                          if ("error" in result && result.error) {
                            setNotice(result.error);
                            return;
                          }
                          setChangingPasswordId(null);
                          setStaffPasswordDraft("");
                          setNotice(`Password changed for ${user.name}.`);
                        });
                      }}
                    >
                      <label className="min-w-0 flex-1 space-y-1.5 text-xs font-semibold text-slate-600">
                        <span className="block">New password for {user.name}</span>
                        <input
                          type="password"
                          autoComplete="new-password"
                          minLength={4}
                          maxLength={128}
                          required
                          value={staffPasswordDraft}
                          onChange={(event) => setStaffPasswordDraft(event.target.value)}
                          className={staffField}
                          placeholder="Enter a new password"
                        />
                      </label>
                      <button
                        type="submit"
                        disabled={pending || staffPasswordDraft.length < 4}
                        className="rounded-xl bg-[#b90c0c] px-4 py-3 text-sm font-semibold text-white transition hover:bg-[#970909] disabled:cursor-wait disabled:opacity-50"
                      >
                        {pending ? "Saving…" : "Save password"}
                      </button>
                    </form>
                  ) : null}
                </div>
              ))}
            </div>
          </>
        ) : null}

        {tab === "customWebsitePromo" ? (() => {
          const communeDraftId = "__commune_website__";
          const promoType = promoTypeDrafts[communeDraftId] ?? "percent";
          const countMode = promoCountModes[communeDraftId] ?? "5";
          const customCount = promoCustomCounts[communeDraftId] ?? "25";
          const prefix = promoPrefixDrafts[communeDraftId] ?? "COMMUNE";
          const expiry = promoExpiryDrafts[communeDraftId] ?? "";
          const itemCount = promoItemCountDrafts[communeDraftId] ?? 1;
          const value = promoValueDrafts[communeDraftId] ?? 10;
          const promos = communePromoCodes;
          const promosByHost = new Map<string, PromotionCode[]>();
          for (const promo of promos) {
            const host = promo.eventHost?.trim() || "No host assigned";
            promosByHost.set(host, [...(promosByHost.get(host) ?? []), promo]);
          }
          const hostGroups = [...promosByHost]
            .sort(([left], [right]) => left.localeCompare(right))
            .map(([host, hostPromos]) => {
              const batches = new Map<string, PromotionCode[]>();
              for (const promo of hostPromos) {
                const batchKey = promo.batchId ?? `legacy-${promo.code}`;
                batches.set(batchKey, [...(batches.get(batchKey) ?? []), promo]);
              }
              return {
                host,
                hostPromos,
                batches: [...batches].map(([, batchPromos]) => ({ batchId: batchPromos[0]?.batchId ?? null, promos: batchPromos })),
              };
            });
          const hostVoucherGroups = hostGroups.map((group) => {
            const voucherCodes = new Set(group.hostPromos.map((promo) => promo.code.trim().toUpperCase()));
            const orders = communeVoucherOrderBreakdown.filter(({ voucherCode }) => voucherCodes.has(voucherCode.trim().toUpperCase()));
            return {
              ...group,
              orders,
              totalDiscountGiven: orders.reduce((sum, { order }) => sum + (order.discount ?? 0), 0),
              hasActiveVouchers: group.hostPromos.some((promo) => !promo.redeemedAt && !isPromotionExpired(promo)),
            };
          });
          const matchedVoucherCodes = new Set(promos.map((promo) => promo.code.trim().toUpperCase()));
          const unassignedOrders = communeVoucherOrderBreakdown.filter(({ voucherCode }) => !matchedVoucherCodes.has(voucherCode.trim().toUpperCase()));
          if (unassignedOrders.length) {
            const unassignedGroup = hostVoucherGroups.find((group) => group.host === "No host assigned");
            if (unassignedGroup) {
              unassignedGroup.orders.push(...unassignedOrders);
              unassignedGroup.totalDiscountGiven += unassignedOrders.reduce((sum, { order }) => sum + (order.discount ?? 0), 0);
            } else {
              hostVoucherGroups.push({
                host: "No host assigned",
                hostPromos: [],
                batches: [],
                orders: unassignedOrders,
                totalDiscountGiven: unassignedOrders.reduce((sum, { order }) => sum + (order.discount ?? 0), 0),
                hasActiveVouchers: false,
              });
            }
          }
          const selectedVoucherHostGroup = hostVoucherGroups.find((group) => group.host === selectedVoucherHost) ?? null;
          const canGenerate = Boolean(
              !pending &&
              expiry &&
              expiry >= phDateString() &&
              /^[A-Z0-9]{1,16}$/.test(prefix) &&
              (promoType !== "item" || (Number.isInteger(itemCount) && itemCount >= 1 && itemCount <= 99)) &&
              (promoType === "item" || (Number.isFinite(value) && value > 0 && (promoType !== "percent" || value <= 100))) &&
              (countMode !== "custom" || (/^\d+$/.test(customCount) && Number(customCount) >= 1 && Number(customCount) <= 100)),
          );

          return (
            <section aria-label="Custom Website Promo" className="rounded-2xl border border-[#e4ebf5] bg-white p-4 shadow-[0_8px_30px_rgba(37,75,130,0.06)] sm:p-6">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <h1 className="text-xl font-semibold tracking-tight text-[#14213d]">Commune checkout vouchers</h1>
                  <p className="mt-1 text-sm text-[#7486a3]">Generate one-time promo codes for the Commune website checkout. These are stored separately from Synorra Owner vouchers.</p>
                </div>
                <button
                  type="button"
                  aria-expanded={!communePromoCollapsed}
                  aria-controls="commune-voucher-content"
                  onClick={() => setCommunePromoCollapsed((collapsed) => !collapsed)}
                  className="shrink-0 rounded-lg border border-[#dce6f4] bg-white px-4 py-2 text-sm font-semibold text-[#536783] transition hover:bg-[#f5f8fc]"
                >
                  {communePromoCollapsed ? "Expand" : "Minimize"}
                </button>
              </div>

              <div id="commune-voucher-content" hidden={communePromoCollapsed} className="mt-5 space-y-5">
                  <div className="space-y-4 border-t border-[#e7edf6] pt-5">
                    <div>
                      <h2 className="text-sm font-semibold text-[#172849]">Generate voucher codes</h2>
                      <p className="mt-1 text-xs text-[#8091ab]">Each code can be redeemed once and expires at the end of the selected date.</p>
                    </div>
                    <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-[minmax(130px,1fr)_minmax(150px,1.1fr)_minmax(130px,1fr)_minmax(140px,1fr)_minmax(140px,1fr)_minmax(150px,1fr)_auto]">
                      <label className="block min-w-0 space-y-1.5 text-xs font-medium text-[#586b89]">
                        <span>Prefix</span>
                        <input aria-label="Commune voucher prefix" value={prefix} maxLength={16} onChange={(event) => setPromoPrefixDrafts((current) => ({ ...current, [communeDraftId]: event.target.value.toUpperCase() }))} className={adminField} />
                      </label>
                      <label className="block min-w-0 space-y-1.5 text-xs font-medium text-[#586b89]">
                        <span>Discount type</span>
                        <select aria-label="Commune voucher discount type" value={promoType} onChange={(event) => setPromoTypeDrafts((current) => ({ ...current, [communeDraftId]: event.target.value as PromotionCode["discountType"] }))} className={adminField}>
                          <option value="percent">Percent discount</option>
                          <option value="amount">Peso discount</option>
                          <option value="item">Free item(s)</option>
                        </select>
                      </label>
                      {promoType === "item" ? (
                        <label className="block min-w-0 space-y-1.5 text-xs font-medium text-[#586b89]">
                          <span>Free item quantity</span>
                          <input aria-label="Commune free item quantity" type="number" min="1" max="99" step="1" value={itemCount} onChange={(event) => setPromoItemCountDrafts((current) => ({ ...current, [communeDraftId]: Number(event.target.value) }))} className={adminField} />
                        </label>
                      ) : (
                        <label className="block min-w-0 space-y-1.5 text-xs font-medium text-[#586b89]">
                          <span>Discount value</span>
                          <input aria-label="Commune discount value" type="number" min="0.01" max={promoType === "percent" ? 100 : undefined} step="0.01" value={value} onChange={(event) => setPromoValueDrafts((current) => ({ ...current, [communeDraftId]: Number(event.target.value) }))} className={adminField} />
                        </label>
                      )}
                      <label className="block min-w-0 space-y-1.5 text-xs font-medium text-[#586b89]">
                        <span>Quantity</span>
                        <select aria-label="Commune voucher quantity" value={countMode} onChange={(event) => setPromoCountModes((current) => ({ ...current, [communeDraftId]: event.target.value }))} className={adminField}>
                          <option value="1">1 voucher</option><option value="5">5 vouchers</option><option value="10">10 vouchers</option><option value="20">20 vouchers</option><option value="custom">Custom</option>
                        </select>
                        {countMode === "custom" ? <input aria-label="Custom Commune voucher quantity" type="number" min="1" max="100" value={customCount} onChange={(event) => setPromoCustomCounts((current) => ({ ...current, [communeDraftId]: event.target.value }))} className={`${adminField} mt-2`} /> : null}
                      </label>
                      <label className="block min-w-0 space-y-1.5 text-xs font-medium text-[#586b89]">
                        <span>Expires on</span>
                        <input aria-label="Commune voucher expiration date" type="date" min={phDateString()} value={expiry} onChange={(event) => setPromoExpiryDrafts((current) => ({ ...current, [communeDraftId]: event.target.value }))} className={adminField} />
                      </label>
                      <label className="block min-w-0 space-y-1.5 text-xs font-medium text-[#586b89]">
                        <span>Event Host</span>
                        <input aria-label="Event Host" type="text" maxLength={120} value={communeEventHost} onChange={(event) => setCommuneEventHost(event.target.value)} placeholder="Enter event host" className={adminField} />
                      </label>
                      <button
                        type="button"
                        disabled={!canGenerate}
                        onClick={() => startTransition(async () => {
                          const count = countMode === "custom" ? Number(customCount) : Number(countMode);
                          const result = await generateCommunePromotionCodes(promoType, promoType === "item" ? itemCount : value, count, prefix, communeEventHost, expiry);
                          const generatedPromos = result.promos ?? [];
                          if (generatedPromos.length) setCommunePromoCodes((current) => [...generatedPromos, ...current]);
                          setNotice("error" in result && result.error ? (generatedPromos.length ? `${result.error} ${generatedPromos.length} voucher(s) were created.` : result.error) : `${generatedPromos.length} Commune voucher(s) generated.`);
                        })}
                        className="h-12 self-end whitespace-nowrap rounded-xl bg-[#b90c0c] px-5 text-xs font-semibold text-white shadow-[0_5px_14px_rgba(185,12,12,0.18)] transition hover:bg-[#970909] disabled:opacity-40"
                      >Generate codes</button>
                    </div>
                  </div>

                  {selectedVoucherHostGroup ? (
                    <div className="fixed inset-0 z-50 flex items-center justify-center bg-[#17243e]/50 p-4" onMouseDown={(event) => { if (event.target === event.currentTarget) setSelectedVoucherHost(null); }}>
                      <section role="dialog" aria-modal="true" aria-labelledby="commune-voucher-total-title" className="flex max-h-[85vh] w-full max-w-4xl flex-col overflow-hidden rounded-2xl bg-white shadow-xl">
                        <header className="flex shrink-0 items-start justify-between gap-4 border-b border-[#e3eaf4] px-6 py-5">
                          <div>
                            <h2 id="commune-voucher-total-title" className="text-lg font-bold text-[#17243e]">{selectedVoucherHostGroup.host} · Voucher order item totals</h2>
                            <p className="mt-1 text-sm text-[#7587a3]">Redeemed voucher orders for this event host that were not voided.</p>
                          </div>
                          <button type="button" onClick={() => setSelectedVoucherHost(null)} className="rounded-lg px-3 py-1.5 text-sm font-semibold text-[#536783] hover:bg-[#f3f6fb]">Close</button>
                        </header>
                        <div className="min-h-0 flex-1 space-y-4 overflow-y-auto p-6">
                          {selectedVoucherHostGroup.orders.length ? selectedVoucherHostGroup.orders.map(({ order, voucherCode, items, itemsTotal }) => (
                            <article key={order.id} className="overflow-hidden rounded-xl border border-[#e3eaf4]">
                              <div className="flex flex-wrap items-center justify-between gap-2 bg-[#f8faff] px-4 py-3 text-sm">
                                <div className="space-x-2"><span className="font-bold text-[#17243e]">Order {order.ticketNo || order.id}</span><span className="text-[#7587a3]">ID: {order.id}</span></div>
                                <span className="font-semibold text-[#4353ff]">Voucher: {voucherCode}</span>
                              </div>
                              <div className="divide-y divide-[#edf1f7]">
                                {items.map((item, index) => (
                                  <div key={`${item.productId}-${index}`} className="flex justify-between gap-4 px-4 py-3 text-sm">
                                    <span className="text-[#405475]">{item.name}{item.style ? ` (${item.style})` : ""} × {item.qty}</span>
                                    <span className="shrink-0 font-medium text-[#17243e]">{formatMoney(item.lineTotal)}</span>
                                  </div>
                                ))}
                              </div>
                              <div className="flex justify-between border-t border-[#e3eaf4] px-4 py-3 text-sm font-bold text-[#17243e]"><span>Total of items</span><span>{formatMoney(itemsTotal)}</span></div>
                              <div className="flex justify-between border-t border-[#e3eaf4] bg-emerald-50/60 px-4 py-3 text-sm font-bold text-emerald-800"><span>Discount to pay for this voucher</span><span>{formatMoney(order.discount ?? 0)}</span></div>
                            </article>
                          )) : <p className="text-sm text-[#7587a3]">No redeemed voucher orders that were not voided.</p>}
                        </div>
                        <footer className="shrink-0 space-y-2 border-t border-[#e3eaf4] bg-[#f8faff] px-6 py-4 font-bold text-[#17243e]">
                          <div className="flex justify-between"><span>Total discounts to pay Commune · {selectedVoucherHostGroup.host}</span><span className="text-emerald-700">{formatMoney(selectedVoucherHostGroup.totalDiscountGiven)}</span></div>
                          <div className="flex justify-between text-sm text-[#536783]"><span>Total value of items ordered</span><span>{formatMoney(selectedVoucherHostGroup.orders.reduce((sum, entry) => sum + entry.itemsTotal, 0))}</span></div>
                          <div className="max-h-[24vh] space-y-3 overflow-y-auto border-t border-[#e3eaf4] pt-3">
                            <p className="text-sm font-semibold text-[#17243e]">Payment Status · {selectedVoucherHostGroup.host}</p>
                            {selectedVoucherHostGroup.batches.map(({ batchId, promos: batchPromos }) => (
                              <div key={batchId ?? batchPromos[0]?.code} className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-[#e3eaf4] bg-white px-3 py-2.5">
                                <span className="text-sm font-medium text-[#536783]">{batchPromos.length} voucher{batchPromos.length === 1 ? "" : "s"}</span>
                                <select
                                  aria-label={`Payment status for ${selectedVoucherHostGroup.host} batch ${batchId ?? "legacy"}`}
                                  value={batchPromos[0]?.paymentStatus === "paid" ? "paid" : "not_paid"}
                                  disabled={!batchId || pending}
                                  onChange={(event) => {
                                    if (!batchId) return;
                                    const nextStatus = event.target.value as "not_paid" | "paid";
                                    startTransition(async () => {
                                      const result = await updateCommunePromotionBatchPaymentStatus(batchId, nextStatus);
                                      if ("error" in result && result.error) { setNotice(result.error); return; }
                                      setCommunePromoCodes((current) => current.map((promo) => promo.batchId === batchId ? { ...promo, paymentStatus: nextStatus } : promo));
                                      setNotice(`${selectedVoucherHostGroup.host} promotion payment status updated to ${nextStatus === "paid" ? "Paid" : "Not Paid"}.`);
                                    });
                                  }}
                                  className="h-9 rounded-lg border border-[#dce6f4] bg-white px-3 text-xs font-medium text-[#243a5e] outline-none focus:border-[#5363ff] disabled:opacity-60"
                                >
                                  <option value="not_paid">Not Paid</option>
                                  <option value="paid">Paid</option>
                                </select>
                              </div>
                            ))}
                            {!selectedVoucherHostGroup.batches.length ? <p className="text-xs font-normal text-[#8091ab]">No promo batches available.</p> : null}
                          </div>
                        </footer>
                      </section>
                    </div>
                  ) : null}

                  <div className="divide-y divide-[#e3eaf4]">
                    {promos.length === 0 ? <p className="p-4 text-sm text-neutral-500">No Commune website vouchers generated.</p> : hostVoucherGroups.map(({ host, hostPromos, batches, totalDiscountGiven, hasActiveVouchers }) => (
                      <section key={host} aria-label={`Commune vouchers for ${host}`} className="overflow-hidden py-4 first:pt-0 last:pb-0">
                        <div className="flex flex-wrap items-center justify-between gap-4 rounded-lg bg-[#f8faff] px-4 py-3">
                          <div className="text-sm font-semibold text-[#172849]">{host}<span className="ml-2 text-xs font-medium text-[#8091ab]">{hostPromos.length} voucher{hostPromos.length === 1 ? "" : "s"}</span></div>
                          <div className="flex items-center gap-4">
                            <div className="text-right">
                              <p className="text-xs font-medium text-[#7587a3]">Total discounts given</p>
                              <p className="text-lg font-bold text-emerald-700">{communeDiscountSummaryLoading ? "Loading…" : communeDiscountSummaryError ? "Unavailable" : formatMoney(totalDiscountGiven)}</p>
                              {communeDiscountSummaryError ? <p className="text-xs text-rose-600">{communeDiscountSummaryError}</p> : null}
                            </div>
                            <div className="flex flex-wrap items-center gap-2">
                              <button type="button" onClick={() => setSelectedVoucherHost(host)} disabled={communeDiscountSummaryLoading || !communeDiscountSummary} className="rounded-lg border border-emerald-200 bg-white px-4 py-2.5 text-sm font-semibold text-emerald-800 transition hover:bg-emerald-50 disabled:cursor-not-allowed disabled:opacity-50">View Total</button>
                              <button type="button" disabled={pending || !hasActiveVouchers || host === "No host assigned"} title={!hasActiveVouchers ? "There are no unused active vouchers for this event." : undefined} onClick={() => {
                                if (!window.confirm(`End the event for ${host}? All unused vouchers for this event will expire immediately. Redeemed vouchers and order history will remain.`)) return;
                                startTransition(async () => {
                                  const result = await endCommunePromotionEvent(host);
                                  if (!result.ok) { setNotice(result.error); return; }
                                  setCommunePromoCodes((current) => current.map((promo) => promo.eventHost?.trim() === host && !promo.redeemedAt && promo.expiresAt && Date.parse(promo.expiresAt) > Date.parse(result.endedAt) ? { ...promo, expiresAt: result.endedAt } : promo));
                                  setNotice(`${host} event ended. ${result.affectedCount} unused voucher(s) expired.`);
                                });
                              }} className="rounded-lg border border-rose-200 bg-white px-4 py-2.5 text-sm font-semibold text-rose-700 transition hover:bg-rose-50 disabled:cursor-not-allowed disabled:opacity-50">End Event</button>
                            </div>
                          </div>
                        </div>
                        <div className="hidden grid-cols-[1.2fr_0.75fr_0.75fr_0.9fr_1.1fr_1fr_0.9fr_0.8fr_auto] gap-3 border-t border-[#e3eaf4] bg-[#f5f8fc] px-4 py-2.5 text-[10px] font-semibold tracking-wide text-[#7587a3] uppercase sm:grid"><span>Code</span><span>Discount</span><span>Prefix</span><span>Total items</span><span>Event Host</span><span>Expires</span><span>Approval</span><span>Status</span><span className="text-right">Actions</span></div>
                        {batches.map(({ batchId, promos: batchPromos }) => (
                          <div key={batchId ?? batchPromos[0]?.code} className="border-t border-[#edf1f7] first:border-t-0">
                            <div className="flex flex-wrap items-center justify-between gap-3 bg-[#fbfcff] px-4 py-2.5">
                              <span className="text-xs font-semibold text-[#536783]">Promo batch · {batchPromos.length} voucher{batchPromos.length === 1 ? "" : "s"}</span>
                            </div>
                            <div className="divide-y divide-[#edf1f7]">{batchPromos.map((promo) => (
                      <div key={promo.code} className="grid grid-cols-2 gap-2 border-t border-[#edf1f7] px-4 py-3 text-xs text-[#405475] sm:grid-cols-[1.2fr_0.75fr_0.75fr_0.9fr_1.1fr_1fr_0.9fr_0.8fr_auto] sm:items-center sm:gap-3">
                        <span className="font-mono font-semibold tracking-widest">{promo.code}</span>
                        <span>{promo.discountType === "item" ? `${promo.discountValue || 1} free item${(promo.discountValue || 1) === 1 ? "" : "s"}` : promo.discountType === "percent" ? `${promo.discountValue}% off` : `PHP ${promo.discountValue} off`}</span>
                        <span>{promo.code.includes("-") ? promo.code.split("-").slice(0, -1).join("-") : "—"}</span>
                        <span>{promo.discountType === "item" ? `${promo.discountValue || 1} free item${(promo.discountValue || 1) === 1 ? "" : "s"}` : "-"}</span>
                        <span>{promo.eventHost?.trim() || "—"}</span>
                        <span>{promo.expiresAt ? phDateString(promo.expiresAt) : "No expiry"}</span>
                        <span className={promo.approvalStatus === "pending" ? "font-semibold text-amber-700" : promo.approvalStatus === "declined" ? "font-semibold text-rose-700" : "font-semibold text-emerald-700"}>{promo.approvalStatus === "pending" ? "Pending" : promo.approvalStatus === "declined" ? "Declined" : "Approved"}</span>
                        <span className={promo.redeemedAt ? "text-neutral-400" : isPromotionExpired(promo) ? "text-amber-700" : "text-emerald-700"}>{promo.redeemedAt ? "Used" : isPromotionExpired(promo) ? "Expired" : "Active"}</span>
                        <button type="button" aria-label={`Delete Commune voucher ${promo.code}`} title={promo.redeemedAt ? "Used vouchers cannot be deleted." : undefined} disabled={pending || Boolean(promo.redeemedAt)} onClick={() => {
                          if (!window.confirm(`Delete promo voucher ${promo.code}?`)) return;
                          startTransition(async () => {
                            const result = await deleteCommunePromotionCode(promo.code);
                            if ("error" in result && result.error) { setNotice(result.error); return; }
                            setCommunePromoCodes((current) => current.filter((entry) => entry.code !== promo.code));
                            setNotice(`Promo voucher ${promo.code} deleted.`);
                          });
                        }} className="justify-self-start rounded-full border border-[#ffd6d9] bg-[#fff8f8] px-3 py-1.5 text-[11px] font-medium text-[#f04452] transition hover:bg-[#fff0f1] disabled:cursor-not-allowed disabled:opacity-40 sm:justify-self-end">{promo.redeemedAt ? "Used" : "Delete"}</button>
                      </div>
                            ))}</div>
                          </div>
                        ))}
                      </section>
                    ))}
                  </div>
              </div>
            </section>
          );
        })() : null}

        {tab === "inout" ? (
          <>
            <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
              <h1 className="text-xl font-semibold tracking-tight">Staff in / out</h1>

              {/* Date Selector placed right next to Staff in / out heading */}
              <div className="flex items-center self-start sm:self-auto rounded-xl border border-neutral-200 bg-white px-3.5 py-2 shadow-sm">
                <div className="relative flex items-center gap-2 cursor-pointer">
                  <span className="text-sm font-medium text-neutral-400 select-none">Date:</span>
                  <input
                    type="date"
                    value={selectedDate}
                    onChange={(event) => setSelectedDate(event.target.value)}
                    className="absolute inset-0 opacity-0 cursor-pointer w-full h-full"
                  />
                  <span className="text-sm font-medium text-neutral-700 select-none">
                    {selectedDate ? new Date(selectedDate).toLocaleDateString('en-US', { timeZone: 'Asia/Manila', month: '2-digit', day: '2-digit', year: 'numeric' }) : "Select date"}
                  </span>
                  <svg viewBox="0 0 24 24" className="h-4 w-4 text-neutral-500 ml-1 pointer-events-none" fill="none" stroke="currentColor">
                    <rect x="3" y="4" width="18" height="18" rx="2" ry="2" strokeWidth="1.7" />
                    <line x1="16" y1="2" x2="16" y2="6" strokeWidth="1.7" strokeLinecap="round" />
                    <line x1="8" y1="2" x2="8" y2="6" strokeWidth="1.7" strokeLinecap="round" />
                    <line x1="3" y1="10" x2="21" y2="10" strokeWidth="1.7" />
                  </svg>
                </div>
              </div>
            </div>

            <form
              className="flex flex-col gap-2 rounded-2xl border border-neutral-200 bg-white p-3 sm:flex-row sm:items-center sm:justify-between"
              onSubmit={(event) => event.preventDefault()}
            >
              <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
                <select
                  value={punchUserId}
                  onChange={(event) => setPunchUserId(event.target.value)}
                  className={`${field} sm:max-w-xs`}
                >
                  <option value="">Select staff</option>
                  {floorStaff.map((user) => (
                    <option key={user.id} value={user.id}>
                      {user.name}
                    </option>
                  ))}
                </select>
                <div className="flex gap-2">
                  <button
                    type="button"
                    disabled={pending || !punchUserId || selectedStaffIsOnShift}
                    onClick={() =>
                      startTransition(async () => {
                        const result = await punchStaff(punchUserId, "login");
                        if (result && "error" in result && result.error) {
                          setNotice(typeof result.error === "string" ? result.error : "Could not record.");
                          return;
                        }
                        setNotice(null);
                      })
                    }
                    className="rounded-full bg-black px-4 py-2 text-sm font-medium text-white disabled:opacity-40"
                  >
                    In
                  </button>
                  <button
                    type="button"
                    disabled={pending || !punchUserId || !selectedStaffIsOnShift}
                    onClick={() =>
                      startTransition(async () => {
                        const result = await punchStaff(punchUserId, "logout");
                        if (result && "error" in result && result.error) {
                          setNotice(typeof result.error === "string" ? result.error : "Could not record.");
                          return;
                        }
                        setNotice(null);
                      })
                    }
                    className="rounded-full border border-neutral-300 px-4 py-2 text-sm font-medium hover:border-black disabled:opacity-40"
                  >
                    Out
                  </button>
                </div>
              </div>
            </form>
            <div className="overflow-x-auto rounded-2xl border border-neutral-200 bg-white">
              <table className="w-full min-w-[520px] text-left text-sm">
                <thead>
                  <tr className="border-b border-neutral-200 text-xs font-medium tracking-wide text-neutral-400 uppercase">
                    <th className="px-4 py-3">Staff</th>
                    <th className="px-4 py-3">In</th>
                    <th className="px-4 py-3">Out</th>
                    <th className="px-4 py-3 text-right"> </th>
                  </tr>
                </thead>
                <tbody>
                  {sessions.length === 0 ? (
                    <tr>
                      <td colSpan={4} className="px-4 py-8 text-center text-sm text-neutral-400">
                        No in / out records for this date.
                      </td>
                    </tr>
                  ) : (
                    sessions.map((row) => {
                      const isEditing = editingSessionId === row.id;
                      return (
                        <tr key={row.id} className="border-t border-neutral-100">
                          <td className="px-4 py-3">
                            <p className="font-medium">{row.name}</p>
                            <p className="text-xs text-neutral-400">{row.role === "pos_cashier" ? "Cashier" : "Barista"} · {row.username}</p>
                          </td>
                          <td className="px-4 py-3 whitespace-nowrap">
                            {isEditing && row.loginId ? (
                              <input
                                type="datetime-local"
                                value={editLoginAt}
                                onChange={(event) => setEditLoginAt(event.target.value)}
                                className={`${field} min-w-48`}
                                required
                              />
                            ) : row.loginAt ? phDateTimeLabel(row.loginAt) : "—"}
                          </td>
                          <td className="px-4 py-3 whitespace-nowrap">
                            {isEditing && row.logoutId ? (
                              <input
                                type="datetime-local"
                                value={editLogoutAt}
                                onChange={(event) => setEditLogoutAt(event.target.value)}
                                className={`${field} min-w-48`}
                                required
                              />
                            ) : row.logoutAt ? phDateTimeLabel(row.logoutAt) : "Still in"}
                          </td>
                          <td className="px-4 py-3">
                            <div className="flex justify-end gap-2 text-xs font-medium">
                              {isEditing ? (
                                <>
                                  <button
                                    type="button"
                                    disabled={pending}
                                    onClick={() =>
                                      startTransition(async () => {
                                        const result = await updateStaffSessionTimes({
                                          loginId: row.loginId ?? undefined,
                                          loginAt: row.loginId ? editLoginAt : undefined,
                                          logoutId: row.logoutId ?? undefined,
                                          logoutAt: row.logoutId ? editLogoutAt : undefined,
                                        });
                                        if (result && "error" in result && result.error) {
                                          setNotice(typeof result.error === "string" ? result.error : "Could not save.");
                                          return;
                                        }
                                        setEditingSessionId(null);
                                        setNotice(null);
                                      })
                                    }
                                    className="hover:underline disabled:opacity-40"
                                  >
                                    Save
                                  </button>
                                  <button
                                    type="button"
                                    disabled={pending}
                                    onClick={() => setEditingSessionId(null)}
                                    className="text-neutral-500 hover:underline disabled:opacity-40"
                                  >
                                    Cancel
                                  </button>
                                </>
                              ) : (
                                <>
                                  <button
                                    type="button"
                                    disabled={pending}
                                    onClick={() => startSessionEdit(row)}
                                    className="hover:underline disabled:opacity-40"
                                  >
                                    Edit
                                  </button>
                                  <button
                                    type="button"
                                    aria-label={`Delete in / out record for ${row.name}`}
                                    title="Delete in / out record"
                                    disabled={pending}
                                    onClick={() => {
                                      startTransition(async () => {
                                        const result = await deleteStaffSession({
                                          loginId: row.loginId ?? undefined,
                                          logoutId: row.logoutId ?? undefined,
                                        });
                                        if (result && "error" in result && result.error) {
                                          setNotice(result.error);
                                          return;
                                        }
                                        setNotice(null);
                                      });
                                    }}
                                    className="inline-flex size-8 items-center justify-center rounded-full border border-neutral-300 bg-white text-neutral-700 shadow-sm hover:border-red-300 hover:bg-red-50 hover:text-red-600 disabled:opacity-40"
                                  >
                                    <svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" aria-hidden="true">
                                      <path d="M5 7h14M10 7V5h4v2M8 7l1 12h6l1-12" strokeWidth="1.7" />
                                    </svg>
                                    <span className="sr-only">Delete</span>
                                  </button>
                                </>
                              )}
                            </div>
                          </td>
                        </tr>
                      );
                    })
                  )}
                </tbody>
              </table>
            </div>
          </>
        ) : null}

        {tab === "off" ? (
          <>
            <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
              <h1 className="text-xl font-semibold tracking-tight">Request off</h1>
              
              {/* Date Selector for Request off matching In / Out style */}
              <div className="flex items-center self-start sm:self-auto rounded-xl border border-neutral-200 bg-white px-3.5 py-2 shadow-sm">
                <div className="relative flex items-center gap-2 cursor-pointer">
                  <span className="text-sm font-medium text-neutral-400 select-none">Date:</span>
                  <input
                    type="date"
                    value={offSelectedDate}
                    onChange={(event) => setOffSelectedDate(event.target.value)}
                    className="absolute inset-0 opacity-0 cursor-pointer w-full h-full"
                  />
                  <span className="text-sm font-medium text-neutral-700 select-none">
                    {offSelectedDate ? new Date(offSelectedDate).toLocaleDateString('en-US', { timeZone: 'Asia/Manila', month: '2-digit', day: '2-digit', year: 'numeric' }) : "Select date"}
                  </span>
                  <svg viewBox="0 0 24 24" className="h-4 w-4 text-neutral-500 ml-1 pointer-events-none" fill="none" stroke="currentColor">
                    <rect x="3" y="4" width="18" height="18" rx="2" ry="2" strokeWidth="1.7" />
                    <line x1="16" y1="2" x2="16" y2="6" strokeWidth="1.7" strokeLinecap="round" />
                    <line x1="8" y1="2" x2="8" y2="6" strokeWidth="1.7" strokeLinecap="round" />
                    <line x1="3" y1="10" x2="21" y2="10" strokeWidth="1.7" />
                  </svg>
                </div>
              </div>
            </div>

            <form
              className="grid gap-3 rounded-2xl border border-neutral-200 bg-white p-4 sm:grid-cols-4 sm:items-end"
              onSubmit={(event) => {
                event.preventDefault();
                startTransition(async () => {
                  const result = await createOffRequest({ userId: offUserId, date: offDate, reason: offReason });
                  if (result && "error" in result && result.error) {
                    setNotice(typeof result.error === "string" ? result.error : "Could not save.");
                    return;
                  }
                  setOffReason("");
                  setNotice(null);
                });
              }}
            >
              <label className="text-xs font-medium text-neutral-600">
                <span className="mb-1.5 block">Staff</span>
                <select value={offUserId} onChange={(event) => setOffUserId(event.target.value)} className={field} required>
                  <option value="">Select staff</option>
                  {floorStaff.map((user) => (
                    <option key={user.id} value={user.id}>
                      {user.name}
                    </option>
                  ))}
                </select>
              </label>
              <label className="text-xs font-medium text-neutral-600">
                <span className="mb-1.5 block">Date</span>
                <input type="date" value={offDate} onChange={(event) => setOffDate(event.target.value)} className={field} required />
              </label>
              <label className="text-xs font-medium text-neutral-600 sm:col-span-1">
                <span className="mb-1.5 block">Reason</span>
                <input value={offReason} onChange={(event) => setOffReason(event.target.value)} className={field} required />
              </label>
              <button
                type="submit"
                disabled={pending}
                className="rounded-full bg-black px-4 py-2.5 text-sm font-medium text-white hover:bg-neutral-800 disabled:opacity-40"
              >
                Add
              </button>
            </form>
            <div className="overflow-x-auto rounded-2xl border border-neutral-200 bg-white">
              <table className="w-full min-w-[640px] text-left text-sm">
                <thead>
                  <tr className="border-b border-neutral-200 text-xs font-medium tracking-wide text-neutral-400 uppercase">
                    <th className="px-4 py-3">Staff</th>
                    <th className="px-4 py-3">Date</th>
                    <th className="px-4 py-3">Reason</th>
                    <th className="px-4 py-3">Status</th>
                    <th className="px-4 py-3 text-right"> </th>
                  </tr>
                </thead>
                <tbody>
                  {requests.length === 0 ? (
                    <tr>
                      <td colSpan={5} className="px-4 py-8 text-center text-sm text-neutral-400">
                        No off requests for this date.
                      </td>
                    </tr>
                  ) : (
                    requests.map((request) => (
                      <tr key={request.id} className="border-t border-neutral-100">
                        <td className="px-4 py-3 font-medium">{request.name}</td>
                        <td className="px-4 py-3 whitespace-nowrap">{phDateTimeLabel(request.date)}</td>
                        <td className="px-4 py-3 text-neutral-600">{request.reason}</td>
                        <td className="px-4 py-3 capitalize">{request.status}</td>
                        <td className="px-4 py-3">
                          <div className="flex justify-end gap-2 text-xs font-medium">
                            {request.status === "pending" ? (
                              <>
                                <button
                                  type="button"
                                  disabled={pending}
                                  onClick={() => startTransition(async () => { await setOffRequestStatus(request.id, "approved"); })}
                                  className="hover:underline"
                                >
                                  Approve
                                </button>
                                <button
                                  type="button"
                                  disabled={pending}
                                  onClick={() => startTransition(async () => { await setOffRequestStatus(request.id, "denied"); })}
                                  className="hover:underline"
                                >
                                  Deny
                                </button>
                              </>
                            ) : null}
                            <button
                              type="button"
                              disabled={pending}
                              onClick={() => startTransition(async () => { await deleteOffRequest(request.id); })}
                              className="text-red-600 hover:underline"
                            >
                              Delete
                            </button>
                          </div>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </>
        ) : null}

        {tab === "settings" ? (
          <>
            <div className={isAdminConsole ? "rounded-2xl border border-[#e4ebf5] bg-white p-5 shadow-[0_8px_30px_rgba(37,75,130,0.06)] sm:p-6" : "rounded-2xl border border-neutral-200 bg-white p-4 sm:p-5"}>
              <div className="flex items-start gap-3">
                {isAdminConsole ? (
                  <span className="mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-xl bg-[#eef2ff] text-[#4353ff]">
                    <svg viewBox="0 0 24 24" className="size-5" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true">
                      <path d="M12 3 20 6v5c0 5-3.4 8.2-8 10-4.6-1.8-8-5-8-10V6l8-3Z" strokeLinejoin="round" />
                      <path d="m8.5 12 2.2 2.2 4.8-4.8" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                  </span>
                ) : null}
                <div className="min-w-0 flex-1">
                  <h1 className="text-xl font-semibold tracking-tight text-[#14213d]">{selectedPermissionOwnerId ? "Owner Permissions" : "Settings"}</h1>
                  <p className="mt-1 text-sm text-neutral-500">
                    {selectedPermissionOwnerId ? "Choose which POS features this Owner account can use." : "Select an Owner to view their permissions."}
                  </p>
                </div>
              </div>
            </div>
            {!selectedPermissionOwnerId ? (
              <div className="divide-y divide-neutral-100 overflow-hidden rounded-2xl border border-neutral-200 bg-white">
                {ownerUsers.length === 0 ? (
                  <p className="p-4 text-sm text-neutral-500">No Owner accounts found.</p>
                ) : ownerUsers.map((owner) => (
                  <div key={owner.id} className="flex items-center justify-between gap-3 px-4 py-4 sm:px-5">
                    <p className="truncate text-sm font-medium">{owner.name}</p>
                    <button
                      type="button"
                      onClick={() => setSelectedPermissionOwnerId(owner.id)}
                      className="shrink-0 rounded-full border border-neutral-300 px-3 py-2 text-xs font-medium text-neutral-700 hover:border-black hover:text-black"
                    >
                      View Permissions
                    </button>
                  </div>
                ))}
              </div>
            ) : (() => {
                const owner = ownerUsers.find((user) => user.id === selectedPermissionOwnerId);
                if (!owner) return <p className="text-sm text-neutral-500">Owner account not found.</p>;
                const permissions = permissionState[owner.id] ?? { ...DEFAULT_STAFF_PERMISSIONS, ...owner.permissions };
                return (
                  <section className={isAdminConsole ? "space-y-5 rounded-2xl border border-[#e4ebf5] bg-white p-4 shadow-[0_8px_30px_rgba(37,75,130,0.06)] sm:p-6" : "space-y-3 rounded-2xl border border-neutral-200 bg-white p-4 sm:p-5"}>
                    <div className="flex items-center justify-between gap-3">
                      <h2 className="font-semibold text-[#14213d]">{owner.name}</h2>
                    <button type="button" onClick={() => setSelectedPermissionOwnerId(null)} className={isAdminConsole ? "rounded-lg border border-[#dce5f2] px-3 py-1.5 text-xs font-medium text-[#516783] transition hover:border-[#58789d] hover:text-[#243a5e]" : "text-xs font-medium text-neutral-600 hover:text-black"}>Back</button>
                    </div>
                    <div className={isAdminConsole ? "grid gap-3 lg:grid-cols-3" : "grid gap-2 sm:grid-cols-2 lg:grid-cols-3"}>
                      {(isAdminConsole ? adminPermissionGroups : [{ title: "Permissions", description: "", icon: "inventory" as const, permissions: permissionOptions.map(({ key }) => key) }]).map((group) => (
                        <section key={group.title} className={isAdminConsole ? "rounded-xl border border-[#e1eaf6] bg-gradient-to-b from-white to-[#fbfdff] p-4" : "contents"}>
                          {isAdminConsole ? (
                            <div className="mb-3 flex items-start gap-2.5">
                              <span className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-[#f0f4fb] text-[#263c61]">
                                {group.icon === "inventory" ? (
                                  <svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true"><path d="m12 3 9 5-9 5-9-5 9-5Z" strokeLinejoin="round"/><path d="M3 8v9l9 5 9-5V8M12 13v9" strokeLinejoin="round"/></svg>
                                ) : group.icon === "operations" ? (
                                  <svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true"><path d="M7 8V3h10v5M6 18H4a2 2 0 0 1-2-2v-5a3 3 0 0 1 3-3h14a3 3 0 0 1 3 3v5a2 2 0 0 1-2 2h-2" strokeLinejoin="round"/><path d="M6 14h12v7H6zM18 11h.01" strokeLinejoin="round"/></svg>
                                ) : (
                                  <svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true"><circle cx="9" cy="8" r="3"/><path d="M3 20v-1a6 6 0 0 1 12 0v1M17 11a3 3 0 1 0 0-6M18 14a5 5 0 0 1 3 5v1" strokeLinecap="round"/></svg>
                                )}
                              </span>
                              <div>
                                <h3 className="text-sm font-semibold text-[#172849]">{group.title}</h3>
                                <p className="mt-0.5 text-[11px] leading-4 text-[#8091ab]">{group.description}</p>
                              </div>
                            </div>
                          ) : null}
                          <div className="space-y-0.5">
                            {group.permissions.map((key) => {
                              const label = permissionOptions.find((option) => option.key === key)?.label ?? key;
                              return (
                                <label key={key} className={isAdminConsole ? "flex min-h-9 cursor-pointer items-center justify-between gap-3 rounded-lg px-1.5 text-xs text-[#364b6d] transition hover:bg-[#f5f8fd]" : "flex cursor-pointer items-center gap-3 rounded-lg border border-neutral-200 px-3 py-2.5 text-sm"}>
                                  <span>{label}</span>
                                  <input
                                    type="checkbox"
                                    checked={permissions[key]}
                                    disabled={pending}
                                    onChange={(event) => {
                                      const next = { ...permissions, [key]: event.target.checked };
                                      setPermissionState((current) => ({ ...current, [owner.id]: next }));
                                      startTransition(async () => {
                                        const result = await updateOwnerPermissions(owner.id, next);
                                        if (result && "error" in result && result.error) {
                                          setPermissionState((current) => ({ ...current, [owner.id]: permissions }));
                                          setNotice(result.error);
                                          return;
                                        }
                                        setNotice(null);
                                      });
                                    }}
                                    className={isAdminConsole ? "peer sr-only" : "size-4 accent-black"}
                                  />
                          {isAdminConsole ? <span aria-hidden="true" className={`relative h-5 w-9 shrink-0 rounded-full transition peer-focus-visible:ring-2 peer-focus-visible:ring-[#58789d] peer-focus-visible:ring-offset-2 ${permissions[key] ? "bg-[#101d37]" : "bg-[#cbd5e1]"}`}><span className={`absolute top-0.5 size-4 rounded-full bg-white shadow-sm transition ${permissions[key] ? "left-[18px]" : "left-0.5"}`} /></span> : null}
                                </label>
                              );
                            })}
                          </div>
                        </section>
                      ))}
                    </div>
                    <div className={isAdminConsole ? "space-y-4 border-t border-[#e7edf6] pt-5" : "space-y-3 border-t border-neutral-200 pt-4"}>
                      <div>
                        <div className="flex items-center gap-2.5">
                          {isAdminConsole ? <span className="flex size-8 items-center justify-center rounded-lg bg-[#eef2ff] text-[#4353ff]"><svg viewBox="0 0 24 24" className="size-4" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true"><path d="M20 12v8H4v-8M2 7h20v5H2zM12 20V7" strokeLinejoin="round"/><path d="M12 7H7.5a2.5 2.5 0 1 1 2.5-2.5C10 6 12 7 12 7ZM12 7h4.5A2.5 2.5 0 1 0 14 4.5C14 6 12 7 12 7Z" strokeLinejoin="round"/></svg></span> : null}
                          <h3 className="text-sm font-semibold text-[#172849]">{isAdminConsole ? "Generate Promotion Codes" : "Generate promo vouchers"}</h3>
                        </div>
                        <p className="text-xs text-neutral-500">Each voucher can only be redeemed once. Add a prefix, then the system generates a unique 6-character suffix.</p>
                      </div>
                      <div className={`grid gap-x-3 gap-y-2 sm:grid-cols-2 ${isAdminConsole ? `items-end ${(promoTypeDrafts[owner.id] ?? "percent") === "item" ? "xl:grid-cols-[minmax(150px,1fr)_minmax(170px,1.1fr)_140px_minmax(170px,1.2fr)_minmax(170px,1fr)_auto]" : "xl:grid-cols-[minmax(150px,1fr)_minmax(170px,1.1fr)_minmax(140px,1fr)_minmax(170px,1.2fr)_minmax(170px,1fr)_auto]"}` : "xl:grid-cols-[1fr_1fr_1fr_1.4fr_1fr_auto]"}`}>
                        <label className={isAdminConsole ? "block min-w-0 space-y-1.5 text-xs font-medium text-[#586b89]" : "block text-xs font-medium text-neutral-600"}>
                          <span className={isAdminConsole ? "block" : "sr-only"}>Prefix</span>
                          <input
                            aria-label="Promo voucher prefix"
                            type="text"
                            value={promoPrefixDrafts[owner.id] ?? "SYNORRA"}
                            maxLength={16}
                            placeholder="Voucher prefix"
                            onChange={(event) => setPromoPrefixDrafts((current) => ({ ...current, [owner.id]: event.target.value.toUpperCase() }))}
                            className={isAdminConsole ? adminField : field}
                          />
                        </label>
                        {isAdminConsole ? <label className="block min-w-0 space-y-1.5 text-xs font-medium text-[#586b89]">
                          <span className="block">Discount type</span>
                          <select
                            aria-label="Promotion discount type"
                            value={promoTypeDrafts[owner.id] ?? "percent"}
                            onChange={(event) => setPromoTypeDrafts((current) => ({ ...current, [owner.id]: event.target.value as PromotionCode["discountType"] }))}
                            className={adminField}
                          >
                            <option value="percent">Percent discount</option>
                            <option value="amount">Peso discount</option>
                            <option value="item">Free item(s)</option>
                          </select>
                        </label> : <select
                          aria-label="Promotion discount type"
                          value={promoTypeDrafts[owner.id] ?? "percent"}
                          onChange={(event) => setPromoTypeDrafts((current) => ({ ...current, [owner.id]: event.target.value as PromotionCode["discountType"] }))}
                          className={field}
                        >
                          <option value="percent">Percent discount</option>
                          <option value="amount">Peso discount</option>
                          <option value="item">Free item(s)</option>
                        </select>}
                        {(promoTypeDrafts[owner.id] ?? "percent") !== "item" ? (
                          isAdminConsole ? <label className="block min-w-0 space-y-1.5 text-xs font-medium text-[#586b89]">
                            <span className="block">Discount value</span>
                            <input
                              aria-label="Promotion discount value"
                              type="number"
                              min="0.01"
                              max={(promoTypeDrafts[owner.id] ?? "percent") === "percent" ? 100 : undefined}
                              step="0.01"
                              value={promoValueDrafts[owner.id] ?? "10"}
                              onChange={(event) => setPromoValueDrafts((current) => ({ ...current, [owner.id]: Number(event.target.value) }))}
                              className={adminField}
                            />
                          </label> : <input
                              aria-label="Promotion discount value"
                              type="number"
                              min="0.01"
                              max={(promoTypeDrafts[owner.id] ?? "percent") === "percent" ? 100 : undefined}
                              step="0.01"
                              value={promoValueDrafts[owner.id] ?? "10"}
                              onChange={(event) => setPromoValueDrafts((current) => ({ ...current, [owner.id]: Number(event.target.value) }))}
                              className={field}
                            />
                        ) : (
                          <label className={isAdminConsole ? "block min-w-0 space-y-1.5 text-xs font-medium text-[#586b89]" : "block text-xs font-medium text-neutral-600"}>
                            <span className={isAdminConsole ? "block whitespace-nowrap" : "mb-1 block"}>Free item quantity</span>
                            <input
                              aria-label="Number of free items per voucher"
                              type="number"
                              min="1"
                              max="99"
                              step="1"
                              value={promoItemCountDrafts[owner.id] ?? 1}
                              onChange={(event) => setPromoItemCountDrafts((current) => ({ ...current, [owner.id]: Number(event.target.value) }))}
                              className={isAdminConsole ? adminField : field}
                            />
                          </label>
                        )}
                        <div className={isAdminConsole ? "min-w-0 space-y-1.5" : "flex gap-2"}>
                          {isAdminConsole ? <span className="block text-xs font-medium text-[#586b89]">Quantity</span> : null}
                          <div className={isAdminConsole ? "flex min-w-0 gap-2" : "contents"}>
                            <select
                              aria-label="Number of promo vouchers"
                              value={promoCountModes[owner.id] ?? "5"}
                              onChange={(event) => setPromoCountModes((current) => ({ ...current, [owner.id]: event.target.value }))}
                              className={isAdminConsole ? `${adminField} flex-1` : field}
                            >
                              <option value="1">1 voucher</option>
                              <option value="5">5 vouchers</option>
                              <option value="10">10 vouchers</option>
                              <option value="20">20 vouchers</option>
                              <option value="custom">Custom</option>
                            </select>
                            {(promoCountModes[owner.id] ?? "5") === "custom" ? (
                              <input
                                aria-label="Custom number of promo vouchers"
                                type="number"
                                min="1"
                                max="100"
                                step="1"
                                value={promoCustomCounts[owner.id] ?? "25"}
                                onChange={(event) => setPromoCustomCounts((current) => ({ ...current, [owner.id]: event.target.value }))}
                                className={`${isAdminConsole ? adminField : field} max-w-24`}
                              />
                            ) : null}
                          </div>
                        </div>
                        <label className={isAdminConsole ? "block min-w-0 space-y-1.5 text-xs font-medium text-[#586b89]" : "block text-xs font-medium text-neutral-600"}>
                          <span className={isAdminConsole ? "block" : "mb-1 block"}>Expires on</span>
                          <input
                            aria-label="Promo voucher expiration date"
                            type="date"
                            min={phDateString()}
                            value={promoExpiryDrafts[owner.id] ?? ""}
                            onChange={(event) => setPromoExpiryDrafts((current) => ({ ...current, [owner.id]: event.target.value }))}
                            className={isAdminConsole ? adminField : field}
                          />
                        </label>
                        <button
                          type="button"
                          disabled={pending || !permissions.promotionsEnabled || !promoExpiryDrafts[owner.id] || promoExpiryDrafts[owner.id] < phDateString() || !/^[A-Z0-9]{1,16}$/.test(promoPrefixDrafts[owner.id] ?? "SYNORRA") || ((promoTypeDrafts[owner.id] ?? "percent") === "item" && (!Number.isInteger(promoItemCountDrafts[owner.id] ?? 1) || (promoItemCountDrafts[owner.id] ?? 1) < 1 || (promoItemCountDrafts[owner.id] ?? 1) > 99)) || ((promoCountModes[owner.id] ?? "5") === "custom" && (!/^\d+$/.test(promoCustomCounts[owner.id] ?? "25") || Number(promoCustomCounts[owner.id] ?? "25") < 1 || Number(promoCustomCounts[owner.id] ?? "25") > 100))}
                          onClick={() => startTransition(async () => {
                            const type = promoTypeDrafts[owner.id] ?? "percent";
                            const countMode = promoCountModes[owner.id] ?? "5";
                            const count = countMode === "custom" ? Number(promoCustomCounts[owner.id] ?? "25") : Number(countMode);
                            const result = await generateOwnerPromotionCode(owner.id, type, type === "item" ? promoItemCountDrafts[owner.id] ?? 1 : promoValueDrafts[owner.id] ?? 10, count, promoPrefixDrafts[owner.id] ?? "SYNORRA", promoExpiryDrafts[owner.id] ?? "");
                            const generatedPromos = result.promos ?? [];
                            if (generatedPromos.length > 0) {
                              setPromoCodeRecords((current) => ({
                                ...current,
                                [owner.id]: [...generatedPromos, ...(current[owner.id] ?? [])],
                              }));
                            }
                            if ("error" in result && result.error) {
                              setNotice(generatedPromos.length ? `${result.error} ${generatedPromos.length} voucher(s) were created.` : result.error);
                              return;
                            }
                            setNotice(`${generatedPromos.length} promo voucher(s) generated.`);
                          })}
                          className={isAdminConsole ? "h-12 whitespace-nowrap self-end rounded-xl bg-[#b90c0c] px-5 text-xs font-semibold text-white shadow-[0_5px_14px_rgba(185,12,12,0.18)] transition hover:bg-[#970909] disabled:opacity-40" : "rounded-full bg-[#b90c0c] px-4 py-2 text-xs font-medium text-white hover:bg-[#970909] disabled:opacity-40"}
                        >Generate codes</button>
                      </div>
                      <div className={isAdminConsole ? "overflow-hidden rounded-xl border border-[#e3eaf4]" : "divide-y divide-neutral-100 rounded-xl border border-neutral-200"}>
                        {isAdminConsole ? <div className="hidden grid-cols-[1.35fr_0.8fr_0.8fr_1fr_1fr_0.8fr_auto] gap-3 bg-[#f5f8fc] px-4 py-2.5 text-[10px] font-semibold tracking-wide text-[#7587a3] uppercase sm:grid"><span>Code</span><span>Discount</span><span>Prefix</span><span>Total items</span><span>Expires</span><span>Status</span><span className="text-right">Actions</span></div> : null}
                        {(promoCodeRecords[owner.id] ?? []).length === 0 ? (
                          <p className="p-3 text-xs text-neutral-500">No promo vouchers generated.</p>
                        ) : (promoCodeRecords[owner.id] ?? []).map((promo) => (
                          <div key={promo.code} className={isAdminConsole ? "grid grid-cols-2 gap-2 border-t border-[#edf1f7] px-4 py-3 text-xs text-[#405475] sm:grid-cols-[1.35fr_0.8fr_0.8fr_1fr_1fr_0.8fr_auto] sm:items-center sm:gap-3" : "flex flex-wrap items-center justify-between gap-2 p-3 text-sm"}>
                            <span className="font-mono font-semibold tracking-widest">{promo.code}</span>
                            <span>{promo.discountType === "item" ? `${promo.discountValue || 1} free item${(promo.discountValue || 1) === 1 ? "" : "s"}` : promo.discountType === "percent" ? `${promo.discountValue}% off` : `₱${promo.discountValue} off`}</span>
                            {isAdminConsole ? <span>{promo.code.includes("-") ? promo.code.split("-").slice(0, -1).join("-") : "—"}</span> : null}
                            {isAdminConsole ? <span>{promo.discountType === "item" ? `${promo.discountValue || 1} free item${(promo.discountValue || 1) === 1 ? "" : "s"}` : "-"}</span> : null}
                            {isAdminConsole ? <span>{promo.expiresAt ? phDateString(promo.expiresAt) : "No expiry"}</span> : null}
                            <span className={promo.redeemedAt ? "text-neutral-400" : promo.expiresAt && Date.parse(promo.expiresAt) <= Date.now() ? "text-amber-700" : "text-emerald-700"}>{promo.redeemedAt ? "Used" : promo.expiresAt && Date.parse(promo.expiresAt) <= Date.now() ? "Expired" : isAdminConsole ? "Active" : "Unused"}</span>
                            <button
                              type="button"
                              aria-label={`Delete promo voucher ${promo.code}`}
                              disabled={pending}
                              onClick={() => {
                                if (!window.confirm(`Delete promo voucher ${promo.code}?`)) return;
                                startTransition(async () => {
                                  const result = await deleteOwnerPromotionCode(owner.id, promo.code);
                                  if ("error" in result && result.error) {
                                    setNotice(result.error);
                                    return;
                                  }
                                  setPromoCodeRecords((current) => ({
                                    ...current,
                                    [owner.id]: (current[owner.id] ?? []).filter((entry) => entry.code !== promo.code),
                                  }));
                                  setNotice(`Promo voucher ${promo.code} deleted.`);
                                });
                              }}
                              className={isAdminConsole ? "justify-self-start rounded-full border border-[#ffd6d9] bg-[#fff8f8] px-3 py-1.5 text-[11px] font-medium text-[#f04452] transition hover:bg-[#fff0f1] disabled:opacity-40 sm:justify-self-end" : "rounded-full border border-neutral-300 px-3 py-1 text-xs font-medium text-red-600 hover:border-red-300 hover:bg-red-50 disabled:opacity-40"}
                            >
                              Delete
                            </button>
                          </div>
                        ))}
                      </div>
                    </div>
                  </section>
                );
              })()}
          </>
        ) : null}

        {tab === "gates" ? (
          <>
            <h1 className="text-xl font-semibold tracking-tight">Login links</h1>
            <div className="space-y-5 rounded-2xl border border-neutral-200 bg-white p-4 sm:p-5">
              <form
                className="flex flex-col gap-3 sm:flex-row sm:items-end"
                onSubmit={(event) => {
                  event.preventDefault();
                  startTransition(async () => {
                    const result = await updateLoginGates(adminPath);
                    if ("error" in result) {
                      setNotice(result.error);
                      return;
                    }
                    setAdminPath(result.admin);
                    setNotice("Admin login link updated.");
                  });
                }}
              >
                <label className="block flex-1 text-sm font-medium">
                  Admin login link
                  <span className="mt-1.5 flex items-center rounded-xl border border-neutral-200 px-3.5 focus-within:border-neutral-900 focus-within:ring-1 focus-within:ring-neutral-900">
                    <span className="text-sm text-neutral-500">/</span>
                    <input
                      value={adminPath}
                      onChange={(event) => setAdminPath(event.target.value)}
                      className="w-full bg-transparent py-2.5 pl-1 text-sm outline-none"
                      autoComplete="off"
                      required
                    />
                  </span>
                </label>
                <button
                  type="submit"
                  disabled={pending}
                  className="rounded-full bg-black px-4 py-2.5 text-sm font-medium text-white hover:bg-neutral-800 disabled:opacity-40"
                >
                  {pending ? "Saving…" : "Save link"}
                </button>
              </form>
              <p className="text-sm text-neutral-600">
                <span className="font-medium text-neutral-900">Owner login link:</span> /back-office
              </p>
            </div>
          </>
        ) : null}
      </div>
    </div>
  );
}
