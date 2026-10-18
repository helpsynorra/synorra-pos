"use client";

import { useCallback } from "react";
import { encodeCustomerReceipt, type ReceiptTicket } from "@/lib/escpos";
import {
  useSerialPrinter,
  type SerialPrinterConnection,
} from "@/lib/serial-printer";

export type ReceiptPrinter = Omit<SerialPrinterConnection, "write"> & {
  printReceipt: (ticket: ReceiptTicket) => Promise<void>;
};

async function receiptLogo(): Promise<Uint8Array | undefined> {
  if (typeof document === "undefined") return undefined;
  try {
    const img = await new Promise<HTMLImageElement>((resolve, reject) => {
      const image = new window.Image();
      image.onload = () => resolve(image);
      image.onerror = () => reject(new Error("Could not load receipt logo."));
      image.src = "/images/logo.png";
    });
    const size = 144;
    const canvas = document.createElement("canvas");
    canvas.width = size;
    canvas.height = size;
    const ctx = canvas.getContext("2d");
    if (!ctx) return undefined;
    ctx.fillStyle = "#ffffff";
    ctx.fillRect(0, 0, size, size);
    ctx.beginPath();
    ctx.arc(size / 2, size / 2, size / 2, 0, Math.PI * 2);
    ctx.closePath();
    ctx.clip();
    ctx.drawImage(img, 0, 0, size, size);
    const pixels = ctx.getImageData(0, 0, size, size).data;
    const widthBytes = Math.ceil(size / 8);
    const raster = new Uint8Array(widthBytes * size);
    for (let y = 0; y < size; y += 1) {
      for (let x = 0; x < size; x += 1) {
        const i = (y * size + x) * 4;
        const luminance =
          pixels[i] * 0.3 + pixels[i + 1] * 0.59 + pixels[i + 2] * 0.11;
        if (luminance < 165) {
          raster[y * widthBytes + (x >> 3)] |= 0x80 >> (x & 7);
        }
      }
    }
    return Uint8Array.from([
      0x1b,
      0x61,
      0x01,
      0x1d,
      0x76,
      0x30,
      0x00,
      widthBytes & 0xff,
      (widthBytes >> 8) & 0xff,
      size & 0xff,
      (size >> 8) & 0xff,
      ...raster,
      0x0a,
      0x1b,
      0x61,
      0x00,
    ]);
  } catch {
    return undefined;
  }
}

export function useReceiptPrinter(): ReceiptPrinter {
  const connection = useSerialPrinter({
    role: "receipt",
    defaultPaperWidth: 80,
  });
  const printReceipt = useCallback(
    async (ticket: ReceiptTicket) => {
      const logo = await receiptLogo();
      await connection.write(
        encodeCustomerReceipt(ticket, connection.paperWidth, logo),
      );
    },
    [connection],
  );

  const { write: _write, ...printer } = connection;
  void _write;
  return { ...printer, printReceipt };
}
