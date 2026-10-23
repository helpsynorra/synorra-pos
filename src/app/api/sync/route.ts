import bcrypt from "bcryptjs";
import { NextRequest, NextResponse } from "next/server";
import { phIsoTimestamp } from "@/lib/datetime";
import { ingredientsForOrderLine, roundQty } from "@/lib/inventory";
import { normalizeMenuAddons, normalizeMenuStyles } from "@/lib/menu";
import { parsePayment } from "@/lib/payments";
import { createPosApiToken, readPosApiToken } from "@/lib/pos-api-auth";
import {
  createOrderAtomic,
  createRestockAtomic,
  deleteOwnerAccountAndData,
  deleteInventoryItemRecord,
  deleteRestockAtomic,
  editRestockAtomic,
  getFreshStore,
  getOwnerAccounts,
  insertLoginActivityRecord,
  insertVoidRequestRecord,
  legacyOwnerId,
  ownerIdForStaff,
  supabaseAdmin,
  upsertStaffUserRecord,
  updateStore,
  voidOrderAtomic,
  withStoreTenant,
} from "@/lib/store";
import type { InventoryItem, Order, OrderItem, VoidRequest } from "@/lib/types";
import { parseRole } from "@/lib/users";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Requested-With",
  "Cache-Control": "no-store, no-cache, must-revalidate",
};

function orderItemsFromApi(value: unknown): OrderItem[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((rawItem) => {
    if (!rawItem || typeof rawItem !== "object") return [];
    const item = rawItem as Record<string, unknown>;
    return [{
      productId: String(item.productId ?? ""),
      name: String(item.name ?? ""),
      qty: Math.max(1, Number(item.qty) || 1),
      price: Number(item.price) || 0,
      style: item.style === "hot" || item.style === "iced" ? item.style : undefined,
      addons: Array.isArray(item.addons)
        ? item.addons.flatMap((rawAddon) => {
            if (!rawAddon || typeof rawAddon !== "object") return [];
            const addon = rawAddon as Record<string, unknown>;
            return [{
              id: typeof addon.id === "string" ? addon.id : "",
              name: String(addon.name ?? ""),
              price: Number(addon.price) || 0,
              qty: Math.max(1, Number(addon.qty) || 1),
              inventoryItemId: typeof addon.inventoryItemId === "string" ? addon.inventoryItemId : undefined,
              usageAmount: addon.usageAmount != null ? Number(addon.usageAmount) : undefined,
              usageUnit: typeof addon.usageUnit === "string" ? addon.usageUnit : undefined,
            }];
          })
        : undefined,
      category: typeof item.category === "string" ? item.category : undefined,
    }];
  });
}

function orderTimestampFromApi(value: unknown): string | null {
  if (typeof value !== "string" || !value.trim()) return null;
  return phIsoTimestamp(value) || null;
}

export async function OPTIONS() {
  return new NextResponse(null, { status: 204, headers: corsHeaders });
}

export async function GET(request: NextRequest) {
  const claims = readPosApiToken(request.headers.get("authorization"));
  if (!claims) {
    return NextResponse.json(
      { ok: false, error: "POS session expired. Sign in again." },
      { status: 401, headers: corsHeaders },
    );
  }
  if (claims.role === "barista") {
    return NextResponse.json(
      { ok: false, error: "This account cannot access the POS store." },
      { status: 403, headers: corsHeaders },
    );
  }

  try {
    const posOwnerId = claims.role === "cashier" ? claims.userId : await legacyOwnerId();
    const store = await getFreshStore({ ownerId: posOwnerId });
    const ownerAccount = posOwnerId
      ? (await getOwnerAccounts()).find((user) => user.id === posOwnerId)
      : undefined;
    if (claims.role === "cashier") {
      const cashier = ownerAccount ?? store.users.find((user) => user.id === claims.userId);
      if (!cashier?.passwordChanged) {
        return NextResponse.json(
          { ok: false, error: "Change your Owner password before using the POS." },
          { status: 403, headers: corsHeaders },
        );
      }
    }
    return NextResponse.json(
      {
        ok: true,
        timestamp: new Date().toISOString(),
        pos: store.pos,
        menu: store.menu.map((item) => ({
          ...item,
          styles: normalizeMenuStyles(item),
          addons: normalizeMenuAddons(item),
        })),
        categories: store.categories,
        inventory: store.inventory,
        orders: store.orders,
        restocks: store.restocks,
        usageLogs: store.usageLogs,
        recipes: store.recipes,
        recipeCostings: store.recipeCostings,
        voidRequests: store.voidRequests,
        loginActivity: store.loginActivity,
        users: [
          ...store.users.filter((user) => user.id !== ownerAccount?.id),
          ...(ownerAccount ? [ownerAccount] : []),
        ].map((u) => {
          const resolvedRole = parseRole(String(u.title ?? ""), u.role);
          return {
            id: u.id,
            username: u.username,
            email: u.email,
            name: u.name,
            passwordChanged: Boolean(u.passwordChanged),
            permissions: u.permissions ?? {
              stockInventory: true,
              restockInventory: true,
              connectLabels: true,
              connectReceipt: true,
              printButton: true,
              customerReceipt: true,
              cupLabels: true,
              dineIn: true,
              takeOut: true,
              promotionDiscount: false,
              promotionsEnabled: false,
              promoCodes: [],
            },
            role: resolvedRole,
            title:
              u.title ||
              (resolvedRole === "admin"
                ? "Owner"
                : resolvedRole === "cashier"
                    ? "Owner"
                    : "Barista"),
          };
        }),
      },
      { headers: corsHeaders },
    );
  } catch (error) {
    return NextResponse.json(
      {
        ok: false,
        error: error instanceof Error ? error.message : "Failed to load centralized store",
      },
      { status: 500, headers: corsHeaders },
    );
  }
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const action = String(body?.action ?? "").trim();
    if (["void_checkout", "void_order", "create_void_request", "delete_void_request", "approve_void_request"].includes(action)) {
      return NextResponse.json(
        { ok: false, error: "Voiding is disabled." },
        { status: 410, headers: corsHeaders },
      );
    }

    if (action === "change_cashier_password") {
      const email = String(body.email ?? "").trim().toLowerCase();
      const password = String(body.password ?? "");
      const newPassword = String(body.newPassword ?? "");
      if (!email || !password || newPassword.length < 8) {
        return NextResponse.json(
          { ok: false, error: "Enter your Owner username or email, current password, and a new password with at least 8 characters." },
          { status: 400, headers: corsHeaders },
        );
      }

      const store = await getFreshStore({ ownerId: null });
      const user = store.users.find(
        (entry) =>
          entry.role === "cashier" &&
          (entry.email?.trim().toLowerCase() === email ||
            entry.username.trim().toLowerCase() === email),
      );
      const currentPasswordMatches = user?.password
        ? user.password.startsWith("$2")
          ? await bcrypt.compare(password, user.password)
          : user.password === password || user.password.trim() === password.trim()
        : false;
      if (
        !user ||
        user.passwordChanged ||
        !currentPasswordMatches
      ) {
        return NextResponse.json(
          { ok: false, error: "Those details do not match an Owner account that needs a password change." },
          { status: 401, headers: corsHeaders },
        );
      }

      const updatedUser = {
        ...user,
        password: await bcrypt.hash(newPassword, 12),
        passwordChanged: true,
      };
      await upsertStaffUserRecord(updatedUser);
      return NextResponse.json(
        {
          ok: true,
          token: createPosApiToken({
            userId: updatedUser.id,
            username: updatedUser.username,
            name: updatedUser.name,
            role: "cashier",
          }),
          user: {
            id: updatedUser.id,
            username: updatedUser.username,
            email: updatedUser.email,
            name: updatedUser.name,
            passwordChanged: true,
            role: "cashier",
            title: updatedUser.title || "Owner",
          },
        },
        { headers: corsHeaders },
      );
    }

    if (action === "new_owner_login") {
      const email = String(body.email ?? "").trim().toLowerCase();
      const username = String(body.username ?? "").trim().toLowerCase();
      const password = String(body.password ?? "");
      if (
        !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ||
        !username ||
        !password ||
        body.legalAccepted !== true
      ) {
        return NextResponse.json(
          { ok: false, error: "Enter valid Owner details and accept the Terms of Use and Privacy Policy." },
          { status: 400, headers: corsHeaders },
        );
      }

      const store = await getFreshStore({ ownerId: null });
      const user = store.users.find(
        (entry) => entry.role === "cashier" && entry.username.trim().toLowerCase() === username,
      );
      const passwordMatches = user?.password
        ? user.password.startsWith("$2")
          ? await bcrypt.compare(password, user.password)
          : user.password === password || user.password.trim() === password.trim()
        : false;
      if (!user || !passwordMatches) {
        return NextResponse.json(
          { ok: false, error: "The Owner username or password is incorrect." },
          { status: 401, headers: corsHeaders },
        );
      }

      const emailInUse = store.users.some(
        (entry) => entry.id !== user.id && entry.email?.trim().toLowerCase() === email,
      );
      if (emailInUse) {
        return NextResponse.json(
          { ok: false, error: "That email is already assigned to another account." },
          { status: 409, headers: corsHeaders },
        );
      }
      if (user.email?.trim() && user.email.trim().toLowerCase() !== email) {
        return NextResponse.json(
          { ok: false, error: "This Owner account is already linked to a different email." },
          { status: 409, headers: corsHeaders },
        );
      }

      const updatedUser = user.email?.trim() ? user : { ...user, email };
      if (!user.email?.trim()) {
        await withStoreTenant(user.id, () => upsertStaffUserRecord({ ...updatedUser, ownerId: user.id }));
      }
      if (!updatedUser.passwordChanged) {
        return NextResponse.json(
          { ok: true, requiresPasswordChange: true },
          { headers: corsHeaders },
        );
      }

      return NextResponse.json(
        {
          ok: true,
          token: createPosApiToken({
            userId: updatedUser.id,
            username: updatedUser.username,
            name: updatedUser.name,
            role: "cashier",
          }),
          user: {
            id: updatedUser.id,
            username: updatedUser.username,
            email: updatedUser.email,
            name: updatedUser.name,
            passwordChanged: true,
            role: "cashier",
            title: updatedUser.title || "Owner",
          },
        },
        { headers: corsHeaders },
      );
    }

    if (action === "auth") {
      const username = String(body.username ?? "").trim().toLowerCase();
      const email = String(body.email ?? "").trim().toLowerCase();
      const password = String(body.password ?? "");
      if ((!username && !email) || !password) {
        return NextResponse.json(
          { ok: false, error: "Enter your Owner username or email and password." },
          { status: 400, headers: corsHeaders },
        );
      }

      const store = await getFreshStore({ ownerId: null });
      const identifier = username || email;
      const user = store.users.find(
        (u) =>
          ["cashier", "admin", "barista", "pos_cashier"].includes(u.role) &&
          (u.username.trim().toLowerCase() === identifier ||
            u.name.trim().toLowerCase() === identifier ||
            Boolean(u.email && u.email.trim().toLowerCase() === identifier)),
      );
      if (!user || !user.password) {
        console.warn("POS staff authentication rejected: staff account unavailable.");
        return NextResponse.json(
          { ok: false, error: "Invalid email or password" },
          { status: 401, headers: corsHeaders },
        );
      }

      const validPassword = user.password.startsWith("$2")
        ? await bcrypt.compare(password, user.password)
        : user.password === password || user.password.trim() === password.trim();

      if (!validPassword) {
        console.warn("POS staff authentication rejected: password mismatch.");
        return NextResponse.json(
          { ok: false, error: "Invalid email or password" },
          { status: 401, headers: corsHeaders },
        );
      }

      const resolvedRole = parseRole(String(user.title ?? ""), user.role);
      if (resolvedRole === "cashier" && !user.passwordChanged) {
        return NextResponse.json(
          { ok: true, requiresPasswordChange: true },
          { headers: corsHeaders },
        );
      }
      return NextResponse.json(
        {
          ok: true,
          token: createPosApiToken({
            userId: user.id,
            username: user.username,
            name: user.name,
            role: resolvedRole,
          }),
          user: {
            id: user.id,
            username: user.username,
            email: user.email,
            name: user.name,
            passwordChanged: Boolean(user.passwordChanged),
            role: resolvedRole,
            title: user.title || (resolvedRole === "admin" ? "Admin" : resolvedRole === "cashier" ? "Owner" : "Barista"),
          },
        },
        { headers: corsHeaders },
      );
    }

    const claims = readPosApiToken(req.headers.get("authorization"));
    if (!claims) {
      return NextResponse.json(
        { ok: false, error: "POS session expired. Sign in again." },
        { status: 401, headers: corsHeaders },
      );
    }

    if (action === "delete_owner_account") {
      if (claims.role !== "cashier") {
        return NextResponse.json(
          { ok: false, error: "Only the Owner can delete this account." },
          { status: 403, headers: corsHeaders },
        );
      }
      const password = String(body.password ?? "");
      if (body.confirmation !== "DELETE MY ACCOUNT" || !password) {
        return NextResponse.json(
          { ok: false, error: "Confirm the deletion phrase and enter your current password." },
          { status: 400, headers: corsHeaders },
        );
      }

      const { data: owner, error: ownerLookupError } = await supabaseAdmin()
        .from("staff_users")
        .select("id, owner_id, role, password")
        .eq("id", claims.userId)
        .maybeSingle();
      if (ownerLookupError || !owner || owner.role !== "cashier" || (owner.owner_id && owner.owner_id !== claims.userId)) {
        return NextResponse.json(
          { ok: false, error: "Owner account could not be verified." },
          { status: 404, headers: corsHeaders },
        );
      }
      const passwordMatches = owner.password
        ? owner.password.startsWith("$2")
          ? await bcrypt.compare(password, owner.password)
          : owner.password === password || owner.password.trim() === password.trim()
        : false;
      if (!passwordMatches) {
        return NextResponse.json(
          { ok: false, error: "Your current password is incorrect." },
          { status: 401, headers: corsHeaders },
        );
      }

      await deleteOwnerAccountAndData(claims.userId);
      return NextResponse.json(
        { ok: true, message: "Owner account and store data were permanently deleted." },
        { headers: corsHeaders },
      );
    }

    const tenantId = claims.role === "cashier"
      ? claims.userId
      : claims.role === "barista" || claims.role === "pos_cashier"
        ? await ownerIdForStaff(claims.userId)
        : await legacyOwnerId();
    if (!tenantId) {
      return NextResponse.json({ ok: false, error: "This account is not assigned to an Owner store." }, { status: 403, headers: corsHeaders });
    }
    return await withStoreTenant(tenantId, async () => {
    if ((claims.role === "barista" || claims.role === "pos_cashier") && action !== "barista_shift_activity") {
      return NextResponse.json(
        { ok: false, error: "This account cannot perform POS actions." },
        { status: 403, headers: corsHeaders },
      );
    }
    if (claims.role === "cashier") {
      const store = await getFreshStore();
      const cashier = store.users.find((user) => user.id === claims.userId);
      if (!cashier?.passwordChanged) {
        return NextResponse.json(
          { ok: false, error: "Change your Owner password before using the POS." },
          { status: 403, headers: corsHeaders },
        );
      }
    }

    if (action === "validate_promotion") {
      const code = String(body.code ?? "").replace(/\s+/g, "").toUpperCase();
      if (!/^(?:[A-Z0-9]{6}|[A-Z0-9]{1,16}-[A-Z0-9]{6})$/.test(code)) {
        return NextResponse.json(
          { ok: false, error: "Enter a valid promotion voucher." },
          { status: 400, headers: corsHeaders },
        );
      }

      const promotionOwner = (await getOwnerAccounts()).find(
        (entry) => entry.id === tenantId,
      );
      const promotionPermissions = promotionOwner?.permissions;
      if (
        !promotionPermissions ||
        promotionPermissions.promotionsEnabled !== true ||
        promotionPermissions.promotionDiscount !== true
      ) {
        return NextResponse.json(
          { ok: false, error: "Promotions are not enabled for this Owner." },
          { status: 403, headers: corsHeaders },
        );
      }
      const promotion = promotionPermissions.promoCodes?.find(
        (entry) => entry.code.trim().toUpperCase() === code,
      );
      if (!promotion) {
        return NextResponse.json(
          { ok: false, error: "Invalid promotion voucher." },
          { status: 404, headers: corsHeaders },
        );
      }
      if (promotion.redeemedAt) {
        return NextResponse.json(
          { ok: false, error: "Promotion voucher already used." },
          { status: 409, headers: corsHeaders },
        );
      }
      if (promotion.expiresAt && Date.parse(promotion.expiresAt) <= Date.now()) {
        return NextResponse.json(
          { ok: false, error: "Promotion voucher has expired." },
          { status: 409, headers: corsHeaders },
        );
      }
      return NextResponse.json(
        {
          ok: true,
          promotion: {
            code: promotion.code,
            discountType: promotion.discountType,
            discountValue: promotion.discountValue,
            expiresAt: promotion.expiresAt ?? null,
          },
        },
        { headers: corsHeaders },
      );
    }

    if (action === "create_order") {
      const rawOrder = body.order ?? {};
      if (!claims || !["cashier", "admin"].includes(claims.role)) {
        return NextResponse.json({ ok: false, error: "Owner access required." }, { status: 403, headers: corsHeaders });
      }
      if (rawOrder.voided) {
        return NextResponse.json(
          { ok: false, error: "Use the authenticated void checkout action." },
          { status: 400, headers: corsHeaders },
        );
      }
      const createdAt = orderTimestampFromApi(rawOrder.createdAt);
      if (!createdAt) {
        return NextResponse.json(
          { ok: false, error: "A valid device order timestamp is required." },
          { status: 400, headers: corsHeaders },
        );
      }
      const store = await getFreshStore({ ownerId: claims.role === "cashier" ? claims.userId : undefined });
      const ownerAccount = (await getOwnerAccounts()).find((user) => user.id === tenantId);
      const existingOrder = store.orders.find((o) => o.id === rawOrder.id);
      if (existingOrder) {
        return NextResponse.json(
          { ok: true, ticketNo: existingOrder.ticketNo ?? rawOrder.ticketNo ?? "", order: existingOrder },
          { headers: corsHeaders },
        );
      }

      const serviceMode: NonNullable<OrderItem["serviceMode"]> =
        rawOrder.serviceMode === "take-out" ? "take-out" : "dine-in";
      const orderItems: OrderItem[] = orderItemsFromApi(rawOrder.items).map(
        (item): OrderItem => ({ ...item, serviceMode }),
      );
      const requestedPromoCode = typeof rawOrder.promoLabel === "string"
        ? rawOrder.promoLabel.replace(/\s+/g, "").toUpperCase()
        : "";
      const requestedDiscount = Math.round(Number(rawOrder.discount) || 0);
      if (requestedPromoCode || requestedDiscount > 0) {
        if (!/^(?:[A-Z0-9]{6}|[A-Z0-9]{1,16}-[A-Z0-9]{6})$/.test(requestedPromoCode)) {
          return NextResponse.json({ ok: false, error: "Invalid promotion code." }, { status: 400, headers: corsHeaders });
        }
        const owner = ownerAccount ?? store.users.find((user) => user.id === claims.userId && user.role === "cashier");
        const permissions = owner?.permissions;
        const promo = Array.isArray(permissions?.promoCodes)
          ? permissions.promoCodes.find((entry) => entry.code.trim().toUpperCase() === requestedPromoCode)
          : undefined;
        if (!owner || permissions?.promotionsEnabled !== true || permissions.promotionDiscount !== true || !promo) {
          return NextResponse.json({ ok: false, error: "Invalid promotion code." }, { status: 400, headers: corsHeaders });
        }
        if (promo.redeemedAt) {
          return NextResponse.json({ ok: false, error: "The promotion code already used." }, { status: 409, headers: corsHeaders });
        }
        if (promo.expiresAt && Date.parse(promo.expiresAt) <= Date.now()) {
          return NextResponse.json({ ok: false, error: "This promo voucher has expired." }, { status: 409, headers: corsHeaders });
        }
        const subtotal = Number(rawOrder.subtotal) || 0;
        const promoItemIndex = typeof rawOrder.promoItemIndex === "number" && Number.isInteger(rawOrder.promoItemIndex)
          ? rawOrder.promoItemIndex
          : null;
        const promoItemQty = typeof rawOrder.promoItemQty === "number" && Number.isInteger(rawOrder.promoItemQty)
          ? rawOrder.promoItemQty
          : 1;
        const selectedItem = promoItemIndex != null ? orderItems[promoItemIndex] : undefined;
        const freeItemQty = Math.max(1, Math.floor(promo.discountValue || 1));
        const rawExpectedDiscount = promo.discountType === "item"
          ? selectedItem && promoItemQty === freeItemQty && promoItemQty <= selectedItem.qty
            ? (selectedItem.price + (selectedItem.addons ?? []).reduce((sum, addon) => sum + addon.price * addon.qty, 0)) * freeItemQty
            : -1
          : promo.discountType === "amount"
            ? promo.discountValue
            : subtotal * promo.discountValue / 100;
        const expectedDiscount = promo.discountType === "item"
          ? Math.round(rawExpectedDiscount)
          : Math.min(subtotal, Math.round(rawExpectedDiscount));
        if (requestedDiscount !== expectedDiscount) {
          return NextResponse.json({ ok: false, error: "Promotion discount does not match this code." }, { status: 400, headers: corsHeaders });
        }
      }
      const requestedCashierId = String(rawOrder.baristaUserId ?? '').trim();
      const requestedCashier = store.users.find((user) => {
        if (user.id !== requestedCashierId) return false;
        const role = parseRole(String(user.title ?? ''), user.role);
        return ['cashier', 'admin'].includes(role);
      });
      const order: Order = {
        id: String(rawOrder.id || `ord-${Date.now()}`),
        createdAt,
        baristaName: requestedCashier?.name ?? claims.name,
        baristaUserId: requestedCashier?.id,
        items: orderItems,
        subtotal: Number(rawOrder.subtotal) || 0,
        discount: Number(rawOrder.discount) || 0,
        promoLabel: typeof rawOrder.promoLabel === "string" ? rawOrder.promoLabel : undefined,
        promoItemIndex: typeof rawOrder.promoItemIndex === "number" && Number.isInteger(rawOrder.promoItemIndex)
          ? rawOrder.promoItemIndex
          : undefined,
        promoItemQty: typeof rawOrder.promoItemQty === "number" && Number.isInteger(rawOrder.promoItemQty)
          ? rawOrder.promoItemQty
          : undefined,
        total: Number(rawOrder.total) || 0,
        paymentMethod: parsePayment(rawOrder.paymentMethod),
        serviceMode,
        ticketNo: typeof rawOrder.ticketNo === "string" ? rawOrder.ticketNo : "",
        paid: Number(rawOrder.paid ?? rawOrder.total) || 0,
        change: Number(rawOrder.change) || 0,
        voided: Boolean(rawOrder.voided),
        voidReason: typeof rawOrder.voidReason === "string" ? rawOrder.voidReason : undefined,
      };

      // Calculate deductions using the exact Admin recipe/costing/addon configuration
      const deductionsByInventoryItem = new Map<
        string,
        {
          inventoryItemId: string;
          itemName: string;
          amount: number;
          unit: string;
          orderItemId?: string;
        }
      >();

      for (const line of order.items) {
        const ingredients = ingredientsForOrderLine(store, line);
        for (const ingredient of ingredients) {
          const matchedStock = store.inventory.find(
            (inv) =>
              (ingredient.inventoryItemId && inv.id === ingredient.inventoryItemId) ||
              inv.name.trim().toLowerCase() === ingredient.name.trim().toLowerCase(),
          );
          if (!matchedStock) continue;
          const usedAmount = roundQty(Number(ingredient.amount) * line.qty);
          if (usedAmount <= 0) continue;
          const existing = deductionsByInventoryItem.get(matchedStock.id);
          if (existing) {
            existing.amount = roundQty(existing.amount + usedAmount);
          } else {
            deductionsByInventoryItem.set(matchedStock.id, {
              inventoryItemId: matchedStock.id,
              itemName: matchedStock.name,
              amount: usedAmount,
              unit: ingredient.unit || matchedStock.unit || "pcs",
              orderItemId: line.productId,
            });
          }
        }
      }
      const deductions = [...deductionsByInventoryItem.values()];

      const result = await createOrderAtomic({
        order,
        deductions,
      });

      if (!result.ok) {
        return NextResponse.json(
          { ok: false, error: result.error },
          { status: 400, headers: corsHeaders },
        );
      }

      order.ticketNo = result.ticketNo || order.ticketNo;
      return NextResponse.json(
        { ok: true, ticketNo: order.ticketNo, order },
        { headers: corsHeaders },
      );
    }

    if (action === "void_checkout") {
      const rawOrder = body.order ?? {};
      const reason = String(body.reason ?? rawOrder.voidReason ?? "").trim();
      const items = orderItemsFromApi(rawOrder.items);
      if (items.length === 0 || !reason) {
        return NextResponse.json({ ok: false, error: "Checkout items and void reason are required." }, { status: 400, headers: corsHeaders });
      }

      let voidedBy = claims.userId;
      let voidedByName = claims.name;
      const store = await getFreshStore();
      if (claims.role !== "admin") {
        const managerUsername = String(body.managerUsername ?? "").trim().toLowerCase();
        const managerPassword = String(body.managerPassword ?? "");
        const manager = store.users.find((user) => user.username.trim().toLowerCase() === managerUsername);
        const managerRole = manager ? parseRole(String(manager.title ?? ""), manager.role) : "barista";
        const validPassword = manager && (manager.password.startsWith("$2")
          ? await bcrypt.compare(managerPassword, manager.password)
          : manager.password === managerPassword);
        if (!manager || !validPassword || managerRole !== "admin") {
          return NextResponse.json({ ok: false, error: "Manager or Admin credentials required to void." }, { status: 403, headers: corsHeaders });
        }
        // The cashier token identifies who rang up the order. The manager
        // whose credentials approved this void is the void actor.
        voidedBy = manager.id;
        voidedByName = manager.name;
      }

      const orderId = String(rawOrder.id || "").trim();
      const createdAt = orderTimestampFromApi(rawOrder.createdAt);
      if (!createdAt) {
        return NextResponse.json(
          { ok: false, error: "A valid device order timestamp is required." },
          { status: 400, headers: corsHeaders },
        );
      }
      const existingOrder = store.orders.find((entry) => entry.id === orderId);
      if (existingOrder) {
        if (existingOrder.voided) {
          return NextResponse.json(
            { ok: true, ticketNo: existingOrder.ticketNo, order: existingOrder },
            { headers: corsHeaders },
          );
        }
        return NextResponse.json(
          { ok: false, error: "Order id already belongs to a completed checkout." },
          { status: 409, headers: corsHeaders },
        );
      }

      const requestedCashierId = String(rawOrder.baristaUserId ?? '').trim();
      const requestedCashier = store.users.find((user) => {
        if (user.id !== requestedCashierId) return false;
        const role = parseRole(String(user.title ?? ''), user.role);
        return ['cashier', 'admin'].includes(role);
      });
      const order: Order = {
        id: orderId || `ord-${Date.now()}`,
        createdAt,
        baristaName: requestedCashier?.name ?? claims.name,
        baristaUserId: requestedCashier?.id,
        items,
        subtotal: Number(rawOrder.subtotal) || 0,
        discount: Number(rawOrder.discount) || 0,
        promoLabel: typeof rawOrder.promoLabel === "string" ? rawOrder.promoLabel : undefined,
        total: Number(rawOrder.total) || 0,
        paymentMethod: parsePayment(rawOrder.paymentMethod),
        ticketNo: "",
        paid: 0,
        change: 0,
        voided: true,
        voidedBy,
        voidedByName,
        voidReason: reason,
      };
      const result = await createOrderAtomic({ order, deductions: [], voidedBy });
      if (!result.ok) {
        return NextResponse.json({ ok: false, error: result.error }, { status: 400, headers: corsHeaders });
      }
      order.ticketNo = result.ticketNo;
      return NextResponse.json({ ok: true, ticketNo: order.ticketNo, order }, { headers: corsHeaders });
    }

    if (action === "void_order") {
      const orderId = String(body.orderId ?? "").trim();
      const reason = String(body.reason ?? "Voided from POS").trim();
      const managerUsername = typeof body.managerUsername === "string" ? body.managerUsername.trim().toLowerCase() : "";
      const managerPassword = typeof body.managerPassword === "string" ? body.managerPassword : "";

      let voidedBy = claims.userId;
      let voidedByName = claims.name;
      if (claims.role !== "admin") {
        if (!managerUsername || !managerPassword) {
          return NextResponse.json(
            { ok: false, error: "Manager approval required to void an order." },
            { status: 403, headers: corsHeaders },
          );
        }
        const store = await getFreshStore();
        const manager = store.users.find((u) => u.username.trim().toLowerCase() === managerUsername);
        const role = manager ? parseRole(String(manager.title ?? ""), manager.role) : "barista";
        if (!manager || role !== "admin") {
          return NextResponse.json(
            { ok: false, error: "Manager or Admin credentials required to void an order." },
            { status: 403, headers: corsHeaders },
          );
        }
        const valid = manager.password.startsWith("$2")
          ? await bcrypt.compare(managerPassword, manager.password)
          : manager.password === managerPassword;
        if (!valid) {
          return NextResponse.json(
            { ok: false, error: "Invalid manager password." },
            { status: 403, headers: corsHeaders },
          );
        }
        // Record the approving manager/admin, not the cashier's API token.
        voidedBy = manager.id;
        voidedByName = manager.name;
      }

      const res = await voidOrderAtomic(orderId, reason, voidedBy);
      return NextResponse.json(
        res.ok ? { ...res, voidedBy, voidedByName } : res,
        { status: res.ok ? 200 : 400, headers: corsHeaders },
      );
    }

    if (action === "delete_order") {
      return NextResponse.json(
        { ok: false, error: "Order deletion is only available to Admin." },
        { status: 403, headers: corsHeaders },
      );
    }

    if (action === "create_restock") {
      const record = body.restock ?? body;
      const id = String(record.id || `rst-${Date.now()}`);
      const inventoryItemId = record.inventoryItemId ? String(record.inventoryItemId) : null;
      const itemNameSnapshot = String(record.itemName ?? record.itemNameSnapshot ?? "");
      const quantityAdded = Number(record.quantityAdded) || 0;
      const createdAt = phIsoTimestamp(String(record.date ?? record.createdAt ?? "")) || new Date().toISOString();
      const purchaseQty = record.purchaseQty != null ? Number(record.purchaseQty) : null;
      const purchaseUnit = typeof record.purchaseUnit === "string" ? record.purchaseUnit : null;

      const store = await getFreshStore();
      if (!store.restocks.some((r) => r.id === id)) {
        await createRestockAtomic({
          id,
          inventoryItemId,
          itemNameSnapshot,
          quantityAdded,
          createdAt,
          purchaseQty,
          purchaseUnit,
        });
      }
      return NextResponse.json({ ok: true, id }, { headers: corsHeaders });
    }

    if (action === "edit_restock") {
      await editRestockAtomic({
        id: String(body.id),
        oldInventoryItemId: body.oldInventoryItemId ?? null,
        oldQuantity: Number(body.oldQuantity) || 0,
        newInventoryItemId: body.newInventoryItemId ?? null,
        newItemNameSnapshot: String(body.newItemNameSnapshot ?? ""),
        newQuantity: Number(body.newQuantity) || 0,
        newCreatedAt: phIsoTimestamp(String(body.newCreatedAt ?? "")) || new Date().toISOString(),
        newPurchaseQty: body.newPurchaseQty != null ? Number(body.newPurchaseQty) : null,
        newPurchaseUnit: body.newPurchaseUnit ?? null,
      });
      return NextResponse.json({ ok: true }, { headers: corsHeaders });
    }

    if (action === "delete_restock") {
      const id = String(body.id ?? "").trim();
      if (!id) {
        return NextResponse.json({ ok: false, error: "Missing restock id" }, { status: 400, headers: corsHeaders });
      }
      await deleteRestockAtomic({ id });
      return NextResponse.json({ ok: true }, { headers: corsHeaders });
    }

    if (action === "upsert_inventory_item") {
      const raw = body.item ?? {};
      const item: InventoryItem = {
        id: String(raw.id || `stock-${Date.now()}`),
        name: String(raw.name ?? "").trim(),
        unit: String(raw.unit || "pcs").trim(),
        cost: Number(raw.cost) || 0,
        stock: Number(raw.stock) || 0,
        maxStock: Number(raw.maxStock ?? raw.stock) || 0,
        openingStock: raw.openingStock != null ? Number(raw.openingStock) : undefined,
        purchaseUnitSize: raw.purchaseUnitSize != null ? Number(raw.purchaseUnitSize) : undefined,
        cupUsageAmount: raw.cupUsageAmount != null ? Number(raw.cupUsageAmount) : undefined,
        cupsMake: raw.cupsMake != null ? Number(raw.cupsMake) : undefined,
        inventoryType: typeof raw.inventoryType === "string" && raw.inventoryType.trim() ? raw.inventoryType.trim().slice(0, 60) : undefined,
      };
      if (!item.name) {
        return NextResponse.json({ ok: false, error: "Item name is required" }, { status: 400, headers: corsHeaders });
      }
      await updateStore((store) => {
        const idx = store.inventory.findIndex((i) => i.id === item.id);
        if (idx >= 0) {
          store.inventory[idx] = item;
        } else {
          store.inventory.push(item);
        }
      });
      return NextResponse.json({ ok: true, item }, { headers: corsHeaders });
    }

    if (action === "delete_inventory_item") {
      const id = String(body.id ?? "").trim();
      if (!id) {
        return NextResponse.json({ ok: false, error: "Missing inventory item id" }, { status: 400, headers: corsHeaders });
      }
      const res = await deleteInventoryItemRecord(id);
      if ("error" in res) {
        return NextResponse.json({ ok: false, error: res.error }, { status: 400, headers: corsHeaders });
      }
      return NextResponse.json({ ok: true }, { headers: corsHeaders });
    }

    if (action === "create_void_request") {
      const raw = body.request ?? body;
      const reqRecord: VoidRequest = {
        id: String(raw.id || `vr-${Date.now()}`),
        requestedAt: phIsoTimestamp(String(raw.requestedAt ?? "")) || new Date().toISOString(),
        requestedById: claims.userId,
        requestedByName: claims.name,
        reason: String(raw.reason || "Void requested"),
        status: "pending",
        orderId: typeof raw.orderId === "string" ? raw.orderId : undefined,
        items: Array.isArray(raw.items) ? raw.items : [],
        subtotal: Number(raw.subtotal) || 0,
        discount: Number(raw.discount) || 0,
        promoLabel: typeof raw.promoLabel === "string" ? raw.promoLabel : undefined,
        total: Number(raw.total) || 0,
        paymentMethod: parsePayment(raw.paymentMethod),
      };
      await insertVoidRequestRecord(reqRecord);
      return NextResponse.json({ ok: true, request: reqRecord }, { headers: corsHeaders });
    }

    if (action === "login_activity" || action === "barista_shift_activity") {
      const isStaffShift = action === "barista_shift_activity";
      const raw = body.activity ?? body;
      let staff: Awaited<ReturnType<typeof getFreshStore>>["users"][number] | undefined;
      let requestedUserId = claims.userId;
      if (isStaffShift) {
        requestedUserId = typeof raw.userId === "string" ? raw.userId : "";
        const isOwnStaffShift =
          (claims.role === "barista" || claims.role === "pos_cashier") &&
          requestedUserId === claims.userId;
        if (
          !["cashier", "admin"].includes(claims.role) &&
          !isOwnStaffShift
        ) {
          return NextResponse.json({ ok: false, error: "Owner access required to record a staff shift." }, { status: 403, headers: corsHeaders });
        }
        const store = await getFreshStore();
        staff = store.users.find((user) => user.id === requestedUserId);
        const staffRole = staff ? parseRole(String(staff.title ?? ""), staff.role) : null;
        if ((!staff && !isOwnStaffShift) || (staff && staffRole !== "barista" && staffRole !== "pos_cashier")) {
          return NextResponse.json({ ok: false, error: "Staff account not found." }, { status: 404, headers: corsHeaders });
        }
      }
      const entry = {
        id: String(raw.id || `log-${Date.now()}`),
        userId: staff?.id ?? requestedUserId,
        username: staff?.username ?? claims.username,
        name: staff?.name ?? claims.name,
        role: staff
          ? parseRole(String(staff.title ?? ""), staff.role)
          : claims.role,
        type: (raw.type === "logout" ? "logout" : "login") as "login" | "logout",
        at: phIsoTimestamp(String(raw.at ?? "")) || new Date().toISOString(),
      };
      await insertLoginActivityRecord(entry);
      if (!isStaffShift && entry.type === "login") {
        await updateStore((store) => {
          store.pos.isOpen = true;
          store.pos.openedBy = entry.name;
          store.pos.openedAt = entry.at;
        });
      }
      return NextResponse.json({ ok: true }, { headers: corsHeaders });
    }

    return NextResponse.json(
      { ok: false, error: `Unknown sync action: ${action}` },
      { status: 400, headers: corsHeaders },
    );
    });
  } catch (error) {
    return NextResponse.json(
      {
        ok: false,
        error: error instanceof Error ? error.message : "Sync operation failed",
      },
      { status: 500, headers: corsHeaders },
    );
  }
}
