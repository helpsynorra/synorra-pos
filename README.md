# Synorra POS

Next.js (App Router) + TypeScript project.

## Getting Started

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) to view the app.

Edit `src/app/page.tsx` — the page updates as you save.

## POS printers

The POS treats cup labels and customer receipts as separate printer roles. Each
role has its own Web Serial connection, ESC/POS adapter, paper width, baud rate,
and persisted print jobs.

- Connect the label and receipt printers independently from the POS header.
- Paper width and baud rate can be changed in the Print dialog. Disconnect a
  printer before changing its baud rate, then reconnect it.
- Completing an order saves its print jobs before attempting either printer.
  Disconnected or failed jobs remain available under Print for an independent
  retry; successful jobs are not retried automatically.
- Test labels remain manual and are available only when
  `NEXT_PUBLIC_TEST_PRINTER=true`.

The initial adapters target ESC/POS over Web Serial. Actual USB, Bluetooth,
network, or vendor-specific printer support may require another transport or
protocol adapter; checkout and persisted job logic should not need to change.

## Commune promotion bridge

Commune validates and redeems Synorra vouchers through the server-only
`/api/commune-promotions` endpoint. Set `COMMUNE_PROMOTION_SHARED_SECRET` to the
same random value of at least 32 characters in both the Synorra and Commune
server environments. Keep it out of Flutter build defines and browser-visible
environment variables. Commune can override the Synorra endpoint with
`SYNORRA_PROMOTION_API_URL`; the default is
`https://synorra-pos.vercel.app/api/commune-promotions`.
