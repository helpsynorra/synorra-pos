"use client";

import { useCallback, useEffect, useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import Image from "next/image";
import { logout } from "@/actions/auth";
import { punchBaristaShift } from "@/actions/users";
import {
  beginPrintJob,
  createOrder,
  recordWaste,
  finishPrintJob,
  getVoidRequestStatus,
  openPos,
  queueReprintJobs,
  requestVoidApproval,
  verifyManager,
  voidCheckout,
  voidOrder,
} from "@/actions/pos";
import { SlipPreview } from "@/components/ReceiptPreview";
import {
  SalePurchaseTransactions,
  type InventoryTab,
} from "@/components/SalePurchaseTransactions";
import {
  addonIdFromName,
  addonAllowsQty,
  cartLineKey,
  cartLineUnitPrice,
  drinkDisplayName,
  drinkStyleLabel,
  formatMoney,
  normalizeMenuAddons,
  normalizeMenuStyles,
  normalizeMenuTypes,
  normalizeMenuTypeOptions,
  orderLineListLabel,
  orderLineOptionsLabel,
  resolveOrderAddons,
} from "@/lib/menu";
import { phDateTimeLabel } from "@/lib/datetime";
import { PAYMENT_METHODS, parsePayment, paymentLabel } from "@/lib/payments";
import {
  slipFromOrder,
  type slipTicket,
} from "@/lib/escpos";
import { useLabelPrinter } from "@/lib/label-printer";
import { useslipPrinter } from "@/lib/receipt-printer";
import type {
  DrinkStyle,
  MenuItem,
  Order,
  OrderAddon,
  OrderItem,
  PaymentMethod,
  PrintJob,
  PrintJobType,
  PosState,
  Session,
  StoreData,
  VoidRequest,
} from "@/lib/types";

type PosClientProps = {
  session: Session;
  pos: PosState;
  inventoryFeaturesEnabled?: boolean;
  menu: MenuItem[];
  categories: string[];
  orders: Order[];
  clockedInBaristas: { id: string; name: string; username: string }[];
  printJobs: PrintJob[];
  voidRequests: VoidRequest[];
  inventoryStore: Pick<
    StoreData,
    | "orders"
    | "inventory"
    | "usageLogs"
    | "restocks"
    | "recipes"
    | "recipeCostings"
    | "menu"
  >;
};

type PosPanel = "pos" | Extract<InventoryTab, "stock" | "restock">;

const CASH_PRESETS = [500, 1000, 2000];
const CHECKOUT_KEY = "synorra_pos_checkout";
const TEST_PRINTER_ENABLED = process.env.NEXT_PUBLIC_TEST_PRINTER === "true";
type SavedCheckout = {
  userId: string;
  cart: OrderItem[];
  tendered: string;
  paymentMethod: PaymentMethod;
  serviceMode: "dine-in" | "take-out";
  voidRequestId: string | null;
  promoCode?: string;
  promoItemIndex?: number | null;
  promoItemQty?: number | null;
};

function readCheckout(userId: string, menu: MenuItem[]): SavedCheckout | null {
  try {
    const raw = window.localStorage.getItem(CHECKOUT_KEY);
    if (!raw) return null;
    const saved = JSON.parse(raw) as SavedCheckout;
    if (saved.userId !== userId || !Array.isArray(saved.cart)) return null;

    const catalog = new Map(menu.map((item) => [item.id, item]));
    const cart = saved.cart.flatMap((item) => {
      const product = catalog.get(item.productId);
      if (!product || product.available === false) return [];
      const qty = Math.floor(Number(item.qty));
      if (!Number.isFinite(qty) || qty < 1) return [];
      const style = item.style === "hot" || item.style === "iced" ? item.style : undefined;
      const addons = resolveOrderAddons(product, item.addons);
      return [
        {
          productId: product.id,
          name: product.name,
          qty,
          price: product.price,
          style,
          addons,
        },
      ];
    });

    return {
      userId,
      cart,
      tendered: typeof saved.tendered === "string" ? saved.tendered : "",
      paymentMethod: parsePayment(saved.paymentMethod),
      serviceMode: saved.serviceMode === "take-out" ? "take-out" : "dine-in",
      voidRequestId:
        typeof saved.voidRequestId === "string" ? saved.voidRequestId : null,
      promoCode: typeof saved.promoCode === "string" ? saved.promoCode : "",
      promoItemIndex: Number.isInteger(saved.promoItemIndex) ? saved.promoItemIndex : null,
      promoItemQty: Number.isInteger(saved.promoItemQty) ? saved.promoItemQty : Number.isInteger(saved.promoItemIndex) ? 1 : null,
    };
  } catch {
    return null;
  }
}

function writeCheckout(value: SavedCheckout) {
  window.localStorage.setItem(CHECKOUT_KEY, JSON.stringify(value));
}

export function PosClient({
  session,
  pos,
  inventoryFeaturesEnabled = false,
  menu,
  categories,
  orders,
  clockedInBaristas,
  printJobs,
  voidRequests,
  inventoryStore,
}: PosClientProps) {
  const router = useRouter();
  const [cart, setCart] = useState<OrderItem[]>([]);
  const [category, setCategory] = useState("All");
  const [itemSearch, setItemSearch] = useState("");
  const [mobileCheckoutOpen, setMobileCheckoutOpen] = useState(false);
  const [tendered, setTendered] = useState("");
  const [paymentMethod, setPaymentMethod] = useState<PaymentMethod>("cash");
  const [serviceMode, setServiceMode] = useState<"dine-in" | "take-out">("dine-in");
  const [promoDraft, setPromoDraft] = useState("");
  const [promoCode, setPromoCode] = useState("");
  const [promoItemIndex, setPromoItemIndex] = useState<number | null>(null);
  const [promoItemQty, setPromoItemQty] = useState<number | null>(null);
  const [voidModalOpen, setVoidModalOpen] = useState(false);
  const [voidUsername, setVoidUsername] = useState("");
  const [voidPassword, setVoidPassword] = useState("");
  const [voidReason, setVoidReason] = useState("");
  const [voidTargetId, setVoidTargetId] = useState<string | null>(null);
  const [activeVoidRequestId, setActiveVoidRequestId] = useState<string | null>(null);
  const [wasteModalOpen, setWasteModalOpen] = useState(false);
  const [wasteReason, setWasteReason] = useState("");
  const [wasteBaristaIds, setWasteBaristaIds] = useState<string[]>([]);
  const [printOrderId, setPrintOrderId] = useState<string | null>(null);
  const [lastTicket, setLastTicket] = useState<slipTicket | null>(null);
  const [lastOrderId, setLastOrderId] = useState<string | null>(null);
  const [lastOrder, setLastOrder] = useState<Order | null>(null);
  const [localPrintJobs, setLocalPrintJobs] = useState<PrintJob[]>([]);
  const canRecordWaste = session.permissions?.wasteManagement !== false;
  const [message, setMessage] = useState<string | null>(null);
  const [baristaModalOpen, setBaristaModalOpen] = useState(false);
  const [baristaUsername, setBaristaUsername] = useState("");
  const [baristaPassword, setBaristaPassword] = useState("");
  const [baristaAction, setBaristaAction] = useState<"login" | "logout">("login");
  const [baristaTargetId, setBaristaTargetId] = useState<string | null>(null);
  const [baristaNotice, setBaristaNotice] = useState<string | null>(null);
  const [onShift, setOnShift] = useState(() => clockedInBaristas);
  const [drinkPick, setDrinkPick] = useState<{
    item: MenuItem;
    style?: DrinkStyle;
    addons: Record<string, number>;
    qty?: number;
  } | null>(null);
  const [pending, startTransition] = useTransition();
  const labelPrinter = useLabelPrinter();
  const slipPrinter = useslipPrinter();
  const [checkoutReady, setCheckoutReady] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [activePanel, setActivePanel] = useState<PosPanel>("pos");
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 60000);
    return () => window.clearInterval(timer);
  }, []);
  const visiblePanel =
    inventoryFeaturesEnabled || (activePanel !== "stock" && activePanel !== "restock")
      ? activePanel
      : "pos";
  const availableOrders = useMemo(() => {
    const byId = new Map(
      orders.filter((order) => !order.voided && !order.deletedAt).map((order) => [order.id, order]),
    );
    const lastOrderVoided = Boolean(
      lastOrder && orders.some((order) => order.id === lastOrder.id && order.voided),
    );
    if (lastOrder && !lastOrder.voided && !lastOrderVoided) {
      byId.set(lastOrder.id, lastOrder);
    }
    return [...byId.values()].sort((a, b) => b.createdAt.localeCompare(a.createdAt));
  }, [lastOrder, orders]);
  const knownPrintJobs = useMemo(() => {
    const byId = new Map(printJobs.map((job) => [job.id, job]));
    for (const job of localPrintJobs) byId.set(job.id, job);
    return [...byId.values()];
  }, [localPrintJobs, printJobs]);
  const selectedPrintOrder = availableOrders.find(
    (order) => order.id === printOrderId,
  );
  const selectedPrintTicket = selectedPrintOrder
    ? slipFromOrder(selectedPrintOrder, availableOrders, menu)
    : null;
  const selectedPrintJobs = selectedPrintOrder
    ? knownPrintJobs.filter((job) => job.orderId === selectedPrintOrder.id)
    : [];

  // Helper function to normalize category strings (combines "Non Coffee" and "Non-Coffee")
  const normalizeCat = (catName: string) => catName.replace(/^non\s*coffee$/i, "Non-Coffee");
  const isAddOnCategory = (catName: string) => {
    const normalized = catName.replace(/[^a-z]/gi, "").toLowerCase();
    return normalized === "addons" || normalized === "addson";
  };

  // Deduplicate categories for the filter buttons
  const floorCategories = useMemo(() => {
    const set = new Set<string>();
    categories.forEach((cat) => {
      if (isAddOnCategory(cat)) return;
      set.add(normalizeCat(cat));
    });
    return ["All", ...Array.from(set)];
  }, [categories]);

  // Filter items by category.
  const items = useMemo(() => {
    return menu.filter((item) => {
      if (!item.available) return false;
      if (isAddOnCategory(item.category)) return false;

      const itemCatNormalized = normalizeCat(item.category);
      const selectedCatNormalized = normalizeCat(category);

      const matchesCategory =
        category === "All" || itemCatNormalized === selectedCatNormalized;
      const matchesSearch = item.name.toLowerCase().includes(itemSearch.trim().toLowerCase());
      return matchesCategory && matchesSearch;
    });
  }, [menu, category, itemSearch]);

  useEffect(() => {
    let cancelled = false;
    Promise.resolve().then(() => {
      if (cancelled) return;
      const saved = readCheckout(session.userId, menu);
      if (saved) {
        setCart(saved.cart);
        setTendered(saved.tendered);
        setPaymentMethod(saved.paymentMethod);
        setServiceMode(saved.serviceMode);
        setActiveVoidRequestId(saved.voidRequestId);
        setPromoCode(saved.promoCode ?? "");
        setPromoDraft(saved.promoCode ?? "");
        setPromoItemIndex(saved.promoItemIndex ?? null);
        setPromoItemQty(saved.promoItemQty ?? null);
      }
      setCheckoutReady(true);
    });
    return () => {
      cancelled = true;
    };
  }, [session.userId, menu]);

  useEffect(() => {
    if (!checkoutReady) return;
    writeCheckout({
      userId: session.userId,
      cart,
      tendered,
      paymentMethod,
      serviceMode,
      voidRequestId: activeVoidRequestId,
      promoCode,
      promoItemIndex,
      promoItemQty,
    });
  }, [checkoutReady, session.userId, cart, tendered, paymentMethod, serviceMode, activeVoidRequestId, promoCode, promoItemIndex, promoItemQty]);

  useEffect(() => {
    document.body.style.overflow = menuOpen ? "hidden" : "";
    return () => {
      document.body.style.overflow = "";
    };
  }, [menuOpen]);

  useEffect(() => {
    if (!menuOpen) return;
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") setMenuOpen(false);
    }
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [menuOpen]);

  const subtotal = cart.reduce((sum, item) => sum + cartLineUnitPrice(item) * item.qty, 0);
  const selectedPromo = session.permissions?.promoCodes?.find((entry) => entry.code.toUpperCase() === promoCode);
  const promoDiscount = !selectedPromo
    ? 0
    : selectedPromo.discountType === "item"
      ? promoItemIndex != null && cart[promoItemIndex] && promoItemQty != null
        ? Math.round(cartLineUnitPrice(cart[promoItemIndex]) * promoItemQty)
        : 0
      : Math.min(subtotal, Math.round(selectedPromo.discountType === "amount" ? selectedPromo.discountValue : subtotal * selectedPromo.discountValue / 100));
  const total = Math.max(0, subtotal - promoDiscount);
  const promoReady = !promoCode || Boolean(
    selectedPromo &&
    (!selectedPromo.expiresAt || Date.parse(selectedPromo.expiresAt) > now) &&
    session.permissions?.promotionsEnabled &&
    session.permissions?.promotionDiscount &&
    (selectedPromo.discountType !== "item" || (promoItemIndex != null && Boolean(cart[promoItemIndex]) && promoItemQty != null && promoItemQty === Math.max(1, Math.floor(selectedPromo.discountValue || 1)) && promoItemQty <= (cart[promoItemIndex]?.qty ?? 0))),
  );
  const isCash = paymentMethod === "cash";
  const paid = isCash ? Number(tendered) || 0 : total;
  const change = isCash && paid >= total ? paid - total : 0;
  const isManager = false;
  const selectedVoidOrder = orders.find((order) => order.id === voidTargetId);
  const voidedLastOrderIds = new Set(
    orders.filter((order) => order.voided).map((order) => order.id),
  );
  const effectiveLastOrderId =
    lastOrderId && !voidedLastOrderIds.has(lastOrderId) ? lastOrderId : null;
  const effectiveLastOrder =
    lastOrder && !voidedLastOrderIds.has(lastOrder.id) ? lastOrder : null;
  const cashierPaidVoid = cart.length === 0 ? (voidTargetId || effectiveLastOrderId) : null;
  const activeVoidRequest = voidRequests.find(
    (request) => request.id === activeVoidRequestId,
  );
  const voidRequestPending =
    Boolean(activeVoidRequestId) && activeVoidRequest?.status !== "approved";
  const canCharge =
    !voidRequestPending &&
    pos.isOpen &&
    cart.length > 0 &&
    promoReady &&
    (!isCash || paid >= total);

  const applyApprovedVoid = useCallback(
    (
      requestId: string,
      request: {
        orderId?: string | null;
        processedOrderId?: string | null;
      },
    ) => {
      const voidedId = request.orderId ?? request.processedOrderId ?? null;
      if (
        voidedId &&
        (effectiveLastOrderId === voidedId || effectiveLastOrder?.id === voidedId)
      ) {
        setLastOrderId(null);
        setLastTicket(null);
        setLastOrder(null);
      }
      if (!request.orderId) {
        setCart([]);
        setTendered("");
        setPaymentMethod("cash");
      }
      setActiveVoidRequestId(null);
      setVoidTargetId(null);
      setVoidReason("");
      setMessage("Admin approved the void. The checkout has been voided.");
      router.refresh();
    },
    [effectiveLastOrder, effectiveLastOrderId, router],
  );

  useEffect(() => {
    if (!activeVoidRequestId) return;
    const requestId: string = activeVoidRequestId;
    if (activeVoidRequest?.status === "approved") {
      const approvedRequest = activeVoidRequest;
      const handleApproved = () => applyApprovedVoid(requestId, approvedRequest);
      const timeout = window.setTimeout(handleApproved, 0);
      return () => window.clearTimeout(timeout);
    }

    let cancelled = false;
    async function checkVoidRequest() {
      const result = await getVoidRequestStatus(requestId);
      if (cancelled || !result.found || result.status !== "approved") return;
      applyApprovedVoid(requestId, result);
    }

    void checkVoidRequest();
    const timer = window.setInterval(() => {
      void checkVoidRequest();
    }, 2000);
    return () => {
      cancelled = true;
      window.clearInterval(timer);
    };
  }, [activeVoidRequest, activeVoidRequestId, applyApprovedVoid]);

  function selectedAddonsFor(item: MenuItem, selected: Record<string, number>): OrderAddon[] {
    return resolveOrderAddons(
      item,
      [
        ...normalizeMenuAddons(item).map((addon) => ({
          id: addon.id,
          name: addon.name,
          price: addon.price,
          qty: selected[addon.id] ?? 0,
        })),
        ...normalizeMenuTypeOptions(item).map((option, index) => ({
          id: `type:${addonIdFromName(option.name, index)}`,
          name: option.name,
          price: option.price,
          qty: selected[`type:${addonIdFromName(option.name, index)}`] ?? 0,
        })),
      ],
    );
  }

  function addItem(id: string, name: string, price: number, style?: DrinkStyle, addons: OrderAddon[] = []) {
    if (!pos.isOpen || voidRequestPending) {
      return;
    }
    const nextLine = { productId: id, name, qty: 1, price, style, addons };
    const nextKey = cartLineKey(nextLine);
    setPromoCode("");
    setPromoDraft("");
    setPromoItemIndex(null);
    setPromoItemQty(null);
    setCart((current) => {
      const existing = current.find((item) => cartLineKey(item) === nextKey);
      if (existing) {
        return current.map((item) =>
          cartLineKey(item) === nextKey ? { ...item, qty: item.qty + 1 } : item,
        );
      }
      return [...current, nextLine];
    });
    setMessage(null);
  }

  function applyPromotionCode() {
    const code = promoDraft.trim().toUpperCase();
    if (!/^(?:[A-Z0-9]{6}|[A-Z0-9]{1,16}-[A-Z0-9]{6})$/.test(code)) {
      setMessage("Enter a valid promo voucher.");
      return;
    }
    const promo = session.permissions?.promoCodes?.find((entry) => entry.code.toUpperCase() === code);
    if (!session.permissions?.promotionsEnabled || !session.permissions?.promotionDiscount || !promo) {
      setMessage("Invalid promo voucher.");
      return;
    }
    if (promo.redeemedAt) {
      setMessage("Promo voucher already used.");
      return;
    }
    if (promo.expiresAt && Date.parse(promo.expiresAt) <= Date.now()) {
      setMessage("This promo voucher has expired.");
      return;
    }
    setPromoCode(code);
    setPromoItemIndex(null);
    setPromoItemQty(null);
    setMessage(promo.discountType === "item" ? `Choose an item with quantity ${Math.max(1, Math.floor(promo.discountValue || 1))} or more.` : "Promotion applied.");
  }

  function changeCartQuantity(key: string, delta: number) {
    setPromoCode("");
    setPromoDraft("");
    setPromoItemIndex(null);
    setPromoItemQty(null);
    setCart((current) => current.flatMap((item) => {
      if (cartLineKey(item) !== key) return [item];
      const qty = Math.max(0, Math.min(99, item.qty + delta));
      return qty === 0 ? [] : [{ ...item, qty }];
    }));
  }

  function handleMenuTap(item: MenuItem) {
    const styles = normalizeMenuStyles(item);
    const addons = normalizeMenuAddons(item);
    if (styles.length > 1 || addons.length > 0 || normalizeMenuTypes(item).length > 0) {
      setDrinkPick({
        item,
        style: styles.length === 1 ? styles[0] : undefined,
        addons: {},
        qty: 1, // <--- I-initialize dito
      });
      return;
    }
    addItem(item.id, item.name, item.price, styles[0]);
  }

  function handleConfirmVoid(e: React.FormEvent) {
    e.preventDefault();
    if (!voidReason.trim()) {
      setMessage("Enter a reason for voiding.");
      return;
    }

    startTransition(async () => {
      if (isManager) {
        if (cart.length > 0) {
          setCart([]);
          setTendered("");
          setPaymentMethod("cash");
          setVoidReason("");
          setVoidModalOpen(false);
          setMessage("Checkout voided.");
          return;
        }
        const targetId = voidTargetId || effectiveLastOrderId;
        if (!targetId) {
          setMessage("Select a ticket to void.");
          return;
        }
        const result = await voidOrder(targetId, voidReason);
        if ("error" in result && result.error) {
          setMessage(result.error);
          return;
        }
        setVoidReason("");
        setVoidTargetId(null);
        setVoidModalOpen(false);
        setMessage("Transaction voided.");
        return;
      }

      if (!voidUsername || !voidPassword) {
        setMessage("Manager or admin credentials required to void.");
        return;
      }
      const auth = await verifyManager(voidUsername, voidPassword);
      if ("error" in auth && auth.error) {
        setMessage(auth.error);
        return;
      }

      if (cart.length > 0) {
        const result = await voidCheckout(
          cart,
          voidReason,
          voidUsername,
          voidPassword,
          paymentMethod,
        );
        if ("error" in result && result.error) {
          setMessage(result.error);
          return;
        }
        setCart([]);
        setTendered("");
        setPaymentMethod("cash");
        setVoidUsername("");
        setVoidPassword("");
        setVoidReason("");
        setVoidModalOpen(false);
        setMessage("Checkout voided.");
        return;
      }

      const targetId = voidTargetId || effectiveLastOrderId;
      if (!targetId) {
        setMessage("No ticket to void.");
        return;
      }
      const result = await voidOrder(targetId, voidReason, voidUsername, voidPassword);
      if ("error" in result && result.error) {
        setMessage(result.error);
        return;
      }
      setCart([]);
      setTendered("");
      setPaymentMethod("cash");
      setLastOrderId(null);
      setLastTicket(null);
      setLastOrder(null);
      setVoidUsername("");
      setVoidPassword("");
      setVoidReason("");
      setVoidTargetId(null);
      setVoidModalOpen(false);
      setMessage("Transaction voided.");
    });
  }

  function handleRequestVoid() {
    if (!voidReason.trim()) {
      setMessage("Enter a reason for voiding.");
      return;
    }
    const targetId = voidTargetId || (cart.length === 0 ? effectiveLastOrderId : null);
    if (cart.length === 0 && !targetId) {
      setMessage("No items to void.");
      return;
    }

    startTransition(async () => {
      const result = await requestVoidApproval(
        cart,
        voidReason,
        targetId,
        paymentMethod,
      );
      if (!result.requestId) {
        setMessage(result.error ?? "Unable to send the void request.");
        return;
      }
      setActiveVoidRequestId(result.requestId);
      setVoidUsername("");
      setVoidPassword("");
      setVoidModalOpen(false);
      setMessage("Void request sent to admin. Waiting for approval.");
    });
  }

  const canPrint = Boolean(effectiveLastOrderId) && cart.length === 0 && !voidRequestPending;

  function printTicket() {
    if (!canPrint || !effectiveLastOrderId) {
      setMessage("Charge the order before printing.");
      return;
    }
    const order = availableOrders.find((entry) => entry.id === effectiveLastOrderId);
    if (!order) {
      setMessage("Charge the order before printing.");
      return;
    }
    setPrintOrderId(order.id);
  }

  function upsertPrintJobs(updated: PrintJob[]) {
    setLocalPrintJobs((current) => {
      const byId = new Map(current.map((job) => [job.id, job]));
      for (const job of updated) byId.set(job.id, job);
      return [...byId.values()];
    });
  }

  function labelTicketForJob(order: Order, job: PrintJob): slipTicket {
    const ticket = slipFromOrder(order, availableOrders, menu);
    const source = job.label
      ? order.items[job.label.itemIndex]
      : undefined;
    if (!job.label) return { ...ticket, items: [] };
    return {
      ...ticket,
      items: [
        {
          productId: job.label.productId,
          name: job.label.name,
          price: job.label.price,
          qty: 1,
          category: source?.category,
        },
      ],
    };
  }

  async function attemptPrintJob(job: PrintJob, order: Order): Promise<PrintJob> {
    const started = await beginPrintJob(job.id);
    if ("error" in started) throw new Error(started.error);
    upsertPrintJobs([started.job]);

    let failure: string | undefined;
    try {
      if (job.type === "cup-label") {
        if (!labelPrinter.supported) {
          throw new Error("Web Serial is unavailable for the label printer.");
        }
        if (!labelPrinter.connected) {
          throw new Error("Label printer is disconnected.");
        }
        await labelPrinter.printLabel(labelTicketForJob(order, job));
      } else {
        if (!slipPrinter.supported) {
          throw new Error("Web Serial is unavailable for the order printer.");
        }
        if (!slipPrinter.connected) {
          throw new Error("Order printer is disconnected.");
        }
        await slipPrinter.printslip(
          slipFromOrder(order, availableOrders, menu),
        );
      }
    } catch (error) {
      failure = error instanceof Error ? error.message : "Printer failed.";
    }

    const finished = await finishPrintJob(
      job.id,
      failure ? "failed" : "printed",
      failure,
    );
    if ("error" in finished) throw new Error(finished.error);
    upsertPrintJobs([finished.job]);
    return finished.job;
  }

  async function attemptPrintJobs(jobs: PrintJob[], order: Order) {
    const results: PrintJob[] = [];
    for (const job of jobs) {
      try {
        results.push(await attemptPrintJob(job, order));
      } catch {
        results.push({
          ...job,
          status: "failed",
          lastError: "Could not record the print attempt.",
        });
      }
    }
    return results;
  }

  function printSummary(results: PrintJob[]): string {
    const printed = results.filter((job) => job.status === "printed").length;
    const failed = results.length - printed;
    if (failed === 0) return `${printed} printed`;
    if (printed === 0) return `${failed} waiting for retry`;
    return `${printed} printed, ${failed} waiting for retry`;
  }

  async function printTypeForOrder(order: Order, type: PrintJobType) {
    let jobs = knownPrintJobs.filter(
      (job) =>
        job.orderId === order.id &&
        job.type === type &&
        (job.status === "pending" || job.status === "failed"),
    );
    if (jobs.length === 0) {
      const queued = await queueReprintJobs(order.id, type);
      if ("error" in queued) throw new Error(queued.error);
      jobs = queued.printJobs;
      upsertPrintJobs(jobs);
    }
    const results = await attemptPrintJobs(jobs, order);
    setMessage(
      `${type === "cup-label" ? "Cup labels" : "Order"}: ${printSummary(results)}.`,
    );
  }

  async function retrySingleJob(job: PrintJob) {
    const order = availableOrders.find((entry) => entry.id === job.orderId);
    if (!order) throw new Error("Completed order not found.");
    const result = await attemptPrintJob(job, order);
    setMessage(
      `${job.type === "cup-label" ? "Cup label" : "Order"}: ${result.status}.`,
    );
  }

  return (
    <div className="pos-root relative flex h-svh flex-col overflow-hidden bg-slate-50 text-slate-950">
      <div className="pos-screen flex min-h-0 flex-1 flex-col overflow-hidden">
        <header className="flex h-14 shrink-0 items-center gap-3 border-b border-slate-200 bg-white px-3 text-slate-900 shadow-sm sm:px-5">
          <button
            type="button"
            aria-label={menuOpen ? "Close menu" : "Open menu"}
            aria-expanded={menuOpen}
            onClick={() => setMenuOpen((open) => !open)}
            className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-slate-200 bg-white text-slate-700 transition hover:bg-slate-100"
          >
            <svg viewBox="0 0 24 24" className="h-4 w-4 stroke-current" fill="none">
              {menuOpen ? (
                <path d="M6 6l12 12M18 6L6 18" strokeWidth="1.8" />
              ) : (
                <path d="M5 8h14M5 12h14M5 16h14" strokeWidth="1.8" />
              )}
            </svg>
          </button>
          <button
            type="button"
            onClick={() => {
              setActivePanel("pos");
              setMenuOpen(false);
            }}
            className="text-base font-bold tracking-tight text-slate-900 lowercase"
          >
            <span className="text-rose-600">syn</span>orra
          </button>
          {visiblePanel !== "pos" ? (
            <p className="truncate text-sm font-medium text-slate-500">
              {visiblePanel === "stock" ? "Stock inventory" : "Restock"}
            </p>
          ) : null}
        </header>

        <button
          type="button"
          tabIndex={menuOpen ? 0 : -1}
          aria-label="Close menu"
          onClick={() => setMenuOpen(false)}
          className={`fixed inset-0 z-40 bg-black/40 transition-opacity duration-200 ${
            menuOpen ? "opacity-100" : "pointer-events-none opacity-0"
          }`}
        />
        <aside
          role="dialog"
          aria-modal="true"
          aria-label="POS menu"
          aria-hidden={!menuOpen}
          className={`fixed inset-y-0 left-0 z-50 flex w-72 max-w-[85vw] flex-col bg-white text-black shadow-[0_18px_50px_rgba(0,0,0,0.18)] transition-transform duration-200 ${
            menuOpen ? "translate-x-0" : "-translate-x-full"
          }`}
        >
          <div className="flex items-center justify-between border-b border-neutral-200 px-5 py-4">
            <button
              type="button"
              onClick={() => {
                setActivePanel("pos");
                setMenuOpen(false);
              }}
              className="text-sm font-semibold tracking-tight lowercase"
            >
              synorra
            </button>
            <button
              type="button"
              aria-label="Close menu"
              onClick={() => setMenuOpen(false)}
              className="flex h-8 w-8 items-center justify-center rounded-full border border-neutral-300 text-neutral-700 transition hover:border-black hover:bg-black hover:text-white"
            >
              <svg viewBox="0 0 24 24" className="h-3.5 w-3.5 stroke-current" fill="none">
                <path d="M6 6l12 12M18 6L6 18" strokeWidth="1.8" />
              </svg>
            </button>
          </div>

          <div className="min-h-0 flex-1 overflow-y-auto p-3">
            <button
              type="button"
              aria-current={visiblePanel === "pos" ? "page" : undefined}
              onClick={() => {
                setActivePanel("pos");
                setMenuOpen(false);
              }}
              className={`mb-3 w-full rounded-2xl px-4 py-3 text-left text-sm font-medium transition ${
                visiblePanel === "pos"
                  ? "bg-[#101d37] text-white"
                  : "text-neutral-600 hover:bg-neutral-100 hover:text-black"
              }`}
            >
              POS
            </button>

            {inventoryFeaturesEnabled ? <div>
              <p className="px-4 pb-1 text-[11px] font-medium tracking-wide text-neutral-400 uppercase">
                Inventory
              </p>
              {(
                [
                  ["stock", "Stock inventory"],
                  ["restock", "Restock"],
                ] as const
              ).map(([id, label]) => (
                <button
                  key={id}
                  type="button"
                  aria-current={visiblePanel === id ? "page" : undefined}
                  onClick={() => {
                    setActivePanel(id);
                    setMenuOpen(false);
                  }}
                  className={`mb-1 w-full rounded-2xl px-4 py-3 text-left text-sm font-medium transition ${
                    visiblePanel === id
                      ? "bg-[#101d37] text-white"
                      : "text-neutral-600 hover:bg-neutral-100 hover:text-black"
                  }`}
                >
                  {label}
                </button>
              ))}
            </div> : null}

            <div className="mt-4 border-t border-neutral-100 pt-4">
              <button
                type="button"
                disabled={pending || !labelPrinter.supported}
                onClick={() =>
                  startTransition(async () => {
                    try {
                      if (labelPrinter.connected) {
                        await labelPrinter.disconnect();
                        setMessage("Label printer disconnected.");
                        return;
                      }
                      await labelPrinter.connect();
                      setMessage("Label printer connected.");
                    } catch (error) {
                      setMessage(
                        error instanceof Error ? error.message : "Label printer error.",
                      );
                    }
                  })
                }
                className="mb-1 w-full rounded-2xl px-4 py-3 text-left text-sm font-medium text-neutral-600 transition hover:bg-neutral-100 hover:text-black disabled:opacity-40"
              >
                {labelPrinter.connected ? "Labels on" : "Connect labels"}
              </button>
              <button
                type="button"
                disabled={pending || !slipPrinter.supported}
                onClick={() =>
                  startTransition(async () => {
                    try {
                      if (slipPrinter.connected) {
                        await slipPrinter.disconnect();
                        setMessage("Order printer disconnected.");
                        return;
                      }
                      await slipPrinter.connect();
                      setMessage("Order printer connected.");
                    } catch (error) {
                      setMessage(
                        error instanceof Error ? error.message : "Order printer error.",
                      );
                    }
                  })
                }
                className="mb-1 w-full rounded-2xl px-4 py-3 text-left text-sm font-medium text-neutral-600 transition hover:bg-neutral-100 hover:text-black disabled:opacity-40"
              >
                {slipPrinter.connected ? "Order printer on" : "Connect order printer"}
              </button>
            </div>

            <div className="mt-4 border-t border-neutral-100 pt-4">
              <p className="px-4 pb-1 text-[11px] font-medium tracking-wide text-neutral-400 uppercase">
                Baristas
              </p>
              {onShift.map((barista) => (
                <div
                  key={barista.id}
                  className="mb-1 flex items-center justify-between gap-2 rounded-2xl px-4 py-2.5"
                >
                  <p className="min-w-0 truncate text-sm font-medium">In - {barista.name}</p>
                  <button
                    type="button"
                    disabled={pending}
                    onClick={() => {
                      setBaristaUsername(barista.username);
                      setBaristaPassword("");
                      setBaristaAction("logout");
                      setBaristaTargetId(barista.id);
                      setBaristaNotice(null);
                      setBaristaModalOpen(true);
                      setMenuOpen(false);
                    }}
                    className="shrink-0 rounded-full border border-neutral-300 px-3 py-1 text-xs font-medium hover:border-black disabled:opacity-40"
                  >
                    Out
                  </button>
                </div>
              ))}
              <button
                type="button"
                disabled={pending}
                onClick={() => {
                  setBaristaUsername("");
                  setBaristaPassword("");
                  setBaristaAction("login");
                  setBaristaTargetId(null);
                  setBaristaNotice(null);
                  setBaristaModalOpen(true);
                  setMenuOpen(false);
                }}
                className="w-full rounded-2xl px-4 py-3 text-left text-sm font-medium text-neutral-600 transition hover:bg-neutral-100 hover:text-black"
              >
                {onShift.length === 0 ? "Barista in" : "Barista in / out"}
              </button>
            </div>
          </div>

          <div className="border-t border-neutral-200 p-3">
            <p className="px-4 py-2 text-sm font-medium text-neutral-900">
              {session.name}
              <span className="ml-2 text-xs font-normal text-neutral-400">
                {session.role}
              </span>
            </p>
            <button
              type="button"
              disabled={pending}
              onClick={() => {
                if (cart.length > 0) {
                  setMessage("Finish or void the checkout before logging out.");
                  setMenuOpen(false);
                  return;
                }
                startTransition(async () => await logout());
              }}
              className="w-full rounded-2xl px-4 py-3 text-left text-sm font-medium text-neutral-600 transition hover:bg-neutral-100 hover:text-black disabled:opacity-40"
            >
              {pending ? "Logging out..." : "Log out"}
            </button>
          </div>
        </aside>

        {drinkPick ? (
          <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4">
            <div className="relative w-full max-w-sm rounded-3xl bg-white p-6 shadow-2xl">
              <button
                type="button"
                aria-label="Close drink options"
                onClick={() => setDrinkPick(null)}
                className="absolute top-5 right-5 flex h-9 w-9 items-center justify-center rounded-full text-neutral-400 hover:bg-neutral-100 hover:text-black"
              >
                ×
              </button>
              <h2 className="text-xl font-semibold tracking-tight">{drinkPick.item.name}</h2>
              {normalizeMenuStyles(drinkPick.item).length > 1 ? (
                <>
                  <p className="mt-1 text-sm text-neutral-500">Choose Iced or Hot.</p>
                  <div className="mt-5 grid grid-cols-2 gap-2">
                    {normalizeMenuStyles(drinkPick.item).map((style) => (
                      <button
                        key={style}
                        type="button"
                        onClick={() => {
                          const next = { ...drinkPick, style };
                          setDrinkPick(next);
                        }}
                        className={`rounded-2xl border px-4 py-4 text-sm font-medium ${
                          drinkPick.style === style
                            ? "border-[#101d37] bg-[#101d37] text-white"
                            : "border-neutral-200 hover:border-[#58789d] hover:bg-[#edf4fc] hover:text-[#101d37]"
                        }`}
                      >
                        {drinkStyleLabel(style)}
                      </button>
                    ))}
                  </div>
                </>
              ) : (
                <p className="mt-1 text-sm text-neutral-500">Add extras if you want them.</p>
              )}

              {/* Quantity Selector para sa Item */}
              <div className="mt-5 flex items-center justify-between rounded-2xl border border-neutral-200 px-4 py-3">
                <span className="text-sm font-medium text-neutral-700">Quantity</span>
                <div className="flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() =>
                      setDrinkPick({
                        ...drinkPick,
                        qty: Math.max(1, (drinkPick.qty ?? 1) - 1),
                      })
                    }
                    className="flex h-8 w-8 items-center justify-center rounded-full border border-neutral-300 text-sm hover:border-black"
                  >
                    −
                  </button>
                  <span className="w-6 text-center text-sm font-medium">
                    {drinkPick.qty ?? 1}
                  </span>
                  <button
                    type="button"
                    onClick={() =>
                      setDrinkPick({
                        ...drinkPick,
                        qty: Math.min(99, (drinkPick.qty ?? 1) + 1),
                      })
                    }
                    className="flex h-8 w-8 items-center justify-center rounded-full border border-neutral-300 text-sm hover:border-black"
                  >
                    +
                  </button>
                </div>
              </div>

              {normalizeMenuAddons(drinkPick.item).some((addon) => addon.id.startsWith("size:")) ? (
                <div className="mt-5 space-y-2">
                  <p className="text-sm text-neutral-500">Choose a size</p>
                  {normalizeMenuAddons(drinkPick.item).filter((addon) => addon.id.startsWith("size:")).map((size) => {
                    const on = (drinkPick.addons[size.id] ?? 0) > 0;
                    return (
                      <button
                        key={size.id}
                        type="button"
                        onClick={() => setDrinkPick({
                          ...drinkPick,
                          addons: {
                            ...Object.fromEntries(Object.entries(drinkPick.addons).filter(([id]) => !id.startsWith("size:"))),
                            [size.id]: 1,
                          },
                        })}
                        className={`flex w-full items-center justify-between rounded-2xl border px-4 py-3 text-left ${on ? "border-black bg-neutral-50" : "border-neutral-200 bg-white"}`}
                      >
                        <span className="text-sm font-medium">{size.name}</span>
                        <span className="text-sm text-neutral-500">₱{size.price}</span>
                      </button>
                    );
                  })}
                </div>
              ) : null}

              {normalizeMenuTypes(drinkPick.item).length > 0 ? (
                <div className="mt-5 space-y-2">
                  <p className="text-sm text-neutral-500">Types</p>
                  {normalizeMenuTypeOptions(drinkPick.item).map((option, index) => {
                    const typeId = `type:${addonIdFromName(option.name, index)}`;
                    const on = (drinkPick.addons[typeId] ?? 0) > 0;
                    return (
                      <button
                        key={typeId}
                        type="button"
                        onClick={() =>
                          setDrinkPick({
                            ...drinkPick,
                            addons: {
                              ...Object.fromEntries(
                                Object.entries(drinkPick.addons).filter(([id]) => !id.startsWith("type:")),
                              ),
                              ...(on ? {} : { [typeId]: 1 }),
                            },
                          })
                        }
                        className={`flex w-full items-center justify-between gap-3 rounded-2xl border px-4 py-3 text-left transition ${
                          on ? "border-black bg-neutral-50" : "border-neutral-200 bg-white"
                        }`}
                      >
                        <span className="text-sm font-medium">{option.name}</span>
                        {option.price > 0 ? <span className="text-sm text-neutral-500">+₱{option.price}</span> : null}
                        <span
                          className={`flex h-5 w-5 items-center justify-center rounded-full border ${
                            on ? "border-black" : "border-neutral-300"
                          }`}
                        >
                          {on ? <span className="h-2.5 w-2.5 rounded-full bg-black" /> : null}
                        </span>
                      </button>
                    );
                  })}
                </div>
              ) : null}

              {normalizeMenuAddons(drinkPick.item).some((addon) => !addon.id.startsWith("size:")) ? (
                <div className="mt-5 space-y-2">
                  <p className="text-sm text-neutral-500">Add-ons</p>
                  {normalizeMenuAddons(drinkPick.item).filter((addon) => !addon.id.startsWith("size:")).map((addon) => {
                    const qty = drinkPick.addons[addon.id] ?? 0;
                    const on = qty > 0;
                    const canQty = addonAllowsQty(addon);
                    return (
                      <button
                        key={addon.id}
                        type="button"
                        onClick={() =>
                          setDrinkPick({
                            ...drinkPick,
                            addons: { ...drinkPick.addons, [addon.id]: on ? 0 : 1 },
                          })
                        }
                        className={`flex w-full items-center justify-between gap-3 rounded-2xl border px-4 py-3 text-left transition ${
                          on ? "border-black bg-neutral-50" : "border-neutral-200 bg-white"
                        }`}
                      >
                        <div className="min-w-0">
                          <p className="text-sm font-medium">{addon.name}</p>
                          <p className="mt-0.5 text-[11px] text-neutral-500">
                            {qty > 1
                              ? `x${qty} · +₱${(addon.price || 0) * qty}`
                              : `+₱${addon.price || 0}${canQty ? " each" : ""}`}
                          </p>
                        </div>
                        <div className="flex shrink-0 items-center gap-2">
                          {canQty && on ? (
                            <div
                              className="flex items-center gap-1"
                              onClick={(event) => event.stopPropagation()}
                            >
                              <span
                                role="button"
                                onClick={() =>
                                  setDrinkPick({
                                    ...drinkPick,
                                    addons: {
                                      ...drinkPick.addons,
                                      [addon.id]: Math.max(0, qty - 1),
                                    },
                                  })
                                }
                                className="flex h-7 w-7 items-center justify-center rounded-full border border-neutral-200 text-sm"
                              >
                                -
                              </span>
                              <span className="w-4 text-center text-xs font-medium">{qty}</span>
                              <span
                                role="button"
                                onClick={() =>
                                  setDrinkPick({
                                    ...drinkPick,
                                    addons: {
                                      ...drinkPick.addons,
                                      [addon.id]: Math.min(9, qty + 1),
                                    },
                                  })
                                }
                                className="flex h-7 w-7 items-center justify-center rounded-full border border-neutral-200 text-sm"
                              >
                                +
                              </span>
                            </div>
                          ) : null}
                          <span
                            className={`flex h-5 w-5 items-center justify-center rounded-full border ${
                              on ? "border-black" : "border-neutral-300"
                            }`}
                          >
                            {on ? <span className="h-2.5 w-2.5 rounded-full bg-black" /> : null}
                          </span>
                        </div>
                      </button>
                    );
                  })}
                </div>
              ) : null}

              <button
                type="button"
                disabled={
                  (normalizeMenuStyles(drinkPick.item).length > 1 && !drinkPick.style) ||
                  (normalizeMenuAddons(drinkPick.item).some((addon) => addon.id.startsWith("size:")) &&
                    !Object.entries(drinkPick.addons).some(([id, qty]) => id.startsWith("size:") && qty > 0))
                }
                onClick={() => {
                  const q = drinkPick.qty ?? 1;
                  for (let i = 0; i < q; i++) {
                    addItem(
                      drinkPick.item.id,
                      drinkPick.item.name,
                      drinkPick.item.price,
                      drinkPick.style,
                      selectedAddonsFor(drinkPick.item, drinkPick.addons)
                    );
                  }
                  setDrinkPick(null);
                }}
                className="mt-5 w-full rounded-2xl bg-black px-4 py-3 text-sm font-medium text-white disabled:opacity-40"
              >
                Add to checkout
              </button>
            </div>
          </div>
        ) : null}

        {baristaModalOpen ? (
          <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4">
            <div className="relative flex w-full max-w-md flex-col rounded-3xl bg-white p-6 shadow-2xl">
              <button
                type="button"
                aria-label="Close barista login"
                onClick={() => setBaristaModalOpen(false)}
                className="absolute top-5 right-5 flex h-9 w-9 items-center justify-center rounded-full text-neutral-400 hover:bg-neutral-100 hover:text-black transition"
              >
                ×
              </button>
              <h2 className="text-xl font-semibold tracking-tight">Baristas</h2>

              {onShift.length > 0 ? (
                <div className="mt-5 space-y-2">
                  <p className="text-xs font-medium uppercase tracking-wide text-neutral-400">On shift</p>
                  {onShift.map((barista) => (
                    <div
                      key={barista.id}
                      className="flex items-center justify-between gap-3 rounded-2xl border border-neutral-200 px-3.5 py-2.5"
                    >
                      <div className="min-w-0">
                        <p className="truncate text-sm font-medium">{barista.name}</p>
                        <p className="truncate text-xs text-neutral-400">{barista.username}</p>
                      </div>
                      <button
                        type="button"
                        disabled={pending}
                        onClick={() => {
                          setBaristaUsername(barista.username);
                          setBaristaPassword("");
                          setBaristaAction("logout");
                          setBaristaTargetId(barista.id);
                          setBaristaNotice(null);
                        }}
                        className="shrink-0 rounded-full border border-neutral-300 px-3 py-1.5 text-xs font-medium hover:border-black disabled:opacity-40"
                      >
                        Out
                      </button>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="mt-5 text-sm text-neutral-500">No barista is on shift yet.</p>
              )}

              <form
                onSubmit={(event) => {
                  event.preventDefault();
                  startTransition(async () => {
                    const result = await punchBaristaShift({
                      type: baristaAction,
                      username: baristaUsername,
                      password: baristaPassword,
                      userId: baristaTargetId ?? undefined,
                    });
                    if (result && "error" in result && result.error) {
                      if (baristaAction === "login" && "id" in result && result.id) {
                        setOnShift((current) =>
                          current.some((entry) => entry.id === result.id)
                            ? current
                            : [...current, { id: result.id, name: result.name, username: result.username }],
                        );
                      }
                      setBaristaNotice(result.error);
                      return;
                    }
                    if (baristaAction === "logout" && baristaTargetId) {
                      setOnShift((current) => current.filter((entry) => entry.id !== baristaTargetId));
                    } else if ("id" in result && result.id) {
                      setOnShift((current) =>
                        current.some((entry) => entry.id === result.id)
                          ? current
                          : [...current, { id: result.id, name: result.name, username: result.username }],
                      );
                    }
                    setBaristaUsername("");
                    setBaristaPassword("");
                    setBaristaAction("login");
                    setBaristaTargetId(null);
                    setBaristaNotice(null);
                    setMessage(`${"name" in result ? result.name : "Barista"} clocked ${baristaAction === "login" ? "in" : "out"}.`);
                    router.refresh();
                  });
                }}
                className="mt-5 border-t border-neutral-100 pt-5"
              >
                <p className="text-xs font-medium uppercase tracking-wide text-neutral-400">
                  {baristaAction === "login" ? "Clock in" : "Clock out"}
                </p>
                <label className="mt-3 block text-xs font-medium text-neutral-600">
                  <span className="mb-1.5 block">Username</span>
                  <input
                    value={baristaUsername}
                    onChange={(event) => setBaristaUsername(event.target.value)}
                    className="w-full rounded-xl border border-neutral-200 px-3.5 py-2.5 text-sm outline-none focus:border-black"
                    autoComplete="username"
                    required
                  />
                </label>
                <label className="mt-3 block text-xs font-medium text-neutral-600">
                  <span className="mb-1.5 block">Password</span>
                  <input
                    type="password"
                    value={baristaPassword}
                    onChange={(event) => setBaristaPassword(event.target.value)}
                    className="w-full rounded-xl border border-neutral-200 px-3.5 py-2.5 text-sm outline-none focus:border-black"
                    autoComplete="current-password"
                    required
                  />
                </label>
                {baristaNotice ? <p className="mt-3 text-sm text-red-600">{baristaNotice}</p> : null}
                <button
                  type="submit"
                  disabled={pending}
                  className="mt-5 w-full rounded-full bg-black px-4 py-2.5 text-sm font-medium text-white disabled:opacity-40"
                >
                  {pending ? "Saving..." : baristaAction === "login" ? "Clock in" : "Clock out"}
                </button>
              </form>
            </div>
          </div>
        ) : null}

        {/* Void Modal */}
        {voidModalOpen ? (
          <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4">
            <form
              onSubmit={handleConfirmVoid}
              className="relative flex w-full max-w-md flex-col rounded-3xl bg-white p-6 shadow-2xl transition-all"
            >
              <button
                type="button"
                aria-label="Close modal"
                onClick={() => setVoidModalOpen(false)}
                className="absolute top-5 right-5 flex h-9 w-9 items-center justify-center rounded-full text-neutral-400 hover:bg-neutral-100 hover:text-black transition"
              >
                <svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor">
                  <path d="M6 6l12 12M18 6L6 18" strokeWidth="2" strokeLinecap="round" />
                </svg>
              </button>

              <div className="mb-6 text-center">
                <div className="mx-auto mb-2 flex h-12 w-12 items-center justify-center rounded-2xl bg-neutral-100 text-neutral-800">
                  <svg viewBox="0 0 24 24" className="h-6 w-6" fill="none" stroke="currentColor">
                    <path
                      d="M12 9v3.75m0 3.75h.008v.008H12v-.008zM12 3a9 9 0 100 18 9 9 0 000-18z"
                      strokeWidth="1.8"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    />
                  </svg>
                </div>
                <h2 className="text-xl font-bold tracking-tight text-neutral-900">
                  {isManager ? "Void this ticket?" : "Void checkout"}
                </h2>
                <p className="mt-1 text-xs text-neutral-500">
                  {isManager
                    ? "This cannot be undone."
                    : "Manager approval required to void."}
                </p>
              </div>

              {selectedVoidOrder || (cashierPaidVoid && lastTicket) ? (
                <div className="mb-4 rounded-2xl border border-neutral-200 bg-neutral-50 px-4 py-3 text-left">
                  {selectedVoidOrder ? (
                    <>
                      <div className="flex items-baseline justify-between gap-3">
                        <p className="text-sm font-semibold">
                          Order #{selectedVoidOrder.ticketNo ?? selectedVoidOrder.id.slice(-4)}
                        </p>
                        <p className="text-sm font-semibold">{formatMoney(selectedVoidOrder.total)}</p>
                      </div>
                      <p className="mt-1 text-xs text-neutral-500">
                        {phDateTimeLabel(selectedVoidOrder.createdAt)} · {selectedVoidOrder.baristaName}
                      </p>
                      <p className="mt-2 text-xs text-neutral-700">
                        {selectedVoidOrder.items.map((item) => `${item.qty}× ${orderLineListLabel(item)}`).join(", ")}
                      </p>
                    </>
                  ) : lastTicket ? (
                    <>
                      <div className="flex items-baseline justify-between gap-3">
                        <p className="text-sm font-semibold">Order #{lastTicket.ticketNo}</p>
                        <p className="text-sm font-semibold">{formatMoney(lastTicket.total)}</p>
                      </div>
                      <p className="mt-2 text-xs text-neutral-700">
                        {lastTicket.items.map((item) => `${item.qty}× ${orderLineListLabel(item)}`).join(", ")}
                      </p>
                    </>
                  ) : null}
                </div>
              ) : null}

              <div className="space-y-4">
                {!isManager ? (
                <div className="space-y-3">
                  <div>
                    <label className="mb-1 block text-xs font-semibold text-neutral-700">
                      Manager username
                    </label>
                    <input
                      type="text"
                      placeholder="Enter username"
                      value={voidUsername}
                      onChange={(e) => setVoidUsername(e.target.value)}
                      className="w-full rounded-xl border border-neutral-200 bg-neutral-50 px-3.5 py-2.5 text-xs text-neutral-900 outline-none transition focus:border-black focus:bg-white focus:ring-1 focus:ring-black"
                    />
                  </div>

                  <div>
                    <label className="mb-1 block text-xs font-semibold text-neutral-700">
                      Manager password
                    </label>
                    <input
                      type="password"
                      placeholder="••••••••"
                      value={voidPassword}
                      onChange={(e) => setVoidPassword(e.target.value)}
                      className="w-full rounded-xl border border-neutral-200 bg-neutral-50 px-3.5 py-2.5 text-xs text-neutral-900 outline-none transition focus:border-black focus:bg-white focus:ring-1 focus:ring-black"
                    />
                  </div>
                </div>
                ) : null}

                <div className="pt-1">
                  <label className="mb-1 block text-xs font-semibold text-neutral-700">
                    Reason for Voiding <span className="text-red-500">*</span>
                  </label>
                  <textarea
                    rows={2}
                    placeholder=""
                    value={voidReason}
                    onChange={(e) => setVoidReason(e.target.value)}
                    className="w-full resize-none rounded-xl border border-neutral-200 bg-neutral-50 px-3.5 py-2.5 text-xs text-neutral-900 outline-none transition focus:border-black focus:bg-white focus:ring-1 focus:ring-black"
                  />
                </div>
              </div>

              <div className="mt-6 flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => setVoidModalOpen(false)}
                  className="w-1/3 rounded-xl border border-neutral-200 py-2.5 text-xs font-medium text-neutral-600 transition hover:bg-neutral-50"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={pending || voidRequestPending}
                  className="w-2/3 rounded-xl bg-black py-2.5 text-xs font-medium text-white transition hover:bg-neutral-800 active:scale-[0.99]"
                >
                  {isManager ? "Void ticket" : "Confirm Void"}
                </button>
              </div>
              {!isManager ? (
                <button
                  type="button"
                  disabled={pending || voidRequestPending}
                  onClick={handleRequestVoid}
                  className="mt-2 w-full rounded-xl border border-black py-2.5 text-xs font-medium text-black transition hover:bg-neutral-100 disabled:opacity-40"
                >
                  {voidRequestPending ? "Waiting for admin approval" : "Request to admin"}
                </button>
              ) : null}
            </form>
          </div>
        ) : null}

        {/* Waste Modal */}
        {canRecordWaste && wasteModalOpen ? (
          <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-xs p-4">
            <div className="relative flex w-full max-w-md flex-col rounded-3xl bg-white p-6 shadow-2xl transition-all">
              <button
                type="button"
                aria-label="Close modal"
                onClick={() => { setWasteModalOpen(false); setWasteReason(""); }}
                className="absolute top-5 right-5 flex h-9 w-9 items-center justify-center rounded-full text-neutral-400 hover:bg-neutral-100 hover:text-black transition"
              >
                <svg viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor">
                  <path d="M6 6l12 12M18 6L6 18" strokeWidth="2" strokeLinecap="round" />
                </svg>
              </button>

              <div className="mb-4">
                <div className="mb-3 flex h-11 w-11 items-center justify-center rounded-2xl bg-amber-100 text-amber-800">
                  <svg viewBox="0 0 24 24" className="h-6 w-6" fill="none" stroke="currentColor">
                    <path
                      d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
                      strokeWidth="1.8"
                      strokeLinecap="round"
                      strokeLinejoin="round"
                    />
                  </svg>
                </div>
                <h3 className="text-base font-bold text-neutral-900">Record Wasted Items</h3>
                <p className="mt-1 text-xs text-neutral-500">
                  Records {cart.reduce((sum, item) => sum + item.qty, 0)} item(s) as waste and deducts stock from inventory with no sale or payment.
                </p>
              </div>

              <div className="space-y-4">
                <div>
                  <label className="text-xs font-semibold text-neutral-700">Select or enter reason / note:</label>
                  <div className="mt-2 flex flex-wrap gap-2">
                    {["Spilled", "Expired", "Wrong Preparation", "Damaged"].map((preset) => (
                      <button
                        key={preset}
                        type="button"
                        onClick={() => setWasteReason(preset)}
                        className={`rounded-full px-3 py-1 text-xs font-medium transition ${
                          wasteReason.trim() === preset
                            ? "bg-amber-200 text-amber-950 font-bold ring-1 ring-amber-400"
                            : "bg-neutral-100 text-neutral-700 hover:bg-neutral-200"
                        }`}
                      >
                        {preset}
                      </button>
                    ))}
                  </div>
                </div>

                <div>
                  <label className="text-xs font-semibold text-neutral-700">
                    Reason / Note <span className="text-red-500">*</span>
                  </label>
                  <input
                    type="text"
                    required
                    autoFocus
                    placeholder="e.g. Spilled, Expired, Wrong Preparation, Damaged"
                    value={wasteReason}
                    onChange={(e) => setWasteReason(e.target.value)}
                    className="mt-1.5 w-full rounded-xl border border-neutral-300 bg-neutral-50 px-3.5 py-2.5 text-xs text-neutral-900 outline-none transition focus:border-black focus:bg-white focus:ring-1 focus:ring-black"
                  />
                </div>

                <div>
                  <label className="text-xs font-semibold text-neutral-700">
                    Barista in Charge
                    <span className="ml-1 font-normal text-neutral-400">(on-shift baristas are selected automatically)</span>
                  </label>
                  {clockedInBaristas.length > 0 ? (
                    <div className="mt-2 flex flex-wrap gap-2">
                      {clockedInBaristas.map((barista) => {
                        const selected = wasteBaristaIds.includes(barista.id);
                        return (
                          <button
                            key={barista.id}
                            type="button"
                            onClick={() =>
                              setWasteBaristaIds((current) =>
                                current.includes(barista.id)
                                  ? current.filter((id) => id !== barista.id)
                                  : [...current, barista.id],
                              )
                            }
                            className={`rounded-full px-3 py-1 text-xs font-medium transition ${
                              selected
                                ? "bg-neutral-900 text-white font-semibold ring-1 ring-neutral-900"
                                : "bg-neutral-100 text-neutral-700 hover:bg-neutral-200"
                            }`}
                          >
                            {barista.name || barista.username}
                          </button>
                        );
                      })}
                    </div>
                  ) : (
                    <p className="mt-2 text-[11px] italic text-neutral-400">No baristas clocked in — baristas in charge will show as “—”.</p>
                  )}
                </div>
              </div>

              <div className="mt-6 flex items-center gap-2">
                <button
                  type="button"
                  onClick={() => { setWasteModalOpen(false); setWasteReason(""); setWasteBaristaIds([]); }}
                  className="w-1/3 rounded-xl border border-neutral-200 py-2.5 text-xs font-medium text-neutral-600 transition hover:bg-neutral-50"
                >
                  Cancel
                </button>
                <button
                  type="button"
                  disabled={pending || !wasteReason.trim()}
                  onClick={() =>
                    startTransition(async () => {
                      const reason = wasteReason.trim();
                      if (!reason) return;
                      const result = await recordWaste(cart, reason, wasteBaristaIds);
                      if (!result.ok) {
                        setMessage(result.error);
                        return;
                      }
                      setCart([]);
                      setWasteReason("");
                      setWasteBaristaIds([]);
                      setWasteModalOpen(false);
                      setMobileCheckoutOpen(false);
                      setMessage(`Waste recorded (${reason}) and inventory deducted.`);
                    })
                  }
                  className="w-2/3 rounded-xl bg-[#b42332] py-2.5 text-xs font-semibold text-white transition hover:bg-[#970909] active:scale-[0.99] disabled:opacity-40"
                >
                  {pending ? "Recording..." : "Record Waste"}
                </button>
              </div>
            </div>
          </div>
        ) : null}

        {selectedPrintTicket && selectedPrintOrder ? (
          <SlipPreview
            ticket={selectedPrintTicket}
            orderId={selectedPrintOrder.id}
            orderOptions={availableOrders.map((order) => ({
              id: order.id,
              label: `Order #${String(order.ticketNo ?? order.id.slice(-4)).replace(/^#/, "")} · ${phDateTimeLabel(order.createdAt)} · ${formatMoney(order.total)}`,
            }))}
            printJobs={selectedPrintJobs}
            labelPaperWidth={labelPrinter.paperWidth}
            slipPaperWidth={slipPrinter.paperWidth}
            labelBaudRate={labelPrinter.baudRate}
            slipBaudRate={slipPrinter.baudRate}
            labelPrinterReady={labelPrinter.connected}
            slipPrinterReady={slipPrinter.connected}
            testPrinterEnabled={TEST_PRINTER_ENABLED}
            pending={pending}
            onClose={() => setPrintOrderId(null)}
            onSelectOrder={setPrintOrderId}
            onSetLabelPaperWidth={labelPrinter.setPaperWidth}
            onSetslipPaperWidth={slipPrinter.setPaperWidth}
            onSetLabelBaudRate={labelPrinter.setBaudRate}
            onSetslipBaudRate={slipPrinter.setBaudRate}
            onPrintLabels={() =>
              startTransition(async () => {
                try {
                  await printTypeForOrder(selectedPrintOrder, "cup-label");
                } catch (error) {
                  setMessage(
                    error instanceof Error ? error.message : "Could not print labels.",
                  );
                }
              })
            }
            onPrintslip={() =>
              startTransition(async () => {
                try {
                  await printTypeForOrder(selectedPrintOrder, "internal-slip");
                } catch (error) {
                  setMessage(
                    error instanceof Error ? error.message : "Could not print order.",
                  );
                }
              })
            }
            onRetryJob={(job) =>
              startTransition(async () => {
                try {
                  await retrySingleJob(job);
                } catch (error) {
                  setMessage(
                    error instanceof Error ? error.message : "Could not retry print job.",
                  );
                }
              })
            }
          />
        ) : null}

        {inventoryFeaturesEnabled && (visiblePanel === "stock" || visiblePanel === "restock") ? (
          <div className="min-h-0 flex-1 overflow-y-auto bg-neutral-100 p-2 sm:p-4">
            <SalePurchaseTransactions
              store={inventoryStore}
              tabs={["stock", "restock"]}
              activeTab={visiblePanel}
              onTabChange={(tab) => {
                if (tab === "stock" || tab === "restock") {
                  setActivePanel(tab);
                }
              }}
              showTabs={false}
            />
          </div>
        ) : (
            <div className="relative flex min-h-0 min-w-0 flex-1 flex-col min-[1024px]:flex-row">
              {!pos.isOpen ? (
                <div className="absolute inset-0 z-20 flex flex-col items-center justify-center bg-neutral-100 px-6 text-center">
                  <p className="font-serif text-4xl italic sm:text-5xl">Closed</p>
                  <p className="mt-3 max-w-sm text-sm text-neutral-500">
                    Open the POS to take orders.
                  </p>
                  <button
                    type="button"
                    disabled={pending}
                    onClick={() => startTransition(() => openPos())}
                    className="mt-8 rounded-full bg-black px-8 py-3 text-sm font-medium text-white shadow-lg transition hover:bg-neutral-800"
                  >
                    Open POS
                  </button>
                </div>
              ) : null}
          {/* Menu Catalog Section */}
          <section className="relative flex min-h-0 min-w-0 flex-1 flex-col">
            <div className="shrink-0 space-y-2 border-b border-slate-200 bg-white px-3 py-3 sm:px-4">
              <label className="flex h-10 items-center gap-2 rounded-xl border border-slate-200 bg-slate-50 px-3 text-slate-400 focus-within:border-slate-400 focus-within:bg-white">
                <svg viewBox="0 0 24 24" className="size-4 shrink-0 fill-none stroke-current" aria-hidden="true"><circle cx="10.8" cy="10.8" r="6.8" strokeWidth="1.8" /><path d="m16 16 5 5" strokeWidth="1.8" strokeLinecap="round" /></svg>
                <input value={itemSearch} onChange={(event) => setItemSearch(event.target.value)} placeholder="Search menu" aria-label="Search menu" className="min-w-0 flex-1 bg-transparent text-sm text-slate-900 outline-none placeholder:text-slate-400" />
              </label>
              <nav aria-label="Menu categories" className="flex gap-2 overflow-x-auto pb-0.5">
                {floorCategories.map((name) => (
                  <button
                    key={name}
                    type="button"
                    onClick={() => setCategory(name)}
                    aria-pressed={category === name}
                    className={`shrink-0 rounded-full border px-3.5 py-2 text-xs font-medium transition ${category === name ? "border-slate-900 bg-slate-900 text-white" : "border-slate-200 bg-white text-slate-600 hover:border-slate-400"}`}
                  >
                    {name}
                  </button>
                ))}
              </nav>
            </div>
            <div className="min-h-0 flex-1 overflow-y-auto px-3 py-3 pb-24 sm:px-4 min-[1024px]:pb-3">
              {items.length === 0 ? (
                <div className="flex h-full items-center justify-center text-xs text-neutral-400">
                  No items found in this category.
                </div>
              ) : (
                <div className="grid grid-cols-2 gap-2.5 min-[600px]:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5">
                  {items.map((item) => (
                    <button
                      key={item.id}
                      type="button"
                      onClick={() => handleMenuTap(item)}
                      disabled={voidRequestPending}
                      className="rounded-2xl border border-slate-200 bg-white p-3 text-center shadow-sm transition hover:-translate-y-0.5 hover:border-slate-400 hover:shadow-md disabled:cursor-not-allowed disabled:opacity-40"
                    >
                      {item.image ? (
                        <Image src={item.image} alt="" width={160} height={100} unoptimized className="mx-auto mb-2 h-16 w-full rounded-xl object-contain sm:h-20" />
                      ) : (
                        <div aria-hidden="true" className="mx-auto mb-2 flex h-16 items-center justify-center rounded-xl bg-slate-50 text-slate-300 sm:h-20">
                          <svg viewBox="0 0 24 24" className="size-8 fill-none stroke-current" strokeWidth="1.5"><path d="M5 8h12v8a4 4 0 0 1-4 4H9a4 4 0 0 1-4-4V8Zm12 2h2a2 2 0 0 1 0 4h-2M8 4v2m4-2v2" strokeLinecap="round" strokeLinejoin="round" /></svg>
                        </div>
                      )}
                      <p className="text-xs font-semibold text-slate-800">{item.name}</p>
                      {normalizeMenuStyles(item).length > 0 ? (
                        <p className="mt-0.5 text-[10px] text-neutral-400">
                          {normalizeMenuStyles(item).map(drinkStyleLabel).join(" / ")}
                          {normalizeMenuTypes(item).length > 0 ? " · Types" : ""}
                          {normalizeMenuAddons(item).length > 0 ? " · Add-ons" : ""}
                        </p>
                      ) : normalizeMenuAddons(item).length > 0 ? (
                        <p className="mt-0.5 text-[10px] text-neutral-400">
                          {normalizeMenuTypes(item).length > 0 ? "Types · Add-ons" : "Add-ons"}
                        </p>
                      ) : normalizeMenuTypes(item).length > 0 ? (
                        <p className="mt-0.5 text-[10px] text-neutral-400">Types</p>
                      ) : null}
                      <p className="mt-0.5 text-xs text-neutral-600">
                        {formatMoney(item.price)}
                      </p>
                    </button>
                  ))}
                </div>
              )}
            </div>

          </section>

          {/* Checkout Panel Sidebar */}
          <aside className={`absolute inset-x-0 bottom-0 z-30 flex min-h-0 min-w-0 flex-col border-t border-slate-200 bg-white shadow-[0_-12px_36px_rgba(15,23,42,0.08)] min-[1024px]:relative min-[1024px]:inset-auto min-[1024px]:z-auto min-[1024px]:h-auto min-[1024px]:w-[40%] min-[1024px]:max-w-[520px] min-[1024px]:shrink-0 min-[1024px]:border-l min-[1024px]:border-t-0 min-[1024px]:shadow-none min-[1280px]:w-[38%] ${mobileCheckoutOpen ? "h-[min(78svh,680px)] rounded-t-3xl border-x border-slate-200" : "h-[76px] rounded-t-2xl border-x border-slate-200 min-[1024px]:h-auto min-[1024px]:rounded-none"}`}>
            <button type="button" aria-expanded={mobileCheckoutOpen} onClick={() => setMobileCheckoutOpen((open) => !open)} className="flex h-[76px] shrink-0 items-center justify-between gap-3 px-4 text-left min-[1024px]:hidden">
              <span>
                <span className="block text-sm font-semibold text-slate-900">View Cart &amp; Pay</span>
                <span className="mt-0.5 block text-xs text-slate-500">{cart.reduce((sum, item) => sum + item.qty, 0)} items in cart</span>
              </span>
              <span className="flex items-center gap-3">
                <span className="text-base font-bold text-slate-900">{formatMoney(total)}</span>
                <span className={`flex size-8 items-center justify-center rounded-full bg-[#101d37] text-white transition ${mobileCheckoutOpen ? "rotate-180" : ""}`} aria-hidden="true"><svg viewBox="0 0 24 24" className="size-4 fill-none stroke-current" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="m6 14 6-6 6 6" /></svg></span>
              </span>
            </button>
            <h2 className="hidden shrink-0 py-2.5 text-center text-lg font-semibold min-[1024px]:block">
              Checkout
            </h2>
            <div className={`${mobileCheckoutOpen ? "flex" : "hidden"} min-h-0 flex-1 flex-col min-[1024px]:flex`}>
            <div className="grid grid-cols-[1fr_auto_auto] gap-x-3 px-3 text-[10px] tracking-wide text-neutral-400 uppercase">
              <span>Name</span>
              <span className="w-16 text-center">Qty</span>
              <span className="w-16 text-right">Price</span>
            </div>
            
            {/* Scrollable Order List */}
            <ul className="min-h-[100px] flex-1 overflow-y-auto px-3 py-1">
              {cart.length === 0 ? (
                <li className="py-6 text-center text-xs text-neutral-400">
                  No items yet.
                </li>
              ) : (
                cart.map((item, itemIndex) => (
                  <li
                    key={cartLineKey(item)}
                    className="grid grid-cols-[minmax(0,1fr)_auto_auto] items-center gap-x-2 border-b border-neutral-100 py-1.5 last:border-none"
                  >
                    <div className="min-w-0">
                      <p className="truncate text-xs">{drinkDisplayName(item)}{promoItemIndex === itemIndex ? <span className="ml-1 font-semibold text-emerald-700">· {promoItemQty ?? 1} free</span> : null}</p>
                      {orderLineOptionsLabel(item) ? (
                        <p className="text-[10px] leading-4 text-neutral-600">
                          Options: {orderLineOptionsLabel(item)}
                        </p>
                      ) : null}
                    </div>
                    <div className="flex w-[116px] items-center justify-center gap-1">
                      <button
                        type="button"
                        aria-label={`Decrease ${item.name} quantity`}
                        onClick={() => changeCartQuantity(cartLineKey(item), -1)}
                        className="flex h-11 w-11 shrink-0 touch-manipulation items-center justify-center rounded-full border border-neutral-300 bg-white text-xl leading-none text-neutral-900 active:bg-neutral-100"
                      >
                        −
                      </button>
                      <span className="min-w-5 text-center text-sm font-semibold tabular-nums">{item.qty}</span>
                      <button
                        type="button"
                        aria-label={`Increase ${item.name} quantity`}
                        disabled={item.qty >= 99}
                        onClick={() => changeCartQuantity(cartLineKey(item), 1)}
                        className="flex h-11 w-11 shrink-0 touch-manipulation items-center justify-center rounded-full border border-neutral-300 bg-white text-xl leading-none text-neutral-900 active:bg-neutral-100 disabled:opacity-40"
                      >
                        +
                      </button>
                    </div>
                    <span className="w-16 text-right text-xs">
                      {formatMoney(cartLineUnitPrice(item) * item.qty - (promoItemIndex === itemIndex ? promoDiscount : 0))}
                    </span>
                  </li>
                ))
              )}
            </ul>

            {/* Scrollable / Compact Bottom Controls */}
            <div className="shrink-0 max-h-[60vh] overflow-y-auto space-y-2 border-t border-neutral-200 px-3 py-3 text-xs">
              {cart.length > 0 && session.permissions?.promotionsEnabled && session.permissions?.promotionDiscount ? (
                <div className="space-y-1.5 rounded-lg border border-neutral-200 p-2">
                  {promoCode && selectedPromo ? (
                    <>
                      <div className="flex items-center justify-between gap-2">
                        <span className="font-medium">{selectedPromo.discountType === "item" ? `${Math.max(1, Math.floor(selectedPromo.discountValue || 1))} free item${Math.max(1, Math.floor(selectedPromo.discountValue || 1)) === 1 ? "" : "s"}` : `Promo voucher ${promoCode}`}</span>
                        <button type="button" onClick={() => { setPromoCode(""); setPromoDraft(""); setPromoItemIndex(null); setPromoItemQty(null); }} className="underline">Remove</button>
                      </div>
                      {selectedPromo.discountType === "item" ? (
                        <>
                        <select
                          aria-label="Choose item to make free"
                          value={promoItemIndex ?? ""}
                          onChange={(event) => {
                            const index = event.target.value === "" ? null : Number(event.target.value);
                            setPromoItemIndex(index);
                            setPromoItemQty(index == null ? null : Math.max(1, Math.floor(selectedPromo.discountValue || 1)));
                          }}
                          className="w-full rounded-md border border-neutral-300 bg-white px-2 py-1.5"
                        >
                          <option value="">Choose an item to make free</option>
                          {cart.map((item, index) => <option key={`${cartLineKey(item)}-${index}`} value={index} disabled={item.qty < Math.max(1, Math.floor(selectedPromo.discountValue || 1))}>{drinkDisplayName(item)} · qty {item.qty}</option>)}
                        </select>
                        <p className="text-[11px] text-neutral-500">Select a cart item with enough quantity; {Math.max(1, Math.floor(selectedPromo.discountValue || 1))} unit(s) will be free.</p>
                        </>
                      ) : null}
                    </>
                  ) : (
                    <div className="flex gap-1.5">
                      <input
                        aria-label="Promo voucher"
                        value={promoDraft}
                        onChange={(event) => setPromoDraft(event.target.value.toUpperCase())}
                        placeholder="Promo voucher"
                        maxLength={23}
                        className="min-w-0 flex-1 rounded-md border border-neutral-300 px-2 py-1.5 uppercase"
                      />
                      <button type="button" onClick={applyPromotionCode} className="rounded-md border border-neutral-300 px-2.5 py-1.5 font-medium">Apply</button>
                    </div>
                  )}
                  {promoDiscount > 0 ? <div className="flex justify-between text-emerald-700"><span>Promotion discount</span><span>−{formatMoney(promoDiscount)}</span></div> : null}
                </div>
              ) : null}
              <div>
                <p className="mb-1 text-xs text-neutral-500">Pay with</p>
                <div className="grid grid-cols-3 gap-1.5">
                  {PAYMENT_METHODS.map((method) => (
                    <button
                      key={method.id}
                      type="button"
                      onClick={() => setPaymentMethod(method.id)}
                      className={`rounded-lg border py-1.5 text-xs transition ${
                        paymentMethod === method.id
                          ? "border-[#101d37] bg-[#101d37] text-white"
                          : "border-neutral-300 bg-white hover:border-black"
                      }`}
                    >
                      {method.label}
                    </button>
                  ))}
                </div>
              </div>

              {isCash ? (
                <>
                  <div className="flex justify-end gap-1">
                    {([{ id: "dine-in", label: "dine in" }, { id: "take-out", label: "Take out" }] as const).map((mode) => (
                      <button
                        key={mode.id}
                        type="button"
                        onClick={() => setServiceMode(mode.id)}
                        aria-pressed={serviceMode === mode.id}
                        className={`rounded-md border px-2 py-1.5 text-xs transition ${serviceMode === mode.id ? "border-[#101d37] bg-[#101d37] text-white" : "border-neutral-300 bg-white hover:border-[#58789d]"}`}
                      >
                        {mode.label}
                      </button>
                    ))}
                  </div>
                  <div className="flex items-center justify-between gap-2 text-xs">
                    <span className="text-neutral-500">Amount</span>
                    <input
                      inputMode="numeric"
                      value={tendered}
                      onChange={(event) =>
                        setTendered(event.target.value.replace(/[^\d]/g, ""))
                      }
                      placeholder="0"
                      className="w-24 rounded-md border border-neutral-300 bg-white px-2 py-1 text-right outline-none focus:border-black"
                    />
                  </div>
                  <div className="flex flex-wrap gap-1.5">
                    <button
                      type="button"
                      onClick={() => setTendered(String(total || ""))}
                      className="rounded-full border border-neutral-300 px-2.5 py-0.5 text-[11px] hover:border-black"
                    >
                      Exact
                    </button>
                    {CASH_PRESETS.map((value) => (
                      <button
                        key={value}
                        type="button"
                        onClick={() => setTendered(String(value))}
                        className="rounded-full border border-neutral-300 px-2.5 py-0.5 text-[11px] hover:border-black"
                      >
                        {formatMoney(value)}
                      </button>
                    ))}
                  </div>
                </>
              ) : (
                <p className="text-xs text-neutral-500">
                  {paymentLabel(paymentMethod)} · exact {formatMoney(total)}
                </p>
              )}

              <div className="flex items-center justify-between text-xs">
                <span className="text-neutral-500">Subtotal</span>
                <span>{formatMoney(subtotal)}</span>
              </div>
              <div className="flex items-center justify-between text-xs">
                <span className="text-neutral-500">Total</span>
                <span className="text-base font-semibold">{formatMoney(total)}</span>
              </div>
              <div className="flex items-center justify-between text-xs">
                <span className="text-neutral-500">{isCash ? "Change" : "Paid"}</span>
                <span>{formatMoney(isCash ? change : total)}</span>
              </div>

              <div className="grid grid-cols-1 gap-1.5 pt-1">
                <button
                  type="button"
                  onClick={printTicket}
                  disabled={!canPrint}
                  className={`rounded-lg border py-2 text-xs transition ${
                    canPrint
                      ? "border-[#b90c0c] bg-[#b90c0c] text-white hover:bg-[#970909]"
                      : "border-neutral-300 text-neutral-400"
                  }`}
                >
                  Print
                </button>
              </div>

              {canRecordWaste ? (
                <button
                  type="button"
                  disabled={pending || cart.length === 0}
                  onClick={() => {
                    setWasteBaristaIds(clockedInBaristas.map((barista) => barista.id));
                    setWasteModalOpen(true);
                  }}
                  className="w-full rounded-xl border border-amber-300 bg-amber-50 py-2.5 text-xs font-semibold text-amber-900 transition hover:bg-amber-100 active:scale-[0.99] disabled:opacity-40"
                >
                  Record Waste
                </button>
              ) : null}

              <button
                type="button"
                disabled={pending || !canCharge}
                onClick={() =>
                  startTransition(async () => {
                    const result = await createOrder(
                      cart,
                      paymentMethod,
                      paid,
                      serviceMode,
                      promoCode,
                      promoItemIndex,
                      promoItemQty,
                    );
                    if (!result.ok) {
                      setMessage(result.error);
                      return;
                    }
                    const savedOrder = result.order;
                    const saved = slipFromOrder(
                      savedOrder,
                      [savedOrder, ...availableOrders],
                      menu,
                    );
                    setLastTicket(saved);
                    setLastOrder(savedOrder);
                    setLastOrderId(savedOrder.id);
                    upsertPrintJobs(result.printJobs);
                    setCart([]);
                    setMobileCheckoutOpen(false);
                    setTendered("");
                    setPaymentMethod("cash");
                    setServiceMode("dine-in");
                    setPromoCode("");
                    setPromoDraft("");
                    setPromoItemIndex(null);
                    setPromoItemQty(null);
                    setMessage(
                      `Paid ${formatMoney(result.total ?? 0)}. Tap Print for labels and order copy.`,
                    );
                    const labelJobs = result.printJobs.filter(
                      (job) => job.type === "cup-label",
                    );
                    const slipJobs = result.printJobs.filter(
                      (job) => job.type === "internal-slip",
                    );
                    void Promise.all([
                      attemptPrintJobs(labelJobs, savedOrder),
                      attemptPrintJobs(slipJobs, savedOrder),
                    ]).then(([labelResults, slipResults]) => {
                      setMessage(
                        `Paid ${formatMoney(result.total ?? 0)} · labels: ${printSummary(labelResults)} · order: ${printSummary(slipResults)} · tap Print for details`,
                      );
                    });
                  })
                }
                className="relative w-full rounded-xl bg-[#b90c0c] py-3 text-sm font-semibold text-white transition hover:bg-[#970909] active:scale-[0.99] disabled:opacity-40"
              >
                Proceed Order
              </button>

              {message ? (
                <p className="text-center text-xs text-neutral-500">{message}</p>
              ) : null}
              {voidRequestPending ? (
                <p className="rounded-lg border border-neutral-300 bg-neutral-50 px-3 py-2 text-center text-xs font-medium text-neutral-700">
                  Void request pending admin approval
                </p>
              ) : null}
            </div>
            </div>
          </aside>
        </div>
      )}
      </div>
    </div>
  );
}
