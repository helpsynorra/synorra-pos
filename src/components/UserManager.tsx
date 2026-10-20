"use client";

import { useEffect, useMemo, useState, useTransition } from "react";
import {
  createOffRequest,
  createStaffUser,
  deleteOffRequest,
  deleteOwnerPromotionCode,
  deleteStaffUser,
  punchStaff,
  setOffRequestStatus,
  updateStaffSessionTimes,
  deleteStaffSession,
  updateOwnerPermissions,
  generateOwnerPromotionCode,
  updateStaffUser,
  updateLoginGates,
} from "@/actions/users";
import type { PublicStaffUser } from "@/lib/users";
import { DEFAULT_STAFF_PERMISSIONS } from "@/lib/users";
import { phDateString, phDateTimeInputValue, phDateTimeLabel } from "@/lib/datetime";
import { pairLoginSessions, type StaffSession } from "@/lib/staff-sessions";
import type { LoginActivity, OffRequest, PromotionCode, Session, StaffPermissions } from "@/lib/types";

const field =
  "w-full rounded-xl border border-neutral-200 bg-white px-3.5 py-2.5 text-sm text-neutral-900 outline-none transition-all focus:border-neutral-900 focus:ring-1 focus:ring-neutral-900";

type UserManagerProps = {
  users: PublicStaffUser[];
  session: Session;
  loginActivity: LoginActivity[];
  offRequests: OffRequest[];
  showShiftTabs?: boolean;
  showAdminRole?: boolean;
  showOwnerRole?: boolean;
  showBaristaRole?: boolean;
  showBaristasOnly?: boolean;
  showEditStaffButton?: boolean;
  showDeleteStaffButton?: boolean;
  baristaOnlyStaffActions?: boolean;
  printButtonHidden?: boolean;
  inventoryFeaturesEnabled?: boolean;
  showLoginLinksTab?: boolean;
  showPrintButtonToggle?: boolean;
  showViewPermissionsButton?: boolean;
  adminLoginPath?: string;
};

type SubTab = "staff" | "inout" | "off" | "gates" | "settings";
type StaffRole = "Admin" | "Barista" | "Owner";

type PermissionFlag = Exclude<keyof StaffPermissions, "promoCodes">;

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

export function UserManager({ users, session, loginActivity, offRequests, showShiftTabs = true, showAdminRole = true, showOwnerRole = true, showBaristaRole = true, showBaristasOnly = false, showEditStaffButton = true, showDeleteStaffButton = true, baristaOnlyStaffActions = false, showLoginLinksTab = true, showPrintButtonToggle = true, showViewPermissionsButton = true, adminLoginPath = "mouna1234" }: UserManagerProps) {
  const [tab, setTab] = useState<SubTab>("staff");
  const [editingId, setEditingId] = useState<string | "new" | null>(null);
  const [name, setName] = useState("");
  const [username, setUsername] = useState("");
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<StaffRole>(showBaristasOnly ? "Barista" : "Owner");
  const [password, setPassword] = useState("");
  const [notice, setNotice] = useState<string | null>(null);
  const [adminPath, setAdminPath] = useState(adminLoginPath);
  const [permissionState, setPermissionState] = useState<Record<string, StaffPermissions>>(
    () => Object.fromEntries(users.map((user) => [user.id, { ...DEFAULT_STAFF_PERMISSIONS, ...user.permissions }])),
  );
  const [selectedPermissionOwnerId, setSelectedPermissionOwnerId] = useState<string | null>(null);
  const [promoCodeRecords, setPromoCodeRecords] = useState<Record<string, PromotionCode[]>>(
    () => Object.fromEntries(users.map((user) => [user.id, user.permissions?.promoCodes ?? []])),
  );
  const [promoValueDrafts, setPromoValueDrafts] = useState<Record<string, number>>({});
  const [promoTypeDrafts, setPromoTypeDrafts] = useState<Record<string, PromotionCode["discountType"]>>({});
  const [promoItemCountDrafts, setPromoItemCountDrafts] = useState<Record<string, number>>({});
  const [promoPrefixDrafts, setPromoPrefixDrafts] = useState<Record<string, string>>({});
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
  
  // Global filter/display date state for In / Out
  const [selectedDate, setSelectedDate] = useState(phDateString());

  // Global filter/display date state for Request off
  const [offSelectedDate, setOffSelectedDate] = useState(phDateString());

  const uniqueUsers = useMemo(
    () => Array.from(new Map(users.map((user) => [user.id, user])).values()),
    [users],
  );
  const visibleUsers = showBaristasOnly
    ? uniqueUsers.filter((user) => user.role === "barista")
    : uniqueUsers;
  const ownerUsers = visibleUsers.filter((user) => user.role === "cashier");
  const editing = visibleUsers.find((user) => user.id === editingId) ?? null;
  const floorStaff = visibleUsers.filter((user) =>
    baristaOnlyStaffActions ? user.role === "barista" : user.role !== "admin",
  );
  const allSessions = useMemo(() => pairLoginSessions(loginActivity), [loginActivity]);
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
    setRole(showBaristasOnly ? "Barista" : "Owner");
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
    <div className="min-h-screen min-w-0 space-y-6 rounded-none border-0 border-neutral-300 bg-white p-3 sm:rounded-xl sm:border sm:p-6">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between border-b border-neutral-400 pb-3">
        <div className="flex gap-2 overflow-x-auto">
          {(
            [
              { id: "staff", label: "Staff" },
              { id: "inout", label: "In / Out" },
              { id: "off", label: "Request off" },
              { id: "gates", label: "Login links" },
              ...(showPrintButtonToggle ? [{ id: "settings" as const, label: "Settings" }] : []),
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
              className={`shrink-0 px-4 py-1.5 rounded text-xs font-bold transition shadow-sm uppercase ${
                tab === entry.id ? "bg-black text-white" : "bg-white text-neutral-700 hover:bg-neutral-100"
              }`}
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
            <div className="flex items-center justify-between gap-3">
              <h1 className="text-xl font-semibold tracking-tight">Staff</h1>
              <button
                type="button"
                onClick={startCreate}
                className="rounded-full bg-black px-4 py-2 text-sm font-medium text-white hover:bg-neutral-800"
              >
                Add staff
              </button>
            </div>

            {editingId ? (
              <form
                className="space-y-4 rounded-2xl border border-neutral-200 bg-white p-4 sm:p-5"
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
                      role: role === "Owner" ? "cashier" : role.toLowerCase(),
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
                <div className="flex items-center justify-between">
                  <p className="text-sm font-medium">
                    {editingId === "new" ? "New staff" : `Edit ${editing?.name ?? ""}`}
                  </p>
                  <button type="button" onClick={resetForm} className="text-xs text-neutral-500 hover:text-black">
                    Cancel
                  </button>
                </div>
                <div className="grid gap-3 sm:grid-cols-2">
                  <label className="text-xs font-medium text-neutral-600">
                    <span className="mb-1.5 block">Busines name</span>
                    <input value={name} onChange={(event) => setName(event.target.value)} className={field} required />
                  </label>
                  <label className="text-xs font-medium text-neutral-600">
                    <span className="mb-1.5 block">Username</span>
                    <input value={username} onChange={(event) => setUsername(event.target.value)} className={field} required />
                  </label>
                  {role === "Owner" && editingId === "new" ? (
                    <p className="sm:col-span-2 text-xs text-neutral-500">
                      The Owner can sign in to POS with this username and password.
                    </p>
                  ) : null}
                  {role === "Owner" && editingId !== "new" ? (
                    <label className="text-xs font-medium text-neutral-600">
                      <span className="mb-1.5 block">Email (optional)</span>
                      <input type="email" value={email} onChange={(event) => setEmail(event.target.value)} className={field} />
                    </label>
                  ) : null}
                  {role === "Barista" ? (
                    <p className="sm:col-span-2 text-xs text-neutral-500">
                      Baristas use this username and password to clock in and out on POS.
                    </p>
                  ) : null}
                  <label className="text-xs font-medium text-neutral-600">
                    <span className="mb-1.5 block">Password</span>
                    <input
                      type="password"
                      value={password}
                      onChange={(event) => setPassword(event.target.value)}
                      className={field}
                      required={editingId === "new"}
                      placeholder={editingId === "new" ? "" : "Leave blank to keep current"}
                    />
                  </label>
                </div>
                <div
                  className="grid gap-2"
                  style={{ gridTemplateColumns: `repeat(${(showAdminRole ? 1 : 0) + (showOwnerRole ? 1 : 0) + (showBaristaRole ? 1 : 0)}, minmax(0, 1fr))` }}
                >
                  {([...(showAdminRole ? ["Admin" as const] : []), ...(showOwnerRole ? ["Owner" as const] : []), ...(showBaristaRole ? ["Barista" as const] : [])] as const).map((id) => (
                    <button
                      key={id}
                      type="button"
                      onClick={() => setRole(id)}
                      className={`rounded-full border py-2 text-xs font-medium ${
                        role === id ? "border-black bg-black text-white" : "border-neutral-200 bg-white text-neutral-600"
                      }`}
                    >
                      {id}
                    </button>
                  ))}
                </div>
                <button
                  type="submit"
                  disabled={pending}
                  className="rounded-full bg-black px-4 py-2 text-sm font-medium text-white hover:bg-neutral-800 disabled:opacity-40"
                >
                  {editingId === "new" ? "Add" : "Save"}
                </button>
              </form>
            ) : null}

            <div className="divide-y divide-neutral-100 overflow-hidden rounded-2xl border border-neutral-200 bg-white">
              {visibleUsers.map((user) => (
                <div key={user.id} className="flex items-center justify-between gap-3 px-4 py-4 sm:px-5">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <p className="truncate text-sm font-medium">{user.name}</p>
                      {user.id === session.userId ? (
                        <span className="rounded-full bg-neutral-100 px-2 py-0.5 text-[10px] font-medium text-neutral-500 uppercase">
                          you
                        </span>
                      ) : null}
                    </div>
                    <p className="mt-0.5 text-xs text-neutral-400">
                      {`${user.username} · ${user.role === "admin" ? "Admin" : user.role === "cashier" ? "Owner" : "Barista"}`}
                    </p>
                  </div>
                  <div className="flex items-center gap-1">
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
                    {showEditStaffButton && (!baristaOnlyStaffActions || user.role === "barista") ? <button
                      type="button"
                      aria-label={`Edit ${user.name}`}
                      onClick={() => startEdit(user)}
                      className="flex h-9 w-9 items-center justify-center rounded-xl text-neutral-400 hover:bg-neutral-100 hover:text-black"
                    >
                      <svg viewBox="0 0 24 24" className="h-4 w-4" fill="none" stroke="currentColor">
                        <path d="M4 20h4l10.5-10.5a2.1 2.1 0 0 0-3-3L5 17v3Z" strokeWidth="1.7" strokeLinejoin="round" />
                        <path d="M13.5 6.5l3 3" strokeWidth="1.7" />
                      </svg>
                    </button> : null}
                    {showDeleteStaffButton && (!baristaOnlyStaffActions || user.role === "barista") ? <button
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
              ))}
            </div>
          </>
        ) : null}

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
                            <p className="text-xs text-neutral-400">{row.username}</p>
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
            <div>
              <h1 className="text-xl font-semibold tracking-tight">{selectedPermissionOwnerId ? "Owner permissions" : "Settings"}</h1>
              <p className="mt-1 text-sm text-neutral-500">
                {selectedPermissionOwnerId ? "Choose which POS features this Owner account can use." : "Select an Owner to view their permissions."}
              </p>
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
                  <section className="space-y-3 rounded-2xl border border-neutral-200 bg-white p-4 sm:p-5">
                    <div className="flex items-center justify-between gap-3">
                      <h2 className="font-semibold">{owner.name}</h2>
                      <button type="button" onClick={() => setSelectedPermissionOwnerId(null)} className="text-xs font-medium text-neutral-600 hover:text-black">Back</button>
                    </div>
                    <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                      {permissionOptions.map(({ key, label }) => (
                        <label key={key} className="flex cursor-pointer items-center gap-3 rounded-lg border border-neutral-200 px-3 py-2.5 text-sm">
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
                            className="size-4 accent-black"
                          />
                          {label}
                        </label>
                      ))}
                    </div>
                    <div className="space-y-3 border-t border-neutral-200 pt-4">
                      <div>
                        <h3 className="text-sm font-semibold">Generate promotion codes</h3>
                        <p className="text-xs text-neutral-500">Each code can only be redeemed once. Add a prefix, then the system generates a unique 6-character suffix.</p>
                      </div>
                      <div className="grid gap-2 sm:grid-cols-2 xl:grid-cols-[1fr_1fr_1fr_1.4fr_auto]">
                        <label className="block text-xs font-medium text-neutral-600">
                          <span className="sr-only">Code prefix</span>
                          <input
                            aria-label="Promotion code prefix"
                            type="text"
                            value={promoPrefixDrafts[owner.id] ?? "SYNORRA"}
                            maxLength={16}
                            placeholder="Code prefix"
                            onChange={(event) => setPromoPrefixDrafts((current) => ({ ...current, [owner.id]: event.target.value.toUpperCase() }))}
                            className={field}
                          />
                        </label>
                        <select
                          aria-label="Promotion discount type"
                          value={promoTypeDrafts[owner.id] ?? "percent"}
                          onChange={(event) => setPromoTypeDrafts((current) => ({ ...current, [owner.id]: event.target.value as PromotionCode["discountType"] }))}
                          className={field}
                        >
                          <option value="percent">Percent discount</option>
                          <option value="amount">Peso discount</option>
                          <option value="item">Free item(s)</option>
                        </select>
                        {(promoTypeDrafts[owner.id] ?? "percent") !== "item" ? (
                          <input
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
                          <label className="block text-xs font-medium text-neutral-600">
                            <span className="mb-1 block">Free item quantity</span>
                            <input
                              aria-label="Number of free items per code"
                              type="number"
                              min="1"
                              max="99"
                              step="1"
                              value={promoItemCountDrafts[owner.id] ?? 1}
                              onChange={(event) => setPromoItemCountDrafts((current) => ({ ...current, [owner.id]: Number(event.target.value) }))}
                              className={field}
                            />
                          </label>
                        )}
                        <div className="flex gap-2">
                          <select
                            aria-label="Number of promotion codes"
                            value={promoCountModes[owner.id] ?? "5"}
                            onChange={(event) => setPromoCountModes((current) => ({ ...current, [owner.id]: event.target.value }))}
                            className={field}
                          >
                            <option value="1">1 code</option>
                            <option value="5">5 codes</option>
                            <option value="10">10 codes</option>
                            <option value="20">20 codes</option>
                            <option value="custom">Custom</option>
                          </select>
                          {(promoCountModes[owner.id] ?? "5") === "custom" ? (
                            <input
                              aria-label="Custom number of promotion codes"
                              type="number"
                              min="1"
                              max="100"
                              step="1"
                              value={promoCustomCounts[owner.id] ?? "25"}
                              onChange={(event) => setPromoCustomCounts((current) => ({ ...current, [owner.id]: event.target.value }))}
                              className={`${field} max-w-24`}
                            />
                          ) : null}
                        </div>
                        <button
                          type="button"
                          disabled={pending || !permissions.promotionsEnabled || !/^[A-Z0-9]{1,16}$/.test(promoPrefixDrafts[owner.id] ?? "SYNORRA") || ((promoTypeDrafts[owner.id] ?? "percent") === "item" && (!Number.isInteger(promoItemCountDrafts[owner.id] ?? 1) || (promoItemCountDrafts[owner.id] ?? 1) < 1 || (promoItemCountDrafts[owner.id] ?? 1) > 99)) || ((promoCountModes[owner.id] ?? "5") === "custom" && (!/^\d+$/.test(promoCustomCounts[owner.id] ?? "25") || Number(promoCustomCounts[owner.id] ?? "25") < 1 || Number(promoCustomCounts[owner.id] ?? "25") > 100))}
                          onClick={() => startTransition(async () => {
                            const type = promoTypeDrafts[owner.id] ?? "percent";
                            const countMode = promoCountModes[owner.id] ?? "5";
                            const count = countMode === "custom" ? Number(promoCustomCounts[owner.id] ?? "25") : Number(countMode);
                            const result = await generateOwnerPromotionCode(owner.id, type, type === "item" ? promoItemCountDrafts[owner.id] ?? 1 : promoValueDrafts[owner.id] ?? 10, count, promoPrefixDrafts[owner.id] ?? "SYNORRA");
                            const generatedPromos = result.promos ?? [];
                            if (generatedPromos.length > 0) {
                              setPromoCodeRecords((current) => ({
                                ...current,
                                [owner.id]: [...generatedPromos, ...(current[owner.id] ?? [])],
                              }));
                            }
                            if ("error" in result && result.error) {
                              setNotice(generatedPromos.length ? `${result.error} ${generatedPromos.length} code(s) were created.` : result.error);
                              return;
                            }
                            setNotice(`${generatedPromos.length} promotion code(s) generated.`);
                          })}
                          className="rounded-full bg-black px-4 py-2 text-xs font-medium text-white disabled:opacity-40"
                        >Generate codes</button>
                      </div>
                      <div className="divide-y divide-neutral-100 rounded-xl border border-neutral-200">
                        {(promoCodeRecords[owner.id] ?? []).length === 0 ? (
                          <p className="p-3 text-xs text-neutral-500">No promotion codes generated.</p>
                        ) : (promoCodeRecords[owner.id] ?? []).map((promo) => (
                          <div key={promo.code} className="flex flex-wrap items-center justify-between gap-2 p-3 text-sm">
                            <span className="font-mono font-semibold tracking-widest">{promo.code}</span>
                            <span>{promo.discountType === "item" ? `${promo.discountValue || 1} free item${(promo.discountValue || 1) === 1 ? "" : "s"}` : promo.discountType === "percent" ? `${promo.discountValue}% off` : `₱${promo.discountValue} off`}</span>
                            <span className={promo.redeemedAt ? "text-neutral-400" : "text-emerald-700"}>{promo.redeemedAt ? "Used" : "Unused"}</span>
                            <button
                              type="button"
                              aria-label={`Delete promotion code ${promo.code}`}
                              disabled={pending}
                              onClick={() => {
                                if (!window.confirm(`Delete promotion code ${promo.code}?`)) return;
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
                                  setNotice(`Promotion code ${promo.code} deleted.`);
                                });
                              }}
                              className="rounded-full border border-neutral-300 px-3 py-1 text-xs font-medium text-red-600 hover:border-red-300 hover:bg-red-50 disabled:opacity-40"
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
