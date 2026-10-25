import { CAFE } from "@/lib/cafe";
import { paymentLabel } from "@/lib/payments";
import { drinkDisplayName, hydrateOrderLine, orderLineOptionsLabel } from "@/lib/menu";
import { phDateString, phDateTimeLabel, phTimestamp } from "@/lib/datetime";
import type { MenuItem, Order, OrderItem, PaymentMethod } from "@/lib/types";

export type PaperWidth = 58 | 80;

export type slipItem = OrderItem;

export type slipTicket = {
  ticketNo: string;
  barista: string;
  items: slipItem[];
  subtotal: number;
  discount: number;
  promoLabel?: string;
  total: number;
  paymentMethod?: PaymentMethod;
  serviceMode?: "dine-in" | "take-out";
  paid?: number;
  change?: number;
  at: Date;
};

type Align = 0 | 1 | 2;
type Size = "normal" | "wide" | "tall" | "huge";

type PrintLine =
  | { kind: "text"; text: string; align?: Align; size?: Size; bold?: boolean }
  | { kind: "rule" }
  | { kind: "feed" }
  | { kind: "bitmap"; bytes: Uint8Array };

const ESC = 0x1b;
const GS = 0x1d;
const LF = 0x0a;

const SIZE_BYTE: Record<Size, number> = {
  normal: 0x00,
  wide: 0x20,
  tall: 0x10,
  huge: 0x30,
};

export function paperColumns(width: PaperWidth): number {
  return width === 58 ? 32 : 42;
}

export function nextTicketNo(orders: Order[], now = new Date()): string {
  const day = phDateString(now);
  const dayOrders = orders.filter((order) => {
    if (phDateString(order.createdAt) !== day || order.deletedAt) return false;
    if (order.recordType === "Waste" || order.paymentMethod === "waste" || order.id.startsWith("waste-") || Boolean(order.wasteReason)) {
      return false;
    }
    return true;
  });
  const ticketNumber = (order: Order) => {
    const ticket = Number(String(order.ticketNo ?? "").replace(/^#/, ""));
    return Number.isInteger(ticket) && ticket > 0 ? ticket : null;
  };
  const activeTickets = new Set(
    dayOrders.filter((order) => !order.voided).map(ticketNumber).filter((ticket): ticket is number => ticket !== null),
  );
  const reclaimedTicket = dayOrders
    .filter((order) => order.voided)
    .map(ticketNumber)
    .filter((ticket): ticket is number => ticket !== null && !activeTickets.has(ticket))
    .sort((a, b) => a - b)[0];
  if (reclaimedTicket !== undefined) return String(reclaimedTicket).padStart(3, "0");

  const highestTicket = dayOrders.reduce((highest, order) => Math.max(highest, ticketNumber(order) ?? 0), 0);
  return String(highestTicket + 1).padStart(3, "0");
}

function sameCalendarDay(a: Date, b: Date) {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

export function ticketNoForOrder(orders: Order[], order: Order): string {
  if (order.ticketNo) return order.ticketNo;
  const day = new Date(order.createdAt);
  const same = [...orders]
    .filter((entry) => sameCalendarDay(new Date(entry.createdAt), day))
    .sort(
      (a, b) => a.createdAt.localeCompare(b.createdAt) || a.id.localeCompare(b.id),
    );
  const index = same.findIndex((entry) => entry.id === order.id);
  return String(Math.max(index, 0) + 1).padStart(3, "0");
}

export function slipFromOrder(
  order: Order,
  orders: Order[] = [],
  menu: MenuItem[] = [],
): slipTicket {
  const subtotal =
    order.subtotal ??
    order.items.reduce((sum, item) => sum + item.price * item.qty, 0);
  const paid = order.paid ?? order.total;
  const digital =
    order.paymentMethod === "gcash" || order.paymentMethod === "maya";
  return {
    ticketNo: ticketNoForOrder(orders, order),
    barista: order.baristaName,
    items: order.items.map((item) => ({
      ...item,
      category:
        item.category ??
        menu.find((menuItem) => menuItem.id === item.productId)?.category,
    })),
    subtotal,
    discount: order.discount ?? 0,
    promoLabel: order.promoLabel,
    total: order.total,
    paymentMethod: order.paymentMethod,
    serviceMode: order.serviceMode ?? order.items[0]?.serviceMode,
    paid,
    change: order.change ?? (digital ? 0 : Math.max(0, paid - order.total)),
    at: new Date(phTimestamp(order.createdAt)),
  };
}

export function slipMoney(amount: number): string {
  return `P${Math.round(amount).toLocaleString("en-PH")}`;
}

export function slipWhen(date: Date): string {
  return phDateTimeLabel(date);
}

export function itemCount(items: OrderItem[]): number {
  return items.reduce((sum, item) => sum + item.qty, 0);
}

export function isDrinkCategory(category?: string): boolean {
  return Boolean(category && !/food|pastr/i.test(category));
}

export function drinkslips(ticket: slipTicket): slipTicket[] {
  return ticket.items.flatMap((item) => {
    if (!isDrinkCategory(item.category)) return [];
    return Array.from({ length: item.qty }, () => ({
      ...ticket,
      items: [{ ...item, qty: 1 }],
    }));
  });
}

function toPrinterText(value: string): string {
  return value
    .replace(/₱/g, "P")
    .normalize("NFKD")
    .replace(/[^\x20-\x7E]/g, "?");
}

function padLine(left: string, right: string, width: number): string {
  const cleanLeft = toPrinterText(left);
  const cleanRight = toPrinterText(right);
  if (cleanLeft.length + 1 + cleanRight.length <= width) {
    return (
      cleanLeft +
      " ".repeat(width - cleanLeft.length - cleanRight.length) +
      cleanRight
    );
  }
  const wrapAt = Math.max(8, width - cleanRight.length - 1);
  const first = cleanLeft.slice(0, wrapAt);
  const rest = cleanLeft.slice(wrapAt).trim();
  const lined =
    first + " ".repeat(width - first.length - cleanRight.length) + cleanRight;
  return rest ? `${lined}\n${padLine(rest, "", width)}` : lined;
}

function dash(width: number): string {
  return "-".repeat(width);
}

function wrapText(text: string, width: number): string[] {
  const words = text.split(/\s+/).filter(Boolean);
  const lines: string[] = [];
  let line = "";
  for (const word of words) {
    if (word.length > width) {
      if (line) lines.push(line);
      line = "";
      for (let index = 0; index < word.length; index += width) {
        lines.push(word.slice(index, index + width));
      }
    } else if (!line) {
      line = word;
    } else if (line.length + word.length + 1 <= width) {
      line += ` ${word}`;
    } else {
      lines.push(line);
      line = word;
    }
  }
  if (line) lines.push(line);
  return lines;
}

function encode(text: string): number[] {
  const bytes: number[] = [];
  for (const char of toPrinterText(text)) {
    bytes.push(char.charCodeAt(0));
  }
  return bytes;
}

function buildBytes(lines: PrintLine[], width: number): Uint8Array {
  const bytes: number[] = [ESC, 0x40, ESC, 0x74, 0x00, ESC, 0x32];

  for (const line of lines) {
    if (line.kind === "feed") {
      bytes.push(LF);
      continue;
    }
    if (line.kind === "bitmap") {
      bytes.push(...line.bytes, LF);
      continue;
    }
    if (line.kind === "rule") {
      bytes.push(ESC, 0x61, 0x00, ESC, 0x21, 0x00, ...encode(dash(width)), LF);
      continue;
    }

    bytes.push(ESC, 0x61, line.align ?? 0);
    bytes.push(ESC, 0x21, SIZE_BYTE[line.size ?? "normal"] | (line.bold ? 0x08 : 0));
    const chunks = line.text.split("\n");
    for (const chunk of chunks) {
      bytes.push(...encode(chunk), LF);
    }
    bytes.push(ESC, 0x21, 0x00, ESC, 0x61, 0x00);
  }

  bytes.push(LF, LF, GS, 0x56, 0x00);
  return Uint8Array.from(bytes);
}

function shopHeader(logo?: Uint8Array): PrintLine[] {
  const lines: PrintLine[] = [];
  if (logo) {
    lines.push({ kind: "bitmap", bytes: logo });
  }
  lines.push(
    { kind: "text", text: CAFE.tagline, align: 1 },
    { kind: "text", text: CAFE.street, align: 1 },
    { kind: "text", text: CAFE.city, align: 1 },
    { kind: "text", text: `Tel ${CAFE.phone}`, align: 1 },
    { kind: "rule" },
  );
  return lines;
}

export function internalLines(
  ticket: slipTicket,
  width: number,
  logo?: Uint8Array,
): PrintLine[] {
  const internalFooter = wrapText(
    "THIS DOCUMENT IS NOT VALID FOR CLAIM OF INPUT TAX / FOR INTERNAL STORE USE ONLY",
    width,
  );
  const lines: PrintLine[] = [
    ...shopHeader(logo),
    ...wrapText("CUSTOMER COPY (FOR INTERNAL USE ONLY)", width).map((text) => ({
      kind: "text" as const,
      text,
      align: 1 as const,
      bold: true,
    })),
    ...wrapText(`Order #${ticket.ticketNo}`, width).map((text) => ({
      kind: "text" as const,
      text,
      align: 1 as const,
      size: "tall" as const,
      bold: true,
    })),
    { kind: "text", text: slipWhen(ticket.at), align: 1 },
    { kind: "text", text: `Cashier: ${ticket.barista}`, align: 1 },
    ...(ticket.serviceMode ? [{ kind: "text" as const, text: ticket.serviceMode === "take-out" ? "Take out" : "Dine in", align: 1 as const }] : []),
    { kind: "rule" },
    { kind: "text", text: padLine("Item", "Amount", width), bold: true },
  ];

  for (const item of ticket.items) {
    lines.push({ kind: "text", text: drinkDisplayName(item) });
    const options = orderLineOptionsLabel(item);
    if (options) {
      lines.push({ kind: "text", text: `  ${options}` });
    }
    lines.push({
      kind: "text",
      text: padLine(
        `  ${item.qty} x ${slipMoney(item.price)}`,
        slipMoney(item.price * item.qty),
        width,
      ),
    });
  }

  lines.push({ kind: "rule" });
  lines.push({
    kind: "text",
    text: padLine("Subtotal", slipMoney(ticket.subtotal), width),
  });
  if (ticket.discount > 0) {
    lines.push({
      kind: "text",
      text: padLine(
        ticket.promoLabel ?? "Discount",
        `-${slipMoney(ticket.discount)}`,
        width,
      ),
    });
  }
  lines.push({
    kind: "text",
    text: padLine("TOTAL", slipMoney(ticket.total), width),
    bold: true,
    size: "tall",
  });

  if (ticket.paid && ticket.paid > 0) {
    lines.push({ kind: "rule" });
    const method = paymentLabel(ticket.paymentMethod);
    lines.push({
      kind: "text",
      text: padLine("Payment", method, width),
    });
    if (ticket.paymentMethod === "gcash" || ticket.paymentMethod === "maya") {
      lines.push({
        kind: "text",
        text: padLine("Paid", slipMoney(ticket.paid), width),
      });
    } else {
      lines.push({
        kind: "text",
        text: padLine("Cash / Tendered", slipMoney(ticket.paid), width),
      });
      lines.push({
        kind: "text",
        text: padLine("Change", slipMoney(ticket.change ?? 0), width),
      });
    }
  }

  lines.push({ kind: "rule" });
  lines.push({ kind: "text", text: CAFE.tagline.toLowerCase(), align: 1 });
  lines.push({ kind: "text", text: "have a seat, take a sip", align: 1 });
  lines.push({ kind: "text", text: "Thank you. Please come again.", align: 1 });
  lines.push({ kind: "rule" });
  lines.push(...internalFooter.map((text) => ({ kind: "text" as const, text, align: 1 as const, bold: true })));
  return lines;
}

export function baristaLines(ticket: slipTicket, width: number): PrintLine[] {
  const drinks = itemCount(ticket.items);
  const lines: PrintLine[] = [
    { kind: "text", text: "MAKE THESE DRINKS", align: 1, bold: true },
    { kind: "rule" },
    { kind: "text", text: `ORDER NO. ${ticket.ticketNo}`, align: 1, bold: true },
    ...(ticket.serviceMode ? [{ kind: "text" as const, text: ticket.serviceMode === "take-out" ? "TAKE OUT" : "DINE IN", align: 1 as const, bold: true }] : []),
    { kind: "text", text: slipWhen(ticket.at), align: 1 },
    { kind: "rule" },
    { kind: "text", text: "Qty  Drink", bold: true },
  ];

  for (const item of ticket.items) {
    const qty = `${item.qty}X`;
    const name = drinkDisplayName(item).toUpperCase();
    const hydrated = hydrateOrderLine(item);
    const style = hydrated.style ? `(${hydrated.style.toUpperCase()}) ` : "";
    const options = orderLineOptionsLabel(item).replace(/^(hot|iced)(,\s*)?/i, "").trim();
    lines.push({
      kind: "text",
      text: `${style}${qty} ${name}`,
    });
    if (options) {
      lines.push({ kind: "text", text: `+${options.toUpperCase()}` });
    }
  }

  lines.push({ kind: "rule" });
  lines.push({
    kind: "text",
    text: `${drinks} ${drinks === 1 ? "DRINK" : "DRINKS"} TO MAKE`,
    align: 1,
    bold: true,
  });
  return lines;
}

export function encodeinternalslip(
  ticket: slipTicket,
  paperWidth: PaperWidth,
  logo?: Uint8Array,
): Uint8Array {
  const width = paperColumns(paperWidth);
  return buildBytes(internalLines(ticket, width, logo), width);
}

export function encodeBaristaTicket(
  ticket: slipTicket,
  paperWidth: PaperWidth,
): Uint8Array {
  const width = paperColumns(paperWidth);
  return buildBytes(baristaLines(ticket, width), width);
}

export function encodeOrderSlips(
  ticket: slipTicket,
  paperWidth: PaperWidth,
): Uint8Array[] {
  return drinkslips(ticket).map((drinkTicket) =>
    encodeBaristaTicket(drinkTicket, paperWidth),
  );
}

export function sampleTicket(now = new Date()): slipTicket {
  return {
    ticketNo: "001",
    barista: "Sale In Charge",
    items: [
      {
        productId: "spanish-latte",
        name: "Spanish Latte",
        qty: 2,
        price: 149,
        category: "Special",
      },
      {
        productId: "matcha-umami",
        name: "Matcha Umami",
        qty: 1,
        price: 169,
        category: "Matcha Drinks",
      },
    ],
    subtotal: 467,
    discount: 0,
    total: 467,
    paymentMethod: "cash",
    paid: 500,
    change: 33,
    at: now,
  };
}
