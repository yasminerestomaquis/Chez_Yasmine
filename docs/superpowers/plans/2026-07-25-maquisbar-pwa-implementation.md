# MaquisBar PWA — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a mono-site, offline-first PWA for managing a maquis-bar's daily operations (catalog, POS, table service, customers/credit, stock, expenses, losses, reports, backup), per `docs/superpowers/specs/2026-07-25-maquisbar-pwa-design.md`.

**Architecture:** React + TypeScript SPA built with Vite, installable as a PWA (manifest + service worker via `vite-plugin-pwa`). All data lives in the browser via IndexedDB (Dexie.js). Business rules (cart totals, payment splitting, stock math, credit balances, report aggregation) live in pure, framework-free functions under `src/domain/`, unit-tested with Vitest. Repositories wrap Dexie tables behind small typed interfaces. Feature folders under `src/features/` hold the screens; a thin app shell provides routing and navigation.

**Tech Stack:** Vite, React 18, TypeScript, react-router-dom, Dexie.js, Tailwind CSS, vite-plugin-pwa, Vitest, @testing-library/react, fake-indexeddb (for repository tests).

**Project location:** `app/` inside `D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT` (sibling to `PROMPT/` and `docs/`). All file paths below are relative to that `app/` folder unless stated otherwise.

---

## Milestone 0 — Project scaffolding

### Task 1: Scaffold the Vite + React + TypeScript project

**Files:**
- Create: `app/` (entire Vite scaffold)

- [ ] **Step 1: Scaffold the project**

Run from `D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT`:

```bash
npm create vite@latest app -- --template react-ts
```

- [ ] **Step 2: Install base dependencies**

```bash
cd app
npm install
```

- [ ] **Step 3: Verify the dev server boots**

Run: `npm run dev -- --port 5173 &` then check `curl -s http://localhost:5173 | grep -o '<title>[^<]*'`
Expected: prints a `<title>` tag (default Vite title). Stop the dev server afterward.

- [ ] **Step 4: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Scaffold Vite + React + TypeScript project"
```

---

### Task 2: Install and configure Tailwind CSS

**Files:**
- Create: `app/tailwind.config.js`
- Create: `app/postcss.config.js`
- Modify: `app/src/index.css`

- [ ] **Step 1: Install Tailwind and its peer dependencies**

```bash
cd app
npm install -D tailwindcss postcss autoprefixer
npx tailwindcss init -p
```

- [ ] **Step 2: Configure content paths**

Replace the contents of `app/tailwind.config.js`:

```js
/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"],
  theme: {
    extend: {},
  },
  plugins: [],
}
```

- [ ] **Step 3: Add Tailwind directives**

Replace the entire contents of `app/src/index.css` with:

```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```

- [ ] **Step 4: Verify Tailwind classes apply**

Replace the contents of `app/src/App.tsx` temporarily with:

```tsx
function App() {
  return <div className="text-3xl font-bold text-blue-600">MaquisBar</div>;
}

export default App;
```

Run: `npm run build`
Expected: build succeeds with no errors (Tailwind classes compiled into `dist/assets/*.css`).

- [ ] **Step 5: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add Tailwind CSS"
```

---

### Task 3: Install routing, IndexedDB, and PWA tooling

**Files:**
- Modify: `app/package.json`
- Modify: `app/vite.config.ts`

- [ ] **Step 1: Install runtime dependencies**

```bash
cd app
npm install dexie react-router-dom
```

- [ ] **Step 2: Install the PWA plugin**

```bash
npm install -D vite-plugin-pwa
```

- [ ] **Step 3: Configure `vite.config.ts`**

Replace the contents of `app/vite.config.ts`:

```ts
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['icons/icon-192.png', 'icons/icon-512.png'],
      manifest: {
        name: 'MaquisBar',
        short_name: 'MaquisBar',
        description: "Gestion de maquis-bar hors ligne",
        theme_color: '#0f172a',
        background_color: '#0f172a',
        display: 'standalone',
        start_url: '/',
        icons: [
          { src: 'icons/icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: 'icons/icon-512.png', sizes: '512x512', type: 'image/png' },
        ],
      },
      workbox: {
        globPatterns: ['**/*.{js,css,html,ico,png,svg,webmanifest}'],
      },
    }),
  ],
})
```

- [ ] **Step 4: Add placeholder PWA icons**

Create `app/public/icons/` and add two solid-color PNG placeholders named `icon-192.png` (192x192) and `icon-512.png` (512x512). Use any local image tool or the following Node script:

```bash
node -e "
const { writeFileSync, mkdirSync } = require('fs');
mkdirSync('public/icons', { recursive: true });
// 1x1 transparent PNG bytes, reused as a placeholder for both sizes
const png = Buffer.from('89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000a4944415478da6360000002000155a3e01e0000000049454e44ae426082','hex');
writeFileSync('public/icons/icon-192.png', png);
writeFileSync('public/icons/icon-512.png', png);
"
```

- [ ] **Step 5: Verify the build produces a manifest and service worker**

Run: `npm run build`
Expected: `dist/manifest.webmanifest` and `dist/sw.js` exist. Check with `ls dist/manifest.webmanifest dist/sw.js`.

- [ ] **Step 6: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add routing, Dexie, and PWA plugin"
```

---

### Task 4: Configure Vitest

**Files:**
- Modify: `app/vite.config.ts`
- Create: `app/src/test/setup.ts`

- [ ] **Step 1: Install test dependencies**

```bash
cd app
npm install -D vitest @testing-library/react @testing-library/jest-dom jsdom fake-indexeddb @testing-library/user-event
```

- [ ] **Step 2: Add the `test` block to `vite.config.ts`**

Add this key to the `defineConfig({...})` object in `app/vite.config.ts` (alongside `plugins`):

```ts
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    globals: true,
  },
```

The top of the file also needs a triple-slash reference so TypeScript recognizes `test`:

```ts
/// <reference types="vitest/config" />
```

Add it as the first line of `app/vite.config.ts`.

- [ ] **Step 3: Create the setup file**

Create `app/src/test/setup.ts`:

```ts
import '@testing-library/jest-dom'
import 'fake-indexeddb/auto'
```

- [ ] **Step 4: Add the `test` script**

In `app/package.json`, add to `"scripts"`:

```json
"test": "vitest run"
```

- [ ] **Step 5: Verify Vitest runs with zero tests**

Run: `npm run test`
Expected: `No test files found` message, exit code reflects no failures (Vitest reports 0 tests, not an error).

- [ ] **Step 6: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Configure Vitest with jsdom and fake-indexeddb"
```

---

## Milestone 1 — Domain layer (pure business rules)

All files in this milestone live under `app/src/domain/` and have **zero** imports from React or Dexie. This is what makes them fast to unit-test.

### Task 5: Shared domain types

**Files:**
- Create: `app/src/domain/types.ts`

- [ ] **Step 1: Define the shared types**

Create `app/src/domain/types.ts`:

```ts
export type PaymentMethod = 'cash' | 'mobile_money' | 'card' | 'credit'

export interface CartLine {
  productId: string
  name: string
  unitPrice: number
  quantity: number
}

export interface Payment {
  method: PaymentMethod
  amount: number
}

export interface StockLevel {
  productId: string
  quantity: number
  alertThreshold: number
}

export type StockMovementType = 'in' | 'out' | 'adjustment' | 'sale' | 'loss'

export interface StockMovementInput {
  productId: string
  type: StockMovementType
  quantity: number
}
```

- [ ] **Step 2: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add shared domain types"
```

---

### Task 6: Cart totals

**Files:**
- Create: `app/src/domain/cart.ts`
- Test: `app/src/domain/cart.test.ts`

- [ ] **Step 1: Write the failing tests**

Create `app/src/domain/cart.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { computeCartTotals } from './cart'
import type { CartLine } from './types'

const lines: CartLine[] = [
  { productId: 'p1', name: 'Bière', unitPrice: 1000, quantity: 3 },
  { productId: 'p2', name: 'Brochette', unitPrice: 1500, quantity: 2 },
]

describe('computeCartTotals', () => {
  it('sums line totals into a subtotal', () => {
    const totals = computeCartTotals(lines, { type: 'amount', value: 0 })
    expect(totals.subtotal).toBe(6000)
  })

  it('applies a fixed-amount discount', () => {
    const totals = computeCartTotals(lines, { type: 'amount', value: 500 })
    expect(totals.discount).toBe(500)
    expect(totals.total).toBe(5500)
  })

  it('applies a percentage discount', () => {
    const totals = computeCartTotals(lines, { type: 'percent', value: 10 })
    expect(totals.discount).toBe(600)
    expect(totals.total).toBe(5400)
  })

  it('never lets a discount push the total below zero', () => {
    const totals = computeCartTotals(lines, { type: 'amount', value: 999999 })
    expect(totals.total).toBe(0)
    expect(totals.discount).toBe(6000)
  })

  it('rejects a negative quantity', () => {
    const badLines: CartLine[] = [{ productId: 'p1', name: 'Bière', unitPrice: 1000, quantity: -1 }]
    expect(() => computeCartTotals(badLines, { type: 'amount', value: 0 })).toThrow('quantité invalide')
  })
})
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `npm run test -- cart`
Expected: FAIL — `Cannot find module './cart'`.

- [ ] **Step 3: Implement `cart.ts`**

Create `app/src/domain/cart.ts`:

```ts
import type { CartLine } from './types'

export type Discount =
  | { type: 'amount'; value: number }
  | { type: 'percent'; value: number }

export interface CartTotals {
  subtotal: number
  discount: number
  total: number
}

function lineTotal(line: CartLine): number {
  if (!Number.isFinite(line.quantity) || line.quantity <= 0) {
    throw new Error(`quantité invalide pour ${line.name}`)
  }
  return line.unitPrice * line.quantity
}

export function computeCartTotals(lines: CartLine[], discount: Discount): CartTotals {
  const subtotal = lines.reduce((sum, line) => sum + lineTotal(line), 0)

  const rawDiscount = discount.type === 'percent' ? subtotal * (discount.value / 100) : discount.value

  const clampedDiscount = Math.max(0, Math.min(rawDiscount, subtotal))

  return {
    subtotal,
    discount: clampedDiscount,
    total: subtotal - clampedDiscount,
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `npm run test -- cart`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add cart totals domain logic"
```

---

### Task 7: Payment splitting

**Files:**
- Create: `app/src/domain/payment.ts`
- Test: `app/src/domain/payment.test.ts`

- [ ] **Step 1: Write the failing tests**

Create `app/src/domain/payment.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { validatePayments } from './payment'
import type { Payment } from './types'

describe('validatePayments', () => {
  it('accepts a single cash payment matching the total exactly', () => {
    const payments: Payment[] = [{ method: 'cash', amount: 5000 }]
    expect(() => validatePayments(payments, 5000)).not.toThrow()
  })

  it('accepts a mixed payment that sums to the total', () => {
    const payments: Payment[] = [
      { method: 'cash', amount: 2000 },
      { method: 'mobile_money', amount: 3000 },
    ]
    expect(() => validatePayments(payments, 5000)).not.toThrow()
  })

  it('rejects an incomplete payment', () => {
    const payments: Payment[] = [{ method: 'cash', amount: 4000 }]
    expect(() => validatePayments(payments, 5000)).toThrow('paiement incomplet')
  })

  it('rejects a payment that overshoots the total', () => {
    const payments: Payment[] = [{ method: 'cash', amount: 6000 }]
    expect(() => validatePayments(payments, 5000)).toThrow('paiement incomplet')
  })

  it('rejects a payment with no lines', () => {
    expect(() => validatePayments([], 5000)).toThrow('paiement incomplet')
  })

  it('rejects a negative payment amount', () => {
    const payments: Payment[] = [{ method: 'cash', amount: -100 }]
    expect(() => validatePayments(payments, 5000)).toThrow('montant invalide')
  })

  it('requires a customer for credit payments, whether or not a context object is passed', () => {
    const payments: Payment[] = [{ method: 'credit', amount: 5000 }]
    expect(() => validatePayments(payments, 5000)).toThrow('client requis')
    expect(() => validatePayments(payments, 5000, { customerId: undefined })).toThrow('client requis')
    expect(() => validatePayments(payments, 5000, { customerId: 'c1' })).not.toThrow()
  })
})
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `npm run test -- payment`
Expected: FAIL — `Cannot find module './payment'`.

- [ ] **Step 3: Implement `payment.ts`**

Create `app/src/domain/payment.ts`:

```ts
import type { Payment } from './types'

const EPSILON = 0.01

export interface PaymentContext {
  customerId?: string
}

export function validatePayments(payments: Payment[], total: number, context?: PaymentContext): void {
  if (payments.length === 0) {
    throw new Error('paiement incomplet : aucune ligne de paiement')
  }

  for (const payment of payments) {
    if (!Number.isFinite(payment.amount) || payment.amount <= 0) {
      throw new Error(`montant invalide pour le paiement ${payment.method}`)
    }
  }

  const hasCredit = payments.some((p) => p.method === 'credit')
  if (hasCredit && !context?.customerId) {
    throw new Error('client requis pour une vente à crédit')
  }

  const sum = payments.reduce((acc, p) => acc + p.amount, 0)
  if (Math.abs(sum - total) > EPSILON) {
    throw new Error(`paiement incomplet : ${sum} reçu pour un total de ${total}`)
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `npm run test -- payment`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add payment validation domain logic"
```

---

### Task 8: Stock math

**Files:**
- Create: `app/src/domain/stock.ts`
- Test: `app/src/domain/stock.test.ts`

- [ ] **Step 1: Write the failing tests**

Create `app/src/domain/stock.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { applyStockMovement, isLowStock } from './stock'

describe('applyStockMovement', () => {
  it('increases quantity for an "in" movement', () => {
    expect(applyStockMovement(10, { productId: 'p1', type: 'in', quantity: 5 })).toBe(15)
  })

  it('decreases quantity for a "sale" movement', () => {
    expect(applyStockMovement(10, { productId: 'p1', type: 'sale', quantity: 4 })).toBe(6)
  })

  it('decreases quantity for a "loss" movement', () => {
    expect(applyStockMovement(10, { productId: 'p1', type: 'loss', quantity: 2 })).toBe(8)
  })

  it('sets quantity directly for an "adjustment" movement', () => {
    expect(applyStockMovement(10, { productId: 'p1', type: 'adjustment', quantity: 7 })).toBe(7)
  })

  it('rejects a sale that would drive stock negative', () => {
    expect(() => applyStockMovement(3, { productId: 'p1', type: 'sale', quantity: 5 })).toThrow('stock insuffisant')
  })

  it('rejects a negative movement quantity', () => {
    expect(() => applyStockMovement(10, { productId: 'p1', type: 'in', quantity: -1 })).toThrow('quantité invalide')
  })
})

describe('isLowStock', () => {
  it('flags stock at or below the alert threshold', () => {
    expect(isLowStock({ productId: 'p1', quantity: 5, alertThreshold: 5 })).toBe(true)
    expect(isLowStock({ productId: 'p1', quantity: 4, alertThreshold: 5 })).toBe(true)
  })

  it('does not flag stock above the alert threshold', () => {
    expect(isLowStock({ productId: 'p1', quantity: 6, alertThreshold: 5 })).toBe(false)
  })
})
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `npm run test -- stock`
Expected: FAIL — `Cannot find module './stock'`.

- [ ] **Step 3: Implement `stock.ts`**

Create `app/src/domain/stock.ts`:

```ts
import type { StockLevel, StockMovementInput } from './types'

export function applyStockMovement(currentQuantity: number, movement: StockMovementInput): number {
  if (!Number.isFinite(movement.quantity) || movement.quantity < 0) {
    throw new Error(`quantité invalide pour le mouvement de stock (${movement.productId})`)
  }

  switch (movement.type) {
    case 'in':
      return currentQuantity + movement.quantity
    case 'sale':
    case 'loss':
    case 'out': {
      const next = currentQuantity - movement.quantity
      if (next < 0) {
        throw new Error(`stock insuffisant pour ${movement.productId}`)
      }
      return next
    }
    case 'adjustment':
      return movement.quantity
    default:
      throw new Error(`type de mouvement inconnu : ${movement.type}`)
  }
}

export function isLowStock(level: StockLevel): boolean {
  return level.quantity <= level.alertThreshold
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `npm run test -- stock`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add stock movement domain logic"
```

---

### Task 9: Credit balances

**Files:**
- Create: `app/src/domain/credit.ts`
- Test: `app/src/domain/credit.test.ts`

- [ ] **Step 1: Write the failing tests**

Create `app/src/domain/credit.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { applyCreditSale, applyRepayment } from './credit'

describe('applyCreditSale', () => {
  it('increases the balance by the sale amount', () => {
    expect(applyCreditSale({ balance: 1000, limit: 5000 }, 2000)).toBe(3000)
  })

  it('rejects a sale that would exceed the credit limit', () => {
    expect(() => applyCreditSale({ balance: 4000, limit: 5000 }, 2000)).toThrow('plafond de crédit dépassé')
  })

  it('rejects a non-positive sale amount', () => {
    expect(() => applyCreditSale({ balance: 0, limit: 5000 }, 0)).toThrow('montant invalide')
  })
})

describe('applyRepayment', () => {
  it('decreases the balance by the repayment amount', () => {
    expect(applyRepayment(3000, 1000)).toBe(2000)
  })

  it('rejects a repayment larger than the current balance', () => {
    expect(() => applyRepayment(500, 1000)).toThrow('remboursement supérieur au solde')
  })

  it('rejects a non-positive repayment amount', () => {
    expect(() => applyRepayment(1000, 0)).toThrow('montant invalide')
  })
})
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `npm run test -- credit`
Expected: FAIL — `Cannot find module './credit'`.

- [ ] **Step 3: Implement `credit.ts`**

Create `app/src/domain/credit.ts`:

```ts
export interface CreditAccount {
  balance: number
  limit: number
}

export function applyCreditSale(account: CreditAccount, amount: number): number {
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new Error('montant invalide pour la vente à crédit')
  }
  const next = account.balance + amount
  if (next > account.limit) {
    throw new Error('plafond de crédit dépassé')
  }
  return next
}

export function applyRepayment(currentBalance: number, amount: number): number {
  if (!Number.isFinite(amount) || amount <= 0) {
    throw new Error('montant invalide pour le remboursement')
  }
  if (amount > currentBalance) {
    throw new Error('remboursement supérieur au solde')
  }
  return currentBalance - amount
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `npm run test -- credit`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add credit balance domain logic"
```

---

### Task 10: Report aggregation

**Files:**
- Create: `app/src/domain/reports.ts`
- Test: `app/src/domain/reports.test.ts`

- [ ] **Step 1: Write the failing tests**

Create `app/src/domain/reports.test.ts`:

```ts
import { describe, it, expect } from 'vitest'
import { summarizeDailySales, topProducts } from './reports'

interface SaleRecord {
  total: number
  createdAt: string
  payments: { method: string; amount: number }[]
  items: { productId: string; name: string; quantity: number; unitPrice: number }[]
}

const sales: SaleRecord[] = [
  {
    total: 5000,
    createdAt: '2026-07-25T10:00:00.000Z',
    payments: [{ method: 'cash', amount: 5000 }],
    items: [{ productId: 'p1', name: 'Bière', quantity: 5, unitPrice: 1000 }],
  },
  {
    total: 3000,
    createdAt: '2026-07-25T18:00:00.000Z',
    payments: [{ method: 'mobile_money', amount: 3000 }],
    items: [{ productId: 'p2', name: 'Brochette', quantity: 2, unitPrice: 1500 }],
  },
  {
    total: 1000,
    createdAt: '2026-07-24T10:00:00.000Z',
    payments: [{ method: 'cash', amount: 1000 }],
    items: [{ productId: 'p1', name: 'Bière', quantity: 1, unitPrice: 1000 }],
  },
]

describe('summarizeDailySales', () => {
  it('sums totals only for the given day', () => {
    const summary = summarizeDailySales(sales, '2026-07-25')
    expect(summary.totalRevenue).toBe(8000)
    expect(summary.saleCount).toBe(2)
  })

  it('breaks down revenue by payment method', () => {
    const summary = summarizeDailySales(sales, '2026-07-25')
    expect(summary.byPaymentMethod).toEqual({ cash: 5000, mobile_money: 3000 })
  })

  it('returns zeroed totals for a day with no sales', () => {
    const summary = summarizeDailySales(sales, '2026-01-01')
    expect(summary.totalRevenue).toBe(0)
    expect(summary.saleCount).toBe(0)
    expect(summary.byPaymentMethod).toEqual({})
  })
})

describe('topProducts', () => {
  it('ranks products by quantity sold, descending', () => {
    const ranked = topProducts(sales)
    expect(ranked[0]).toEqual({ productId: 'p1', name: 'Bière', quantity: 6, revenue: 6000 })
    expect(ranked[1]).toEqual({ productId: 'p2', name: 'Brochette', quantity: 2, revenue: 3000 })
  })
})
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `npm run test -- reports`
Expected: FAIL — `Cannot find module './reports'`.

- [ ] **Step 3: Implement `reports.ts`**

Create `app/src/domain/reports.ts`:

```ts
export interface SaleItem {
  productId: string
  name: string
  quantity: number
  unitPrice: number
}

export interface SaleForReport {
  total: number
  createdAt: string
  payments: { method: string; amount: number }[]
  items: SaleItem[]
}

export interface DailySalesSummary {
  totalRevenue: number
  saleCount: number
  byPaymentMethod: Record<string, number>
}

function isSameDay(isoDate: string, day: string): boolean {
  return isoDate.slice(0, 10) === day
}

export function summarizeDailySales(sales: SaleForReport[], day: string): DailySalesSummary {
  const daySales = sales.filter((sale) => isSameDay(sale.createdAt, day))

  const byPaymentMethod: Record<string, number> = {}
  for (const sale of daySales) {
    for (const payment of sale.payments) {
      byPaymentMethod[payment.method] = (byPaymentMethod[payment.method] ?? 0) + payment.amount
    }
  }

  return {
    totalRevenue: daySales.reduce((sum, sale) => sum + sale.total, 0),
    saleCount: daySales.length,
    byPaymentMethod,
  }
}

export interface ProductRanking {
  productId: string
  name: string
  quantity: number
  revenue: number
}

export function topProducts(sales: SaleForReport[]): ProductRanking[] {
  const byProduct = new Map<string, ProductRanking>()

  for (const sale of sales) {
    for (const item of sale.items) {
      const existing = byProduct.get(item.productId)
      const revenue = item.unitPrice * item.quantity
      if (existing) {
        existing.quantity += item.quantity
        existing.revenue += revenue
      } else {
        byProduct.set(item.productId, {
          productId: item.productId,
          name: item.name,
          quantity: item.quantity,
          revenue,
        })
      }
    }
  }

  return [...byProduct.values()].sort((a, b) => b.quantity - a.quantity)
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `npm run test -- reports`
Expected: PASS, 4 tests.

- [ ] **Step 5: Run the full domain test suite**

Run: `npm run test -- domain`
Expected: PASS, all domain tests (cart, payment, stock, credit, reports) green.

- [ ] **Step 6: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add report aggregation domain logic"
```

---

## Milestone 2 — Database schema & repositories

### Task 11: Dexie schema

**Files:**
- Create: `app/src/db/schema.ts`

- [ ] **Step 1: Define entity record types and the Dexie database**

Create `app/src/db/schema.ts`:

```ts
import Dexie, { type Table } from 'dexie'
import type { PaymentMethod, StockMovementType } from '../domain/types'

export interface CategoryRecord {
  id: string
  name: string
}

export interface ProductRecord {
  id: string
  name: string
  categoryId: string
  price: number
  photoDataUrl: string | null
  stockQuantity: number
  alertThreshold: number
  createdAt: string
}

export interface StockMovementRecord {
  id: string
  productId: string
  type: StockMovementType
  quantity: number
  reason: string
  createdAt: string
}

export interface CustomerRecord {
  id: string
  name: string
  phone: string
  address: string
  creditBalance: number
  creditLimit: number
}

export interface CreditMovementRecord {
  id: string
  customerId: string
  type: 'credit' | 'repayment'
  amount: number
  note: string
  createdAt: string
}

export type TableStatus = 'free' | 'occupied' | 'billing'

export interface TableRecord {
  id: string
  name: string
  zone: string
  status: TableStatus
}

export interface AdditionItem {
  productId: string
  name: string
  unitPrice: number
  quantity: number
  addedAt: string
}

export type AdditionStatus = 'open' | 'closed'

export interface AdditionRecord {
  id: string
  tableId: string
  items: AdditionItem[]
  status: AdditionStatus
  openedAt: string
  closedAt: string | null
}

export interface SaleRecord {
  id: string
  source: 'pos' | 'table'
  tableId: string | null
  items: AdditionItem[]
  subtotal: number
  discount: number
  total: number
  payments: { method: PaymentMethod; amount: number }[]
  customerId: string | null
  createdAt: string
}

export interface ExpenseRecord {
  id: string
  label: string
  category: string
  amount: number
  date: string
  note: string
}

export interface LossRecord {
  id: string
  productId: string
  quantity: number
  reason: string
  author: string
  createdAt: string
}

export interface SettingsRecord {
  id: 'main'
  establishmentName: string
  address: string
  currency: 'FCFA'
  pinHash: string | null
  createdAt: string
}

export class MaquisBarDatabase extends Dexie {
  categories!: Table<CategoryRecord, string>
  products!: Table<ProductRecord, string>
  stockMovements!: Table<StockMovementRecord, string>
  customers!: Table<CustomerRecord, string>
  creditMovements!: Table<CreditMovementRecord, string>
  // Named `restaurantTables`, not `tables` — Dexie's own base class reserves
  // the `tables` property (its internal list of all tables), so a store
  // literally named `tables` fails to bind (both at the type level and at
  // runtime). The exported `tablesRepo` name is unaffected.
  restaurantTables!: Table<TableRecord, string>
  additions!: Table<AdditionRecord, string>
  sales!: Table<SaleRecord, string>
  expenses!: Table<ExpenseRecord, string>
  losses!: Table<LossRecord, string>
  settings!: Table<SettingsRecord, string>

  constructor(name = 'maquisbar') {
    super(name)
    this.version(1).stores({
      categories: 'id, name',
      products: 'id, categoryId, name',
      stockMovements: 'id, productId, createdAt',
      customers: 'id, name',
      creditMovements: 'id, customerId, createdAt',
      restaurantTables: 'id, zone, status',
      additions: 'id, tableId, status, openedAt',
      sales: 'id, tableId, customerId, createdAt',
      expenses: 'id, date',
      losses: 'id, productId, createdAt',
      settings: 'id',
    })
  }
}

export const db = new MaquisBarDatabase()
```

- [ ] **Step 2: Verify the project still builds**

Run: `npm run build`
Expected: build succeeds (schema file has no consumers yet, so this only checks for syntax/type errors).

- [ ] **Step 3: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add Dexie database schema"
```

---

### Task 12: Generic repository factory

**Files:**
- Create: `app/src/db/repository.ts`
- Test: `app/src/db/repository.test.ts`

- [ ] **Step 1: Write the failing test**

Create `app/src/db/repository.test.ts`:

```ts
import { describe, it, expect, beforeEach } from 'vitest'
import Dexie, { type Table } from 'dexie'
import { createRepository } from './repository'

interface Widget {
  id: string
  label: string
}

class TestDatabase extends Dexie {
  widgets!: Table<Widget, string>
  constructor() {
    super('repository-test-' + Math.random())
    this.version(1).stores({ widgets: 'id, label' })
  }
}

describe('createRepository', () => {
  let db: TestDatabase
  let repo: ReturnType<typeof createRepository<Widget>>

  beforeEach(() => {
    db = new TestDatabase()
    repo = createRepository(db.widgets)
  })

  it('creates a record with a generated id', async () => {
    const created = await repo.create({ label: 'first' })
    expect(created.id).toBeTruthy()
    expect(created.label).toBe('first')
  })

  it('lists all created records', async () => {
    await repo.create({ label: 'a' })
    await repo.create({ label: 'b' })
    const all = await repo.list()
    expect(all).toHaveLength(2)
  })

  it('gets a record by id', async () => {
    const created = await repo.create({ label: 'findme' })
    const found = await repo.get(created.id)
    expect(found?.label).toBe('findme')
  })

  it('returns undefined for a missing id', async () => {
    const found = await repo.get('does-not-exist')
    expect(found).toBeUndefined()
  })

  it('updates a record', async () => {
    const created = await repo.create({ label: 'before' })
    await repo.update(created.id, { label: 'after' })
    const found = await repo.get(created.id)
    expect(found?.label).toBe('after')
  })

  it('removes a record', async () => {
    const created = await repo.create({ label: 'temp' })
    await repo.remove(created.id)
    const found = await repo.get(created.id)
    expect(found).toBeUndefined()
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- db/repository`
Expected: FAIL — `Cannot find module './repository'`.

- [ ] **Step 3: Implement `repository.ts`**

Create `app/src/db/repository.ts`:

```ts
import type { Table } from 'dexie'

export interface Repository<T extends { id: string }> {
  list(): Promise<T[]>
  get(id: string): Promise<T | undefined>
  create(data: Omit<T, 'id'>): Promise<T>
  update(id: string, changes: Partial<Omit<T, 'id'>>): Promise<void>
  remove(id: string): Promise<void>
}

export function createRepository<T extends { id: string }>(table: Table<T, string>): Repository<T> {
  return {
    async list() {
      return table.toArray()
    },
    async get(id) {
      return table.get(id)
    },
    async create(data) {
      const record = { ...data, id: crypto.randomUUID() } as T
      await table.add(record)
      return record
    },
    async update(id, changes) {
      // Dexie 4.x's Table.update() expects UpdateSpec<T> (a keypath-based
      // mapped type), not a plain Partial<T> — the double cast below keeps
      // the public Repository<T>.update signature as Partial<Omit<T,'id'>>.
      await table.update(id, changes as unknown as import('dexie').UpdateSpec<T>)
    },
    async remove(id) {
      await table.delete(id)
    },
  }
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- db/repository`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add generic Dexie repository factory"
```

---

### Task 13: Entity repositories

**Files:**
- Create: `app/src/db/repositories.ts`
- Test: `app/src/db/repositories.test.ts`

- [ ] **Step 1: Write the failing test**

Create `app/src/db/repositories.test.ts`:

```ts
import { describe, it, expect, beforeEach } from 'vitest'
import { db } from './schema'
import {
  categoriesRepo,
  productsRepo,
  customersRepo,
  tablesRepo,
  additionsRepo,
  salesRepo,
  expensesRepo,
  lossesRepo,
  stockMovementsRepo,
  creditMovementsRepo,
} from './repositories'

describe('entity repositories', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
  })

  it('creates and lists a category', async () => {
    await categoriesRepo.create({ name: 'Boissons' })
    const all = await categoriesRepo.list()
    expect(all).toHaveLength(1)
  })

  it('creates and lists a product', async () => {
    const category = await categoriesRepo.create({ name: 'Boissons' })
    await productsRepo.create({
      name: 'Bière',
      categoryId: category.id,
      price: 1000,
      photoDataUrl: null,
      stockQuantity: 20,
      alertThreshold: 5,
      createdAt: new Date().toISOString(),
    })
    const all = await productsRepo.list()
    expect(all).toHaveLength(1)
  })

  it('creates a customer, table, addition, sale, expense, loss, stock movement, credit movement', async () => {
    const customer = await customersRepo.create({ name: 'Client A', phone: '0700000000', address: '', creditBalance: 0, creditLimit: 10000 })
    const table = await tablesRepo.create({ name: 'T1', zone: 'Terrasse', status: 'free' })
    const addition = await additionsRepo.create({ tableId: table.id, items: [], status: 'open', openedAt: new Date().toISOString(), closedAt: null })
    const sale = await salesRepo.create({ source: 'pos', tableId: null, items: [], subtotal: 0, discount: 0, total: 0, payments: [], customerId: null, createdAt: new Date().toISOString() })
    const expense = await expensesRepo.create({ label: 'Loyer', category: 'Loyer', amount: 50000, date: new Date().toISOString(), note: '' })
    const loss = await lossesRepo.create({ productId: 'p1', quantity: 1, reason: 'Casse', author: 'Gérant', createdAt: new Date().toISOString() })
    const stockMovement = await stockMovementsRepo.create({ productId: 'p1', type: 'in', quantity: 10, reason: 'Réception', createdAt: new Date().toISOString() })
    const creditMovement = await creditMovementsRepo.create({ customerId: customer.id, type: 'credit', amount: 1000, note: '', createdAt: new Date().toISOString() })

    expect(customer.id).toBeTruthy()
    expect(table.id).toBeTruthy()
    expect(addition.id).toBeTruthy()
    expect(sale.id).toBeTruthy()
    expect(expense.id).toBeTruthy()
    expect(loss.id).toBeTruthy()
    expect(stockMovement.id).toBeTruthy()
    expect(creditMovement.id).toBeTruthy()
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- db/repositories`
Expected: FAIL — `Cannot find module './repositories'`.

- [ ] **Step 3: Implement `repositories.ts`**

Create `app/src/db/repositories.ts`:

```ts
import { db } from './schema'
import { createRepository } from './repository'

export const categoriesRepo = createRepository(db.categories)
export const productsRepo = createRepository(db.products)
export const stockMovementsRepo = createRepository(db.stockMovements)
export const customersRepo = createRepository(db.customers)
export const creditMovementsRepo = createRepository(db.creditMovements)
export const tablesRepo = createRepository(db.restaurantTables)
export const additionsRepo = createRepository(db.additions)
export const salesRepo = createRepository(db.sales)
export const expensesRepo = createRepository(db.expenses)
export const lossesRepo = createRepository(db.losses)
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- db/repositories`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add entity repositories"
```

---

### Task 14: Settings repository and PIN hashing

**Files:**
- Create: `app/src/db/settings.ts`
- Test: `app/src/db/settings.test.ts`

- [ ] **Step 1: Write the failing test**

Create `app/src/db/settings.test.ts`:

```ts
import { describe, it, expect, beforeEach } from 'vitest'
import { db } from './schema'
import { getSettings, setPin, verifyPin, updateEstablishmentInfo } from './settings'

describe('settings', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
  })

  it('creates default settings on first access', async () => {
    const settings = await getSettings()
    expect(settings.id).toBe('main')
    expect(settings.currency).toBe('FCFA')
    expect(settings.pinHash).toBeNull()
  })

  it('hashes and verifies a PIN', async () => {
    await setPin('1234')
    expect(await verifyPin('1234')).toBe(true)
    expect(await verifyPin('0000')).toBe(false)
  })

  it('updates establishment info', async () => {
    await updateEstablishmentInfo({ establishmentName: 'Le Bon Coin', address: 'Yopougon' })
    const settings = await getSettings()
    expect(settings.establishmentName).toBe('Le Bon Coin')
    expect(settings.address).toBe('Yopougon')
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- db/settings`
Expected: FAIL — `Cannot find module './settings'`.

- [ ] **Step 3: Implement `settings.ts`**

Create `app/src/db/settings.ts`:

```ts
import { db } from './schema'
import type { SettingsRecord } from './schema'

async function hash(value: string): Promise<string> {
  const data = new TextEncoder().encode(value)
  const digest = await crypto.subtle.digest('SHA-256', data)
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

export async function getSettings(): Promise<SettingsRecord> {
  const existing = await db.settings.get('main')
  if (existing) return existing

  const defaults: SettingsRecord = {
    id: 'main',
    establishmentName: 'Mon établissement',
    address: '',
    currency: 'FCFA',
    pinHash: null,
    createdAt: new Date().toISOString(),
  }
  await db.settings.add(defaults)
  return defaults
}

export async function setPin(pin: string): Promise<void> {
  const pinHash = await hash(pin)
  await getSettings()
  await db.settings.update('main', { pinHash })
}

export async function verifyPin(pin: string): Promise<boolean> {
  const settings = await getSettings()
  if (!settings.pinHash) return false
  return (await hash(pin)) === settings.pinHash
}

export async function updateEstablishmentInfo(changes: { establishmentName?: string; address?: string }): Promise<void> {
  await getSettings()
  await db.settings.update('main', changes)
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- db/settings`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add settings repository with PIN hashing"
```

---

### Task 15: Demo data seeding

**Files:**
- Create: `app/src/db/seed.ts`
- Test: `app/src/db/seed.test.ts`

- [ ] **Step 1: Write the failing test**

Create `app/src/db/seed.test.ts`:

```ts
import { describe, it, expect, beforeEach } from 'vitest'
import { db } from './schema'
import { seedDemoData } from './seed'

describe('seedDemoData', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
  })

  it('creates demo categories, products, tables, and customers', async () => {
    await seedDemoData()
    expect((await db.categories.count())).toBeGreaterThan(0)
    expect((await db.products.count())).toBeGreaterThan(0)
    expect((await db.restaurantTables.count())).toBeGreaterThan(0)
    expect((await db.customers.count())).toBeGreaterThan(0)
  })

  it('is idempotent — running it twice does not duplicate data', async () => {
    await seedDemoData()
    const firstCount = await db.products.count()
    await seedDemoData()
    const secondCount = await db.products.count()
    expect(secondCount).toBe(firstCount)
  })

  it('is idempotent even when two calls race concurrently (React StrictMode double-invokes effects)', async () => {
    await Promise.all([seedDemoData(), seedDemoData()])
    expect(await db.categories.count()).toBe(2)
    expect(await db.products.count()).toBe(5)
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- db/seed`
Expected: FAIL — `Cannot find module './seed'`.

- [ ] **Step 3: Implement `seed.ts`**

Create `app/src/db/seed.ts`:

```ts
import { db } from './schema'

export async function seedDemoData(): Promise<void> {
  // The count-check and inserts must be atomic: React 18 StrictMode
  // double-invokes effects in development, so two overlapping calls to
  // seedDemoData() can otherwise both see an empty categories table and
  // both proceed to insert, duplicating every demo record. Wrapping the
  // whole function in a single Dexie 'rw' transaction serializes concurrent
  // calls on these tables, so the second call's count-check runs only after
  // the first call's inserts have committed.
  await db.transaction('rw', [db.categories, db.products, db.restaurantTables, db.customers], async () => {
    const existingCategories = await db.categories.count()
    if (existingCategories > 0) return

    const now = new Date().toISOString()

    const boissons = { id: crypto.randomUUID(), name: 'Boissons' }
    const grillades = { id: crypto.randomUUID(), name: 'Grillades' }
    await db.categories.bulkAdd([boissons, grillades])

    await db.products.bulkAdd([
      { id: crypto.randomUUID(), name: 'Bière 65cl', categoryId: boissons.id, price: 1000, photoDataUrl: null, stockQuantity: 48, alertThreshold: 12, createdAt: now },
      { id: crypto.randomUUID(), name: 'Eau minérale', categoryId: boissons.id, price: 300, photoDataUrl: null, stockQuantity: 60, alertThreshold: 12, createdAt: now },
      { id: crypto.randomUUID(), name: 'Soda', categoryId: boissons.id, price: 500, photoDataUrl: null, stockQuantity: 36, alertThreshold: 12, createdAt: now },
      { id: crypto.randomUUID(), name: 'Brochette de bœuf', categoryId: grillades.id, price: 1500, photoDataUrl: null, stockQuantity: 30, alertThreshold: 10, createdAt: now },
      { id: crypto.randomUUID(), name: 'Poisson braisé', categoryId: grillades.id, price: 3000, photoDataUrl: null, stockQuantity: 15, alertThreshold: 5, createdAt: now },
    ])

    await db.restaurantTables.bulkAdd([
      { id: crypto.randomUUID(), name: 'T1', zone: 'Terrasse', status: 'free' },
      { id: crypto.randomUUID(), name: 'T2', zone: 'Terrasse', status: 'free' },
      { id: crypto.randomUUID(), name: 'T3', zone: 'Salle', status: 'free' },
      { id: crypto.randomUUID(), name: 'T4', zone: 'Salle', status: 'free' },
    ])

    await db.customers.bulkAdd([
      { id: crypto.randomUUID(), name: 'Client comptant', phone: '', address: '', creditBalance: 0, creditLimit: 0 },
      { id: crypto.randomUUID(), name: 'Kouassi Jean', phone: '0700000001', address: 'Yopougon', creditBalance: 0, creditLimit: 20000 },
    ])
  })
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- db/seed`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add idempotent demo data seeding"
```

---

### Task 16: JSON backup export/import

**Files:**
- Create: `app/src/db/backup.ts`
- Test: `app/src/db/backup.test.ts`

- [ ] **Step 1: Write the failing test**

Create `app/src/db/backup.test.ts`:

```ts
import { describe, it, expect, beforeEach } from 'vitest'
import { db } from './schema'
import { exportBackup, importBackup } from './backup'
import { categoriesRepo } from './repositories'

describe('backup', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
  })

  it('exports all tables as a JSON string with a version marker', async () => {
    await categoriesRepo.create({ name: 'Boissons' })
    const json = await exportBackup()
    const parsed = JSON.parse(json)
    expect(parsed.version).toBe(1)
    expect(parsed.tables.categories).toHaveLength(1)
  })

  it('restores data from a previously exported backup', async () => {
    await categoriesRepo.create({ name: 'Boissons' })
    const json = await exportBackup()

    await db.delete()
    await db.open()
    expect(await db.categories.count()).toBe(0)

    await importBackup(json)
    expect(await db.categories.count()).toBe(1)
  })

  it('rejects a file that is not valid JSON', async () => {
    await expect(importBackup('not json')).rejects.toThrow('fichier de sauvegarde invalide')
  })

  it('rejects JSON that is missing the expected structure', async () => {
    await expect(importBackup(JSON.stringify({ hello: 'world' }))).rejects.toThrow('fichier de sauvegarde invalide')
  })

  it('rejects a backup whose tables object is missing the expected keys, without wiping existing data', async () => {
    await categoriesRepo.create({ name: 'Boissons' })
    await expect(importBackup(JSON.stringify({ version: 1, tables: {} }))).rejects.toThrow('fichier de sauvegarde invalide')
    expect(await db.categories.count()).toBe(1)
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- db/backup`
Expected: FAIL — `Cannot find module './backup'`.

- [ ] **Step 3: Implement `backup.ts`**

Create `app/src/db/backup.ts`:

```ts
import { db } from './schema'

const BACKUP_VERSION = 1

const TABLE_NAMES = [
  'categories',
  'products',
  'stockMovements',
  'customers',
  'creditMovements',
  'restaurantTables',
  'additions',
  'sales',
  'expenses',
  'losses',
  'settings',
] as const

export async function exportBackup(): Promise<string> {
  const tables: Record<string, unknown[]> = {}
  for (const name of TABLE_NAMES) {
    tables[name] = await db.table(name).toArray()
  }
  return JSON.stringify({ version: BACKUP_VERSION, exportedAt: new Date().toISOString(), tables }, null, 2)
}

interface ParsedBackup {
  version: number
  tables: Record<string, unknown[]>
}

function isValidBackup(value: unknown): value is ParsedBackup {
  if (typeof value !== 'object' || value === null) return false
  const candidate = value as Record<string, unknown>
  if (typeof candidate.version !== 'number' || typeof candidate.tables !== 'object' || candidate.tables === null) {
    return false
  }
  // Every expected table key must be present as an array (an empty array is
  // fine — a table can legitimately have no rows) so a truncated or
  // hand-edited file can't silently wipe every table with nothing restored.
  const tables = candidate.tables as Record<string, unknown>
  return TABLE_NAMES.every((name) => Array.isArray(tables[name]))
}

export async function importBackup(json: string): Promise<void> {
  let parsed: unknown
  try {
    parsed = JSON.parse(json)
  } catch {
    throw new Error('fichier de sauvegarde invalide : JSON illisible')
  }

  if (!isValidBackup(parsed)) {
    throw new Error('fichier de sauvegarde invalide : structure inattendue')
  }

  await db.transaction('rw', TABLE_NAMES.map((name) => db.table(name)), async () => {
    for (const name of TABLE_NAMES) {
      await db.table(name).clear()
      const rows = parsed.tables[name]
      if (Array.isArray(rows) && rows.length > 0) {
        await db.table(name).bulkAdd(rows)
      }
    }
  })
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- db/backup`
Expected: PASS, 5 tests.

- [ ] **Step 5: Run the full `db` test suite**

Run: `npm run test -- db/`
Expected: PASS, all repository/settings/seed/backup tests green.

- [ ] **Step 6: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add JSON backup export/import"
```

---

## Milestone 3 — App shell

### Task 17: Router and page placeholders

**Files:**
- Create: `app/src/features/dashboard/DashboardPage.tsx`
- Create: `app/src/features/catalog/CatalogPage.tsx`
- Create: `app/src/features/pos/PosPage.tsx`
- Create: `app/src/features/tables/TablesPage.tsx`
- Create: `app/src/features/customers/CustomersPage.tsx`
- Create: `app/src/features/stock/StockPage.tsx`
- Create: `app/src/features/expenses/ExpensesPage.tsx`
- Create: `app/src/features/losses/LossesPage.tsx`
- Create: `app/src/features/reports/ReportsPage.tsx`
- Create: `app/src/features/settings/SettingsPage.tsx`
- Modify: `app/src/App.tsx`

- [ ] **Step 1: Create one placeholder page per module**

Each file follows the same shape. Create `app/src/features/dashboard/DashboardPage.tsx`:

```tsx
export function DashboardPage() {
  return <h1 className="text-2xl font-semibold">Tableau de bord</h1>
}
```

Repeat for the other nine files, swapping the component name and heading text:

- `app/src/features/catalog/CatalogPage.tsx` → `CatalogPage` / "Catalogue"
- `app/src/features/pos/PosPage.tsx` → `PosPage` / "Caisse"
- `app/src/features/tables/TablesPage.tsx` → `TablesPage` / "Tables"
- `app/src/features/customers/CustomersPage.tsx` → `CustomersPage` / "Clients"
- `app/src/features/stock/StockPage.tsx` → `StockPage` / "Stock"
- `app/src/features/expenses/ExpensesPage.tsx` → `ExpensesPage` / "Dépenses"
- `app/src/features/losses/LossesPage.tsx` → `LossesPage` / "Pertes"
- `app/src/features/reports/ReportsPage.tsx` → `ReportsPage` / "Rapports"
- `app/src/features/settings/SettingsPage.tsx` → `SettingsPage` / "Paramètres"

- [ ] **Step 2: Wire routes in `App.tsx`**

Replace the contents of `app/src/App.tsx`:

```tsx
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import { AppLayout } from './app/AppLayout'
import { DashboardPage } from './features/dashboard/DashboardPage'
import { CatalogPage } from './features/catalog/CatalogPage'
import { PosPage } from './features/pos/PosPage'
import { TablesPage } from './features/tables/TablesPage'
import { CustomersPage } from './features/customers/CustomersPage'
import { StockPage } from './features/stock/StockPage'
import { ExpensesPage } from './features/expenses/ExpensesPage'
import { LossesPage } from './features/losses/LossesPage'
import { ReportsPage } from './features/reports/ReportsPage'
import { SettingsPage } from './features/settings/SettingsPage'

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route element={<AppLayout />}>
          <Route index element={<Navigate to="/dashboard" replace />} />
          <Route path="/dashboard" element={<DashboardPage />} />
          <Route path="/catalog" element={<CatalogPage />} />
          <Route path="/pos" element={<PosPage />} />
          <Route path="/tables" element={<TablesPage />} />
          <Route path="/customers" element={<CustomersPage />} />
          <Route path="/stock" element={<StockPage />} />
          <Route path="/expenses" element={<ExpensesPage />} />
          <Route path="/losses" element={<LossesPage />} />
          <Route path="/reports" element={<ReportsPage />} />
          <Route path="/settings" element={<SettingsPage />} />
        </Route>
      </Routes>
    </BrowserRouter>
  )
}
```

Note: `AppLayout` is created in the next task. This task will not build successfully until Task 18 adds it — that is expected; both tasks are committed together conceptually, but keep them as separate steps for reviewability.

- [ ] **Step 3: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add route placeholders for all feature pages"
```

---

### Task 18: Responsive app layout with navigation

**Files:**
- Create: `app/src/app/AppLayout.tsx`
- Create: `app/src/app/navigation.ts`
- Test: `app/src/app/AppLayout.test.tsx`

- [ ] **Step 1: Define the shared navigation list**

Create `app/src/app/navigation.ts`:

```ts
export interface NavItem {
  path: string
  label: string
}

export const navItems: NavItem[] = [
  { path: '/dashboard', label: 'Tableau de bord' },
  { path: '/pos', label: 'Caisse' },
  { path: '/tables', label: 'Tables' },
  { path: '/catalog', label: 'Catalogue' },
  { path: '/stock', label: 'Stock' },
  { path: '/customers', label: 'Clients' },
  { path: '/expenses', label: 'Dépenses' },
  { path: '/losses', label: 'Pertes' },
  { path: '/reports', label: 'Rapports' },
  { path: '/settings', label: 'Paramètres' },
]
```

- [ ] **Step 2: Write the failing layout test**

Create `app/src/app/AppLayout.test.tsx`:

```tsx
import { describe, it, expect } from 'vitest'
import { render, screen } from '@testing-library/react'
import { MemoryRouter, Routes, Route } from 'react-router-dom'
import { AppLayout } from './AppLayout'
import { navItems } from './navigation'

describe('AppLayout', () => {
  it('renders a navigation link for every module', () => {
    render(
      <MemoryRouter initialEntries={['/dashboard']}>
        <Routes>
          <Route element={<AppLayout />}>
            <Route path="/dashboard" element={<div>Contenu</div>} />
          </Route>
        </Routes>
      </MemoryRouter>
    )

    for (const item of navItems) {
      expect(screen.getAllByText(item.label).length).toBeGreaterThan(0)
    }
  })

  it('renders the routed page content via the outlet', () => {
    render(
      <MemoryRouter initialEntries={['/dashboard']}>
        <Routes>
          <Route element={<AppLayout />}>
            <Route path="/dashboard" element={<div>Contenu</div>} />
          </Route>
        </Routes>
      </MemoryRouter>
    )

    expect(screen.getByText('Contenu')).toBeInTheDocument()
  })
})
```

- [ ] **Step 3: Run the test and confirm it fails**

Run: `npm run test -- app/AppLayout`
Expected: FAIL — `Cannot find module './AppLayout'`.

- [ ] **Step 4: Implement `AppLayout.tsx`**

Create `app/src/app/AppLayout.tsx`:

```tsx
import { NavLink, Outlet } from 'react-router-dom'
import { navItems } from './navigation'

function linkClasses(isActive: boolean): string {
  return `block rounded px-3 py-2 text-sm font-medium ${
    isActive ? 'bg-blue-600 text-white' : 'text-slate-200 hover:bg-slate-700'
  }`
}

export function AppLayout() {
  return (
    <div className="flex h-screen flex-col md:flex-row">
      <nav className="hidden w-56 shrink-0 flex-col gap-1 bg-slate-900 p-3 md:flex">
        {navItems.map((item) => (
          <NavLink key={item.path} to={item.path} className={({ isActive }) => linkClasses(isActive)}>
            {item.label}
          </NavLink>
        ))}
      </nav>

      <main className="flex-1 overflow-y-auto bg-slate-50 p-4 pb-20 md:pb-4">
        <Outlet />
      </main>

      <nav className="fixed bottom-0 left-0 right-0 flex justify-around border-t bg-white p-2 md:hidden">
        {navItems.slice(0, 5).map((item) => (
          <NavLink
            key={item.path}
            to={item.path}
            className={({ isActive }) => `rounded px-2 py-1 text-xs ${isActive ? 'text-blue-600' : 'text-slate-500'}`}
          >
            {item.label}
          </NavLink>
        ))}
      </nav>
    </div>
  )
}
```

- [ ] **Step 5: Run the test and confirm it passes**

Run: `npm run test -- app/AppLayout`
Expected: PASS, 2 tests.

- [ ] **Step 6: Verify the app builds and routes render**

Run: `npm run build`
Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add responsive app layout with sidebar and mobile nav"
```

---

### Task 19: PIN gate for sensitive actions

**Files:**
- Create: `app/src/app/PinGate.tsx`
- Test: `app/src/app/PinGate.test.tsx`
- Modify: `app/src/App.tsx`

- [ ] **Step 1: Write the failing test**

Create `app/src/app/PinGate.test.tsx`:

```tsx
import { describe, it, expect, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { useState } from 'react'
import { db } from '../db/schema'
import { setPin } from '../db/settings'
import { PinGateProvider, usePinGate } from './PinGate'

function TestConsumer() {
  const requirePin = usePinGate()
  const [result, setResult] = useState('idle')
  return (
    <>
      <button onClick={async () => setResult((await requirePin()) ? 'granted' : 'denied')}>Demander</button>
      <div data-testid="result">{result}</div>
    </>
  )
}

function TestDoubleConsumer() {
  const requirePin = usePinGate()
  const [results, setResults] = useState<string[]>([])
  return (
    <>
      <button
        onClick={() => {
          const first = requirePin()
          const second = requirePin()
          Promise.all([first, second]).then(([a, b]) => setResults([a ? 'granted' : 'denied', b ? 'granted' : 'denied']))
        }}
      >
        Demander deux fois
      </button>
      <div data-testid="results">{results.join(',')}</div>
    </>
  )
}

describe('PinGate', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
    await setPin('1234')
  })

  it('grants access when the correct PIN is entered', async () => {
    const user = userEvent.setup()
    render(
      <PinGateProvider>
        <TestConsumer />
      </PinGateProvider>
    )

    await user.click(screen.getByText('Demander'))
    await user.type(screen.getByLabelText('Code PIN'), '1234')
    await user.click(screen.getByText('Confirmer'))

    expect(await screen.findByTestId('result')).toHaveTextContent('granted')
  })

  it('shows an error and does not grant access for a wrong PIN', async () => {
    const user = userEvent.setup()
    render(
      <PinGateProvider>
        <TestConsumer />
      </PinGateProvider>
    )

    await user.click(screen.getByText('Demander'))
    await user.type(screen.getByLabelText('Code PIN'), '0000')
    await user.click(screen.getByText('Confirmer'))

    expect(await screen.findByText('Code PIN incorrect')).toBeInTheDocument()
    expect(screen.getByTestId('result')).toHaveTextContent('idle')
  })

  it('denies access when cancelled', async () => {
    const user = userEvent.setup()
    render(
      <PinGateProvider>
        <TestConsumer />
      </PinGateProvider>
    )

    await user.click(screen.getByText('Demander'))
    await user.click(screen.getByText('Annuler'))

    expect(await screen.findByTestId('result')).toHaveTextContent('denied')
  })

  it('resolves a stale prompt as denied when requirePin() is called again before it settles', async () => {
    const user = userEvent.setup()
    render(
      <PinGateProvider>
        <TestDoubleConsumer />
      </PinGateProvider>
    )

    await user.click(screen.getByText('Demander deux fois'))
    // Only the second (still-open) modal can be answered; the first call's
    // promise must already have resolved to false rather than hanging.
    await user.type(screen.getByLabelText('Code PIN'), '1234')
    await user.click(screen.getByText('Confirmer'))

    expect(await screen.findByTestId('results')).toHaveTextContent('denied,granted')
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- app/PinGate`
Expected: FAIL — `Cannot find module './PinGate'`.

- [ ] **Step 3: Implement `PinGate.tsx`**

Create `app/src/app/PinGate.tsx`:

```tsx
import { createContext, useCallback, useContext, useRef, useState, type ReactNode } from 'react'
import { verifyPin } from '../db/settings'

type RequirePin = () => Promise<boolean>

const PinGateContext = createContext<RequirePin | null>(null)

export function usePinGate(): RequirePin {
  const ctx = useContext(PinGateContext)
  if (!ctx) throw new Error('usePinGate must be used within a PinGateProvider')
  return ctx
}

export function PinGateProvider({ children }: { children: ReactNode }) {
  const [isOpen, setIsOpen] = useState(false)
  const [pin, setPinValue] = useState('')
  const [error, setError] = useState<string | null>(null)
  const resolveRef = useRef<((granted: boolean) => void) | null>(null)

  const requirePin = useCallback<RequirePin>(() => {
    // If a previous requirePin() call is still awaiting input, its promise
    // would otherwise be silently overwritten below and never resolve,
    // leaving that caller hung forever. Deny the stale prompt first.
    if (resolveRef.current) {
      resolveRef.current(false)
      resolveRef.current = null
    }
    setIsOpen(true)
    setPinValue('')
    setError(null)
    return new Promise((resolve) => {
      resolveRef.current = resolve
    })
  }, [])

  function close(granted: boolean) {
    setIsOpen(false)
    resolveRef.current?.(granted)
    resolveRef.current = null
  }

  async function handleConfirm() {
    const ok = await verifyPin(pin)
    if (ok) {
      close(true)
    } else {
      setError('Code PIN incorrect')
    }
  }

  return (
    <PinGateContext.Provider value={requirePin}>
      {children}
      {isOpen && (
        <div className="fixed inset-0 flex items-center justify-center bg-black/40">
          <div className="w-72 rounded bg-white p-4 shadow-lg">
            <label className="mb-2 block text-sm font-medium" htmlFor="pin-gate-input">
              Code PIN
            </label>
            <input
              id="pin-gate-input"
              type="password"
              inputMode="numeric"
              className="mb-2 w-full rounded border px-2 py-1"
              value={pin}
              onChange={(e) => setPinValue(e.target.value)}
            />
            {error && <p className="mb-2 text-sm text-red-600">{error}</p>}
            <div className="flex justify-end gap-2">
              <button className="rounded px-3 py-1 text-sm text-slate-600" onClick={() => close(false)}>
                Annuler
              </button>
              <button className="rounded bg-blue-600 px-3 py-1 text-sm text-white" onClick={handleConfirm}>
                Confirmer
              </button>
            </div>
          </div>
        </div>
      )}
    </PinGateContext.Provider>
  )
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- app/PinGate`
Expected: PASS, 4 tests.

- [ ] **Step 5: Wrap the app with the provider**

In `app/src/App.tsx`, import `PinGateProvider` from `./app/PinGate` and wrap the `<Routes>` element with it, inside `<BrowserRouter>`:

```tsx
<BrowserRouter>
  <PinGateProvider>
    <Routes>
      {/* ...unchanged... */}
    </Routes>
  </PinGateProvider>
</BrowserRouter>
```

- [ ] **Step 6: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add PIN gate for sensitive actions"
```

---

### Task 20: First-run demo data bootstrap

**Files:**
- Modify: `app/src/App.tsx`
- Create: `app/src/app/useBootstrap.ts`
- Test: `app/src/app/useBootstrap.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `app/src/app/useBootstrap.test.tsx`:

```tsx
import { describe, it, expect, beforeEach } from 'vitest'
import { renderHook, waitFor } from '@testing-library/react'
import { db } from '../db/schema'
import { useBootstrap } from './useBootstrap'

describe('useBootstrap', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
  })

  it('is not ready immediately, then becomes ready after seeding', async () => {
    const { result } = renderHook(() => useBootstrap())
    expect(result.current).toBe(false)
    await waitFor(() => expect(result.current).toBe(true))
    expect(await db.categories.count()).toBeGreaterThan(0)
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- app/useBootstrap`
Expected: FAIL — `Cannot find module './useBootstrap'`.

- [ ] **Step 3: Implement `useBootstrap.ts`**

Create `app/src/app/useBootstrap.ts`:

```ts
import { useEffect, useState } from 'react'
import { seedDemoData } from '../db/seed'

export function useBootstrap(): boolean {
  const [ready, setReady] = useState(false)

  useEffect(() => {
    let cancelled = false
    seedDemoData().then(() => {
      if (!cancelled) setReady(true)
    })
    return () => {
      cancelled = true
    }
  }, [])

  return ready
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- app/useBootstrap`
Expected: PASS, 1 test.

- [ ] **Step 5: Wire the bootstrap into `App.tsx`**

In `app/src/App.tsx`, call `useBootstrap()` at the top of the `App` component and short-circuit rendering until it is ready:

```tsx
export default function App() {
  const ready = useBootstrap()

  if (!ready) {
    return (
      <div className="flex h-screen items-center justify-center text-slate-500">
        Chargement de MaquisBar…
      </div>
    )
  }

  return (
    <BrowserRouter>
      {/* ...unchanged... */}
    </BrowserRouter>
  )
}
```

Add the import: `import { useBootstrap } from './app/useBootstrap'`.

- [ ] **Step 6: Verify the app builds**

Run: `npm run build`
Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Bootstrap demo data on first run"
```

---

## Milestone 4 — Catalog (categories & products with photos)

### Task 21: Category management UI

**Files:**
- Create: `app/src/features/catalog/CategoryManager.tsx`
- Test: `app/src/features/catalog/CategoryManager.test.tsx`
- Modify: `app/src/features/catalog/CatalogPage.tsx`

- [ ] **Step 1: Write the failing test**

Create `app/src/features/catalog/CategoryManager.test.tsx`:

```tsx
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { db } from '../../db/schema'
import { categoriesRepo } from '../../db/repositories'
import { CategoryManager } from './CategoryManager'

describe('CategoryManager', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
  })

  it('creates a category and shows it in the list', async () => {
    const user = userEvent.setup()
    render(<CategoryManager />)

    await user.type(screen.getByLabelText('Nom de la catégorie'), 'Bières')
    await user.click(screen.getByText('Ajouter'))

    expect(await screen.findByText('Bières')).toBeInTheDocument()
  })

  it('rejects an empty category name', async () => {
    const user = userEvent.setup()
    render(<CategoryManager />)

    await user.click(screen.getByText('Ajouter'))

    expect(await screen.findByText('Le nom est obligatoire')).toBeInTheDocument()
  })

  it('removes a category after confirmation', async () => {
    const user = userEvent.setup()
    render(<CategoryManager />)

    await user.type(screen.getByLabelText('Nom de la catégorie'), 'Bières')
    await user.click(screen.getByText('Ajouter'))
    await screen.findByText('Bières')

    await user.click(screen.getByLabelText('Supprimer Bières'))

    expect(screen.queryByText('Bières')).not.toBeInTheDocument()
  })

  it('shows an error and keeps the category listed when the delete fails', async () => {
    const user = userEvent.setup()
    render(<CategoryManager />)

    await user.type(screen.getByLabelText('Nom de la catégorie'), 'Bières')
    await user.click(screen.getByText('Ajouter'))
    await screen.findByText('Bières')

    vi.spyOn(categoriesRepo, 'remove').mockRejectedValueOnce(new Error('échec de suppression'))

    await user.click(screen.getByLabelText('Supprimer Bières'))

    expect(await screen.findByText('échec de suppression')).toBeInTheDocument()
    expect(await screen.findByText('Bières')).toBeInTheDocument()
  })
})
```

This test file relies on `window.confirm` returning `true` by default so the delete flow proceeds without an extra click. jsdom doesn't implement `window.confirm` at all (it's a no-op that logs a warning), so before running these tests, add a global stub to the shared Vitest setup file — append to `app/src/test/setup.ts` (created in Task 4):

```ts
// jsdom doesn't implement window.confirm; default to "confirmed" so delete
// flows that gate on it don't silently no-op. Individual tests that need to
// simulate the user cancelling can still override this with
// vi.spyOn(window, 'confirm').mockReturnValueOnce(false).
window.confirm = () => true
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- catalog/CategoryManager`
Expected: FAIL — `Cannot find module './CategoryManager'`.

- [ ] **Step 3: Implement `CategoryManager.tsx`**

Create `app/src/features/catalog/CategoryManager.tsx`:

```tsx
import { useEffect, useState } from 'react'
import { categoriesRepo } from '../../db/repositories'
import type { CategoryRecord } from '../../db/schema'

export function CategoryManager() {
  const [categories, setCategories] = useState<CategoryRecord[]>([])
  const [name, setName] = useState('')
  const [error, setError] = useState<string | null>(null)

  async function reload() {
    setCategories(await categoriesRepo.list())
  }

  useEffect(() => {
    reload()
  }, [])

  async function handleAdd() {
    if (!name.trim()) {
      setError('Le nom est obligatoire')
      return
    }
    setError(null)
    await categoriesRepo.create({ name: name.trim() })
    setName('')
    await reload()
  }

  async function handleRemove(id: string) {
    if (!window.confirm('Supprimer cette catégorie ?')) return
    // Update optimistically (awaiting the repo call first, then reloading,
    // is measurably flaky under Testing Library's synchronous assertions —
    // reproduced ~3/8 runs). Roll back and surface an error if the delete
    // itself fails, so a rejected removal can't silently desync the UI
    // from IndexedDB.
    const previous = categories
    setCategories(previous.filter((category) => category.id !== id))
    try {
      await categoriesRepo.remove(id)
    } catch (err) {
      setCategories(previous)
      setError((err as Error).message)
    }
  }

  return (
    <div className="mb-6">
      <h2 className="mb-2 text-lg font-semibold">Catégories</h2>
      <div className="mb-2 flex gap-2">
        <label className="sr-only" htmlFor="category-name">
          Nom de la catégorie
        </label>
        <input
          id="category-name"
          aria-label="Nom de la catégorie"
          className="rounded border px-2 py-1"
          value={name}
          onChange={(e) => setName(e.target.value)}
        />
        <button className="rounded bg-blue-600 px-3 py-1 text-white" onClick={handleAdd}>
          Ajouter
        </button>
      </div>
      {error && <p className="mb-2 text-sm text-red-600">{error}</p>}
      <ul className="flex flex-wrap gap-2">
        {categories.map((category) => (
          <li key={category.id} className="flex items-center gap-1 rounded bg-slate-200 px-2 py-1 text-sm">
            {category.name}
            <button
              aria-label={`Supprimer ${category.name}`}
              className="text-red-600"
              onClick={() => handleRemove(category.id)}
            >
              ×
            </button>
          </li>
        ))}
      </ul>
    </div>
  )
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- catalog/CategoryManager`
Expected: PASS, 4 tests.

- [ ] **Step 5: Mount it in `CatalogPage`**

Replace the contents of `app/src/features/catalog/CatalogPage.tsx`:

```tsx
import { CategoryManager } from './CategoryManager'

export function CatalogPage() {
  return (
    <div>
      <h1 className="mb-4 text-2xl font-semibold">Catalogue</h1>
      <CategoryManager />
    </div>
  )
}
```

- [ ] **Step 6: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add category management UI"
```

---

### Task 22: Product management UI

**Files:**
- Create: `app/src/features/catalog/ProductManager.tsx`
- Test: `app/src/features/catalog/ProductManager.test.tsx`
- Modify: `app/src/features/catalog/CatalogPage.tsx`

- [ ] **Step 1: Write the failing test**

Create `app/src/features/catalog/ProductManager.test.tsx`:

```tsx
import { describe, it, expect, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { db } from '../../db/schema'
import { categoriesRepo } from '../../db/repositories'
import { ProductManager } from './ProductManager'

describe('ProductManager', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
    await categoriesRepo.create({ name: 'Boissons' })
  })

  it('creates a product with the entered fields', async () => {
    const user = userEvent.setup()
    render(<ProductManager />)

    await user.type(await screen.findByLabelText('Nom du produit'), 'Bière 65cl')
    await user.type(screen.getByLabelText('Prix de vente'), '1000')
    await user.type(screen.getByLabelText('Stock initial'), '20')
    await user.type(screen.getByLabelText("Seuil d'alerte"), '5')
    await user.click(screen.getByText('Enregistrer le produit'))

    expect(await screen.findByText('Bière 65cl')).toBeInTheDocument()
    expect(screen.getByText('1000 FCFA')).toBeInTheDocument()
  })

  it('rejects a product with a non-positive price', async () => {
    const user = userEvent.setup()
    render(<ProductManager />)

    await user.type(await screen.findByLabelText('Nom du produit'), 'Bière 65cl')
    await user.type(screen.getByLabelText('Prix de vente'), '0')
    await user.click(screen.getByText('Enregistrer le produit'))

    expect(await screen.findByText('Le prix doit être positif')).toBeInTheDocument()
  })

  it('rejects a negative stock quantity', async () => {
    const user = userEvent.setup()
    render(<ProductManager />)

    await user.type(await screen.findByLabelText('Nom du produit'), 'Bière 65cl')
    await user.type(screen.getByLabelText('Prix de vente'), '1000')
    await user.type(screen.getByLabelText('Stock initial'), '-5')
    await user.click(screen.getByText('Enregistrer le produit'))

    expect(await screen.findByText('Le stock ne peut pas être négatif')).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- catalog/ProductManager`
Expected: FAIL — `Cannot find module './ProductManager'`.

- [ ] **Step 3: Implement `ProductManager.tsx`**

Create `app/src/features/catalog/ProductManager.tsx`:

```tsx
import { useEffect, useState } from 'react'
import { categoriesRepo, productsRepo } from '../../db/repositories'
import type { CategoryRecord, ProductRecord } from '../../db/schema'

export function ProductManager() {
  const [categories, setCategories] = useState<CategoryRecord[]>([])
  const [products, setProducts] = useState<ProductRecord[]>([])
  const [name, setName] = useState('')
  const [categoryId, setCategoryId] = useState('')
  const [price, setPrice] = useState('')
  const [stockQuantity, setStockQuantity] = useState('')
  const [alertThreshold, setAlertThreshold] = useState('')
  const [error, setError] = useState<string | null>(null)

  async function reload() {
    const [cats, prods] = await Promise.all([categoriesRepo.list(), productsRepo.list()])
    setCategories(cats)
    setProducts(prods)
    if (!categoryId && cats[0]) setCategoryId(cats[0].id)
  }

  useEffect(() => {
    reload()
  }, [])

  async function handleSave() {
    const priceValue = Number(price)
    const stockValue = Number(stockQuantity || 0)
    const thresholdValue = Number(alertThreshold || 0)

    if (!name.trim()) {
      setError('Le nom est obligatoire')
      return
    }
    if (!Number.isFinite(priceValue) || priceValue <= 0) {
      setError('Le prix doit être positif')
      return
    }
    if (!Number.isFinite(stockValue) || stockValue < 0) {
      setError('Le stock ne peut pas être négatif')
      return
    }
    if (!Number.isFinite(thresholdValue) || thresholdValue < 0) {
      setError("Le seuil d'alerte ne peut pas être négatif")
      return
    }
    setError(null)

    await productsRepo.create({
      name: name.trim(),
      categoryId,
      price: priceValue,
      photoDataUrl: null,
      stockQuantity: stockValue,
      alertThreshold: thresholdValue,
      createdAt: new Date().toISOString(),
    })

    setName('')
    setPrice('')
    setStockQuantity('')
    setAlertThreshold('')
    await reload()
  }

  return (
    <div>
      <h2 className="mb-2 text-lg font-semibold">Produits</h2>
      <div className="mb-4 grid grid-cols-2 gap-2 md:grid-cols-5">
        <div>
          <label className="block text-xs" htmlFor="product-name">
            Nom du produit
          </label>
          <input id="product-name" className="w-full rounded border px-2 py-1" value={name} onChange={(e) => setName(e.target.value)} />
        </div>
        <div>
          <label className="block text-xs" htmlFor="product-category">
            Catégorie
          </label>
          <select id="product-category" className="w-full rounded border px-2 py-1" value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-xs" htmlFor="product-price">
            Prix de vente
          </label>
          <input id="product-price" type="number" className="w-full rounded border px-2 py-1" value={price} onChange={(e) => setPrice(e.target.value)} />
        </div>
        <div>
          <label className="block text-xs" htmlFor="product-stock">
            Stock initial
          </label>
          <input id="product-stock" type="number" className="w-full rounded border px-2 py-1" value={stockQuantity} onChange={(e) => setStockQuantity(e.target.value)} />
        </div>
        <div>
          <label className="block text-xs" htmlFor="product-threshold">
            Seuil d'alerte
          </label>
          <input id="product-threshold" type="number" className="w-full rounded border px-2 py-1" value={alertThreshold} onChange={(e) => setAlertThreshold(e.target.value)} />
        </div>
      </div>
      {error && <p className="mb-2 text-sm text-red-600">{error}</p>}
      <button className="mb-4 rounded bg-blue-600 px-3 py-1 text-white" onClick={handleSave}>
        Enregistrer le produit
      </button>

      <ul className="grid grid-cols-2 gap-2 md:grid-cols-4">
        {products.map((product) => (
          <li key={product.id} className="rounded border p-2 text-sm">
            <div className="font-medium">{product.name}</div>
            <div>{product.price} FCFA</div>
          </li>
        ))}
      </ul>
    </div>
  )
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- catalog/ProductManager`
Expected: PASS, 3 tests.

- [ ] **Step 5: Mount it in `CatalogPage`**

Add the import and render `<ProductManager />` below `<CategoryManager />` in `app/src/features/catalog/CatalogPage.tsx`:

```tsx
import { CategoryManager } from './CategoryManager'
import { ProductManager } from './ProductManager'

export function CatalogPage() {
  return (
    <div>
      <h1 className="mb-4 text-2xl font-semibold">Catalogue</h1>
      <CategoryManager />
      <ProductManager />
    </div>
  )
}
```

- [ ] **Step 6: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add product management UI"
```

---

### Task 23: Product photo capture and compression

**Files:**
- Create: `app/src/features/catalog/photo.ts`
- Modify: `app/src/features/catalog/ProductManager.tsx`

- [ ] **Step 1: Implement the resize/compress helper**

This helper touches `Image`, `canvas`, and `FileReader` — real browser APIs that jsdom does not fully implement (canvas pixel encoding in particular), so it is verified manually in Task 46 rather than unit-tested, consistent with the spec's scope for automated tests (pure business rules only).

Create `app/src/features/catalog/photo.ts`:

```ts
const MAX_DIMENSION = 480
const JPEG_QUALITY = 0.8

export function resizeImageFile(file: File, maxDimension = MAX_DIMENSION): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onerror = () => reject(new Error("échec de lecture de l'image"))
    reader.onload = () => {
      const image = new Image()
      image.onerror = () => reject(new Error('image invalide'))
      image.onload = () => {
        const scale = Math.min(1, maxDimension / Math.max(image.width, image.height))
        const canvas = document.createElement('canvas')
        canvas.width = Math.round(image.width * scale)
        canvas.height = Math.round(image.height * scale)
        const ctx = canvas.getContext('2d')
        if (!ctx) {
          reject(new Error('canvas non supporté'))
          return
        }
        ctx.drawImage(image, 0, 0, canvas.width, canvas.height)
        resolve(canvas.toDataURL('image/jpeg', JPEG_QUALITY))
      }
      image.src = reader.result as string
    }
    reader.readAsDataURL(file)
  })
}
```

- [ ] **Step 2: Add photo capture inputs to `ProductManager.tsx`**

Add state and handler near the top of the `ProductManager` component in `app/src/features/catalog/ProductManager.tsx`:

```tsx
const [photoDataUrl, setPhotoDataUrl] = useState<string | null>(null)

async function handlePhotoChange(e: React.ChangeEvent<HTMLInputElement>) {
  const file = e.target.files?.[0]
  if (!file) return
  const dataUrl = await resizeImageFile(file)
  setPhotoDataUrl(dataUrl)
}
```

Add the import: `import { resizeImageFile } from './photo'`.

Include `photoDataUrl` (instead of `null`) in the `productsRepo.create` call inside `handleSave`, and reset it to `null` after saving alongside the other field resets.

Add two file inputs and a preview inside the form grid, after the "Seuil d'alerte" field:

```tsx
<div>
  <label className="block text-xs">Photo</label>
  <div className="flex gap-1">
    <label className="cursor-pointer rounded border px-2 py-1 text-xs">
      Caméra
      <input type="file" accept="image/*" capture="environment" className="hidden" onChange={handlePhotoChange} />
    </label>
    <label className="cursor-pointer rounded border px-2 py-1 text-xs">
      Galerie
      <input type="file" accept="image/*" className="hidden" onChange={handlePhotoChange} />
    </label>
  </div>
  {photoDataUrl && <img src={photoDataUrl} alt="Aperçu" className="mt-1 h-10 w-10 rounded object-cover" />}
</div>
```

Also render the stored photo (or a generic per-category placeholder) in the product list item, replacing the list `<li>` body:

```tsx
<li key={product.id} className="rounded border p-2 text-sm">
  <img
    src={product.photoDataUrl ?? '/icons/icon-192.png'}
    alt={product.name}
    className="mb-1 h-16 w-full rounded object-cover"
  />
  <div className="font-medium">{product.name}</div>
  <div>{product.price} FCFA</div>
</li>
```

- [ ] **Step 3: Run the full test suite to confirm nothing regressed**

Run: `npm run test`
Expected: PASS, all existing tests still green (photo capture itself has no automated test per Step 1's rationale).

- [ ] **Step 4: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add product photo capture and compression"
```

---

### Task 24: Low-stock badge in the catalog

**Files:**
- Modify: `app/src/features/catalog/ProductManager.tsx`
- Test: `app/src/features/catalog/ProductManager.test.tsx`

- [ ] **Step 1: Write the failing test**

Add this test to the `describe('ProductManager', ...)` block in `app/src/features/catalog/ProductManager.test.tsx`:

```tsx
it('shows a low-stock badge when quantity is at or below the alert threshold', async () => {
  const user = userEvent.setup()
  render(<ProductManager />)

  await user.type(await screen.findByLabelText('Nom du produit'), 'Bière 65cl')
  await user.type(screen.getByLabelText('Prix de vente'), '1000')
  await user.type(screen.getByLabelText('Stock initial'), '3')
  await user.type(screen.getByLabelText("Seuil d'alerte"), '5')
  await user.click(screen.getByText('Enregistrer le produit'))

  expect(await screen.findByText('Stock faible')).toBeInTheDocument()
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- catalog/ProductManager`
Expected: FAIL — "Stock faible" not found.

- [ ] **Step 3: Add the badge**

Import the domain helper at the top of `app/src/features/catalog/ProductManager.tsx`:

```tsx
import { isLowStock } from '../../domain/stock'
```

In the product list item, add the badge after the price line:

```tsx
{isLowStock({ productId: product.id, quantity: product.stockQuantity, alertThreshold: product.alertThreshold }) && (
  <div className="mt-1 inline-block rounded bg-amber-200 px-1 text-xs text-amber-900">Stock faible</div>
)}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- catalog/ProductManager`
Expected: PASS, all `ProductManager` tests including the new one.

- [ ] **Step 5: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add low-stock badge to catalog"
```

---

## Milestone 5 — POS (Caisse)

The product tile grid and cart/payment building blocks in this milestone are written for reuse by the Tables module (Milestone 6), since the spec requires the same photo-illustrated item selector when taking a table order.

### Task 25: Shared product tile grid

**Files:**
- Create: `app/src/features/catalog/ProductTileGrid.tsx`
- Test: `app/src/features/catalog/ProductTileGrid.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `app/src/features/catalog/ProductTileGrid.test.tsx`:

```tsx
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { db } from '../../db/schema'
import { categoriesRepo, productsRepo } from '../../db/repositories'
import { ProductTileGrid } from './ProductTileGrid'

describe('ProductTileGrid', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
    const boissons = await categoriesRepo.create({ name: 'Boissons' })
    const grillades = await categoriesRepo.create({ name: 'Grillades' })
    await productsRepo.create({ name: 'Bière', categoryId: boissons.id, price: 1000, photoDataUrl: null, stockQuantity: 10, alertThreshold: 2, createdAt: '' })
    await productsRepo.create({ name: 'Brochette', categoryId: grillades.id, price: 1500, photoDataUrl: null, stockQuantity: 10, alertThreshold: 2, createdAt: '' })
  })

  it('shows all products by default', async () => {
    render(<ProductTileGrid onSelect={() => {}} />)
    expect(await screen.findByText('Bière')).toBeInTheDocument()
    expect(screen.getByText('Brochette')).toBeInTheDocument()
  })

  it('filters products by search text', async () => {
    const user = userEvent.setup()
    render(<ProductTileGrid onSelect={() => {}} />)
    await screen.findByText('Bière')
    await user.type(screen.getByLabelText('Rechercher un produit'), 'Broch')
    expect(screen.queryByText('Bière')).not.toBeInTheDocument()
    expect(screen.getByText('Brochette')).toBeInTheDocument()
  })

  it('filters products by category', async () => {
    const user = userEvent.setup()
    render(<ProductTileGrid onSelect={() => {}} />)
    await screen.findByText('Bière')
    await user.click(screen.getByText('Grillades'))
    expect(screen.queryByText('Bière')).not.toBeInTheDocument()
    expect(screen.getByText('Brochette')).toBeInTheDocument()
  })

  it('calls onSelect with the clicked product', async () => {
    const user = userEvent.setup()
    const onSelect = vi.fn()
    render(<ProductTileGrid onSelect={onSelect} />)
    await user.click(await screen.findByText('Bière'))
    expect(onSelect).toHaveBeenCalledWith(expect.objectContaining({ name: 'Bière' }))
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- catalog/ProductTileGrid`
Expected: FAIL — `Cannot find module './ProductTileGrid'`.

- [ ] **Step 3: Implement `ProductTileGrid.tsx`**

Create `app/src/features/catalog/ProductTileGrid.tsx`:

```tsx
import { useEffect, useMemo, useState } from 'react'
import { categoriesRepo, productsRepo } from '../../db/repositories'
import type { CategoryRecord, ProductRecord } from '../../db/schema'

interface ProductTileGridProps {
  onSelect: (product: ProductRecord) => void
}

export function ProductTileGrid({ onSelect }: ProductTileGridProps) {
  const [categories, setCategories] = useState<CategoryRecord[]>([])
  const [products, setProducts] = useState<ProductRecord[]>([])
  const [search, setSearch] = useState('')
  const [activeCategoryId, setActiveCategoryId] = useState<string | null>(null)

  useEffect(() => {
    categoriesRepo.list().then(setCategories)
    productsRepo.list().then(setProducts)
  }, [])

  const filtered = useMemo(() => {
    return products.filter((product) => {
      const matchesSearch = product.name.toLowerCase().includes(search.toLowerCase())
      const matchesCategory = !activeCategoryId || product.categoryId === activeCategoryId
      return matchesSearch && matchesCategory
    })
  }, [products, search, activeCategoryId])

  return (
    <div>
      <input
        aria-label="Rechercher un produit"
        placeholder="Rechercher…"
        className="mb-2 w-full rounded border px-2 py-1"
        value={search}
        onChange={(e) => setSearch(e.target.value)}
      />
      <div className="mb-2 flex flex-wrap gap-1">
        <button
          className={`rounded px-2 py-1 text-xs ${activeCategoryId === null ? 'bg-blue-600 text-white' : 'bg-slate-200'}`}
          onClick={() => setActiveCategoryId(null)}
        >
          Toutes
        </button>
        {categories.map((category) => (
          <button
            key={category.id}
            className={`rounded px-2 py-1 text-xs ${activeCategoryId === category.id ? 'bg-blue-600 text-white' : 'bg-slate-200'}`}
            onClick={() => setActiveCategoryId(category.id)}
          >
            {category.name}
          </button>
        ))}
      </div>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 md:grid-cols-4">
        {filtered.map((product) => (
          <button key={product.id} className="rounded border p-2 text-left hover:bg-slate-50" onClick={() => onSelect(product)}>
            <img src={product.photoDataUrl ?? '/icons/icon-192.png'} alt={product.name} className="mb-1 h-16 w-full rounded object-cover" />
            <div className="text-sm font-medium">{product.name}</div>
            <div className="text-xs text-slate-600">{product.price} FCFA</div>
          </button>
        ))}
      </div>
    </div>
  )
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- catalog/ProductTileGrid`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add shared illustrated product tile grid"
```

---

### Task 26: Cart panel component

**Files:**
- Create: `app/src/features/sales/CartPanel.tsx`
- Test: `app/src/features/sales/CartPanel.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `app/src/features/sales/CartPanel.test.tsx`:

```tsx
import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { CartPanel } from './CartPanel'
import type { CartLine } from '../../domain/types'

const lines: CartLine[] = [{ productId: 'p1', name: 'Bière', unitPrice: 1000, quantity: 2 }]

describe('CartPanel', () => {
  it('shows the computed total', () => {
    render(
      <CartPanel
        lines={lines}
        discount={{ type: 'amount', value: 0 }}
        onIncrement={() => {}}
        onDecrement={() => {}}
        onRemove={() => {}}
        onDiscountChange={() => {}}
      />
    )
    expect(screen.getByText('Total : 2000 FCFA')).toBeInTheDocument()
  })

  it('calls onIncrement and onDecrement for the right line', async () => {
    const user = userEvent.setup()
    const onIncrement = vi.fn()
    const onDecrement = vi.fn()
    render(
      <CartPanel
        lines={lines}
        discount={{ type: 'amount', value: 0 }}
        onIncrement={onIncrement}
        onDecrement={onDecrement}
        onRemove={() => {}}
        onDiscountChange={() => {}}
      />
    )
    await user.click(screen.getByLabelText('Augmenter Bière'))
    await user.click(screen.getByLabelText('Diminuer Bière'))
    expect(onIncrement).toHaveBeenCalledWith('p1')
    expect(onDecrement).toHaveBeenCalledWith('p1')
  })

  it('calls onDiscountChange when the discount value changes', async () => {
    const user = userEvent.setup()
    const onDiscountChange = vi.fn()
    render(
      <CartPanel
        lines={lines}
        discount={{ type: 'amount', value: 0 }}
        onIncrement={() => {}}
        onDecrement={() => {}}
        onRemove={() => {}}
        onDiscountChange={onDiscountChange}
      />
    )
    await user.type(screen.getByLabelText('Remise'), '5')
    expect(onDiscountChange).toHaveBeenCalled()
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- sales/CartPanel`
Expected: FAIL — `Cannot find module './CartPanel'`.

- [ ] **Step 3: Implement `CartPanel.tsx`**

Create `app/src/features/sales/CartPanel.tsx`:

```tsx
import type { CartLine } from '../../domain/types'
import { computeCartTotals, type Discount } from '../../domain/cart'

interface CartPanelProps {
  lines: CartLine[]
  discount: Discount
  onIncrement: (productId: string) => void
  onDecrement: (productId: string) => void
  onRemove: (productId: string) => void
  onDiscountChange: (discount: Discount) => void
}

export function CartPanel({ lines, discount, onIncrement, onDecrement, onRemove, onDiscountChange }: CartPanelProps) {
  const totals = computeCartTotals(lines, discount)

  return (
    <div className="flex flex-col gap-2">
      <ul className="flex flex-col gap-1">
        {lines.map((line) => (
          <li key={line.productId} className="flex items-center justify-between text-sm">
            <span>{line.name}</span>
            <div className="flex items-center gap-1">
              <button aria-label={`Diminuer ${line.name}`} onClick={() => onDecrement(line.productId)}>
                -
              </button>
              <span>{line.quantity}</span>
              <button aria-label={`Augmenter ${line.name}`} onClick={() => onIncrement(line.productId)}>
                +
              </button>
              <button aria-label={`Retirer ${line.name}`} className="text-red-600" onClick={() => onRemove(line.productId)}>
                ×
              </button>
            </div>
          </li>
        ))}
      </ul>

      <div className="flex items-center gap-2 text-sm">
        <label htmlFor="discount-value">Remise</label>
        <input
          id="discount-value"
          aria-label="Remise"
          type="number"
          className="w-20 rounded border px-1"
          value={discount.value}
          onChange={(e) => onDiscountChange({ ...discount, value: Number(e.target.value) })}
        />
        <select
          aria-label="Type de remise"
          value={discount.type}
          onChange={(e) => onDiscountChange({ ...discount, type: e.target.value as Discount['type'] })}
        >
          <option value="amount">FCFA</option>
          <option value="percent">%</option>
        </select>
      </div>

      <div className="border-t pt-2 text-sm">
        <div>Sous-total : {totals.subtotal} FCFA</div>
        <div>Remise : {totals.discount} FCFA</div>
        <div className="text-lg font-semibold">Total : {totals.total} FCFA</div>
      </div>
    </div>
  )
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- sales/CartPanel`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add shared cart panel component"
```

---

### Task 27: Sale finalization service

**Files:**
- Create: `app/src/features/sales/checkout.ts`
- Test: `app/src/features/sales/checkout.test.ts`

- [ ] **Step 1: Write the failing test**

Create `app/src/features/sales/checkout.test.ts`:

```ts
import { describe, it, expect, beforeEach } from 'vitest'
import { db } from '../../db/schema'
import { categoriesRepo, customersRepo, productsRepo } from '../../db/repositories'
import { finalizeSale } from './checkout'

describe('finalizeSale', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
  })

  it('decrements stock and records the sale for a cash payment', async () => {
    const category = await categoriesRepo.create({ name: 'Boissons' })
    const product = await productsRepo.create({ name: 'Bière', categoryId: category.id, price: 1000, photoDataUrl: null, stockQuantity: 10, alertThreshold: 2, createdAt: '' })

    const sale = await finalizeSale({
      items: [{ productId: product.id, name: product.name, unitPrice: product.price, quantity: 3 }],
      discount: { type: 'amount', value: 0 },
      payments: [{ method: 'cash', amount: 3000 }],
      source: 'pos',
      tableId: null,
    })

    expect(sale.total).toBe(3000)
    const updatedProduct = await productsRepo.get(product.id)
    expect(updatedProduct?.stockQuantity).toBe(7)
    expect(await db.stockMovements.count()).toBe(1)
    expect(await db.sales.count()).toBe(1)
  })

  it('rolls back without side effects when stock is insufficient', async () => {
    const category = await categoriesRepo.create({ name: 'Boissons' })
    const product = await productsRepo.create({ name: 'Bière', categoryId: category.id, price: 1000, photoDataUrl: null, stockQuantity: 2, alertThreshold: 1, createdAt: '' })

    await expect(
      finalizeSale({
        items: [{ productId: product.id, name: product.name, unitPrice: product.price, quantity: 5 }],
        discount: { type: 'amount', value: 0 },
        payments: [{ method: 'cash', amount: 5000 }],
        source: 'pos',
        tableId: null,
      })
    ).rejects.toThrow('stock insuffisant')

    const unchangedProduct = await productsRepo.get(product.id)
    expect(unchangedProduct?.stockQuantity).toBe(2)
    expect(await db.sales.count()).toBe(0)
  })

  it('increases the customer credit balance for a credit sale', async () => {
    const category = await categoriesRepo.create({ name: 'Boissons' })
    const product = await productsRepo.create({ name: 'Bière', categoryId: category.id, price: 1000, photoDataUrl: null, stockQuantity: 10, alertThreshold: 2, createdAt: '' })
    const customer = await customersRepo.create({ name: 'Client A', phone: '', address: '', creditBalance: 0, creditLimit: 5000 })

    await finalizeSale({
      items: [{ productId: product.id, name: product.name, unitPrice: product.price, quantity: 2 }],
      discount: { type: 'amount', value: 0 },
      payments: [{ method: 'credit', amount: 2000 }],
      customerId: customer.id,
      source: 'pos',
      tableId: null,
    })

    const updatedCustomer = await customersRepo.get(customer.id)
    expect(updatedCustomer?.creditBalance).toBe(2000)
    expect(await db.creditMovements.count()).toBe(1)
  })

  it('only bills the credit portion of a split cash+credit payment to the customer account', async () => {
    const category = await categoriesRepo.create({ name: 'Boissons' })
    const product = await productsRepo.create({ name: 'Bière', categoryId: category.id, price: 1000, photoDataUrl: null, stockQuantity: 10, alertThreshold: 2, createdAt: '' })
    const customer = await customersRepo.create({ name: 'Client A', phone: '', address: '', creditBalance: 0, creditLimit: 5000 })

    await finalizeSale({
      items: [{ productId: product.id, name: product.name, unitPrice: product.price, quantity: 3 }],
      discount: { type: 'amount', value: 0 },
      payments: [
        { method: 'cash', amount: 2000 },
        { method: 'credit', amount: 1000 },
      ],
      customerId: customer.id,
      source: 'pos',
      tableId: null,
    })

    const updatedCustomer = await customersRepo.get(customer.id)
    expect(updatedCustomer?.creditBalance).toBe(1000)
    const creditMovements = await db.creditMovements.toArray()
    expect(creditMovements).toHaveLength(1)
    expect(creditMovements[0].amount).toBe(1000)
  })

  it('rejects a credit sale with no customer', async () => {
    const category = await categoriesRepo.create({ name: 'Boissons' })
    const product = await productsRepo.create({ name: 'Bière', categoryId: category.id, price: 1000, photoDataUrl: null, stockQuantity: 10, alertThreshold: 2, createdAt: '' })

    await expect(
      finalizeSale({
        items: [{ productId: product.id, name: product.name, unitPrice: product.price, quantity: 1 }],
        discount: { type: 'amount', value: 0 },
        payments: [{ method: 'credit', amount: 1000 }],
        source: 'pos',
        tableId: null,
      })
    ).rejects.toThrow('client requis')
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- sales/checkout`
Expected: FAIL — `Cannot find module './checkout'`.

- [ ] **Step 3: Implement `checkout.ts`**

Create `app/src/features/sales/checkout.ts`:

```ts
import { db } from '../../db/schema'
import { productsRepo, salesRepo, stockMovementsRepo, customersRepo, creditMovementsRepo } from '../../db/repositories'
import { computeCartTotals, type Discount } from '../../domain/cart'
import { validatePayments } from '../../domain/payment'
import { applyStockMovement } from '../../domain/stock'
import { applyCreditSale } from '../../domain/credit'
import type { CartLine, Payment } from '../../domain/types'
import type { SaleRecord } from '../../db/schema'

export interface FinalizeSaleInput {
  items: CartLine[]
  discount: Discount
  payments: Payment[]
  customerId?: string
  source: 'pos' | 'table'
  tableId?: string | null
}

export async function finalizeSale(input: FinalizeSaleInput): Promise<SaleRecord> {
  const totals = computeCartTotals(input.items, input.discount)
  const hasCredit = input.payments.some((p) => p.method === 'credit')
  validatePayments(input.payments, totals.total, { customerId: hasCredit ? input.customerId : undefined })

  return db.transaction('rw', [db.products, db.stockMovements, db.sales, db.customers, db.creditMovements], async () => {
    for (const line of input.items) {
      const product = await productsRepo.get(line.productId)
      if (!product) throw new Error(`produit introuvable : ${line.productId}`)
      const nextQuantity = applyStockMovement(product.stockQuantity, {
        productId: line.productId,
        type: 'sale',
        quantity: line.quantity,
      })
      await productsRepo.update(line.productId, { stockQuantity: nextQuantity })
      await stockMovementsRepo.create({
        productId: line.productId,
        type: 'sale',
        quantity: line.quantity,
        reason: 'Vente',
        createdAt: new Date().toISOString(),
      })
    }

    if (hasCredit && input.customerId) {
      // Only the portion of the total actually paid via the "credit" method
      // goes on the customer's account — a split payment (e.g. cash + credit)
      // must not bill the customer for the whole sale.
      const creditAmount = input.payments.filter((p) => p.method === 'credit').reduce((sum, p) => sum + p.amount, 0)
      const customer = await customersRepo.get(input.customerId)
      if (!customer) throw new Error('client introuvable')
      const nextBalance = applyCreditSale({ balance: customer.creditBalance, limit: customer.creditLimit }, creditAmount)
      await customersRepo.update(input.customerId, { creditBalance: nextBalance })
      await creditMovementsRepo.create({
        customerId: input.customerId,
        type: 'credit',
        amount: creditAmount,
        note: 'Vente à crédit',
        createdAt: new Date().toISOString(),
      })
    }

    return salesRepo.create({
      source: input.source,
      tableId: input.tableId ?? null,
      items: input.items.map((line) => ({
        productId: line.productId,
        name: line.name,
        unitPrice: line.unitPrice,
        quantity: line.quantity,
        addedAt: new Date().toISOString(),
      })),
      subtotal: totals.subtotal,
      discount: totals.discount,
      total: totals.total,
      payments: input.payments,
      customerId: input.customerId ?? null,
      createdAt: new Date().toISOString(),
    })
  })
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- sales/checkout`
Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add shared sale finalization service"
```

---

### Task 28: Payment modal

**Files:**
- Create: `app/src/features/sales/PaymentModal.tsx`
- Test: `app/src/features/sales/PaymentModal.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `app/src/features/sales/PaymentModal.test.tsx`:

```tsx
import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { PaymentModal } from './PaymentModal'
import type { CustomerRecord } from '../../db/schema'

const customers: CustomerRecord[] = [{ id: 'c1', name: 'Client A', phone: '', address: '', creditBalance: 0, creditLimit: 5000 }]

describe('PaymentModal', () => {
  it('confirms a full cash payment matching the total', async () => {
    const user = userEvent.setup()
    const onConfirm = vi.fn()
    render(<PaymentModal total={3000} customers={customers} onConfirm={onConfirm} onCancel={() => {}} />)

    await user.click(screen.getByText('Valider le paiement'))

    expect(onConfirm).toHaveBeenCalledWith([{ method: 'cash', amount: 3000 }], undefined)
  })

  it('shows an error and does not confirm when the amount is wrong', async () => {
    const user = userEvent.setup()
    const onConfirm = vi.fn()
    render(<PaymentModal total={3000} customers={customers} onConfirm={onConfirm} onCancel={() => {}} />)

    await user.clear(screen.getByLabelText('Montant 1'))
    await user.type(screen.getByLabelText('Montant 1'), '1000')
    await user.click(screen.getByText('Valider le paiement'))

    expect(await screen.findByText(/paiement incomplet/)).toBeInTheDocument()
    expect(onConfirm).not.toHaveBeenCalled()
  })

  it('requires a customer when the method is credit', async () => {
    const user = userEvent.setup()
    const onConfirm = vi.fn()
    render(<PaymentModal total={3000} customers={customers} onConfirm={onConfirm} onCancel={() => {}} />)

    await user.selectOptions(screen.getByLabelText('Méthode de paiement 1'), 'credit')
    await user.click(screen.getByText('Valider le paiement'))
    expect(await screen.findByText(/client requis/)).toBeInTheDocument()

    await user.selectOptions(screen.getByLabelText('Client (obligatoire pour le crédit)'), 'c1')
    await user.click(screen.getByText('Valider le paiement'))
    expect(onConfirm).toHaveBeenCalledWith([{ method: 'credit', amount: 3000 }], 'c1')
  })

  it('calls onCancel', async () => {
    const user = userEvent.setup()
    const onCancel = vi.fn()
    render(<PaymentModal total={3000} customers={customers} onConfirm={() => {}} onCancel={onCancel} />)
    await user.click(screen.getByText('Annuler'))
    expect(onCancel).toHaveBeenCalled()
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- sales/PaymentModal`
Expected: FAIL — `Cannot find module './PaymentModal'`.

- [ ] **Step 3: Implement `PaymentModal.tsx`**

Create `app/src/features/sales/PaymentModal.tsx`:

```tsx
import { useState } from 'react'
import type { Payment, PaymentMethod } from '../../domain/types'
import { validatePayments } from '../../domain/payment'
import type { CustomerRecord } from '../../db/schema'

interface PaymentModalProps {
  total: number
  customers: CustomerRecord[]
  onConfirm: (payments: Payment[], customerId?: string) => void
  onCancel: () => void
}

const METHOD_LABELS: Record<PaymentMethod, string> = {
  cash: 'Espèces',
  mobile_money: 'Mobile Money',
  card: 'Carte',
  credit: 'Crédit',
}

export function PaymentModal({ total, customers, onConfirm, onCancel }: PaymentModalProps) {
  const [payments, setPayments] = useState<Payment[]>([{ method: 'cash', amount: total }])
  const [customerId, setCustomerId] = useState('')
  const [error, setError] = useState<string | null>(null)

  const hasCredit = payments.some((p) => p.method === 'credit')

  function updatePayment(index: number, changes: Partial<Payment>) {
    setPayments((prev) => prev.map((p, i) => (i === index ? { ...p, ...changes } : p)))
  }

  function addLine() {
    const paid = payments.reduce((sum, p) => sum + p.amount, 0)
    setPayments((prev) => [...prev, { method: 'cash', amount: Math.max(0, total - paid) }])
  }

  function removeLine(index: number) {
    setPayments((prev) => prev.filter((_, i) => i !== index))
  }

  function handleConfirm() {
    try {
      validatePayments(payments, total, { customerId: hasCredit ? customerId || undefined : undefined })
      setError(null)
      onConfirm(payments, hasCredit ? customerId : undefined)
    } catch (err) {
      setError((err as Error).message)
    }
  }

  return (
    <div className="fixed inset-0 flex items-center justify-center bg-black/40">
      <div className="w-96 rounded bg-white p-4 shadow-lg">
        <h2 className="mb-2 text-lg font-semibold">Encaissement — {total} FCFA</h2>

        {payments.map((payment, index) => (
          <div key={index} className="mb-2 flex items-center gap-2">
            <select
              aria-label={`Méthode de paiement ${index + 1}`}
              value={payment.method}
              onChange={(e) => updatePayment(index, { method: e.target.value as PaymentMethod })}
              className="rounded border px-1 py-1 text-sm"
            >
              {Object.entries(METHOD_LABELS).map(([value, label]) => (
                <option key={value} value={value}>
                  {label}
                </option>
              ))}
            </select>
            <input
              aria-label={`Montant ${index + 1}`}
              type="number"
              className="w-24 rounded border px-1 py-1 text-sm"
              value={payment.amount}
              onChange={(e) => updatePayment(index, { amount: Number(e.target.value) })}
            />
            {payments.length > 1 && (
              <button aria-label={`Retirer le paiement ${index + 1}`} onClick={() => removeLine(index)}>
                ×
              </button>
            )}
          </div>
        ))}

        <button className="mb-2 text-sm text-blue-600" onClick={addLine}>
          + Ajouter un mode de paiement
        </button>

        {hasCredit && (
          <div className="mb-2">
            <label className="block text-xs" htmlFor="payment-customer">
              Client (obligatoire pour le crédit)
            </label>
            <select
              id="payment-customer"
              className="w-full rounded border px-2 py-1"
              value={customerId}
              onChange={(e) => setCustomerId(e.target.value)}
            >
              <option value="">— Sélectionner —</option>
              {customers.map((customer) => (
                <option key={customer.id} value={customer.id}>
                  {customer.name}
                </option>
              ))}
            </select>
          </div>
        )}

        {error && <p className="mb-2 text-sm text-red-600">{error}</p>}

        <div className="flex justify-end gap-2">
          <button className="rounded px-3 py-1 text-sm text-slate-600" onClick={onCancel}>
            Annuler
          </button>
          <button className="rounded bg-blue-600 px-3 py-1 text-sm text-white" onClick={handleConfirm}>
            Valider le paiement
          </button>
        </div>
      </div>
    </div>
  )
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- sales/PaymentModal`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add payment modal"
```

---

### Task 29: Receipt view with print and reprint

**Files:**
- Create: `app/src/features/sales/Receipt.tsx`
- Test: `app/src/features/sales/Receipt.test.tsx`
- Modify: `app/src/index.css`

- [ ] **Step 1: Add print-only CSS**

Append to `app/src/index.css`:

```css
@media print {
  body * {
    visibility: hidden;
  }
  #receipt-print-area,
  #receipt-print-area * {
    visibility: visible;
  }
  #receipt-print-area {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
  }
}
```

- [ ] **Step 2: Write the failing test**

Create `app/src/features/sales/Receipt.test.tsx`:

```tsx
import { describe, it, expect, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Receipt } from './Receipt'
import type { SaleRecord } from '../../db/schema'

const sale: SaleRecord = {
  id: 's1',
  source: 'pos',
  tableId: null,
  items: [{ productId: 'p1', name: 'Bière', unitPrice: 1000, quantity: 2, addedAt: '' }],
  subtotal: 2000,
  discount: 0,
  total: 2000,
  payments: [{ method: 'cash', amount: 2000 }],
  customerId: null,
  createdAt: '2026-07-25T10:00:00.000Z',
}

describe('Receipt', () => {
  it('shows the sale items and total', () => {
    render(<Receipt sale={sale} onClose={() => {}} />)
    expect(screen.getByText('Bière')).toBeInTheDocument()
    expect(screen.getByText('Total : 2000 FCFA')).toBeInTheDocument()
  })

  it('triggers window.print when the print button is clicked', async () => {
    const user = userEvent.setup()
    const printSpy = vi.spyOn(window, 'print').mockImplementation(() => {})
    render(<Receipt sale={sale} onClose={() => {}} />)
    await user.click(screen.getByText('Imprimer'))
    expect(printSpy).toHaveBeenCalled()
    printSpy.mockRestore()
  })

  it('calls onClose when the close button is clicked', async () => {
    const user = userEvent.setup()
    const onClose = vi.fn()
    render(<Receipt sale={sale} onClose={onClose} />)
    await user.click(screen.getByText('Fermer'))
    expect(onClose).toHaveBeenCalled()
  })
})
```

- [ ] **Step 3: Run the test and confirm it fails**

Run: `npm run test -- sales/Receipt`
Expected: FAIL — `Cannot find module './Receipt'`.

- [ ] **Step 4: Implement `Receipt.tsx`**

Create `app/src/features/sales/Receipt.tsx`:

```tsx
import type { SaleRecord } from '../../db/schema'

interface ReceiptProps {
  sale: SaleRecord
  onClose: () => void
}

export function Receipt({ sale, onClose }: ReceiptProps) {
  return (
    <div className="fixed inset-0 flex items-center justify-center bg-black/40">
      <div className="w-80 rounded bg-white p-4 shadow-lg">
        <div id="receipt-print-area">
          <h2 className="mb-2 text-center text-lg font-semibold">Reçu</h2>
          <p className="mb-2 text-center text-xs text-slate-500">{new Date(sale.createdAt).toLocaleString('fr-FR')}</p>
          <ul className="mb-2 text-sm">
            {sale.items.map((item) => (
              <li key={item.productId} className="flex justify-between">
                <span>
                  {/* item.name in its own nested span: Testing Library's
                      getByText only concatenates an element's direct
                      text-node children, so a bare "Bière" query wouldn't
                      match a sibling-text-node "Bière × 2" otherwise. */}
                  <span>{item.name}</span> × {item.quantity}
                </span>
                <span>{item.unitPrice * item.quantity} FCFA</span>
              </li>
            ))}
          </ul>
          <div className="border-t pt-1 text-sm">
            <div>Sous-total : {sale.subtotal} FCFA</div>
            <div>Remise : {sale.discount} FCFA</div>
            <div className="font-semibold">Total : {sale.total} FCFA</div>
          </div>
          <div className="mt-2 text-sm">
            {sale.payments.map((payment, index) => (
              <div key={index}>
                {payment.method} : {payment.amount} FCFA
              </div>
            ))}
          </div>
        </div>

        <div className="mt-4 flex justify-end gap-2">
          <button className="rounded px-3 py-1 text-sm text-slate-600" onClick={onClose}>
            Fermer
          </button>
          <button className="rounded bg-blue-600 px-3 py-1 text-sm text-white" onClick={() => window.print()}>
            Imprimer
          </button>
        </div>
      </div>
    </div>
  )
}
```

- [ ] **Step 5: Run the test and confirm it passes**

Run: `npm run test -- sales/Receipt`
Expected: PASS, 3 tests.

- [ ] **Step 6: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add printable receipt with reprint support"
```

---

### Task 30: Wire the POS page

**Files:**
- Modify: `app/src/features/pos/PosPage.tsx`
- Test: `app/src/features/pos/PosPage.test.tsx`

- [ ] **Step 1: Write the failing integration test**

Create `app/src/features/pos/PosPage.test.tsx`:

```tsx
import { describe, it, expect, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { db } from '../../db/schema'
import { categoriesRepo, productsRepo } from '../../db/repositories'
import { PosPage } from './PosPage'

describe('PosPage', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
    const category = await categoriesRepo.create({ name: 'Boissons' })
    await productsRepo.create({ name: 'Bière', categoryId: category.id, price: 1000, photoDataUrl: null, stockQuantity: 10, alertThreshold: 2, createdAt: '' })
  })

  it('adds a product to the cart, checks out, and decrements stock', async () => {
    const user = userEvent.setup()
    render(<PosPage />)

    await user.click(await screen.findByText('Bière'))
    expect(screen.getByText('Total : 1000 FCFA')).toBeInTheDocument()

    await user.click(screen.getByText('Encaisser'))
    await user.click(await screen.findByText('Valider le paiement'))

    expect(await screen.findByText('Reçu')).toBeInTheDocument()

    const products = await productsRepo.list()
    expect(products[0].stockQuantity).toBe(9)
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- pos/PosPage`
Expected: FAIL — `PosPage` still renders the Task 17 placeholder, no cart/tiles present.

- [ ] **Step 3: Implement the wired `PosPage.tsx`**

Replace the contents of `app/src/features/pos/PosPage.tsx`:

```tsx
import { useEffect, useState } from 'react'
import { ProductTileGrid } from '../catalog/ProductTileGrid'
import { CartPanel } from '../sales/CartPanel'
import { PaymentModal } from '../sales/PaymentModal'
import { Receipt } from '../sales/Receipt'
import { finalizeSale } from '../sales/checkout'
import { computeCartTotals, type Discount } from '../../domain/cart'
import { customersRepo } from '../../db/repositories'
import type { CartLine, Payment } from '../../domain/types'
import type { CustomerRecord, ProductRecord, SaleRecord } from '../../db/schema'

export function PosPage() {
  const [lines, setLines] = useState<CartLine[]>([])
  const [discount, setDiscount] = useState<Discount>({ type: 'amount', value: 0 })
  const [customers, setCustomers] = useState<CustomerRecord[]>([])
  const [showPayment, setShowPayment] = useState(false)
  const [lastSale, setLastSale] = useState<SaleRecord | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    customersRepo.list().then(setCustomers)
  }, [])

  function handleSelectProduct(product: ProductRecord) {
    setLines((prev) => {
      const existing = prev.find((l) => l.productId === product.id)
      if (existing) {
        return prev.map((l) => (l.productId === product.id ? { ...l, quantity: l.quantity + 1 } : l))
      }
      return [...prev, { productId: product.id, name: product.name, unitPrice: product.price, quantity: 1 }]
    })
  }

  function increment(productId: string) {
    setLines((prev) => prev.map((l) => (l.productId === productId ? { ...l, quantity: l.quantity + 1 } : l)))
  }

  function decrement(productId: string) {
    setLines((prev) => prev.flatMap((l) => {
      if (l.productId !== productId) return [l]
      return l.quantity > 1 ? [{ ...l, quantity: l.quantity - 1 }] : []
    }))
  }

  function remove(productId: string) {
    setLines((prev) => prev.filter((l) => l.productId !== productId))
  }

  async function handlePaymentConfirm(payments: Payment[], customerId?: string) {
    try {
      const sale = await finalizeSale({ items: lines, discount, payments, customerId, source: 'pos', tableId: null })
      setLastSale(sale)
      setLines([])
      setDiscount({ type: 'amount', value: 0 })
      setShowPayment(false)
      setError(null)
    } catch (err) {
      setError((err as Error).message)
      setShowPayment(false)
    }
  }

  const totals = computeCartTotals(lines, discount)

  return (
    <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
      <div className="md:col-span-2">
        <h1 className="mb-4 text-2xl font-semibold">Caisse</h1>
        <ProductTileGrid onSelect={handleSelectProduct} />
      </div>
      <div>
        <CartPanel
          lines={lines}
          discount={discount}
          onIncrement={increment}
          onDecrement={decrement}
          onRemove={remove}
          onDiscountChange={setDiscount}
        />
        {error && <p className="mt-2 text-sm text-red-600">{error}</p>}
        <button
          className="mt-2 w-full rounded bg-green-600 px-3 py-2 text-white disabled:opacity-50"
          disabled={lines.length === 0}
          onClick={() => setShowPayment(true)}
        >
          Encaisser
        </button>
      </div>

      {showPayment && (
        <PaymentModal total={totals.total} customers={customers} onConfirm={handlePaymentConfirm} onCancel={() => setShowPayment(false)} />
      )}

      {lastSale && <Receipt sale={lastSale} onClose={() => setLastSale(null)} />}
    </div>
  )
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- pos/PosPage`
Expected: PASS, 1 test.

- [ ] **Step 5: Run the full test suite**

Run: `npm run test`
Expected: PASS, all tests green.

- [ ] **Step 6: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Wire the POS page: tiles, cart, payment, receipt"
```

---

## Milestone 6 — Tables (service à table)

Per the spec, stock only decrements when a sale is validated. Adding items to an open addition just accumulates them; the existing `finalizeSale` from Milestone 5 is reused, unmodified, when the addition is checked out.

### Task 31: Table service

**Files:**
- Create: `app/src/features/tables/tableService.ts`
- Test: `app/src/features/tables/tableService.test.ts`

- [ ] **Step 1: Write the failing tests**

Create `app/src/features/tables/tableService.test.ts`:

```ts
import { describe, it, expect, beforeEach } from 'vitest'
import { db } from '../../db/schema'
import { categoriesRepo, productsRepo, tablesRepo, additionsRepo } from '../../db/repositories'
import {
  openTable,
  addItemToAddition,
  decrementAdditionItem,
  removeItemFromAddition,
  transferAddition,
  checkoutAddition,
  listTablesWithStatus,
} from './tableService'

describe('tableService', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
  })

  it('opens a free table and marks it occupied', async () => {
    const table = await tablesRepo.create({ name: 'T1', zone: 'Terrasse', status: 'free' })
    const addition = await openTable(table.id)
    expect(addition.status).toBe('open')
    expect((await tablesRepo.get(table.id))?.status).toBe('occupied')
  })

  it('rejects opening a table that is not free', async () => {
    const table = await tablesRepo.create({ name: 'T1', zone: 'Terrasse', status: 'occupied' })
    await expect(openTable(table.id)).rejects.toThrow('table déjà occupée')
  })

  it('adds a new item then increments it on a second add', async () => {
    const table = await tablesRepo.create({ name: 'T1', zone: 'Terrasse', status: 'free' })
    const addition = await openTable(table.id)
    await addItemToAddition(addition.id, { id: 'p1', name: 'Bière', price: 1000 })
    await addItemToAddition(addition.id, { id: 'p1', name: 'Bière', price: 1000 })
    const updated = await additionsRepo.get(addition.id)
    expect(updated?.items).toEqual([{ productId: 'p1', name: 'Bière', unitPrice: 1000, quantity: 2, addedAt: expect.any(String) }])
  })

  it('decrements and removes items', async () => {
    const table = await tablesRepo.create({ name: 'T1', zone: 'Terrasse', status: 'free' })
    const addition = await openTable(table.id)
    await addItemToAddition(addition.id, { id: 'p1', name: 'Bière', price: 1000 })
    await addItemToAddition(addition.id, { id: 'p1', name: 'Bière', price: 1000 })
    await decrementAdditionItem(addition.id, 'p1')
    expect((await additionsRepo.get(addition.id))?.items[0].quantity).toBe(1)
    await removeItemFromAddition(addition.id, 'p1')
    expect((await additionsRepo.get(addition.id))?.items).toHaveLength(0)
  })

  it('transfers an open addition to a free table', async () => {
    const t1 = await tablesRepo.create({ name: 'T1', zone: 'Terrasse', status: 'free' })
    const t2 = await tablesRepo.create({ name: 'T2', zone: 'Terrasse', status: 'free' })
    const addition = await openTable(t1.id)

    await transferAddition(addition.id, t2.id)

    expect((await tablesRepo.get(t1.id))?.status).toBe('free')
    expect((await tablesRepo.get(t2.id))?.status).toBe('occupied')
    expect((await additionsRepo.get(addition.id))?.tableId).toBe(t2.id)
  })

  it('rejects transferring to a table that is not free', async () => {
    const t1 = await tablesRepo.create({ name: 'T1', zone: 'Terrasse', status: 'free' })
    const t2 = await tablesRepo.create({ name: 'T2', zone: 'Terrasse', status: 'occupied' })
    const addition = await openTable(t1.id)
    await expect(transferAddition(addition.id, t2.id)).rejects.toThrow('table de destination occupée')
  })

  it('checks out an addition, decrements stock, closes the addition, and frees the table', async () => {
    const category = await categoriesRepo.create({ name: 'Boissons' })
    const product = await productsRepo.create({ name: 'Bière', categoryId: category.id, price: 1000, photoDataUrl: null, stockQuantity: 10, alertThreshold: 2, createdAt: '' })
    const table = await tablesRepo.create({ name: 'T1', zone: 'Terrasse', status: 'free' })
    const addition = await openTable(table.id)
    await addItemToAddition(addition.id, { id: product.id, name: product.name, price: product.price })

    const sale = await checkoutAddition({ additionId: addition.id, discount: { type: 'amount', value: 0 }, payments: [{ method: 'cash', amount: 1000 }] })

    expect(sale.total).toBe(1000)
    expect((await additionsRepo.get(addition.id))?.status).toBe('closed')
    expect((await tablesRepo.get(table.id))?.status).toBe('free')
    expect((await productsRepo.get(product.id))?.stockQuantity).toBe(9)
  })

  it('rejects checking out an empty addition', async () => {
    const table = await tablesRepo.create({ name: 'T1', zone: 'Terrasse', status: 'free' })
    const addition = await openTable(table.id)
    await expect(
      checkoutAddition({ additionId: addition.id, discount: { type: 'amount', value: 0 }, payments: [] })
    ).rejects.toThrow("l'addition est vide")
  })

  it('derives free/occupied/billing status per table', async () => {
    const free = await tablesRepo.create({ name: 'T1', zone: 'Terrasse', status: 'free' })
    const occupiedTable = await tablesRepo.create({ name: 'T2', zone: 'Terrasse', status: 'free' })
    const billingTable = await tablesRepo.create({ name: 'T3', zone: 'Terrasse', status: 'free' })

    const occupiedAddition = await openTable(occupiedTable.id)
    const billingAddition = await openTable(billingTable.id)
    await addItemToAddition(billingAddition.id, { id: 'p1', name: 'Bière', price: 1000 })

    const statuses = await listTablesWithStatus()
    const byId = new Map(statuses.map((s) => [s.table.id, s.status]))
    expect(byId.get(free.id)).toBe('free')
    expect(byId.get(occupiedTable.id)).toBe('occupied')
    expect(byId.get(billingTable.id)).toBe('billing')
    expect(statuses.find((s) => s.table.id === occupiedTable.id)?.addition?.id).toBe(occupiedAddition.id)
  })
})
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `npm run test -- tables/tableService`
Expected: FAIL — `Cannot find module './tableService'`.

- [ ] **Step 3: Implement `tableService.ts`**

Create `app/src/features/tables/tableService.ts`:

```ts
import { additionsRepo, tablesRepo } from '../../db/repositories'
import { finalizeSale } from '../sales/checkout'
import type { Discount } from '../../domain/cart'
import type { Payment } from '../../domain/types'
import type { AdditionRecord, SaleRecord, TableRecord, TableStatus } from '../../db/schema'

export async function openTable(tableId: string): Promise<AdditionRecord> {
  const table = await tablesRepo.get(tableId)
  if (!table) throw new Error('table introuvable')
  if (table.status !== 'free') throw new Error('table déjà occupée')

  const addition = await additionsRepo.create({
    tableId,
    items: [],
    status: 'open',
    openedAt: new Date().toISOString(),
    closedAt: null,
  })
  await tablesRepo.update(tableId, { status: 'occupied' })
  return addition
}

async function requireOpenAddition(additionId: string): Promise<AdditionRecord> {
  const addition = await additionsRepo.get(additionId)
  if (!addition) throw new Error('addition introuvable')
  if (addition.status !== 'open') throw new Error('addition déjà encaissée')
  return addition
}

export async function addItemToAddition(additionId: string, product: { id: string; name: string; price: number }): Promise<void> {
  const addition = await requireOpenAddition(additionId)
  const existing = addition.items.find((item) => item.productId === product.id)
  const items = existing
    ? addition.items.map((item) => (item.productId === product.id ? { ...item, quantity: item.quantity + 1 } : item))
    : [...addition.items, { productId: product.id, name: product.name, unitPrice: product.price, quantity: 1, addedAt: new Date().toISOString() }]
  await additionsRepo.update(additionId, { items })
}

export async function decrementAdditionItem(additionId: string, productId: string): Promise<void> {
  const addition = await requireOpenAddition(additionId)
  const items = addition.items.flatMap((item) => {
    if (item.productId !== productId) return [item]
    return item.quantity > 1 ? [{ ...item, quantity: item.quantity - 1 }] : []
  })
  await additionsRepo.update(additionId, { items })
}

export async function removeItemFromAddition(additionId: string, productId: string): Promise<void> {
  const addition = await requireOpenAddition(additionId)
  const items = addition.items.filter((item) => item.productId !== productId)
  await additionsRepo.update(additionId, { items })
}

export async function transferAddition(additionId: string, toTableId: string): Promise<void> {
  const addition = await requireOpenAddition(additionId)
  const toTable = await tablesRepo.get(toTableId)
  if (!toTable) throw new Error('table de destination introuvable')
  if (toTable.status !== 'free') throw new Error('table de destination occupée')

  const fromTableId = addition.tableId
  await additionsRepo.update(additionId, { tableId: toTableId })
  await tablesRepo.update(fromTableId, { status: 'free' })
  await tablesRepo.update(toTableId, { status: 'occupied' })
}

export interface CheckoutAdditionInput {
  additionId: string
  discount: Discount
  payments: Payment[]
  customerId?: string
}

export async function checkoutAddition(input: CheckoutAdditionInput): Promise<SaleRecord> {
  const addition = await requireOpenAddition(input.additionId)
  if (addition.items.length === 0) throw new Error("l'addition est vide")

  const sale = await finalizeSale({
    items: addition.items.map((item) => ({ productId: item.productId, name: item.name, unitPrice: item.unitPrice, quantity: item.quantity })),
    discount: input.discount,
    payments: input.payments,
    customerId: input.customerId,
    source: 'table',
    tableId: addition.tableId,
  })

  await additionsRepo.update(input.additionId, { status: 'closed', closedAt: new Date().toISOString() })
  await tablesRepo.update(addition.tableId, { status: 'free' })

  return sale
}

export interface TableWithStatus {
  table: TableRecord
  addition: AdditionRecord | null
  status: TableStatus
}

export async function listTablesWithStatus(): Promise<TableWithStatus[]> {
  const [allTables, allAdditions] = await Promise.all([tablesRepo.list(), additionsRepo.list()])
  const openByTable = new Map(allAdditions.filter((a) => a.status === 'open').map((a) => [a.tableId, a]))

  return allTables.map((table) => {
    const addition = openByTable.get(table.id) ?? null
    const status: TableStatus = !addition ? 'free' : addition.items.length > 0 ? 'billing' : 'occupied'
    return { table, addition, status }
  })
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `npm run test -- tables/tableService`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add table/addition service: open, order, transfer, checkout"
```

---

### Task 32: Floor plan view

**Files:**
- Create: `app/src/features/tables/FloorPlan.tsx`
- Test: `app/src/features/tables/FloorPlan.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `app/src/features/tables/FloorPlan.test.tsx`:

```tsx
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { db } from '../../db/schema'
import { tablesRepo } from '../../db/repositories'
import { openTable, addItemToAddition } from './tableService'
import { FloorPlan } from './FloorPlan'

describe('FloorPlan', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
  })

  it('groups tables by zone and colors them by status', async () => {
    const free = await tablesRepo.create({ name: 'T1', zone: 'Terrasse', status: 'free' })
    const occupiedTable = await tablesRepo.create({ name: 'T2', zone: 'Salle', status: 'free' })
    await openTable(occupiedTable.id)

    render(<FloorPlan onSelectTable={() => {}} refreshToken={0} />)

    expect(await screen.findByText('Terrasse')).toBeInTheDocument()
    expect(screen.getByText('Salle')).toBeInTheDocument()
    expect(screen.getByText('T1').closest('button')).toHaveClass('bg-emerald-100')
    expect(screen.getByText('T2').closest('button')).toHaveClass('bg-amber-100')
  })

  it('calls onSelectTable with the table id when clicked', async () => {
    const user = userEvent.setup()
    const table = await tablesRepo.create({ name: 'T1', zone: 'Terrasse', status: 'free' })
    const onSelectTable = vi.fn()

    render(<FloorPlan onSelectTable={onSelectTable} refreshToken={0} />)
    await user.click(await screen.findByText('T1'))

    expect(onSelectTable).toHaveBeenCalledWith(table.id)
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- tables/FloorPlan`
Expected: FAIL — `Cannot find module './FloorPlan'`.

- [ ] **Step 3: Implement `FloorPlan.tsx`**

Create `app/src/features/tables/FloorPlan.tsx`:

```tsx
import { useEffect, useState } from 'react'
import { listTablesWithStatus, type TableWithStatus } from './tableService'
import type { TableStatus } from '../../db/schema'

const STATUS_CLASSES: Record<TableStatus, string> = {
  free: 'bg-emerald-100 border-emerald-400',
  occupied: 'bg-amber-100 border-amber-400',
  billing: 'bg-rose-100 border-rose-400',
}

const STATUS_LABELS: Record<TableStatus, string> = {
  free: 'Libre',
  occupied: 'Occupée',
  billing: 'À encaisser',
}

interface FloorPlanProps {
  onSelectTable: (tableId: string) => void
  refreshToken: number
}

export function FloorPlan({ onSelectTable, refreshToken }: FloorPlanProps) {
  const [entries, setEntries] = useState<TableWithStatus[]>([])

  useEffect(() => {
    listTablesWithStatus().then(setEntries)
  }, [refreshToken])

  const zones = [...new Set(entries.map((e) => e.table.zone))]

  return (
    <div className="flex flex-col gap-4">
      {zones.map((zone) => (
        <div key={zone}>
          <h3 className="mb-2 font-semibold">{zone}</h3>
          <div className="flex flex-wrap gap-2">
            {entries
              .filter((e) => e.table.zone === zone)
              .map((entry) => (
                <button
                  key={entry.table.id}
                  className={`w-24 rounded border-2 p-3 text-center ${STATUS_CLASSES[entry.status]}`}
                  onClick={() => onSelectTable(entry.table.id)}
                >
                  <div className="font-semibold">{entry.table.name}</div>
                  <div className="text-xs">{STATUS_LABELS[entry.status]}</div>
                </button>
              ))}
          </div>
        </div>
      ))}
    </div>
  )
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- tables/FloorPlan`
Expected: PASS, 2 tests.

- [ ] **Step 5: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add floor plan view grouped by zone"
```

---

### Task 33: Addition detail panel

**Files:**
- Create: `app/src/features/tables/AdditionDetail.tsx`
- Test: `app/src/features/tables/AdditionDetail.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `app/src/features/tables/AdditionDetail.test.tsx`:

```tsx
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { db } from '../../db/schema'
import { categoriesRepo, customersRepo, productsRepo, tablesRepo } from '../../db/repositories'
import { openTable } from './tableService'
import { AdditionDetail } from './AdditionDetail'

describe('AdditionDetail', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
  })

  it('adds an item from the tile grid and shows the running total', async () => {
    const user = userEvent.setup()
    const category = await categoriesRepo.create({ name: 'Boissons' })
    await productsRepo.create({ name: 'Bière', categoryId: category.id, price: 1000, photoDataUrl: null, stockQuantity: 10, alertThreshold: 2, createdAt: '' })
    const table = await tablesRepo.create({ name: 'T1', zone: 'Terrasse', status: 'free' })
    const addition = await openTable(table.id)

    render(<AdditionDetail additionId={addition.id} onClosed={() => {}} onBack={() => {}} />)

    await user.click(await screen.findByText('Ajouter des articles'))
    await user.click(await screen.findByText('Bière'))

    expect(await screen.findByText('Total : 1000 FCFA')).toBeInTheDocument()
  })

  it('checks out the addition and calls onClosed', async () => {
    const user = userEvent.setup()
    const category = await categoriesRepo.create({ name: 'Boissons' })
    await productsRepo.create({ name: 'Bière', categoryId: category.id, price: 1000, photoDataUrl: null, stockQuantity: 10, alertThreshold: 2, createdAt: '' })
    const table = await tablesRepo.create({ name: 'T1', zone: 'Terrasse', status: 'free' })
    const addition = await openTable(table.id)
    const onClosed = vi.fn()

    render(<AdditionDetail additionId={addition.id} onClosed={onClosed} onBack={() => {}} />)

    await user.click(await screen.findByText('Ajouter des articles'))
    await user.click(await screen.findByText('Bière'))
    await user.click(screen.getByText('Encaisser'))
    await user.click(await screen.findByText('Valider le paiement'))

    expect(onClosed).toHaveBeenCalled()
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- tables/AdditionDetail`
Expected: FAIL — `Cannot find module './AdditionDetail'`.

- [ ] **Step 3: Implement `AdditionDetail.tsx`**

Create `app/src/features/tables/AdditionDetail.tsx`:

```tsx
import { useEffect, useState } from 'react'
import { additionsRepo, customersRepo, tablesRepo } from '../../db/repositories'
import { ProductTileGrid } from '../catalog/ProductTileGrid'
import { CartPanel } from '../sales/CartPanel'
import { PaymentModal } from '../sales/PaymentModal'
import { Receipt } from '../sales/Receipt'
import {
  addItemToAddition,
  decrementAdditionItem,
  removeItemFromAddition,
  transferAddition,
  checkoutAddition,
} from './tableService'
import type { Discount } from '../../domain/cart'
import type { Payment } from '../../domain/types'
import type { AdditionRecord, CustomerRecord, ProductRecord, SaleRecord, TableRecord } from '../../db/schema'

interface AdditionDetailProps {
  additionId: string
  onClosed: () => void
  onBack: () => void
}

export function AdditionDetail({ additionId, onClosed, onBack }: AdditionDetailProps) {
  const [addition, setAddition] = useState<AdditionRecord | null>(null)
  const [showTiles, setShowTiles] = useState(false)
  const [showTransfer, setShowTransfer] = useState(false)
  const [freeTables, setFreeTables] = useState<TableRecord[]>([])
  const [discount, setDiscount] = useState<Discount>({ type: 'amount', value: 0 })
  const [customers, setCustomers] = useState<CustomerRecord[]>([])
  const [showPayment, setShowPayment] = useState(false)
  const [lastSale, setLastSale] = useState<SaleRecord | null>(null)
  const [error, setError] = useState<string | null>(null)

  async function reload() {
    setAddition((await additionsRepo.get(additionId)) ?? null)
  }

  useEffect(() => {
    reload()
    customersRepo.list().then(setCustomers)
  }, [additionId])

  async function handleSelectProduct(product: ProductRecord) {
    await addItemToAddition(additionId, { id: product.id, name: product.name, price: product.price })
    await reload()
  }

  async function handleIncrement(productId: string) {
    const product = addition?.items.find((i) => i.productId === productId)
    if (!product) return
    await addItemToAddition(additionId, { id: product.productId, name: product.name, price: product.unitPrice })
    await reload()
  }

  async function handleDecrement(productId: string) {
    await decrementAdditionItem(additionId, productId)
    await reload()
  }

  async function handleRemove(productId: string) {
    await removeItemFromAddition(additionId, productId)
    await reload()
  }

  async function openTransfer() {
    const tables = await tablesRepo.list()
    setFreeTables(tables.filter((t) => t.status === 'free'))
    setShowTransfer(true)
  }

  async function handleTransfer(toTableId: string) {
    await transferAddition(additionId, toTableId)
    setShowTransfer(false)
    onBack()
  }

  async function handlePaymentConfirm(payments: Payment[], customerId?: string) {
    try {
      const sale = await checkoutAddition({ additionId, discount, payments, customerId })
      setLastSale(sale)
      setShowPayment(false)
      setError(null)
      onClosed()
    } catch (err) {
      setError((err as Error).message)
      setShowPayment(false)
    }
  }

  if (!addition) return null

  const lines = addition.items.map((item) => ({ productId: item.productId, name: item.name, unitPrice: item.unitPrice, quantity: item.quantity }))

  return (
    <div>
      <button className="mb-2 text-sm text-blue-600" onClick={onBack}>
        ← Retour au plan de salle
      </button>

      <CartPanel
        lines={lines}
        discount={discount}
        onIncrement={handleIncrement}
        onDecrement={handleDecrement}
        onRemove={handleRemove}
        onDiscountChange={setDiscount}
      />

      <div className="mt-2 flex flex-wrap gap-2">
        <button className="rounded bg-slate-200 px-3 py-1 text-sm" onClick={() => setShowTiles((v) => !v)}>
          Ajouter des articles
        </button>
        <button className="rounded bg-slate-200 px-3 py-1 text-sm" onClick={openTransfer}>
          Transférer
        </button>
        <button
          className="rounded bg-green-600 px-3 py-1 text-sm text-white disabled:opacity-50"
          disabled={lines.length === 0}
          onClick={() => setShowPayment(true)}
        >
          Encaisser
        </button>
      </div>

      {error && <p className="mt-2 text-sm text-red-600">{error}</p>}

      {showTiles && (
        <div className="mt-4">
          <ProductTileGrid onSelect={handleSelectProduct} />
        </div>
      )}

      {showTransfer && (
        <div className="fixed inset-0 flex items-center justify-center bg-black/40">
          <div className="w-72 rounded bg-white p-4 shadow-lg">
            <h3 className="mb-2 font-semibold">Transférer vers…</h3>
            <ul className="flex flex-col gap-1">
              {freeTables.map((table) => (
                <li key={table.id}>
                  <button className="w-full rounded border px-2 py-1 text-left" onClick={() => handleTransfer(table.id)}>
                    {table.name} ({table.zone})
                  </button>
                </li>
              ))}
            </ul>
            <button className="mt-2 text-sm text-slate-600" onClick={() => setShowTransfer(false)}>
              Annuler
            </button>
          </div>
        </div>
      )}

      {showPayment && (
        <PaymentModal
          total={lines.reduce((sum, l) => sum + l.unitPrice * l.quantity, 0) - discount.value}
          customers={customers}
          onConfirm={handlePaymentConfirm}
          onCancel={() => setShowPayment(false)}
        />
      )}

      {lastSale && <Receipt sale={lastSale} onClose={() => setLastSale(null)} />}
    </div>
  )
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- tables/AdditionDetail`
Expected: PASS, 2 tests.

- [ ] **Step 5: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add addition detail panel: order, transfer, checkout"
```

---

### Task 34: Wire the Tables page (golden-path demo walkthrough)

**Files:**
- Modify: `app/src/features/tables/TablesPage.tsx`
- Test: `app/src/features/tables/TablesPage.test.tsx`

- [ ] **Step 1: Write the failing integration test**

This test is the spec's demo walkthrough: open a table, add items, check out, verify stock decrements.

Create `app/src/features/tables/TablesPage.test.tsx`:

```tsx
import { describe, it, expect, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { db } from '../../db/schema'
import { categoriesRepo, productsRepo, tablesRepo } from '../../db/repositories'
import { TablesPage } from './TablesPage'

describe('TablesPage', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
    const category = await categoriesRepo.create({ name: 'Boissons' })
    await productsRepo.create({ name: 'Bière', categoryId: category.id, price: 1000, photoDataUrl: null, stockQuantity: 10, alertThreshold: 2, createdAt: '' })
    await tablesRepo.create({ name: 'T1', zone: 'Terrasse', status: 'free' })
  })

  it('opens a table, adds an item, checks out, and decrements stock', async () => {
    const user = userEvent.setup()
    render(<TablesPage />)

    await user.click(await screen.findByText('T1'))
    await user.click(await screen.findByText('Ajouter des articles'))
    await user.click(await screen.findByText('Bière'))
    expect(await screen.findByText('Total : 1000 FCFA')).toBeInTheDocument()

    await user.click(screen.getByText('Encaisser'))
    await user.click(await screen.findByText('Valider le paiement'))

    expect(await screen.findByText('Reçu')).toBeInTheDocument()

    const products = await productsRepo.list()
    expect(products[0].stockQuantity).toBe(9)
    const tables = await tablesRepo.list()
    expect(tables[0].status).toBe('free')
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- tables/TablesPage`
Expected: FAIL — `TablesPage` still renders the Task 17 placeholder.

- [ ] **Step 3: Implement the wired `TablesPage.tsx`**

Replace the contents of `app/src/features/tables/TablesPage.tsx`:

```tsx
import { useState } from 'react'
import { FloorPlan } from './FloorPlan'
import { AdditionDetail } from './AdditionDetail'
import { openTable, listTablesWithStatus } from './tableService'

export function TablesPage() {
  const [selectedAdditionId, setSelectedAdditionId] = useState<string | null>(null)
  const [refreshToken, setRefreshToken] = useState(0)

  async function handleSelectTable(tableId: string) {
    const entries = await listTablesWithStatus()
    const entry = entries.find((e) => e.table.id === tableId)
    if (!entry) return

    if (entry.status === 'free') {
      const addition = await openTable(tableId)
      setSelectedAdditionId(addition.id)
    } else if (entry.addition) {
      setSelectedAdditionId(entry.addition.id)
    }
    setRefreshToken((t) => t + 1)
  }

  function handleBack() {
    setSelectedAdditionId(null)
    setRefreshToken((t) => t + 1)
  }

  return (
    <div>
      <h1 className="mb-4 text-2xl font-semibold">Tables</h1>
      {selectedAdditionId ? (
        <AdditionDetail additionId={selectedAdditionId} onClosed={handleBack} onBack={handleBack} />
      ) : (
        <FloorPlan onSelectTable={handleSelectTable} refreshToken={refreshToken} />
      )}
    </div>
  )
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- tables/TablesPage`
Expected: PASS, 1 test.

- [ ] **Step 5: Run the full test suite**

Run: `npm run test`
Expected: PASS, all tests green.

- [ ] **Step 6: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Wire the Tables page: floor plan, orders, transfer, checkout"
```

---

## Milestone 7 — Customers & credit

Credit *sales* are already handled by `finalizeSale` (Milestone 5), triggered from the payment modal in POS and Tables. This milestone adds customer management and the repayment side of the credit ledger.

### Task 35: Customer management UI

**Files:**
- Create: `app/src/features/customers/CustomerManager.tsx`
- Test: `app/src/features/customers/CustomerManager.test.tsx`
- Modify: `app/src/features/customers/CustomersPage.tsx`

- [ ] **Step 1: Write the failing test**

Create `app/src/features/customers/CustomerManager.test.tsx`:

```tsx
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { db } from '../../db/schema'
import { CustomerManager } from './CustomerManager'

describe('CustomerManager', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
  })

  it('creates a customer with a credit limit', async () => {
    const user = userEvent.setup()
    render(<CustomerManager onSelectCustomer={() => {}} />)

    await user.type(screen.getByLabelText('Nom du client'), 'Kouassi Jean')
    await user.type(screen.getByLabelText('Téléphone'), '0700000001')
    await user.type(screen.getByLabelText('Plafond de crédit'), '20000')
    await user.click(screen.getByText('Ajouter le client'))

    expect(await screen.findByText('Kouassi Jean')).toBeInTheDocument()
  })

  it('calls onSelectCustomer when a row is clicked', async () => {
    const user = userEvent.setup()
    const onSelectCustomer = vi.fn()
    render(<CustomerManager onSelectCustomer={onSelectCustomer} />)

    await user.type(screen.getByLabelText('Nom du client'), 'Kouassi Jean')
    await user.click(screen.getByText('Ajouter le client'))
    await user.click(await screen.findByText('Kouassi Jean'))

    expect(onSelectCustomer).toHaveBeenCalled()
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- customers/CustomerManager`
Expected: FAIL — `Cannot find module './CustomerManager'`.

- [ ] **Step 3: Implement `CustomerManager.tsx`**

Create `app/src/features/customers/CustomerManager.tsx`:

```tsx
import { useEffect, useState } from 'react'
import { customersRepo } from '../../db/repositories'
import type { CustomerRecord } from '../../db/schema'

interface CustomerManagerProps {
  onSelectCustomer: (customerId: string) => void
}

export function CustomerManager({ onSelectCustomer }: CustomerManagerProps) {
  const [customers, setCustomers] = useState<CustomerRecord[]>([])
  const [name, setName] = useState('')
  const [phone, setPhone] = useState('')
  const [address, setAddress] = useState('')
  const [creditLimit, setCreditLimit] = useState('')
  const [error, setError] = useState<string | null>(null)

  async function reload() {
    setCustomers(await customersRepo.list())
  }

  useEffect(() => {
    reload()
  }, [])

  async function handleAdd() {
    if (!name.trim()) {
      setError('Le nom est obligatoire')
      return
    }
    setError(null)
    await customersRepo.create({
      name: name.trim(),
      phone,
      address,
      creditBalance: 0,
      creditLimit: Number(creditLimit || 0),
    })
    setName('')
    setPhone('')
    setAddress('')
    setCreditLimit('')
    await reload()
  }

  return (
    <div>
      <h2 className="mb-2 text-lg font-semibold">Clients</h2>
      <div className="mb-2 grid grid-cols-2 gap-2 md:grid-cols-4">
        <div>
          <label className="block text-xs" htmlFor="customer-name">
            Nom du client
          </label>
          <input id="customer-name" className="w-full rounded border px-2 py-1" value={name} onChange={(e) => setName(e.target.value)} />
        </div>
        <div>
          <label className="block text-xs" htmlFor="customer-phone">
            Téléphone
          </label>
          <input id="customer-phone" className="w-full rounded border px-2 py-1" value={phone} onChange={(e) => setPhone(e.target.value)} />
        </div>
        <div>
          <label className="block text-xs" htmlFor="customer-address">
            Adresse
          </label>
          <input id="customer-address" className="w-full rounded border px-2 py-1" value={address} onChange={(e) => setAddress(e.target.value)} />
        </div>
        <div>
          <label className="block text-xs" htmlFor="customer-credit-limit">
            Plafond de crédit
          </label>
          <input
            id="customer-credit-limit"
            type="number"
            className="w-full rounded border px-2 py-1"
            value={creditLimit}
            onChange={(e) => setCreditLimit(e.target.value)}
          />
        </div>
      </div>
      {error && <p className="mb-2 text-sm text-red-600">{error}</p>}
      <button className="mb-4 rounded bg-blue-600 px-3 py-1 text-white" onClick={handleAdd}>
        Ajouter le client
      </button>

      <ul className="flex flex-col gap-1">
        {customers.map((customer) => (
          <li key={customer.id}>
            <button className="w-full rounded border p-2 text-left text-sm hover:bg-slate-50" onClick={() => onSelectCustomer(customer.id)}>
              <span className="font-medium">{customer.name}</span> — encours {customer.creditBalance} / {customer.creditLimit} FCFA
            </button>
          </li>
        ))}
      </ul>
    </div>
  )
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- customers/CustomerManager`
Expected: PASS, 2 tests.

- [ ] **Step 5: Mount it in `CustomersPage`**

Replace the contents of `app/src/features/customers/CustomersPage.tsx`:

```tsx
import { CustomerManager } from './CustomerManager'

export function CustomersPage() {
  return (
    <div>
      <h1 className="mb-4 text-2xl font-semibold">Clients</h1>
      <CustomerManager onSelectCustomer={() => {}} />
    </div>
  )
}
```

- [ ] **Step 6: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add customer management UI"
```

---

### Task 36: Repayment service

**Files:**
- Create: `app/src/features/customers/creditService.ts`
- Test: `app/src/features/customers/creditService.test.ts`

- [ ] **Step 1: Write the failing tests**

Create `app/src/features/customers/creditService.test.ts`:

```ts
import { describe, it, expect, beforeEach } from 'vitest'
import { db } from '../../db/schema'
import { customersRepo, creditMovementsRepo } from '../../db/repositories'
import { repayCredit } from './creditService'

describe('repayCredit', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
  })

  it('decreases the balance and records a repayment movement', async () => {
    const customer = await customersRepo.create({ name: 'Kouassi Jean', phone: '', address: '', creditBalance: 5000, creditLimit: 20000 })

    await repayCredit(customer.id, 2000)

    expect((await customersRepo.get(customer.id))?.creditBalance).toBe(3000)
    const movements = await creditMovementsRepo.list()
    expect(movements).toHaveLength(1)
    expect(movements[0]).toMatchObject({ customerId: customer.id, type: 'repayment', amount: 2000 })
  })

  it('rejects a repayment larger than the balance', async () => {
    const customer = await customersRepo.create({ name: 'Kouassi Jean', phone: '', address: '', creditBalance: 1000, creditLimit: 20000 })
    await expect(repayCredit(customer.id, 5000)).rejects.toThrow('remboursement supérieur au solde')
    expect((await customersRepo.get(customer.id))?.creditBalance).toBe(1000)
  })

  it('rejects an unknown customer', async () => {
    await expect(repayCredit('missing', 100)).rejects.toThrow('client introuvable')
  })
})
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `npm run test -- customers/creditService`
Expected: FAIL — `Cannot find module './creditService'`.

- [ ] **Step 3: Implement `creditService.ts`**

Create `app/src/features/customers/creditService.ts`:

```ts
import { customersRepo, creditMovementsRepo } from '../../db/repositories'
import { applyRepayment } from '../../domain/credit'

export async function repayCredit(customerId: string, amount: number): Promise<void> {
  const customer = await customersRepo.get(customerId)
  if (!customer) throw new Error('client introuvable')

  const nextBalance = applyRepayment(customer.creditBalance, amount)
  await customersRepo.update(customerId, { creditBalance: nextBalance })
  await creditMovementsRepo.create({
    customerId,
    type: 'repayment',
    amount,
    note: 'Remboursement',
    createdAt: new Date().toISOString(),
  })
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `npm run test -- customers/creditService`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add credit repayment service"
```

---

### Task 37: Customer detail view with history and repayment

**Files:**
- Create: `app/src/features/customers/CustomerDetail.tsx`
- Test: `app/src/features/customers/CustomerDetail.test.tsx`
- Modify: `app/src/features/customers/CustomersPage.tsx`

- [ ] **Step 1: Write the failing test**

Create `app/src/features/customers/CustomerDetail.test.tsx`:

```tsx
import { describe, it, expect, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { db } from '../../db/schema'
import { customersRepo, creditMovementsRepo } from '../../db/repositories'
import { CustomerDetail } from './CustomerDetail'

describe('CustomerDetail', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
  })

  it('shows the balance and credit history', async () => {
    const customer = await customersRepo.create({ name: 'Kouassi Jean', phone: '', address: '', creditBalance: 3000, creditLimit: 20000 })
    await creditMovementsRepo.create({ customerId: customer.id, type: 'credit', amount: 5000, note: 'Vente à crédit', createdAt: '2026-07-25T10:00:00.000Z' })
    await creditMovementsRepo.create({ customerId: customer.id, type: 'repayment', amount: 2000, note: 'Remboursement', createdAt: '2026-07-25T12:00:00.000Z' })

    render(<CustomerDetail customerId={customer.id} onBack={() => {}} />)

    expect(await screen.findByText('Solde : 3000 / 20000 FCFA')).toBeInTheDocument()
    expect(screen.getByText(/5000 FCFA/)).toBeInTheDocument()
    expect(screen.getByText(/2000 FCFA/)).toBeInTheDocument()
  })

  it('records a repayment and updates the displayed balance', async () => {
    const user = userEvent.setup()
    const customer = await customersRepo.create({ name: 'Kouassi Jean', phone: '', address: '', creditBalance: 3000, creditLimit: 20000 })

    render(<CustomerDetail customerId={customer.id} onBack={() => {}} />)

    await user.type(await screen.findByLabelText('Montant du remboursement'), '1000')
    await user.click(screen.getByText('Enregistrer le remboursement'))

    expect(await screen.findByText('Solde : 2000 / 20000 FCFA')).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- customers/CustomerDetail`
Expected: FAIL — `Cannot find module './CustomerDetail'`.

- [ ] **Step 3: Implement `CustomerDetail.tsx`**

Create `app/src/features/customers/CustomerDetail.tsx`:

```tsx
import { useEffect, useState } from 'react'
import { customersRepo, creditMovementsRepo } from '../../db/repositories'
import { repayCredit } from './creditService'
import type { CreditMovementRecord, CustomerRecord } from '../../db/schema'

interface CustomerDetailProps {
  customerId: string
  onBack: () => void
}

export function CustomerDetail({ customerId, onBack }: CustomerDetailProps) {
  const [customer, setCustomer] = useState<CustomerRecord | null>(null)
  const [movements, setMovements] = useState<CreditMovementRecord[]>([])
  const [amount, setAmount] = useState('')
  const [error, setError] = useState<string | null>(null)

  async function reload() {
    setCustomer((await customersRepo.get(customerId)) ?? null)
    const all = await creditMovementsRepo.list()
    setMovements(all.filter((m) => m.customerId === customerId))
  }

  useEffect(() => {
    reload()
  }, [customerId])

  async function handleRepay() {
    try {
      await repayCredit(customerId, Number(amount))
      setAmount('')
      setError(null)
      await reload()
    } catch (err) {
      setError((err as Error).message)
    }
  }

  if (!customer) return null

  return (
    <div>
      <button className="mb-2 text-sm text-blue-600" onClick={onBack}>
        ← Retour aux clients
      </button>
      <h2 className="mb-2 text-lg font-semibold">{customer.name}</h2>
      <p className="mb-4">
        Solde : {customer.creditBalance} / {customer.creditLimit} FCFA
      </p>

      <div className="mb-4 flex items-end gap-2">
        <div>
          <label className="block text-xs" htmlFor="repayment-amount">
            Montant du remboursement
          </label>
          <input
            id="repayment-amount"
            type="number"
            className="rounded border px-2 py-1"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
          />
        </div>
        <button className="rounded bg-blue-600 px-3 py-1 text-white" onClick={handleRepay}>
          Enregistrer le remboursement
        </button>
      </div>
      {error && <p className="mb-2 text-sm text-red-600">{error}</p>}

      <h3 className="mb-1 font-semibold">Historique</h3>
      <ul className="text-sm">
        {movements.map((movement) => (
          <li key={movement.id}>
            {movement.type === 'credit' ? 'Vente à crédit' : 'Remboursement'} : {movement.amount} FCFA — {new Date(movement.createdAt).toLocaleDateString('fr-FR')}
          </li>
        ))}
      </ul>
    </div>
  )
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- customers/CustomerDetail`
Expected: PASS, 2 tests.

- [ ] **Step 5: Wire selection into `CustomersPage`**

Replace the contents of `app/src/features/customers/CustomersPage.tsx`:

```tsx
import { useState } from 'react'
import { CustomerManager } from './CustomerManager'
import { CustomerDetail } from './CustomerDetail'

export function CustomersPage() {
  const [selectedCustomerId, setSelectedCustomerId] = useState<string | null>(null)

  return (
    <div>
      <h1 className="mb-4 text-2xl font-semibold">Clients</h1>
      {selectedCustomerId ? (
        <CustomerDetail customerId={selectedCustomerId} onBack={() => setSelectedCustomerId(null)} />
      ) : (
        <CustomerManager onSelectCustomer={setSelectedCustomerId} />
      )}
    </div>
  )
}
```

- [ ] **Step 6: Run the full test suite**

Run: `npm run test`
Expected: PASS, all tests green.

- [ ] **Step 7: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add customer detail view with credit history and repayment"
```

---

## Milestone 8 — Stock movements, expenses, losses

### Task 38: Manual stock movement service

**Files:**
- Create: `app/src/features/stock/stockService.ts`
- Test: `app/src/features/stock/stockService.test.ts`

- [ ] **Step 1: Write the failing tests**

Create `app/src/features/stock/stockService.test.ts`:

```ts
import { describe, it, expect, beforeEach } from 'vitest'
import { db } from '../../db/schema'
import { categoriesRepo, productsRepo, stockMovementsRepo } from '../../db/repositories'
import { recordStockMovement } from './stockService'

describe('recordStockMovement', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
  })

  it('increases stock for an "in" movement and records it', async () => {
    const category = await categoriesRepo.create({ name: 'Boissons' })
    const product = await productsRepo.create({ name: 'Bière', categoryId: category.id, price: 1000, photoDataUrl: null, stockQuantity: 10, alertThreshold: 2, createdAt: '' })

    await recordStockMovement({ productId: product.id, type: 'in', quantity: 20, reason: 'Réception fournisseur' })

    expect((await productsRepo.get(product.id))?.stockQuantity).toBe(30)
    expect(await stockMovementsRepo.count()).toBe(1)
  })

  it('sets the counted quantity for an "adjustment" movement', async () => {
    const category = await categoriesRepo.create({ name: 'Boissons' })
    const product = await productsRepo.create({ name: 'Bière', categoryId: category.id, price: 1000, photoDataUrl: null, stockQuantity: 10, alertThreshold: 2, createdAt: '' })

    await recordStockMovement({ productId: product.id, type: 'adjustment', quantity: 7, reason: 'Inventaire mensuel' })

    expect((await productsRepo.get(product.id))?.stockQuantity).toBe(7)
  })

  it('requires a non-empty reason', async () => {
    const category = await categoriesRepo.create({ name: 'Boissons' })
    const product = await productsRepo.create({ name: 'Bière', categoryId: category.id, price: 1000, photoDataUrl: null, stockQuantity: 10, alertThreshold: 2, createdAt: '' })

    await expect(recordStockMovement({ productId: product.id, type: 'in', quantity: 5, reason: '  ' })).rejects.toThrow('justification est obligatoire')
  })

  it('rejects an unknown product', async () => {
    await expect(recordStockMovement({ productId: 'missing', type: 'in', quantity: 5, reason: 'Test' })).rejects.toThrow('produit introuvable')
  })
})
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `npm run test -- stock/stockService`
Expected: FAIL — `Cannot find module './stockService'`.

- [ ] **Step 3: Implement `stockService.ts`**

Create `app/src/features/stock/stockService.ts`:

```ts
import { productsRepo, stockMovementsRepo } from '../../db/repositories'
import { applyStockMovement } from '../../domain/stock'
import type { StockMovementType } from '../../domain/types'

export interface RecordStockMovementInput {
  productId: string
  type: StockMovementType
  quantity: number
  reason: string
}

export async function recordStockMovement(input: RecordStockMovementInput): Promise<void> {
  if (!input.reason.trim()) {
    throw new Error('la justification est obligatoire')
  }

  const product = await productsRepo.get(input.productId)
  if (!product) throw new Error('produit introuvable')

  const nextQuantity = applyStockMovement(product.stockQuantity, {
    productId: input.productId,
    type: input.type,
    quantity: input.quantity,
  })
  await productsRepo.update(input.productId, { stockQuantity: nextQuantity })
  await stockMovementsRepo.create({
    productId: input.productId,
    type: input.type,
    quantity: input.quantity,
    reason: input.reason,
    createdAt: new Date().toISOString(),
  })
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `npm run test -- stock/stockService`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add manual stock movement service"
```

---

### Task 39: Stock movement UI and history

**Files:**
- Create: `app/src/features/stock/StockManager.tsx`
- Test: `app/src/features/stock/StockManager.test.tsx`
- Modify: `app/src/features/stock/StockPage.tsx`

- [ ] **Step 1: Write the failing test**

Create `app/src/features/stock/StockManager.test.tsx`:

```tsx
import { describe, it, expect, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { db } from '../../db/schema'
import { categoriesRepo, productsRepo } from '../../db/repositories'
import { StockManager } from './StockManager'

describe('StockManager', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
    const category = await categoriesRepo.create({ name: 'Boissons' })
    await productsRepo.create({ name: 'Bière', categoryId: category.id, price: 1000, photoDataUrl: null, stockQuantity: 10, alertThreshold: 2, createdAt: '' })
  })

  it('records an entry movement and shows it in the history', async () => {
    const user = userEvent.setup()
    render(<StockManager />)

    await user.selectOptions(await screen.findByLabelText('Produit'), 'Bière')
    await user.selectOptions(screen.getByLabelText('Type de mouvement'), 'in')
    await user.type(screen.getByLabelText('Quantité'), '15')
    await user.type(screen.getByLabelText('Justification'), 'Réception fournisseur')
    await user.click(screen.getByText('Enregistrer le mouvement'))

    expect(await screen.findByText(/Réception fournisseur/)).toBeInTheDocument()
    const products = await productsRepo.list()
    expect(products[0].stockQuantity).toBe(25)
  })

  it('shows an error when the reason is missing', async () => {
    const user = userEvent.setup()
    render(<StockManager />)

    await user.selectOptions(await screen.findByLabelText('Produit'), 'Bière')
    await user.type(screen.getByLabelText('Quantité'), '5')
    await user.click(screen.getByText('Enregistrer le mouvement'))

    expect(await screen.findByText(/justification est obligatoire/)).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- stock/StockManager`
Expected: FAIL — `Cannot find module './StockManager'`.

- [ ] **Step 3: Implement `StockManager.tsx`**

Create `app/src/features/stock/StockManager.tsx`:

```tsx
import { useEffect, useState } from 'react'
import { productsRepo, stockMovementsRepo } from '../../db/repositories'
import { recordStockMovement } from './stockService'
import type { ProductRecord, StockMovementRecord } from '../../db/schema'
import type { StockMovementType } from '../../domain/types'

const TYPE_LABELS: Record<'in' | 'adjustment', string> = {
  in: 'Entrée',
  adjustment: 'Correction / inventaire',
}

export function StockManager() {
  const [products, setProducts] = useState<ProductRecord[]>([])
  const [movements, setMovements] = useState<StockMovementRecord[]>([])
  const [productId, setProductId] = useState('')
  const [type, setType] = useState<Extract<StockMovementType, 'in' | 'adjustment'>>('in')
  const [quantity, setQuantity] = useState('')
  const [reason, setReason] = useState('')
  const [error, setError] = useState<string | null>(null)

  async function reload() {
    const [prods, moves] = await Promise.all([productsRepo.list(), stockMovementsRepo.list()])
    setProducts(prods)
    setMovements([...moves].sort((a, b) => b.createdAt.localeCompare(a.createdAt)))
    if (!productId && prods[0]) setProductId(prods[0].id)
  }

  useEffect(() => {
    reload()
  }, [])

  async function handleSubmit() {
    try {
      await recordStockMovement({ productId, type, quantity: Number(quantity), reason })
      setQuantity('')
      setReason('')
      setError(null)
      await reload()
    } catch (err) {
      setError((err as Error).message)
    }
  }

  function productName(id: string): string {
    return products.find((p) => p.id === id)?.name ?? id
  }

  return (
    <div>
      <h2 className="mb-2 text-lg font-semibold">Mouvement de stock</h2>
      <div className="mb-2 grid grid-cols-2 gap-2 md:grid-cols-4">
        <div>
          <label className="block text-xs" htmlFor="stock-product">
            Produit
          </label>
          <select id="stock-product" className="w-full rounded border px-2 py-1" value={productId} onChange={(e) => setProductId(e.target.value)}>
            {products.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-xs" htmlFor="stock-type">
            Type de mouvement
          </label>
          <select
            id="stock-type"
            className="w-full rounded border px-2 py-1"
            value={type}
            onChange={(e) => setType(e.target.value as 'in' | 'adjustment')}
          >
            <option value="in">{TYPE_LABELS.in}</option>
            <option value="adjustment">{TYPE_LABELS.adjustment}</option>
          </select>
        </div>
        <div>
          <label className="block text-xs" htmlFor="stock-quantity">
            Quantité
          </label>
          <input id="stock-quantity" type="number" className="w-full rounded border px-2 py-1" value={quantity} onChange={(e) => setQuantity(e.target.value)} />
        </div>
        <div>
          <label className="block text-xs" htmlFor="stock-reason">
            Justification
          </label>
          <input id="stock-reason" className="w-full rounded border px-2 py-1" value={reason} onChange={(e) => setReason(e.target.value)} />
        </div>
      </div>
      {error && <p className="mb-2 text-sm text-red-600">{error}</p>}
      <button className="mb-4 rounded bg-blue-600 px-3 py-1 text-white" onClick={handleSubmit}>
        Enregistrer le mouvement
      </button>

      <h3 className="mb-1 font-semibold">Historique</h3>
      <ul className="text-sm">
        {movements.map((movement) => (
          <li key={movement.id}>
            {new Date(movement.createdAt).toLocaleString('fr-FR')} — {productName(movement.productId)} — {movement.type} ({movement.quantity}) — {movement.reason}
          </li>
        ))}
      </ul>
    </div>
  )
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- stock/StockManager`
Expected: PASS, 2 tests.

- [ ] **Step 5: Mount it in `StockPage`**

Replace the contents of `app/src/features/stock/StockPage.tsx`:

```tsx
import { StockManager } from './StockManager'

export function StockPage() {
  return (
    <div>
      <h1 className="mb-4 text-2xl font-semibold">Stock</h1>
      <StockManager />
    </div>
  )
}
```

- [ ] **Step 6: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add stock movement UI and history"
```

---

### Task 40: Expenses CRUD

**Files:**
- Create: `app/src/features/expenses/ExpenseManager.tsx`
- Test: `app/src/features/expenses/ExpenseManager.test.tsx`
- Modify: `app/src/features/expenses/ExpensesPage.tsx`

- [ ] **Step 1: Write the failing test**

Create `app/src/features/expenses/ExpenseManager.test.tsx`:

```tsx
import { describe, it, expect, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { db } from '../../db/schema'
import { ExpenseManager } from './ExpenseManager'

describe('ExpenseManager', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
  })

  it('creates an expense and lists it', async () => {
    const user = userEvent.setup()
    render(<ExpenseManager />)

    await user.type(screen.getByLabelText('Libellé'), 'Loyer juillet')
    await user.selectOptions(screen.getByLabelText('Catégorie'), 'Loyer')
    await user.type(screen.getByLabelText('Montant'), '50000')
    await user.click(screen.getByText("Enregistrer la dépense"))

    expect(await screen.findByText('Loyer juillet')).toBeInTheDocument()
    expect(screen.getByText('50000 FCFA')).toBeInTheDocument()
  })

  it('rejects an expense with a non-positive amount', async () => {
    const user = userEvent.setup()
    render(<ExpenseManager />)

    await user.type(screen.getByLabelText('Libellé'), 'Loyer juillet')
    await user.type(screen.getByLabelText('Montant'), '0')
    await user.click(screen.getByText("Enregistrer la dépense"))

    expect(await screen.findByText('Le montant doit être positif')).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- expenses/ExpenseManager`
Expected: FAIL — `Cannot find module './ExpenseManager'`.

- [ ] **Step 3: Implement `ExpenseManager.tsx`**

Create `app/src/features/expenses/ExpenseManager.tsx`:

```tsx
import { useEffect, useState } from 'react'
import { expensesRepo } from '../../db/repositories'
import type { ExpenseRecord } from '../../db/schema'

const CATEGORIES = ['Loyer', 'Salaires', 'Carburant', 'Eau', 'Électricité', 'Entretien', 'Divers']

export function ExpenseManager() {
  const [expenses, setExpenses] = useState<ExpenseRecord[]>([])
  const [label, setLabel] = useState('')
  const [category, setCategory] = useState(CATEGORIES[0])
  const [amount, setAmount] = useState('')
  const [note, setNote] = useState('')
  const [error, setError] = useState<string | null>(null)

  async function reload() {
    setExpenses(await expensesRepo.list())
  }

  useEffect(() => {
    reload()
  }, [])

  async function handleAdd() {
    const amountValue = Number(amount)
    if (!label.trim()) {
      setError('Le libellé est obligatoire')
      return
    }
    if (!Number.isFinite(amountValue) || amountValue <= 0) {
      setError('Le montant doit être positif')
      return
    }
    setError(null)
    await expensesRepo.create({ label: label.trim(), category, amount: amountValue, date: new Date().toISOString(), note })
    setLabel('')
    setAmount('')
    setNote('')
    await reload()
  }

  return (
    <div>
      <h2 className="mb-2 text-lg font-semibold">Dépenses</h2>
      <div className="mb-2 grid grid-cols-2 gap-2 md:grid-cols-4">
        <div>
          <label className="block text-xs" htmlFor="expense-label">
            Libellé
          </label>
          <input id="expense-label" className="w-full rounded border px-2 py-1" value={label} onChange={(e) => setLabel(e.target.value)} />
        </div>
        <div>
          <label className="block text-xs" htmlFor="expense-category">
            Catégorie
          </label>
          <select id="expense-category" className="w-full rounded border px-2 py-1" value={category} onChange={(e) => setCategory(e.target.value)}>
            {CATEGORIES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-xs" htmlFor="expense-amount">
            Montant
          </label>
          <input id="expense-amount" type="number" className="w-full rounded border px-2 py-1" value={amount} onChange={(e) => setAmount(e.target.value)} />
        </div>
        <div>
          <label className="block text-xs" htmlFor="expense-note">
            Note
          </label>
          <input id="expense-note" className="w-full rounded border px-2 py-1" value={note} onChange={(e) => setNote(e.target.value)} />
        </div>
      </div>
      {error && <p className="mb-2 text-sm text-red-600">{error}</p>}
      <button className="mb-4 rounded bg-blue-600 px-3 py-1 text-white" onClick={handleAdd}>
        Enregistrer la dépense
      </button>

      <ul className="text-sm">
        {expenses.map((expense) => (
          <li key={expense.id}>
            {expense.label} ({expense.category}) — {expense.amount} FCFA — {new Date(expense.date).toLocaleDateString('fr-FR')}
          </li>
        ))}
      </ul>
    </div>
  )
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- expenses/ExpenseManager`
Expected: PASS, 2 tests.

- [ ] **Step 5: Mount it in `ExpensesPage`**

Replace the contents of `app/src/features/expenses/ExpensesPage.tsx`:

```tsx
import { ExpenseManager } from './ExpenseManager'

export function ExpensesPage() {
  return (
    <div>
      <h1 className="mb-4 text-2xl font-semibold">Dépenses</h1>
      <ExpenseManager />
    </div>
  )
}
```

- [ ] **Step 6: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add expenses management UI"
```

---

### Task 41: Losses CRUD (with stock deduction)

**Files:**
- Create: `app/src/features/losses/lossService.ts`
- Test: `app/src/features/losses/lossService.test.ts`
- Create: `app/src/features/losses/LossManager.tsx`
- Test: `app/src/features/losses/LossManager.test.tsx`
- Modify: `app/src/features/losses/LossesPage.tsx`

- [ ] **Step 1: Write the failing service test**

Create `app/src/features/losses/lossService.test.ts`:

```ts
import { describe, it, expect, beforeEach } from 'vitest'
import { db } from '../../db/schema'
import { categoriesRepo, productsRepo, lossesRepo } from '../../db/repositories'
import { recordLoss } from './lossService'

describe('recordLoss', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
  })

  it('deducts stock and records the loss', async () => {
    const category = await categoriesRepo.create({ name: 'Boissons' })
    const product = await productsRepo.create({ name: 'Bière', categoryId: category.id, price: 1000, photoDataUrl: null, stockQuantity: 10, alertThreshold: 2, createdAt: '' })

    await recordLoss({ productId: product.id, quantity: 2, reason: 'Casse', author: 'Gérant' })

    expect((await productsRepo.get(product.id))?.stockQuantity).toBe(8)
    expect(await lossesRepo.count()).toBe(1)
  })

  it('requires an author', async () => {
    const category = await categoriesRepo.create({ name: 'Boissons' })
    const product = await productsRepo.create({ name: 'Bière', categoryId: category.id, price: 1000, photoDataUrl: null, stockQuantity: 10, alertThreshold: 2, createdAt: '' })

    await expect(recordLoss({ productId: product.id, quantity: 1, reason: 'Casse', author: '  ' })).rejects.toThrow('auteur est obligatoire')
  })

  it('rejects a loss larger than the available stock', async () => {
    const category = await categoriesRepo.create({ name: 'Boissons' })
    const product = await productsRepo.create({ name: 'Bière', categoryId: category.id, price: 1000, photoDataUrl: null, stockQuantity: 1, alertThreshold: 2, createdAt: '' })

    await expect(recordLoss({ productId: product.id, quantity: 5, reason: 'Casse', author: 'Gérant' })).rejects.toThrow('stock insuffisant')
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- losses/lossService`
Expected: FAIL — `Cannot find module './lossService'`.

- [ ] **Step 3: Implement `lossService.ts`**

Create `app/src/features/losses/lossService.ts`:

```ts
import { lossesRepo } from '../../db/repositories'
import { recordStockMovement } from '../stock/stockService'

export interface RecordLossInput {
  productId: string
  quantity: number
  reason: string
  author: string
}

export async function recordLoss(input: RecordLossInput): Promise<void> {
  if (!input.author.trim()) {
    throw new Error("l'auteur est obligatoire")
  }

  await recordStockMovement({ productId: input.productId, type: 'loss', quantity: input.quantity, reason: input.reason })
  await lossesRepo.create({
    productId: input.productId,
    quantity: input.quantity,
    reason: input.reason,
    author: input.author,
    createdAt: new Date().toISOString(),
  })
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- losses/lossService`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit the service**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add loss recording service with stock deduction"
```

- [ ] **Step 6: Write the failing UI test**

Create `app/src/features/losses/LossManager.test.tsx`:

```tsx
import { describe, it, expect, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { db } from '../../db/schema'
import { categoriesRepo, productsRepo } from '../../db/repositories'
import { LossManager } from './LossManager'

describe('LossManager', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
    const category = await categoriesRepo.create({ name: 'Boissons' })
    await productsRepo.create({ name: 'Bière', categoryId: category.id, price: 1000, photoDataUrl: null, stockQuantity: 10, alertThreshold: 2, createdAt: '' })
  })

  it('records a loss and shows it in the list', async () => {
    const user = userEvent.setup()
    render(<LossManager />)

    await user.selectOptions(await screen.findByLabelText('Produit'), 'Bière')
    await user.type(screen.getByLabelText('Quantité'), '2')
    await user.selectOptions(screen.getByLabelText('Motif'), 'Casse')
    await user.type(screen.getByLabelText('Auteur'), 'Gérant')
    await user.click(screen.getByText('Enregistrer la perte'))

    expect(await screen.findByText(/Casse/)).toBeInTheDocument()
    const products = await productsRepo.list()
    expect(products[0].stockQuantity).toBe(8)
  })

  it('shows an error when the author is missing', async () => {
    const user = userEvent.setup()
    render(<LossManager />)

    await user.selectOptions(await screen.findByLabelText('Produit'), 'Bière')
    await user.type(screen.getByLabelText('Quantité'), '2')
    await user.click(screen.getByText('Enregistrer la perte'))

    expect(await screen.findByText(/auteur est obligatoire/)).toBeInTheDocument()
  })
})
```

- [ ] **Step 7: Run the test and confirm it fails**

Run: `npm run test -- losses/LossManager`
Expected: FAIL — `Cannot find module './LossManager'`.

- [ ] **Step 8: Implement `LossManager.tsx`**

Create `app/src/features/losses/LossManager.tsx`:

```tsx
import { useEffect, useState } from 'react'
import { productsRepo, lossesRepo } from '../../db/repositories'
import { recordLoss } from './lossService'
import type { LossRecord, ProductRecord } from '../../db/schema'

const REASONS = ['Casse', 'Offert', 'Péremption', 'Vol', 'Consommation interne']

export function LossManager() {
  const [products, setProducts] = useState<ProductRecord[]>([])
  const [losses, setLosses] = useState<LossRecord[]>([])
  const [productId, setProductId] = useState('')
  const [quantity, setQuantity] = useState('')
  const [reason, setReason] = useState(REASONS[0])
  const [author, setAuthor] = useState('')
  const [error, setError] = useState<string | null>(null)

  async function reload() {
    const [prods, allLosses] = await Promise.all([productsRepo.list(), lossesRepo.list()])
    setProducts(prods)
    setLosses([...allLosses].sort((a, b) => b.createdAt.localeCompare(a.createdAt)))
    if (!productId && prods[0]) setProductId(prods[0].id)
  }

  useEffect(() => {
    reload()
  }, [])

  function productName(id: string): string {
    return products.find((p) => p.id === id)?.name ?? id
  }

  async function handleSubmit() {
    try {
      await recordLoss({ productId, quantity: Number(quantity), reason, author })
      setQuantity('')
      setAuthor('')
      setError(null)
      await reload()
    } catch (err) {
      setError((err as Error).message)
    }
  }

  return (
    <div>
      <h2 className="mb-2 text-lg font-semibold">Pertes</h2>
      <div className="mb-2 grid grid-cols-2 gap-2 md:grid-cols-4">
        <div>
          <label className="block text-xs" htmlFor="loss-product">
            Produit
          </label>
          <select id="loss-product" className="w-full rounded border px-2 py-1" value={productId} onChange={(e) => setProductId(e.target.value)}>
            {products.map((p) => (
              <option key={p.id} value={p.id}>
                {p.name}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-xs" htmlFor="loss-quantity">
            Quantité
          </label>
          <input id="loss-quantity" type="number" className="w-full rounded border px-2 py-1" value={quantity} onChange={(e) => setQuantity(e.target.value)} />
        </div>
        <div>
          <label className="block text-xs" htmlFor="loss-reason">
            Motif
          </label>
          <select id="loss-reason" className="w-full rounded border px-2 py-1" value={reason} onChange={(e) => setReason(e.target.value)}>
            {REASONS.map((r) => (
              <option key={r} value={r}>
                {r}
              </option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-xs" htmlFor="loss-author">
            Auteur
          </label>
          <input id="loss-author" className="w-full rounded border px-2 py-1" value={author} onChange={(e) => setAuthor(e.target.value)} />
        </div>
      </div>
      {error && <p className="mb-2 text-sm text-red-600">{error}</p>}
      <button className="mb-4 rounded bg-blue-600 px-3 py-1 text-white" onClick={handleSubmit}>
        Enregistrer la perte
      </button>

      <ul className="text-sm">
        {losses.map((loss) => (
          <li key={loss.id}>
            {new Date(loss.createdAt).toLocaleString('fr-FR')} — {productName(loss.productId)} × {loss.quantity} — {loss.reason} ({loss.author})
          </li>
        ))}
      </ul>
    </div>
  )
}
```

- [ ] **Step 9: Run the test and confirm it passes**

Run: `npm run test -- losses/LossManager`
Expected: PASS, 2 tests.

- [ ] **Step 10: Mount it in `LossesPage`**

Replace the contents of `app/src/features/losses/LossesPage.tsx`:

```tsx
import { LossManager } from './LossManager'

export function LossesPage() {
  return (
    <div>
      <h1 className="mb-4 text-2xl font-semibold">Pertes</h1>
      <LossManager />
    </div>
  )
}
```

- [ ] **Step 11: Run the full test suite**

Run: `npm run test`
Expected: PASS, all tests green.

- [ ] **Step 12: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Add losses management UI"
```

---

## Milestone 9 — Dashboard, reports, settings

### Task 42: Dashboard page

**Files:**
- Modify: `app/src/features/dashboard/DashboardPage.tsx`
- Test: `app/src/features/dashboard/DashboardPage.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `app/src/features/dashboard/DashboardPage.test.tsx`:

```tsx
import { describe, it, expect, beforeEach } from 'vitest'
import { render, screen } from '@testing-library/react'
import { db } from '../../db/schema'
import { categoriesRepo, productsRepo, salesRepo } from '../../db/repositories'
import { DashboardPage } from './DashboardPage'

describe('DashboardPage', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
    const category = await categoriesRepo.create({ name: 'Boissons' })
    await productsRepo.create({ name: 'Bière', categoryId: category.id, price: 1000, photoDataUrl: null, stockQuantity: 1, alertThreshold: 5, createdAt: '' })
    const today = new Date().toISOString()
    await salesRepo.create({
      source: 'pos',
      tableId: null,
      items: [{ productId: 'p1', name: 'Bière', unitPrice: 1000, quantity: 2, addedAt: today }],
      subtotal: 2000,
      discount: 0,
      total: 2000,
      payments: [{ method: 'cash', amount: 2000 }],
      customerId: null,
      createdAt: today,
    })
  })

  it("shows today's revenue, sale count, and low-stock alert count", async () => {
    render(<DashboardPage />)

    expect(await screen.findByText('2000 FCFA')).toBeInTheDocument()
    expect(screen.getByText('1', { selector: 'div.text-xl' })).toBeInTheDocument()
    expect(screen.getByText('Bière — 1 restants (seuil 5)')).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- dashboard/DashboardPage`
Expected: FAIL — the placeholder page from Task 17 has none of this content.

- [ ] **Step 3: Implement the wired `DashboardPage.tsx`**

Replace the contents of `app/src/features/dashboard/DashboardPage.tsx`:

```tsx
import { useEffect, useState } from 'react'
import { salesRepo, productsRepo } from '../../db/repositories'
import { summarizeDailySales, topProducts } from '../../domain/reports'
import { isLowStock } from '../../domain/stock'
import type { ProductRecord, SaleRecord } from '../../db/schema'

export function DashboardPage() {
  const [sales, setSales] = useState<SaleRecord[]>([])
  const [products, setProducts] = useState<ProductRecord[]>([])

  useEffect(() => {
    salesRepo.list().then(setSales)
    productsRepo.list().then(setProducts)
  }, [])

  const today = new Date().toISOString().slice(0, 10)
  const summary = summarizeDailySales(sales, today)
  const daySales = sales.filter((s) => s.createdAt.slice(0, 10) === today)
  const ranking = topProducts(daySales).slice(0, 5)
  const lowStockProducts = products.filter((p) =>
    isLowStock({ productId: p.id, quantity: p.stockQuantity, alertThreshold: p.alertThreshold })
  )

  return (
    <div>
      <h1 className="mb-4 text-2xl font-semibold">Tableau de bord</h1>
      <div className="mb-4 grid grid-cols-2 gap-4 md:grid-cols-4">
        <div className="rounded border p-3">
          <div className="text-xs text-slate-500">Ventes du jour</div>
          <div className="text-xl font-semibold">{summary.totalRevenue} FCFA</div>
        </div>
        <div className="rounded border p-3">
          <div className="text-xs text-slate-500">Nombre de ventes</div>
          <div className="text-xl font-semibold">{summary.saleCount}</div>
        </div>
        <div className="rounded border p-3">
          <div className="text-xs text-slate-500">Alertes de stock</div>
          <div className="text-xl font-semibold">{lowStockProducts.length}</div>
        </div>
      </div>

      <h2 className="mb-2 font-semibold">Produits les plus vendus aujourd'hui</h2>
      <ul className="mb-4 text-sm">
        {ranking.map((p) => (
          <li key={p.productId}>
            {p.name} — {p.quantity} vendus — {p.revenue} FCFA
          </li>
        ))}
      </ul>

      {lowStockProducts.length > 0 && (
        <div>
          <h2 className="mb-2 font-semibold">Alertes de stock</h2>
          <ul className="text-sm text-amber-700">
            {lowStockProducts.map((p) => (
              <li key={p.id}>
                {p.name} — {p.stockQuantity} restants (seuil {p.alertThreshold})
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- dashboard/DashboardPage`
Expected: PASS, 1 test.

- [ ] **Step 5: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Wire the dashboard: today's KPIs and stock alerts"
```

---

### Task 43: Daily report page

**Files:**
- Modify: `app/src/features/reports/ReportsPage.tsx`
- Test: `app/src/features/reports/ReportsPage.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `app/src/features/reports/ReportsPage.test.tsx`:

```tsx
import { describe, it, expect, beforeEach } from 'vitest'
import { render, screen, fireEvent } from '@testing-library/react'
import { db } from '../../db/schema'
import { salesRepo, expensesRepo } from '../../db/repositories'
import { ReportsPage } from './ReportsPage'

describe('ReportsPage', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
    await salesRepo.create({
      source: 'pos',
      tableId: null,
      items: [{ productId: 'p1', name: 'Bière', unitPrice: 1000, quantity: 2, addedAt: '' }],
      subtotal: 2000,
      discount: 0,
      total: 2000,
      payments: [{ method: 'cash', amount: 2000 }],
      customerId: null,
      createdAt: '2026-07-25T10:00:00.000Z',
    })
    await salesRepo.create({
      source: 'pos',
      tableId: null,
      items: [{ productId: 'p1', name: 'Bière', unitPrice: 1000, quantity: 1, addedAt: '' }],
      subtotal: 1000,
      discount: 0,
      total: 1000,
      payments: [{ method: 'cash', amount: 1000 }],
      customerId: null,
      createdAt: '2026-01-01T10:00:00.000Z',
    })
    await expensesRepo.create({ label: 'Loyer', category: 'Loyer', amount: 5000, date: '2026-07-25T00:00:00.000Z', note: '' })
  })

  it('shows totals for the selected date and recomputes when the date changes', async () => {
    render(<ReportsPage />)

    const dateInput = await screen.findByLabelText('Date')
    fireEvent.change(dateInput, { target: { value: '2026-07-25' } })

    expect(await screen.findByText('2000 FCFA')).toBeInTheDocument()
    expect(screen.getByText('5000 FCFA')).toBeInTheDocument()
    expect(screen.getByText('Bière — 2 vendus — 2000 FCFA')).toBeInTheDocument()

    fireEvent.change(dateInput, { target: { value: '2026-01-01' } })
    expect(await screen.findByText('1000 FCFA')).toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- reports/ReportsPage`
Expected: FAIL — the placeholder page from Task 17 has none of this content.

- [ ] **Step 3: Implement the wired `ReportsPage.tsx`**

Replace the contents of `app/src/features/reports/ReportsPage.tsx`:

```tsx
import { useEffect, useState } from 'react'
import { salesRepo, expensesRepo, lossesRepo } from '../../db/repositories'
import { summarizeDailySales, topProducts } from '../../domain/reports'
import type { ExpenseRecord, LossRecord, SaleRecord } from '../../db/schema'

function todayIso(): string {
  return new Date().toISOString().slice(0, 10)
}

export function ReportsPage() {
  const [sales, setSales] = useState<SaleRecord[]>([])
  const [expenses, setExpenses] = useState<ExpenseRecord[]>([])
  const [losses, setLosses] = useState<LossRecord[]>([])
  const [date, setDate] = useState(todayIso())

  useEffect(() => {
    salesRepo.list().then(setSales)
    expensesRepo.list().then(setExpenses)
    lossesRepo.list().then(setLosses)
  }, [])

  const summary = summarizeDailySales(sales, date)
  const daySales = sales.filter((s) => s.createdAt.slice(0, 10) === date)
  const ranking = topProducts(daySales)
  const dayExpenses = expenses.filter((e) => e.date.slice(0, 10) === date)
  const dayLosses = losses.filter((l) => l.createdAt.slice(0, 10) === date)
  const totalExpenses = dayExpenses.reduce((sum, e) => sum + e.amount, 0)

  return (
    <div>
      <h1 className="mb-4 text-2xl font-semibold">Rapports</h1>
      <label className="mb-4 block text-sm" htmlFor="report-date">
        Date
        <input id="report-date" type="date" className="ml-2 rounded border px-2 py-1" value={date} onChange={(e) => setDate(e.target.value)} />
      </label>

      <div className="mb-4 grid grid-cols-2 gap-4 md:grid-cols-4">
        <div className="rounded border p-3">
          <div className="text-xs text-slate-500">Chiffre d'affaires</div>
          <div className="text-xl font-semibold">{summary.totalRevenue} FCFA</div>
        </div>
        <div className="rounded border p-3">
          <div className="text-xs text-slate-500">Ventes</div>
          <div className="text-xl font-semibold">{summary.saleCount}</div>
        </div>
        <div className="rounded border p-3">
          <div className="text-xs text-slate-500">Dépenses</div>
          <div className="text-xl font-semibold">{totalExpenses} FCFA</div>
        </div>
        <div className="rounded border p-3">
          <div className="text-xs text-slate-500">Pertes</div>
          <div className="text-xl font-semibold">{dayLosses.length}</div>
        </div>
      </div>

      <h2 className="mb-2 font-semibold">Ventes par mode de paiement</h2>
      <ul className="mb-4 text-sm">
        {Object.entries(summary.byPaymentMethod).map(([method, amount]) => (
          <li key={method}>
            {method} : {amount} FCFA
          </li>
        ))}
      </ul>

      <h2 className="mb-2 font-semibold">Produits les plus vendus</h2>
      <ul className="text-sm">
        {ranking.map((p) => (
          <li key={p.productId}>
            {p.name} — {p.quantity} vendus — {p.revenue} FCFA
          </li>
        ))}
      </ul>
    </div>
  )
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- reports/ReportsPage`
Expected: PASS, 1 test.

- [ ] **Step 5: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Wire the daily reports page"
```

---

### Task 44: Settings page (establishment info, PIN, backup)

**Files:**
- Modify: `app/src/features/settings/SettingsPage.tsx`
- Test: `app/src/features/settings/SettingsPage.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `app/src/features/settings/SettingsPage.test.tsx`:

```tsx
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { db } from '../../db/schema'
import { setPin } from '../../db/settings'
import { categoriesRepo } from '../../db/repositories'
import { PinGateProvider } from '../../app/PinGate'
import { SettingsPage } from './SettingsPage'

describe('SettingsPage', () => {
  beforeEach(async () => {
    await db.delete()
    await db.open()
  })

  it('updates establishment info directly when no PIN is set yet', async () => {
    const user = userEvent.setup()
    render(
      <PinGateProvider>
        <SettingsPage />
      </PinGateProvider>
    )

    const nameInput = await screen.findByLabelText("Nom de l'établissement")
    await user.clear(nameInput)
    await user.type(nameInput, 'Le Bon Coin')
    await user.click(screen.getByText('Enregistrer'))

    expect(await screen.findByText('Établissement mis à jour')).toBeInTheDocument()
  })

  it('requires the PIN before saving once one is set', async () => {
    const user = userEvent.setup()
    await setPin('1234')
    render(
      <PinGateProvider>
        <SettingsPage />
      </PinGateProvider>
    )

    const nameInput = await screen.findByLabelText("Nom de l'établissement")
    await user.clear(nameInput)
    await user.type(nameInput, 'Le Bon Coin')
    await user.click(screen.getByText('Enregistrer'))

    await user.type(await screen.findByLabelText('Code PIN'), '1234')
    await user.click(screen.getByText('Confirmer'))

    expect(await screen.findByText('Établissement mis à jour')).toBeInTheDocument()
  })

  it('exports a backup by triggering a file download', async () => {
    const user = userEvent.setup()
    await categoriesRepo.create({ name: 'Boissons' })
    const clickSpy = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {})

    render(
      <PinGateProvider>
        <SettingsPage />
      </PinGateProvider>
    )

    await user.click(await screen.findByText('Exporter une sauvegarde (JSON)'))

    expect(clickSpy).toHaveBeenCalled()
    clickSpy.mockRestore()
  })

  it('imports a backup after PIN confirmation and a warning acknowledgement', async () => {
    const user = userEvent.setup()
    await categoriesRepo.create({ name: 'Boissons' })
    const backupJson = JSON.stringify({ version: 1, tables: { categories: [{ id: 'c9', name: 'Grillades' }] } })
    const file = new File([backupJson], 'backup.json', { type: 'application/json' })

    await setPin('1234')
    const confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(true)

    render(
      <PinGateProvider>
        <SettingsPage />
      </PinGateProvider>
    )

    const fileInput = await screen.findByLabelText('Importer une sauvegarde')
    await user.upload(fileInput, file)
    await user.click(screen.getByText('Restaurer cette sauvegarde'))

    await user.type(await screen.findByLabelText('Code PIN'), '1234')
    await user.click(screen.getByText('Confirmer'))

    expect(await screen.findByText('Sauvegarde importée avec succès')).toBeInTheDocument()
    expect(await db.categories.count()).toBe(1)
    confirmSpy.mockRestore()
  })
})
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `npm run test -- settings/SettingsPage`
Expected: FAIL — the placeholder page from Task 17 has none of this content.

- [ ] **Step 3: Implement the wired `SettingsPage.tsx`**

Replace the contents of `app/src/features/settings/SettingsPage.tsx`:

```tsx
import { useEffect, useState, type ChangeEvent } from 'react'
import { getSettings, setPin as persistPin, updateEstablishmentInfo } from '../../db/settings'
import { exportBackup, importBackup } from '../../db/backup'
import { usePinGate } from '../../app/PinGate'
import type { SettingsRecord } from '../../db/schema'

export function SettingsPage() {
  const requirePin = usePinGate()
  const [settings, setSettings] = useState<SettingsRecord | null>(null)
  const [establishmentName, setEstablishmentName] = useState('')
  const [address, setAddress] = useState('')
  const [newPin, setNewPin] = useState('')
  const [importText, setImportText] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  async function reload() {
    const s = await getSettings()
    setSettings(s)
    setEstablishmentName(s.establishmentName)
    setAddress(s.address)
  }

  useEffect(() => {
    reload()
  }, [])

  async function guardIfPinSet(): Promise<boolean> {
    if (!settings?.pinHash) return true
    return requirePin()
  }

  async function handleSaveInfo() {
    if (!(await guardIfPinSet())) return
    await updateEstablishmentInfo({ establishmentName, address })
    setMessage('Établissement mis à jour')
    setError(null)
    await reload()
  }

  async function handleSetPin() {
    if (!(await guardIfPinSet())) return
    if (newPin.length < 4) {
      setError('Le code PIN doit contenir au moins 4 chiffres')
      return
    }
    await persistPin(newPin)
    setNewPin('')
    setMessage('Code PIN mis à jour')
    setError(null)
    await reload()
  }

  async function handleExport() {
    const json = await exportBackup()
    const blob = new Blob([json], { type: 'application/json' })
    const url = URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = url
    link.download = `maquisbar-sauvegarde-${new Date().toISOString().slice(0, 10)}.json`
    link.click()
    URL.revokeObjectURL(url)
  }

  async function handleFileSelected(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    setImportText(await file.text())
  }

  async function handleImport() {
    if (!importText) return
    if (!(await guardIfPinSet())) return
    if (!window.confirm('Cette opération remplace toutes les données locales. Avez-vous exporté une sauvegarde récente ?')) return
    try {
      await importBackup(importText)
      setMessage('Sauvegarde importée avec succès')
      setError(null)
      setImportText(null)
    } catch (err) {
      setError((err as Error).message)
    }
  }

  if (!settings) return null

  return (
    <div>
      <h1 className="mb-4 text-2xl font-semibold">Paramètres</h1>

      <section className="mb-6">
        <h2 className="mb-2 font-semibold">Établissement</h2>
        <div className="mb-2 flex flex-col gap-2 md:w-96">
          <label className="text-xs" htmlFor="settings-name">
            Nom de l'établissement
          </label>
          <input id="settings-name" className="rounded border px-2 py-1" value={establishmentName} onChange={(e) => setEstablishmentName(e.target.value)} />
          <label className="text-xs" htmlFor="settings-address">
            Adresse
          </label>
          <input id="settings-address" className="rounded border px-2 py-1" value={address} onChange={(e) => setAddress(e.target.value)} />
          <p className="text-xs text-slate-500">Devise : FCFA</p>
        </div>
        <button className="rounded bg-blue-600 px-3 py-1 text-white" onClick={handleSaveInfo}>
          Enregistrer
        </button>
      </section>

      <section className="mb-6">
        <h2 className="mb-2 font-semibold">Code PIN administrateur</h2>
        <div className="mb-2 flex items-end gap-2">
          <div>
            <label className="block text-xs" htmlFor="settings-pin">
              Nouveau code PIN
            </label>
            <input id="settings-pin" type="password" inputMode="numeric" className="rounded border px-2 py-1" value={newPin} onChange={(e) => setNewPin(e.target.value)} />
          </div>
          <button className="rounded bg-blue-600 px-3 py-1 text-white" onClick={handleSetPin}>
            Enregistrer le PIN
          </button>
        </div>
      </section>

      <section className="mb-6">
        <h2 className="mb-2 font-semibold">Sauvegarde</h2>
        <div className="flex flex-col gap-2 md:w-96">
          <button className="rounded bg-slate-200 px-3 py-1" onClick={handleExport}>
            Exporter une sauvegarde (JSON)
          </button>
          <label className="block text-xs" htmlFor="settings-import">
            Importer une sauvegarde
          </label>
          <input id="settings-import" type="file" accept="application/json" onChange={handleFileSelected} />
          <button className="rounded bg-red-600 px-3 py-1 text-white disabled:opacity-50" disabled={!importText} onClick={handleImport}>
            Restaurer cette sauvegarde
          </button>
        </div>
      </section>

      {message && <p className="text-sm text-green-700">{message}</p>}
      {error && <p className="text-sm text-red-600">{error}</p>}
    </div>
  )
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `npm run test -- settings/SettingsPage`
Expected: PASS, 4 tests.

- [ ] **Step 5: Run the full test suite**

Run: `npm run test`
Expected: PASS, all tests green.

- [ ] **Step 6: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Wire the settings page: establishment info, PIN, backup"
```

---

## Milestone 10 — PWA packaging & final verification

### Task 45: Finalize PWA metadata and verify the production build

**Files:**
- Modify: `app/index.html`

- [ ] **Step 1: Set the page title and description**

Replace the `<title>` line and add a description meta tag inside `<head>` in `app/index.html`:

```html
<title>MaquisBar</title>
<meta name="description" content="Gestion de maquis-bar hors ligne : caisse, tables, stock, clients." />
```

- [ ] **Step 2: Run the full automated test suite**

Run: `npm run test`
Expected: PASS, every test written across Milestones 0–9 is green.

- [ ] **Step 3: Type-check the project**

Run: `npx tsc --noEmit`
Expected: no type errors.

- [ ] **Step 4: Build for production**

Run: `npm run build`
Expected: build succeeds. Verify the PWA artifacts exist:

```bash
ls dist/manifest.webmanifest dist/sw.js dist/registerSW.js
```

Expected: all three files listed.

- [ ] **Step 5: Serve the production build and confirm the manifest is linked**

Run: `npm run preview -- --port 4173 &` then `curl -s http://localhost:4173 | grep -o 'manifest.webmanifest'`
Expected: prints `manifest.webmanifest`. Stop the preview server afterward.

- [ ] **Step 6: Commit**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add app/
git commit -m "Finalize PWA metadata and verify production build"
```

---

### Task 46: Manual offline-install and photo-capture verification

This task cannot be automated with Vitest/jsdom — it exercises the real Service Worker cache and the camera/gallery file pickers in an actual browser. Perform it once before considering v1 done, using the project's browser preview tooling.

**Files:** none (verification only).

- [ ] **Step 1: Start the production preview**

Run: `npm run build` then `npm run preview -- --port 4173`, and open `http://localhost:4173` in a real browser tab.

- [ ] **Step 2: Confirm installability**

In the browser's address bar / menu, confirm an "Install app" affordance appears (Chrome/Edge show an install icon in the address bar once the manifest and service worker are valid). Install it and confirm it opens in its own window.

- [ ] **Step 3: Confirm offline reload**

Open DevTools → Application → Service Workers, check "Offline", then reload the page.
Expected: the app shell still loads (no browser "no internet" error page), because Workbox precached it per Task 3's `globPatterns` config.

- [ ] **Step 4: Confirm photo capture and gallery import**

On the Catalog page, create a product, click "Caméra" (or "Galerie" on desktop, since desktop browsers have no camera capture prompt — use the file picker) and select an image.
Expected: a resized preview appears (per Task 23's `resizeImageFile`, capped at 480px / JPEG quality 0.8) and the product tile shows the photo after saving.

- [ ] **Step 5: Record the result**

No commit for this task — it is a verification checklist. If any step fails, file it as a follow-up fix before treating v1 as done.

---

### Task 47: Final regression run

**Files:** none (verification only).

- [ ] **Step 1: Run the full test suite one last time**

Run: `npm run test`
Expected: PASS, 0 failures.

- [ ] **Step 2: Run the production build one last time**

Run: `npm run build`
Expected: build succeeds with no errors or warnings about missing chunks.

- [ ] **Step 3: Confirm the demo walkthrough from the spec still passes**

The `PosPage.test.tsx` (Task 30) and `TablesPage.test.tsx` (Task 34) integration tests already cover the spec's required demo walkthrough — opening a table, adding items, checking out, and confirming stock decrements. Re-run them explicitly:

Run: `npm run test -- pos/PosPage tables/TablesPage`
Expected: PASS, both integration tests green.

- [ ] **Step 4: Tag the v1 milestone**

```bash
cd "D:\MES LOGICIELS\GESTION MAQUIS ET RESTAURANT"
git add -A
git commit -m "MaquisBar v1: mono-site offline PWA complete" --allow-empty
git tag v1.0.0
```

---

## Plan self-review notes

**Spec coverage:** tableau de bord (Task 42), catalogue illustré (Tasks 21–24), caisse tactile (Tasks 25–30), service à table (Tasks 31–34), clients/crédit (Tasks 35–37), mouvements de stock/dépenses/pertes (Tasks 38–41), rapports journaliers + export/import JSON (Tasks 16, 43), paramètres/devise FCFA/PIN (Task 44), PWA installable et hors ligne (Tasks 3, 45, 46). All spec sections have a corresponding task.

**Placeholder scan:** no TBD/TODO markers; every step carries complete, runnable code or an exact command with an expected result.

**Type consistency:** `CartLine`, `Payment`, `Discount`, and the Dexie record types (`ProductRecord`, `AdditionRecord`, `SaleRecord`, etc.) are defined once in Milestones 1–2 and reused verbatim by every later feature — verified by re-reading each task's imports against those original definitions.

