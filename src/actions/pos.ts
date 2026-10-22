"use server";

import { revalidatePath } from "next/cache";
import { getSession } from "@/lib/auth";
import { isDrinkCategory } from "@/lib/escpos";
import { orderLineOptionsLabel, pricedOrderLine } from "@/lib/menu";
import { parsePayment } from "@/lib/payments";
import { ingredientsForOrderLine, roundQty } from "@/lib/inventory";
import { canUsePos } from "@/lib/users";
import {
  appendPrintJobs,
  approveVoidRequestAtomic,
  createOrderAtomic,
  createRestockAtomic,
  deleteInventoryItemRecord,
  deleteOrderAtomic,
  deleteRecipeCostingRecord,
  deleteRestockAtomic,
  deleteRestockRecord,
  deleteVoidRequestRecord,
  editRestockAtomic,
  getFreshStore,
  getStore,
  getVoidRequestRecord,
  insertVoidRequestRecord,
  saveRecipeCostingRecord,
  saveUsageLogRecords,
  updateStore,
  voidOrderAtomic,
} from "@/lib/store";
import type {
  MenuItem,
  Order,
  OrderItem,
  PrintJob,
  PrintJobStatus,
  PrintJobType,
  StoreData,
} from "@/lib/types";

async function cashierMustChangePassword(userId: string) {
  const store = await getFreshStore();
  return !store.users.some((user) => user.id === userId && user.role === "cashier" && user.passwordChanged);
}

async function requirePos() {
  const session = await getSession();
  if (
    !session ||
    !canUsePos(session.role) ||
    session.mustChangePassword ||
    (session.role === "cashier" && await cashierMustChangePassword(session.userId))
  ) {
    throw new Error("Only POS staff can use the POS.");
  }
  return session;
}

async function requireCashier() {
  const session = await getSession();
  if (
    !session ||
    !canUsePos(session.role) ||
    session.mustChangePassword ||
    (session.role === "cashier" && await cashierMustChangePassword(session.userId))
  ) {
    throw new Error("Only authorized staff can take orders.");
  }
  return session;
}

async function requireAdmin() {
  const session = await getSession();
  if (!session || session.role !== "admin") {
    throw new Error("Only an admin can change store records.");
  }
  return session;
}

async function requireInventoryAccess() {
  const session = await getSession();
  if (!session || (session.role !== "admin" && session.role !== "cashier")) {
    throw new Error("Only an Owner or admin can change these store records.");
  }
  return session;
}

function labelJobsForOrder(
  order: Order,
  menu: MenuItem[],
  idPrefix: string,
  createdAt: string,
): PrintJob[] {
  const categoryByProduct = new Map(menu.map((item) => [item.id, item.category]));
  let labelIndex = 0;

  return order.items.flatMap((item, itemIndex) => {
    const category = item.category ?? categoryByProduct.get(item.productId);
    if (!isDrinkCategory(category)) return [];

    return Array.from({ length: item.qty }, (_, copyIndex) => {
      labelIndex += 1;
      return {
        id: `${idPrefix}-label-${labelIndex}`,
        orderId: order.id,
        type: "cup-label" as const,
        status: "pending" as const,
        attempts: 0,
        createdAt,
        updatedAt: createdAt,
        label: {
          productId: item.productId,
          name: orderLineOptionsLabel(item)
            ? `${item.name} / ${orderLineOptionsLabel(item)}`
            : item.name,
          price: item.price,
          itemIndex,
          copyIndex,
          copiesForItem: item.qty,
        },
      };
    });
  });
}

function initialPrintJobs(order: Order, menu: MenuItem[]): PrintJob[] {
  const createdAt = order.createdAt;
  return [
    ...labelJobsForOrder(order, menu, order.id, createdAt),
    {
      id: `${order.id}-receipt`,
      orderId: order.id,
      type: "customer-receipt",
      status: "pending",
      attempts: 0,
      createdAt,
      updatedAt: createdAt,
    },
  ];
}

function reprintId(orderId: string, type: PrintJobType): string {
  return `${orderId}-${type}-reprint-${Date.now().toString(36)}-${Math.random()
    .toString(36)
    .slice(2, 7)}`;
}

export async function saveAdminData(data: {
  inventory?: StoreData["inventory"];
  restocks?: StoreData["restocks"];
  recipes?: StoreData["recipes"];
  recipeCostings?: StoreData["recipeCostings"];
  usageLogs?: StoreData["usageLogs"];
}) {
  // Owners can manage the complete inventory setup, including recipes and
  // recipe costings. POS-only cashier checks remain in requireCashier().
  await requireInventoryAccess();

  if (data.usageLogs) {
    await saveUsageLogRecords(data.usageLogs);
  }

  if (data.recipeCostings) {
    // Freeze usage calculated from the current recipes before they are edited
    // or deleted. Otherwise the Usage Logbook would reconstruct old orders
    // from the changed recipe and their historical usage could disappear.
    const current = await getFreshStore();
    const loggedOrderIds = new Set(current.usageLogs.map((entry) => entry.orderId).filter(Boolean));
    const usageSnapshots = current.orders
      .filter((order) => !order.voided && !order.deletedAt && !loggedOrderIds.has(order.id))
      .flatMap((order) => {
        const entries = order.items.flatMap((line, lineIndex) =>
          ingredientsForOrderLine(current, line).map((ingredient, ingredientIndex) => ({
            id: `recipe-snapshot-${order.id}-${lineIndex}-${ingredientIndex}`,
            ownerId: undefined,
            orderId: order.id,
            orderItemId: line.productId,
            inventoryItemId: ingredient.inventoryItemId && ingredient.inventoryItemId !== "other"
              ? ingredient.inventoryItemId
              : undefined,
            date: order.createdAt,
            itemName: ingredient.name,
            usedAmount: roundQty(Number(ingredient.amount) * line.qty),
            unit: ingredient.unit,
          })),
        );
        // A marker preserves the fact that this order was checked and had no
        // recipe, so a later recipe addition cannot rewrite its history.
        return entries.length > 0 ? entries : [{
          id: `recipe-snapshot-${order.id}-none`,
          ownerId: undefined,
          orderId: order.id,
          orderItemId: "",
          inventoryItemId: undefined,
          date: order.createdAt,
          itemName: "__usage_snapshot_empty__",
          // usage_logs requires used_amount > 0. This internal marker is
          // filtered from the logbook and has no inventory item, so it never
          // changes stock or appears as a real usage quantity.
          usedAmount: 1,
          unit: "__snapshot__",
        }];
      });
    if (usageSnapshots.length > 0) await saveUsageLogRecords(usageSnapshots);

    // SaveCostings()/deleteRecipeCosting() send the full resulting costing
    // array (a delete is the array without that entry).
    const nextIds = new Set(data.recipeCostings.map((entry) => entry.id));
    for (const existing of current.recipeCostings) {
      if (!nextIds.has(existing.id)) {
        await deleteRecipeCostingRecord(existing.id);
      }
    }
    for (const costing of data.recipeCostings) {
      await saveRecipeCostingRecord(costing);
    }
  }

  await updateStore((store) => {
    if (data.inventory) store.inventory = data.inventory;
    if (data.restocks) store.restocks = data.restocks;
    if (data.recipes && Object.keys(data.recipes).length > 0) store.recipes = data.recipes;
    if (data.recipeCostings) store.recipeCostings = data.recipeCostings;
  });
  revalidatePath("/pos");
  revalidatePath("/owner");
  return { ok: true };
}

export async function setPosInventoryFeaturesEnabled(enabled: boolean) {
  await requireInventoryAccess();
  await updateStore((store) => {
    store.pos.inventoryFeaturesEnabled = enabled;
  });
  revalidatePath("/pos");
  revalidatePath("/owner");
  return { ok: true };
}

export async function setPosPrintButtonHidden(hidden: boolean) {
  const session = await getSession();
  if (!session || (session.role !== "admin" && session.role !== "cashier")) {
    throw new Error("Only an Owner or admin can change POS print settings.");
  }
  await updateStore((store) => {
    store.pos.printButtonHidden = hidden;
  });
  revalidatePath("/pos");
  revalidatePath("/owner");
  return { ok: true };
}

export async function deleteAdminRecord(kind: "order" | "inventory" | "restock" | "usage", id: string) {
  await requireInventoryAccess();

  if (kind === "order") {
    // Order deletion is soft: the row and its audit children remain stored.
    // Inventory is restored atomically unless the order was already voided.
    await deleteOrderAtomic(id);
  } else if (kind === "restock") {
    await deleteRestockRecord(id);
  } else if (kind === "inventory") {
    const result = await deleteInventoryItemRecord(id);
    if ("error" in result) return result;
  } else {
    // No live UI deletes a single usage_logs row directly; usage_logs
    // cleanup for a deleted order is handled by delete_order_atomic's cascade.
    await updateStore((store) => {
      store.usageLogs = store.usageLogs.filter((record) => record.id !== id);
    });
  }

  revalidatePath("/pos");
  revalidatePath("/owner");
  return { ok: true };
}

export async function createRestock(input: {
  id: string;
  inventoryItemId: string | null;
  itemNameSnapshot: string;
  quantityAdded: number;
  createdAt: string;
  purchaseQty?: number | null;
  purchaseUnit?: string | null;
}) {
  await requireInventoryAccess();
  await createRestockAtomic(input);
  revalidatePath("/pos");
  revalidatePath("/owner");
  return { ok: true };
}

export async function editRestock(input: {
  id: string;
  oldInventoryItemId: string | null;
  oldQuantity: number;
  newInventoryItemId: string | null;
  newItemNameSnapshot: string;
  newQuantity: number;
  newCreatedAt: string;
  newPurchaseQty?: number | null;
  newPurchaseUnit?: string | null;
}) {
  await requireInventoryAccess();
  await editRestockAtomic(input);
  revalidatePath("/pos");
  revalidatePath("/owner");
  return { ok: true };
}

export async function deleteRestock(input: { id: string }) {
  await requireInventoryAccess();
  await deleteRestockAtomic(input);
  revalidatePath("/pos");
  revalidatePath("/owner");
  return { ok: true };
}

export async function openPos() {
  const session = await requirePos();
  await updateStore((store) => {
    store.pos = {
      ...store.pos,
      isOpen: true,
      openedAt: new Date().toISOString(),
      openedBy: session.name,
    };
  });
  revalidatePath("/pos");
  revalidatePath("/owner");
}

export async function closePos() {
  await requirePos();
  await updateStore((store) => {
    store.pos = {
      ...store.pos,
      isOpen: false,
      openedAt: null,
      openedBy: null,
    };
  });
  revalidatePath("/pos");
  revalidatePath("/owner");
}

export async function createOrder(
  cart: OrderItem[],
  paymentMethod?: string | null,
  tendered?: number | null,
  serviceMode?: "dine-in" | "take-out",
  promoCode?: string | null,
  promoItemIndex?: number | null,
  promoItemQty?: number | null,
) {
  const session = await requireCashier();

  if (cart.length === 0) {
    return { ok: false as const, error: "Add a drink before charging." };
  }

  const store = await getStore();
  if (!store.pos.isOpen) {
    return { ok: false as const, error: "Open the POS before taking orders." };
  }

  const priced: OrderItem[] = [];
  for (const line of cart) {
    const menuItem = store.menu.find((item) => item.id === line.productId);
    const qty = Number(line.qty);
    if (!menuItem || !menuItem.available) {
      return { ok: false as const, error: "One of the items is no longer on the menu." };
    }
    if (!Number.isSafeInteger(qty) || qty < 1 || qty > 99) {
      return { ok: false as const, error: "Each item quantity must be a whole number from 1 to 99." };
    }
    priced.push({
      ...pricedOrderLine(menuItem, { ...line, qty }),
      serviceMode: serviceMode === "take-out" ? "take-out" : "dine-in",
    });
  }

  const subtotal = priced.reduce(
    (sum, item) => sum + (item.price + (item.addons ?? []).reduce((addonSum, addon) => addonSum + addon.price * addon.qty, 0)) * item.qty,
    0,
  );
  let discount = 0;
  let normalizedPromoCode: string | undefined;
  let selectedPromoItemIndex: number | undefined;
  let selectedPromoItemQty: number | undefined;
  if (promoCode?.trim()) {
    normalizedPromoCode = promoCode.trim().toUpperCase();
    const owner = store.users.find((user) => user.id === session.userId && user.role === "cashier");
    const permissions = owner?.permissions;
    const promo = permissions?.promoCodes?.find((entry) => entry.code.toUpperCase() === normalizedPromoCode);
    if (!owner || permissions?.promotionsEnabled !== true || permissions.promotionDiscount !== true || !promo) {
      return { ok: false as const, error: "Invalid promotion code." };
    }
    if (promo.redeemedAt) return { ok: false as const, error: "The promotion code already used." };
    if (promo.expiresAt && Date.parse(promo.expiresAt) <= Date.now()) {
      return { ok: false as const, error: "This promo voucher has expired." };
    }
    if (promo.discountType === "item") {
      const freeItemQty = Math.max(1, Math.floor(promo.discountValue || 1));
      if (!Number.isInteger(promoItemIndex) || promoItemIndex! < 0 || promoItemIndex! >= priced.length) {
        return { ok: false as const, error: `Choose an item with quantity ${freeItemQty} or more to make free.` };
      }
      const selectedItem = priced[promoItemIndex!];
      const selectedQty = Number(promoItemQty);
      if (!Number.isInteger(selectedQty) || selectedQty !== freeItemQty || selectedQty > selectedItem.qty) {
        return { ok: false as const, error: `Select ${freeItemQty} unit(s) of the chosen item to make free.` };
      }
      discount = Math.round((selectedItem.price + (selectedItem.addons ?? []).reduce((sum, addon) => sum + addon.price * addon.qty, 0)) * selectedQty);
      selectedPromoItemIndex = promoItemIndex!;
      selectedPromoItemQty = selectedQty;
    } else {
      discount = Math.min(subtotal, Math.round(promo.discountType === "amount" ? promo.discountValue : subtotal * promo.discountValue / 100));
    }
  }
  const total = Math.max(0, subtotal - discount);
  const method = parsePayment(paymentMethod);
  const cashIn = method === "cash" ? Math.max(0, Math.round(Number(tendered) || 0)) : total;
  if (method === "cash" && cashIn < total) {
    return { ok: false as const, error: "Cash tendered is short." };
  }

  // The ticket number is allocated inside create_order_atomic on a per-PH-day
  // DB counter, not from this (possibly stale) cached order list.
  const orderId = `ord-${Date.now()}`;
  const createdAt = new Date().toISOString();

  // Aggregate ingredient deductions per inventory item across all cart
  // lines (same resolution logic and normalization as before - only the
  // write path changed). This is the "current server-side recipe/costing
  // logic" the atomic RPC applies; recipe/costing resolution stays here in
  // TypeScript rather than being reimplemented in SQL.
  const normalize = (value: string) => value.trim().toLowerCase().replace(/[-_]+/g, " ").replace(/\s+/g, " ");
  const deductionsByItem = new Map<string, { itemName: string; amount: number; unit: string; orderItemId: string }>();
  for (const line of priced) {
    for (const ingredient of ingredientsForOrderLine(store, line)) {
      const inventory = store.inventory.find(
        (item) => item.id === ingredient.inventoryItemId || normalize(item.name) === normalize(ingredient.name),
      );
      if (!inventory) continue;
      const amount = roundQty(ingredient.amount * line.qty);
      const existing = deductionsByItem.get(inventory.id);
      if (existing) {
        existing.amount = roundQty(existing.amount + amount);
      } else {
        deductionsByItem.set(inventory.id, { itemName: inventory.name, amount, unit: ingredient.unit, orderItemId: line.productId });
      }
    }
  }
  const deductions = Array.from(deductionsByItem.entries()).map(([inventoryItemId, value]) => ({
    inventoryItemId,
    ...value,
  }));

  const createdOrder: Order = {
    id: orderId,
    createdAt,
    baristaName: session.name,
    baristaUserId: session.userId,
    items: priced,
    subtotal,
    discount,
    promoLabel: normalizedPromoCode,
    promoItemIndex: selectedPromoItemIndex,
    promoItemQty: selectedPromoItemQty,
    total,
    paymentMethod: method,
    serviceMode: serviceMode === "take-out" ? "take-out" : "dine-in",
    paid: cashIn,
    change: method === "cash" ? cashIn - total : 0,
    voided: false,
  };

  const result = await createOrderAtomic({ order: createdOrder, deductions });
  if (!result.ok) {
    return { ok: false as const, error: result.error };
  }
  const ticketNo = result.ticketNo;
  createdOrder.ticketNo = ticketNo;

  const createdPrintJobs = initialPrintJobs(createdOrder, store.menu);
  await appendPrintJobs(createdPrintJobs);

  revalidatePath("/pos");
  revalidatePath("/owner");
  return {
    ok: true as const,
    total,
    ticketNo,
    id: orderId,
    order: createdOrder,
    printJobs: createdPrintJobs,
  };
}

function voidingIsDisabled(): boolean {
  return true;
}

export async function verifyManager(username: string, password: string) {
  if (voidingIsDisabled()) return { error: "Voiding is disabled." };
  await requirePos();
  const store = await getStore();
  const user = store.users.find(
    (entry) =>
      entry.role === "admin" &&
      entry.username === username.trim().toLowerCase() &&
      Boolean(entry.password) &&
      entry.password === password,
  );
  if (!user) {
    return { error: "Manager or admin credentials required to void." };
  }
  return { ok: true, name: user.name, id: user.id };
}

export async function voidOrder(
  orderId: string,
  reason: string,
  managerUsername?: string,
  managerPassword?: string,
) {
  if (voidingIsDisabled()) return { error: "Voiding is disabled." };
  const session = await requirePos();
  if (!reason.trim()) {
    return { error: "Enter a reason for voiding." };
  }

  // Attribute cashier-authorized voids to the manager/admin who approved them.
  let voidedBy: string | null = null;
  if (session.role === "cashier") {
    const auth = await verifyManager(managerUsername ?? "", managerPassword ?? "");
    if ("error" in auth) return auth;
    voidedBy = auth.id;
  } else if (session.role === "admin") {
    voidedBy = session.userId;
  } else {
    return { error: "Only a manager or admin can void a transaction." };
  }

  const result = await voidOrderAtomic(orderId, reason.trim(), voidedBy);
  if (!result.ok) return { error: result.error };

  revalidatePath("/pos");
  revalidatePath("/owner");
  return { ok: true };
}

export async function requestVoidApproval(
  cart: OrderItem[],
  reason: string,
  orderId?: string | null,
  paymentMethod?: string | null,
) {
  if (voidingIsDisabled()) return { error: "Voiding is disabled." };
  const session = await requireCashier();
  const trimmedReason = reason.trim();
  if (!trimmedReason) return { error: "Enter a reason for voiding." };

  // Validation needs current data (order state, menu, existing
  // pending requests), not the TTL-cached snapshot.
  const store = await getFreshStore();

  if (
    store.voidRequests.some(
      (request) =>
        request.requestedById === session.userId && request.status === "pending",
    )
  ) {
    return { error: "You already have a void request waiting for admin approval." };
  }

  const existingOrder = orderId
    ? store.orders.find((order) => order.id === orderId)
    : undefined;
  if (orderId && !existingOrder) {
    return { error: "Ticket not found." };
  }
  if (existingOrder?.voided) {
    return { error: "Ticket is already voided." };
  }

  let items: OrderItem[] = [];
  let subtotal = 0;
  let discount = 0;
  let promoLabel: string | undefined;
  let total = 0;
  let requestedPayment = parsePayment(paymentMethod);

  if (existingOrder) {
    items = existingOrder.items.map((item) => ({ ...item }));
    subtotal = existingOrder.subtotal ?? existingOrder.total;
    discount = existingOrder.discount ?? 0;
    promoLabel = existingOrder.promoLabel;
    total = existingOrder.total;
    requestedPayment = parsePayment(existingOrder.paymentMethod);
  } else {
    if (cart.length === 0) {
      return { error: "No items to void." };
    }
    for (const line of cart) {
      const menuItem = store.menu.find((item) => item.id === line.productId);
      const qty = Number(line.qty);
      if (!menuItem) {
        return { error: "One of the items is no longer on the menu." };
      }
      if (!Number.isSafeInteger(qty) || qty < 1 || qty > 99) {
        return { error: "Each item quantity must be a whole number from 1 to 99." };
      }
      items.push(pricedOrderLine(menuItem, { ...line, qty }));
    }
    subtotal = items.reduce((sum, item) => sum + item.price * item.qty, 0);
    total = subtotal;
  }

  const requestId = `void-request-${Date.now().toString(36)}-${Math.random()
    .toString(36)
    .slice(2, 7)}`;

  try {
    await insertVoidRequestRecord({
      id: requestId,
      requestedAt: new Date().toISOString(),
      requestedById: session.userId,
      requestedByName: session.name,
      reason: trimmedReason,
      status: "pending",
      orderId: existingOrder?.id,
      items,
      subtotal,
      discount,
      promoLabel,
      total,
      paymentMethod: requestedPayment,
    });
  } catch (insertError) {
    // The partial unique index enforces one pending request per cashier at
    // the DB level, so a cross-instance double-submit lands here.
    if (/one_pending_per_user/.test((insertError as Error).message)) {
      return { error: "You already have a void request waiting for admin approval." };
    }
    throw insertError;
  }

  revalidatePath("/pos");
  revalidatePath("/owner");
  return { ok: true, requestId };
}

export async function getVoidRequestStatus(requestId: string) {
  const session = await requirePos();
  // Targeted DB read, not the cached store: a cashier polling on one
  // instance must see an approval committed by another instance promptly.
  const request = await getVoidRequestRecord(requestId);
  if (!request || request.requestedById !== session.userId) {
    return { found: false as const };
  }
  return {
    found: true as const,
    status: request.status,
    orderId: request.orderId ?? null,
    processedOrderId: request.processedOrderId ?? null,
  };
}

export async function deleteVoidRequest(requestId: string) {
  if (voidingIsDisabled()) return { error: "Voiding is disabled." };
  await requireAdmin();
  const request = await getVoidRequestRecord(requestId);
  if (!request) {
    return { error: "Void request not found." };
  }

  await deleteVoidRequestRecord(requestId);

  revalidatePath("/pos");
  revalidatePath("/owner");
  return { ok: true };
}

export async function approveVoidRequest(requestId: string) {
  if (voidingIsDisabled()) return { error: "Voiding is disabled." };
  const session = await requireAdmin();
  try {
    // Read durable state rather than a potentially stale cached snapshot.
    const request = await getVoidRequestRecord(requestId);
    if (!request) {
      return { error: "Void request not found." };
    }
    if (request.status !== "pending") {
      return { error: "Void request is already approved." };
    }

    const newOrderId = request.orderId
      ? null
      : `ord-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`;

    const result = await approveVoidRequestAtomic({
      requestId,
      approvedById: session.userId,
      approvedByName: session.name,
      newOrderId,
    });
    if (!result.ok) return { error: result.error };

    revalidatePath("/pos");
    revalidatePath("/owner");
    return { ok: true };
  } catch (error) {
    console.error("Unable to approve void request:", error);
    return {
      error: error instanceof Error
        ? error.message
        : "Unable to approve void request. Check the server logs for details.",
    };
  }
}

export async function voidCheckout(
  cart: OrderItem[],
  reason: string,
  managerUsername: string,
  managerPassword: string,
  paymentMethod?: string | null,
) {
  if (voidingIsDisabled()) return { error: "Voiding is disabled." };
  const session = await requireCashier();
  if (!reason.trim()) {
    return { error: "Enter a reason for voiding." };
  }
  if (cart.length === 0) {
    return { error: "No items to void." };
  }

  const auth = await verifyManager(managerUsername, managerPassword);
  if ("error" in auth) return auth;

  const store = await getStore();
  const priced: OrderItem[] = [];
  for (const line of cart) {
    const menuItem = store.menu.find((item) => item.id === line.productId);
    const qty = Number(line.qty);
    if (!menuItem) {
      return { error: "One of the items is no longer on the menu." };
    }
    if (!Number.isSafeInteger(qty) || qty < 1 || qty > 99) {
      return { error: "Each item quantity must be a whole number from 1 to 99." };
    }
    priced.push(pricedOrderLine(menuItem, { ...line, qty }));
  }

  const subtotal = priced.reduce((sum, item) => sum + item.price * item.qty, 0);
  const total = subtotal;

  // create_order_atomic writes the already-voided order + items atomically:
  // it allocates the ticket on the DB counter, sets voided_at = now(), and
  // records the approving manager/admin in voided_by. No
  // deductions - a pre-checkout void never touched inventory.
  const orderId = `ord-${Date.now()}`;
  const createdOrder: Order = {
    id: orderId,
    createdAt: new Date().toISOString(),
    baristaName: session.name,
    items: priced,
    subtotal,
    discount: 0,
    total,
    paymentMethod: parsePayment(paymentMethod),
    paid: 0,
    change: 0,
    voided: true,
    voidedBy: auth.id,
    voidedByName: auth.name,
    voidReason: reason.trim(),
  };

  const result = await createOrderAtomic({ order: createdOrder, deductions: [], voidedBy: auth.id });
  if (!result.ok) return { error: result.error };

  revalidatePath("/pos");
  revalidatePath("/owner");
  return { ok: true, id: orderId };
}

export async function beginPrintJob(jobId: string) {
  await requirePos();
  let error: string | undefined;
  let updated: PrintJob | null = null;

  await updateStore((store) => {
    const job = store.printJobs.find((entry) => entry.id === jobId);
    const order = job
      ? store.orders.find((entry) => entry.id === job.orderId)
      : undefined;
    if (!job || !order) {
      error = "Print job not found.";
      return;
    }
    if (order.voided || job.status === "cancelled") {
      error = "A voided order cannot be printed.";
      return;
    }
    if (job.status === "printed") {
      error = "This print job has already succeeded.";
      return;
    }

    job.attempts += 1;
    job.status = "pending";
    job.updatedAt = new Date().toISOString();
    delete job.lastError;
    updated = { ...job, label: job.label ? { ...job.label } : undefined };
  });

  if (error || !updated) return { error: error ?? "Unable to start print job." };
  revalidatePath("/pos");
  return { ok: true, job: updated };
}

export async function finishPrintJob(
  jobId: string,
  status: Extract<PrintJobStatus, "printed" | "failed">,
  message?: string,
) {
  await requirePos();
  if (status !== "printed" && status !== "failed") {
    return { error: "Invalid print job status." };
  }
  let error: string | undefined;
  let updated: PrintJob | null = null;

  await updateStore((store) => {
    const job = store.printJobs.find((entry) => entry.id === jobId);
    if (!job) {
      error = "Print job not found.";
      return;
    }
    if (job.status === "cancelled") {
      error = "A cancelled print job cannot be updated.";
      return;
    }

    const now = new Date().toISOString();
    job.status = status;
    job.updatedAt = now;
    if (status === "printed") {
      job.printedAt = now;
      delete job.lastError;
    } else {
      job.lastError = (message || "Printer failed.").trim().slice(0, 240);
    }
    updated = { ...job, label: job.label ? { ...job.label } : undefined };
  });

  if (error || !updated) return { error: error ?? "Unable to update print job." };
  revalidatePath("/pos");
  return { ok: true, job: updated };
}

export async function queueReprintJobs(
  orderId: string,
  type: PrintJobType,
  sourceLabelJobId?: string,
) {
  await requirePos();
  if (type !== "cup-label" && type !== "customer-receipt") {
    return { error: "Invalid print job type." };
  }
  let error: string | undefined;
  let created: PrintJob[] = [];

  await updateStore((store) => {
    const order = store.orders.find((entry) => entry.id === orderId);
    if (!order || order.voided) {
      error = "Completed order not found.";
      return;
    }

    const createdAt = new Date().toISOString();
    if (type === "customer-receipt") {
      created = [
        {
          id: reprintId(order.id, type),
          orderId: order.id,
          type,
          status: "pending",
          attempts: 0,
          createdAt,
          updatedAt: createdAt,
        },
      ];
    } else if (sourceLabelJobId) {
      const source = store.printJobs.find(
        (job) =>
          job.id === sourceLabelJobId &&
          job.orderId === order.id &&
          job.type === "cup-label" &&
          job.label,
      );
      if (!source?.label) {
        error = "Cup label job not found.";
        return;
      }
      created = [
        {
          id: reprintId(order.id, type),
          orderId: order.id,
          type,
          status: "pending",
          attempts: 0,
          createdAt,
          updatedAt: createdAt,
          label: { ...source.label },
        },
      ];
    } else {
      created = labelJobsForOrder(
        order,
        store.menu,
        reprintId(order.id, type),
        createdAt,
      );
      if (created.length === 0) {
        error = "This order has no cup labels.";
        return;
      }
    }

    store.printJobs.push(...created);
  });

  if (error) return { error };
  revalidatePath("/pos");
  return { ok: true, printJobs: created };
}
