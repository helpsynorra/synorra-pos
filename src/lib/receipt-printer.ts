"use client";

import { useCallback } from "react";
import { encodeinternalslip, type slipTicket } from "@/lib/escpos";
import {
  useSerialPrinter,
  type SerialPrinterConnection,
} from "@/lib/serial-printer";

export type slipPrinter = Omit<SerialPrinterConnection, "write"> & {
  printslip: (ticket: slipTicket) => Promise<void>;
};

async function slipLogo(): Promise<Uint8Array | undefined> {
  if (typeof document === "undefined") return undefined;
  try {
    const img = await new Promise<HTMLImageElement>((resolve, reject) => {
      const image = new window.Image();
      image.onload = () => resolve(image);
      image.onerror = () => reject(new Error("Could not load slip logo."));
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

export function useslipPrinter(): slipPrinter {
  const connection = useSerialPrinter({
    role: "slip",
    defaultPaperWidth: 80,
  });
  const printslip = useCallback(
    async (ticket: slipTicket) => {
      const logo = await slipLogo();
      await connection.write(
        encodeinternalslip(ticket, connection.paperWidth, logo),
      );
    },
    [connection],
  );

  const { write: _write, ...printer } = connection;
  void _write;
  return { ...printer, printslip };
}
