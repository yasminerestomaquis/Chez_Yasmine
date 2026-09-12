# Refonte du module Dépenses (4 sous-onglets) + sous-module Salaires — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transformer le module Dépenses en 4 sous-onglets (Vue d'ensemble, Dépenses, Salaires, Historique), avec un sous-module Salaires entièrement nouveau (employés + workflow de paie préparé→validé→payé→annulé) dont tout paiement effectif crée automatiquement et de façon idempotente une dépense de nature « Salaires ».

**Architecture:** Backend NestJS/Prisma : extension additive du modèle `Expense` (paymentMethod, status, payrollRunId) + trois nouveaux modèles (`Employee`, `PayrollRun`, `PayrollLine`) dans un nouveau module `payroll/` ; extension de `ExpensesService` avec une synthèse par période (résolution de bornes locale, propre à ce module, sans toucher `ReportsService`/`ChartsService` existants) et un historique paginé/filtré exportable en Excel (réutilise le pattern `ExcelJS` déjà utilisé par `ReportsService.beveragesSoldExcel`). Frontend Flutter : `ExpensesPage` explosée en coquille à 4 onglets, dont l'onglet "Dépenses" est une extraction **verbatim** de l'écran actuel (zéro changement de comportement) ; nouveaux widgets (donut chart via `fl_chart`, déjà en dépendance) et nouveaux écrans Salaires.

**Tech Stack:** NestJS + Prisma + Supabase Postgres (backend), Flutter Web + `fl_chart` (frontend), `ExcelJS` (export).

**Contrainte transversale (rappel explicite de l'utilisateur) : ne modifier le comportement d'AUCUN module existant.** Toute modification de fichier partagé (schema.prisma, seed de permissions) doit être strictement additive (nouvelles lignes/colonnes avec valeurs par défaut, jamais de suppression/renommage). `ReportsService` et `ChartsService` ne sont PAS modifiés par ce plan (lus pour référence uniquement) — la résolution de période pour Dépenses est dupliquée localement plutôt que factorisée, précisément pour ne pas toucher `reports.service.ts`.

---

## Contexte déjà audité (ne pas re-explorer)

- **Module Dépenses actuel** : `apps/web/flutter/lib/expenses/{expenses_page.dart, expense_models.dart, expenses_repository.dart}` (page unique, pas d'onglets). Backend `apps/api/nestjs/src/expenses/{expenses.controller.ts, expenses.service.ts, dto/expense.dto.ts, expenses.module.ts, expenses.service.spec.ts}` — CRUD + `nextMarketNumber`, filtre `from`/`to` brut, permission unique `expenses.manage` (pas de séparation view/manage sur ce module — **on ne change pas ça dans ce plan**, aucun rôle n'en a besoin aujourd'hui).
- **Modèle `Expense`** (`apps/api/nestjs/prisma/schema.prisma:505-521`) : `id, establishmentId, label, category (String? libre), amount (Decimal 12,2), expenseDate (@db.Date), periodicity (String, défaut "one_off"), note, marketNumber (Int?), createdAt`. Aucun `paymentMethod`, `status`, lien employé/paie.
- **Aucun module Employés/Salaires/Paie n'existe** — à créer intégralement.
- **Permissions** (`supabase/seed/001_roles_permissions.sql`) : pattern lecture/gestion déjà établi (`products.view`/`products.manage`, `stock.view`/`stock.manage`, `purchases.view`/`purchases.manage`) — à reproduire pour `payroll.view`/`payroll.manage`. Rôle `Comptable` est le plus pertinent pour la Paie.
- **Export Excel** : pattern `ReportsService.beveragesSoldExcel` (`apps/api/nestjs/src/reports/reports.service.ts:290-331`) via `ExcelJS` (déjà en dépendance) + contrôleur `@Res({passthrough:true})` (`reports.controller.ts:35-46`) — directement transposable.
- **Graphiques Flutter réutilisables** : `apps/web/flutter/lib/charts/monthly_line_chart.dart` (`MonthlyLineChartWidget`), `ranking_bar_chart.dart` (`RankingBarChartWidget`). `fl_chart: ^0.69.2` (pubspec) supporte nativement `PieChart` — aucun nouveau package nécessaire pour le donut "répartition par nature".
- **`ApiClient`** (`apps/web/flutter/lib/api/api_client.dart`) : `get(path, {query})`, `getBytes(path, {query}) → ({bytes, filename})`, `post/patch(path, {body})` (pas de `query` sur ceux-ci), `delete(path)`, `uploadFile(...)`. `lib/common/browser_download.dart` expose `void downloadBytes(List<int> bytes, String filename)`.
- **Stockage photo produit** (`apps/api/nestjs/src/storage/{supabase-storage.service.ts, image-processing.service.ts}`, `apps/api/nestjs/src/catalog/product-images.service.ts`) : pipeline complet (validation MIME/taille, variantes WebP, bucket `product-images`, URL signée). **Décision de périmètre** : le champ `Employee.photoUrl` est créé dans le schéma mais **aucun upload n'est implémenté dans ce plan** — réutiliser correctement ce pipeline demanderait de toucher `SupabaseStorageService`/ses policies RLS (bucket unique `product-images`, codé en dur), ce qui risquerait d'affecter le module Catalogue existant. La photo employé est donc différée (case notée dans la doc finale comme suivi possible) ; la liste des employés affiche une icône générique à la place, comme `StockPage._StockProductRow` le fait déjà pour un produit sans photo.

## File Structure

**Backend — nouveaux fichiers :**
- `apps/api/nestjs/src/payroll/employees.controller.ts`, `employees.service.ts`, `employees.service.spec.ts`, `payroll.controller.ts`, `payroll.service.ts`, `payroll.service.spec.ts`, `payroll.module.ts`, `dto/employee.dto.ts`, `dto/payroll.dto.ts`
- `supabase/migrations/20260912090000_add_expenses_payroll_module.sql`

**Backend — fichiers modifiés (additifs uniquement) :**
- `apps/api/nestjs/prisma/schema.prisma` (Expense + Establishment : nouvelles colonnes/relations ; nouveaux modèles Employee/PayrollRun/PayrollLine)
- `apps/api/nestjs/src/expenses/{expenses.service.ts, expenses.controller.ts, expenses.service.spec.ts, dto/expense.dto.ts}`
- `apps/api/nestjs/src/app.module.ts` (enregistrement `PayrollModule`)
- `supabase/seed/001_roles_permissions.sql` (nouvelles permissions `payroll.manage`/`payroll.view`)

**Frontend — nouveaux fichiers :**
- `apps/web/flutter/lib/expenses/expenses_overview_tab.dart`, `expenses_form_tab.dart`, `expenses_history_tab.dart`, `expense_category_donut_chart.dart`, `expense_summary_models.dart`
- `apps/web/flutter/lib/payroll/{employee_models.dart, employees_repository.dart, payroll_models.dart, payroll_repository.dart, payroll_tab.dart, employee_form_dialog.dart, payroll_run_page.dart}`

**Frontend — fichiers modifiés :**
- `apps/web/flutter/lib/expenses/{expenses_page.dart, expense_models.dart, expenses_repository.dart}`
- `apps/web/flutter/test/expenses_page_test.dart` (adapté à la nouvelle structure à onglets)

---

### Task 1 : Schéma Prisma + migration (Expense étendu, Employee, PayrollRun, PayrollLine)

**Files:**
- Modify: `apps/api/nestjs/prisma/schema.prisma:39-64` (Establishment), `apps/api/nestjs/prisma/schema.prisma:505-521` (Expense)
- Create: `supabase/migrations/20260912090000_add_expenses_payroll_module.sql`

- [ ] **Step 1: Étendre le modèle `Expense` et ajouter les 3 nouveaux modèles dans `schema.prisma`**

Remplacer le bloc `model Expense { ... }` (lignes 505-521) par :

```prisma
model Expense {
  id              String   @id @default(uuid())
  establishmentId String   @map("establishment_id")
  label           String
  category        String?
  amount          Decimal  @db.Decimal(12, 2)
  expenseDate     DateTime @default(now()) @map("expense_date") @db.Date
  periodicity     String   @default("one_off")
  note            String?
  /** Suggestion éditable, pertinente uniquement pour category === 'Marché' (même principe que Purchase.orderNumber) — jamais contrainte en unicité côté serveur. */
  marketNumber    Int?     @map("market_number")
  createdAt       DateTime @default(now()) @map("created_at")
  /** 'cash' | 'mobile_money' | 'bank_transfer' — défaut 'cash', cohérent avec l'hypothèse déjà documentée dans ARCHITECTURE.md (CashService.close). */
  paymentMethod   String   @default("cash") @map("payment_method")
  /** 'paid' | 'pending' | 'cancelled' — défaut 'paid' pour préserver le sens des dépenses déjà enregistrées (aucune ne portait de notion d'annulation). */
  status          String   @default("paid")
  /** Non-null uniquement pour une dépense générée automatiquement par PayrollService.pay() — la contrainte @unique est la seconde ligne de défense (avec le contrôle de statut du run) garantissant qu'un paiement de paie ne crée jamais deux fois la même dépense. */
  payrollRunId    String?  @unique @map("payroll_run_id")

  establishment Establishment @relation(fields: [establishmentId], references: [id], onDelete: Cascade)
  payrollRun    PayrollRun?   @relation(fields: [payrollRunId], references: [id])

  @@map("expenses")
}

model Employee {
  id                 String    @id @default(uuid())
  establishmentId    String    @map("establishment_id")
  lastName           String    @map("last_name")
  firstName          String    @map("first_name")
  gender             String?
  birthDate          DateTime? @map("birth_date") @db.Date
  phone              String
  address            String?
  /** Voir docs/api/expenses.md — pipeline d'upload volontairement différé, ce champ reste vide en attendant. */
  photoUrl           String?   @map("photo_url")
  position           String
  hireDate           DateTime  @map("hire_date") @db.Date
  contractType       String?   @map("contract_type")
  weeklySalary       Decimal   @map("weekly_salary") @db.Decimal(12, 2)
  team               String?
  registrationNumber String?   @map("registration_number")
  notes              String?
  /** 'active' | 'inactive' */
  status             String    @default("active")
  createdAt          DateTime  @default(now()) @map("created_at")
  updatedAt          DateTime  @updatedAt @map("updated_at")

  establishment Establishment @relation(fields: [establishmentId], references: [id], onDelete: Cascade)
  payrollLines  PayrollLine[]

  @@map("employees")
}

/// Statuts : 'prepared' -> 'validated' -> 'paid' (paid crée l'Expense liée et
/// n'est jamais réversible) ; 'cancelled' atteignable seulement depuis
/// 'prepared'/'validated' — voir PayrollService.
model PayrollRun {
  id              String    @id @default(uuid())
  establishmentId String    @map("establishment_id")
  periodStart     DateTime  @map("period_start") @db.Date
  periodEnd       DateTime  @map("period_end") @db.Date
  status          String    @default("prepared")
  preparedBy      String    @map("prepared_by")
  validatedBy     String?   @map("validated_by")
  paidBy          String?   @map("paid_by")
  validatedAt     DateTime? @map("validated_at")
  paidAt          DateTime? @map("paid_at")
  cancelledAt     DateTime? @map("cancelled_at")
  createdAt       DateTime  @default(now()) @map("created_at")

  establishment Establishment @relation(fields: [establishmentId], references: [id], onDelete: Cascade)
  lines         PayrollLine[]
  expense       Expense?

  @@map("payroll_runs")
}

model PayrollLine {
  id           String  @id @default(uuid())
  payrollRunId String  @map("payroll_run_id")
  employeeId   String  @map("employee_id")
  /** Copie de Employee.weeklySalary au moment de la préparation — un changement de salaire plus tard ne doit jamais réécrire un bulletin déjà préparé. */
  baseSalary   Decimal @map("base_salary") @db.Decimal(12, 2)
  advance      Decimal @default(0) @db.Decimal(12, 2)
  /** Prime (positif) ou retenue (négatif). */
  adjustment   Decimal @default(0) @db.Decimal(12, 2)
  netAmount    Decimal @map("net_amount") @db.Decimal(12, 2)

  payrollRun PayrollRun @relation(fields: [payrollRunId], references: [id], onDelete: Cascade)
  employee   Employee   @relation(fields: [employeeId], references: [id], onDelete: Restrict)

  @@unique([payrollRunId, employeeId])
  @@map("payroll_lines")
}
```

Dans `model Establishment` (ligne 58, juste après `expenses Expense[]`), ajouter deux lignes :

```prisma
  employees          Employee[]
  payrollRuns        PayrollRun[]
```

- [ ] **Step 2: Écrire la migration SQL**

```sql
-- Étend `expenses` (mode de paiement, statut, lien optionnel vers un
-- paiement de paie) et crée les tables employees/payroll_runs/payroll_lines
-- pour le sous-module Salaires (voir docs/api/expenses.md).
-- Purement additif : aucune colonne existante modifiée/supprimée, valeurs
-- par défaut choisies pour que les dépenses déjà enregistrées restent
-- interprétées exactement comme avant (payment_method='cash', status='paid').

alter table expenses
  add column payment_method text not null default 'cash',
  add column status text not null default 'paid',
  add column payroll_run_id uuid unique;

create table employees (
  id                  uuid primary key default gen_random_uuid(),
  establishment_id    uuid not null references establishments(id) on delete cascade,
  last_name           text not null,
  first_name          text not null,
  gender              text,
  birth_date          date,
  phone               text not null,
  address             text,
  photo_url           text,
  position            text not null,
  hire_date           date not null,
  contract_type       text,
  weekly_salary       numeric(12, 2) not null,
  team                text,
  registration_number text,
  notes               text,
  status              text not null default 'active',
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index employees_establishment_id_idx on employees(establishment_id);

create table payroll_runs (
  id               uuid primary key default gen_random_uuid(),
  establishment_id uuid not null references establishments(id) on delete cascade,
  period_start     date not null,
  period_end       date not null,
  status           text not null default 'prepared',
  prepared_by      uuid not null,
  validated_by     uuid,
  paid_by          uuid,
  validated_at     timestamptz,
  paid_at          timestamptz,
  cancelled_at     timestamptz,
  created_at       timestamptz not null default now()
);
create index payroll_runs_establishment_id_idx on payroll_runs(establishment_id);

create table payroll_lines (
  id             uuid primary key default gen_random_uuid(),
  payroll_run_id uuid not null references payroll_runs(id) on delete cascade,
  employee_id    uuid not null references employees(id) on delete restrict,
  base_salary    numeric(12, 2) not null,
  advance        numeric(12, 2) not null default 0,
  adjustment     numeric(12, 2) not null default 0,
  net_amount     numeric(12, 2) not null,
  unique (payroll_run_id, employee_id)
);
create index payroll_lines_payroll_run_id_idx on payroll_lines(payroll_run_id);
create index payroll_lines_employee_id_idx on payroll_lines(employee_id);

alter table expenses
  add constraint expenses_payroll_run_id_fkey foreign key (payroll_run_id) references payroll_runs(id);

alter table employees enable row level security;
alter table payroll_runs enable row level security;
alter table payroll_lines enable row level security;

-- RLS : même politique établissement que le reste de l'app (isolation par
-- appartenance de l'utilisateur à l'établissement via user_establishment_roles),
-- copiée du modèle déjà en place pour `expenses` (voir supabase/migrations/20260905191510_rls_policies.sql).
create policy employees_establishment_isolation on employees
  using (establishment_id in (
    select establishment_id from user_establishment_roles where user_id = auth.uid()
  ));
create policy payroll_runs_establishment_isolation on payroll_runs
  using (establishment_id in (
    select establishment_id from user_establishment_roles where user_id = auth.uid()
  ));
create policy payroll_lines_establishment_isolation on payroll_lines
  using (payroll_run_id in (
    select id from payroll_runs where establishment_id in (
      select establishment_id from user_establishment_roles where user_id = auth.uid()
    )
  ));
```

- [ ] **Step 3: Appliquer la migration sur le projet Supabase de production**

Utiliser l'outil MCP Supabase `apply_migration` (projet `tsebsulvhgttdwtgqfoj`) avec le nom `add_expenses_payroll_module` et le contenu SQL ci-dessus — ne jamais exécuter de DDL via `execute_sql`.

- [ ] **Step 4: Régénérer le client Prisma et vérifier la compilation**

Run: `cd apps/api/nestjs && npx prisma validate && npx prisma generate && npm run build`
Expected: les trois commandes réussissent sans erreur (`schema.prisma` valide, client généré, `nest build` compile).

- [ ] **Step 5: Commit**

```bash
git add apps/api/nestjs/prisma/schema.prisma supabase/migrations/20260912090000_add_expenses_payroll_module.sql
git commit -m "feat(payroll): ajoute le schéma Employee/PayrollRun/PayrollLine et étend Expense

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2 : Permissions `payroll.manage`/`payroll.view`

**Files:**
- Modify: `supabase/seed/001_roles_permissions.sql`

- [ ] **Step 1: Ajouter les deux permissions et le grant Comptable**

Dans le bloc `insert into permissions`, ajouter avant la ligne `on conflict (code) do nothing;` :

```sql
  ('payroll.manage',    'Gérer les employés et le workflow de paie (préparer/valider/payer/annuler)'),
  ('payroll.view',      'Consulter les employés, la paie et son historique — sans les modifier'),
```

Après le bloc Comptable existant, ajouter :

```sql
-- Comptable : rôle le plus pertinent pour la Paie (voir docs/api/expenses.md).
-- `payroll.manage` inclut `payroll.view` par convention (comme
-- products/stock/purchases) : accordé explicitement pour ne pas dépendre
-- d'un futur découplage.
insert into role_permissions (role_id, permission_id)
select r.id, p.id
from roles r
join permissions p on p.code in ('payroll.manage', 'payroll.view')
where r.is_system and r.name = 'Comptable'
on conflict do nothing;
```

- [ ] **Step 2: Appliquer sur la base de production**

Exécuter via l'outil MCP Supabase `execute_sql` (projet `tsebsulvhgttdwtgqfoj`) :
1. Le nouveau bloc `insert into permissions (...) values ('payroll.manage', ...), ('payroll.view', ...) on conflict (code) do nothing;`
2. Le nouveau grant Comptable ci-dessus
3. Les deux blocs "accès complet" déjà existants (Super Administrateur/Administrateur/Propriétaire via `cross join permissions`, et Gérant `p.code <> 'roles.manage'`) — les rejouer capte automatiquement les 2 nouvelles permissions (idempotent, `on conflict do nothing`).

- [ ] **Step 3: Vérifier**

Requête de vérification (`execute_sql`) :
```sql
select p.code from role_permissions rp
join roles r on r.id = rp.role_id
join permissions p on p.id = rp.permission_id
where r.name = 'Comptable' and p.code like 'payroll.%';
```
Expected: `payroll.manage` et `payroll.view` tous les deux présents.

- [ ] **Step 4: Commit**

```bash
git add supabase/seed/001_roles_permissions.sql
git commit -m "feat(payroll): permissions payroll.manage/payroll.view (rôle Comptable)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3 : Backend — module Employés (CRUD)

**Files:**
- Create: `apps/api/nestjs/src/payroll/dto/employee.dto.ts`, `apps/api/nestjs/src/payroll/employees.service.ts`, `apps/api/nestjs/src/payroll/employees.service.spec.ts`, `apps/api/nestjs/src/payroll/employees.controller.ts`

- [ ] **Step 1: DTOs avec validation téléphone ivoirienne**

`apps/api/nestjs/src/payroll/dto/employee.dto.ts` :

```typescript
import { Transform } from 'class-transformer';
import { IsDateString, IsIn, IsNumber, IsOptional, IsString, Matches, Min, MinLength } from 'class-validator';

const normalizePhone = ({ value }: { value: unknown }) =>
  typeof value === 'string' ? value.replace(/[\s.-]/g, '') : value;

/** Numérotation ivoirienne en vigueur depuis 2021 : 10 chiffres commençant par 0. */
const CI_PHONE_REGEX = /^0\d{9}$/;
const CI_PHONE_MESSAGE = 'Numéro de téléphone invalide (format attendu : 10 chiffres commençant par 0, ex. 0708091011)';

export class CreateEmployeeDto {
  @IsString()
  @MinLength(1)
  lastName!: string;

  @IsString()
  @MinLength(1)
  firstName!: string;

  @IsOptional()
  @IsString()
  gender?: string;

  @IsOptional()
  @IsDateString()
  birthDate?: string;

  @Transform(normalizePhone)
  @Matches(CI_PHONE_REGEX, { message: CI_PHONE_MESSAGE })
  phone!: string;

  @IsOptional()
  @IsString()
  address?: string;

  @IsString()
  @MinLength(1)
  position!: string;

  @IsDateString()
  hireDate!: string;

  @IsOptional()
  @IsString()
  contractType?: string;

  @IsNumber()
  @Min(0.01)
  weeklySalary!: number;

  @IsOptional()
  @IsString()
  team?: string;

  @IsOptional()
  @IsString()
  registrationNumber?: string;

  @IsOptional()
  @IsString()
  notes?: string;
}

export class UpdateEmployeeDto {
  @IsOptional()
  @IsString()
  @MinLength(1)
  lastName?: string;

  @IsOptional()
  @IsString()
  @MinLength(1)
  firstName?: string;

  @IsOptional()
  @IsString()
  gender?: string;

  @IsOptional()
  @IsDateString()
  birthDate?: string;

  @IsOptional()
  @Transform(normalizePhone)
  @Matches(CI_PHONE_REGEX, { message: CI_PHONE_MESSAGE })
  phone?: string;

  @IsOptional()
  @IsString()
  address?: string;

  @IsOptional()
  @IsString()
  @MinLength(1)
  position?: string;

  @IsOptional()
  @IsDateString()
  hireDate?: string;

  @IsOptional()
  @IsString()
  contractType?: string;

  @IsOptional()
  @IsNumber()
  @Min(0.01)
  weeklySalary?: number;

  @IsOptional()
  @IsString()
  team?: string;

  @IsOptional()
  @IsString()
  registrationNumber?: string;

  @IsOptional()
  @IsString()
  notes?: string;

  @IsOptional()
  @IsIn(['active', 'inactive'])
  status?: string;
}
```

- [ ] **Step 2: Écrire le test du service (échoue, service inexistant)**

`apps/api/nestjs/src/payroll/employees.service.spec.ts` :

```typescript
import { NotFoundException } from '@nestjs/common';
import { beforeEach, describe, expect, it } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import { EmployeesService } from './employees.service.js';

function makePrismaMock() {
  return {
    employee: {
      findMany: vi.fn(),
      findFirst: vi.fn(),
      create: vi.fn(),
      updateMany: vi.fn(),
      findUniqueOrThrow: vi.fn(),
    },
  };
}

describe('EmployeesService', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: EmployeesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new EmployeesService(prisma as unknown as PrismaService);
  });

  it('lists employees scoped to the establishment, ordered by last name', async () => {
    (prisma.employee as any).findMany.mockResolvedValue([]);
    await service.list('est-1');
    expect(prisma.employee.findMany).toHaveBeenCalledWith({
      where: { establishmentId: 'est-1' },
      orderBy: { lastName: 'asc' },
    });
  });

  it('creates an employee defaulting status to active', async () => {
    (prisma.employee as any).create.mockResolvedValue({ id: 'emp-1' });
    await service.create('est-1', {
      lastName: 'Koffi',
      firstName: 'Awa',
      phone: '0708091011',
      position: 'Cuisinière',
      hireDate: '2026-01-10',
      weeklySalary: 30000,
    });
    expect(prisma.employee.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ establishmentId: 'est-1', status: 'active' }),
    });
  });

  it('throws NotFoundException updating an employee outside the establishment', async () => {
    (prisma.employee as any).updateMany.mockResolvedValue({ count: 0 });
    await expect(service.update('est-1', 'emp-x', { position: 'Serveur' })).rejects.toBeInstanceOf(NotFoundException);
  });

  it('deactivates an employee via status update rather than deleting the row (préserve l\'historique de paie)', async () => {
    (prisma.employee as any).updateMany.mockResolvedValue({ count: 1 });
    (prisma.employee as any).findUniqueOrThrow.mockResolvedValue({ id: 'emp-1', status: 'inactive' });
    const result = await service.update('est-1', 'emp-1', { status: 'inactive' });
    expect(result.status).toBe('inactive');
  });
});
```

Ajouter en tête du fichier l'import vitest manquant : `import { vi } from 'vitest';` (à fusionner avec la ligne `import { beforeEach, describe, expect, it } from 'vitest';` en une seule ligne `import { beforeEach, describe, expect, it, vi } from 'vitest';`).

- [ ] **Step 3: Run test to verify it fails**

Run: `cd apps/api/nestjs && npx vitest run src/payroll/employees.service.spec.ts`
Expected: FAIL — `Cannot find module './employees.service.js'`

- [ ] **Step 4: Implémenter `EmployeesService`**

`apps/api/nestjs/src/payroll/employees.service.ts` :

```typescript
import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import type { CreateEmployeeDto, UpdateEmployeeDto } from './dto/employee.dto.js';

@Injectable()
export class EmployeesService {
  constructor(private readonly prisma: PrismaService) {}

  list(establishmentId: string) {
    return this.prisma.employee.findMany({
      where: { establishmentId },
      orderBy: { lastName: 'asc' },
    });
  }

  async create(establishmentId: string, dto: CreateEmployeeDto) {
    return this.prisma.employee.create({
      data: {
        establishmentId,
        lastName: dto.lastName,
        firstName: dto.firstName,
        gender: dto.gender,
        birthDate: dto.birthDate ? new Date(dto.birthDate) : undefined,
        phone: dto.phone,
        address: dto.address,
        position: dto.position,
        hireDate: new Date(dto.hireDate),
        contractType: dto.contractType,
        weeklySalary: dto.weeklySalary,
        team: dto.team,
        registrationNumber: dto.registrationNumber,
        notes: dto.notes,
        status: 'active',
      },
    });
  }

  /** Désactivation via `status: 'inactive'`, jamais de suppression : un employé peut être référencé par des PayrollLine passées (onDelete: Restrict), et son historique de paie doit rester consultable. */
  async update(establishmentId: string, employeeId: string, dto: UpdateEmployeeDto) {
    const { count } = await this.prisma.employee.updateMany({
      where: { id: employeeId, establishmentId },
      data: {
        lastName: dto.lastName,
        firstName: dto.firstName,
        gender: dto.gender,
        birthDate: dto.birthDate ? new Date(dto.birthDate) : undefined,
        phone: dto.phone,
        address: dto.address,
        position: dto.position,
        hireDate: dto.hireDate ? new Date(dto.hireDate) : undefined,
        contractType: dto.contractType,
        weeklySalary: dto.weeklySalary,
        team: dto.team,
        registrationNumber: dto.registrationNumber,
        notes: dto.notes,
        status: dto.status,
      },
    });
    if (count === 0) {
      throw new NotFoundException('Employé introuvable pour cet établissement');
    }
    return this.prisma.employee.findUniqueOrThrow({ where: { id: employeeId } });
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd apps/api/nestjs && npx vitest run src/payroll/employees.service.spec.ts`
Expected: PASS (4 tests)

- [ ] **Step 6: Contrôleur**

`apps/api/nestjs/src/payroll/employees.controller.ts` :

```typescript
import { Body, Controller, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { CreateEmployeeDto, UpdateEmployeeDto } from './dto/employee.dto.js';
import { EmployeesService } from './employees.service.js';

@Controller('establishments/:establishmentId/employees')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
export class EmployeesController {
  constructor(private readonly employees: EmployeesService) {}

  @Get()
  @RequirePermissions('payroll.view')
  list(@Param('establishmentId') establishmentId: string) {
    return this.employees.list(establishmentId);
  }

  @Post()
  @RequirePermissions('payroll.manage')
  create(@Param('establishmentId') establishmentId: string, @Body() dto: CreateEmployeeDto) {
    return this.employees.create(establishmentId, dto);
  }

  @Patch(':employeeId')
  @RequirePermissions('payroll.manage')
  update(
    @Param('establishmentId') establishmentId: string,
    @Param('employeeId') employeeId: string,
    @Body() dto: UpdateEmployeeDto,
  ) {
    return this.employees.update(establishmentId, employeeId, dto);
  }
}
```

- [ ] **Step 7: Commit**

```bash
git add apps/api/nestjs/src/payroll/dto/employee.dto.ts apps/api/nestjs/src/payroll/employees.service.ts apps/api/nestjs/src/payroll/employees.service.spec.ts apps/api/nestjs/src/payroll/employees.controller.ts
git commit -m "feat(payroll): CRUD employés (EmployeesService/Controller)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4 : Backend — préparation d'une paie (PayrollRun + PayrollLine)

**Files:**
- Create: `apps/api/nestjs/src/payroll/dto/payroll.dto.ts`, `apps/api/nestjs/src/payroll/payroll.service.ts` (partiel — complété Task 5), `apps/api/nestjs/src/payroll/payroll.service.spec.ts`

- [ ] **Step 1: DTOs**

`apps/api/nestjs/src/payroll/dto/payroll.dto.ts` :

```typescript
import { IsArray, IsDateString, IsNumber, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';

export class PrepareLineDto {
  employeeId!: string;

  @IsNumber()
  advance!: number;

  @IsNumber()
  adjustment!: number;
}

export class PreparePayrollRunDto {
  @IsDateString()
  periodStart!: string;

  @IsDateString()
  periodEnd!: string;
}

export class UpdatePayrollLineDto {
  @IsNumber()
  advance!: number;

  @IsNumber()
  adjustment!: number;
}
```

- [ ] **Step 2: Écrire les tests de préparation (échouent, service inexistant)**

`apps/api/nestjs/src/payroll/payroll.service.spec.ts` :

```typescript
import { BadRequestException } from '@nestjs/common';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { PrismaService } from '../prisma/prisma.service.js';
import type { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import { PayrollService } from './payroll.service.js';

const activityNotifierMock = { notify: vi.fn() } as unknown as ActivityNotifierService;

function makePrismaMock() {
  return {
    employee: { findMany: vi.fn() },
    payrollRun: { create: vi.fn(), findFirst: vi.fn(), findMany: vi.fn(), update: vi.fn() },
    payrollLine: { update: vi.fn(), findFirst: vi.fn() },
    expense: { create: vi.fn(), findFirst: vi.fn() },
    $transaction: vi.fn((fn: any) => (typeof fn === 'function' ? fn(makePrismaMock()) : Promise.all(fn))),
  };
}

describe('PayrollService.prepare', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: PayrollService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new PayrollService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('creates one PayrollLine per active employee, snapshotting weeklySalary as baseSalary', async () => {
    (prisma.employee as any).findMany.mockResolvedValue([
      { id: 'emp-1', weeklySalary: { toNumber: () => 30000 } },
      { id: 'emp-2', weeklySalary: { toNumber: () => 25000 } },
    ]);
    (prisma.payrollRun as any).create.mockImplementation(({ data }: any) => Promise.resolve({ id: 'run-1', ...data }));

    await service.prepare('est-1', 'user-1', { periodStart: '2026-09-07', periodEnd: '2026-09-13' });

    expect(prisma.employee.findMany).toHaveBeenCalledWith({
      where: { establishmentId: 'est-1', status: 'active' },
      select: { id: true, weeklySalary: true },
    });
    const createCall = (prisma.payrollRun as any).create.mock.calls[0][0];
    expect(createCall.data.status).toBe('prepared');
    expect(createCall.data.preparedBy).toBe('user-1');
    expect(createCall.data.lines.create).toEqual([
      { employeeId: 'emp-1', baseSalary: 30000, advance: 0, adjustment: 0, netAmount: 30000 },
      { employeeId: 'emp-2', baseSalary: 25000, advance: 0, adjustment: 0, netAmount: 25000 },
    ]);
  });
});

describe('PayrollService.updateLine', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: PayrollService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new PayrollService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('recomputes netAmount = baseSalary - advance + adjustment', async () => {
    (prisma.payrollLine as any).findFirst.mockResolvedValue({
      id: 'line-1',
      baseSalary: { toNumber: () => 30000 },
      payrollRun: { id: 'run-1', establishmentId: 'est-1', status: 'prepared' },
    });
    await service.updateLine('est-1', 'run-1', 'line-1', { advance: 5000, adjustment: -2000 });
    expect(prisma.payrollLine.update).toHaveBeenCalledWith({
      where: { id: 'line-1' },
      data: { advance: 5000, adjustment: -2000, netAmount: 23000 },
    });
  });

  it('rejects editing a line on a run that is not "prepared"', async () => {
    (prisma.payrollLine as any).findFirst.mockResolvedValue({
      id: 'line-1',
      baseSalary: { toNumber: () => 30000 },
      payrollRun: { id: 'run-1', establishmentId: 'est-1', status: 'validated' },
    });
    await expect(service.updateLine('est-1', 'run-1', 'line-1', { advance: 0, adjustment: 0 })).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd apps/api/nestjs && npx vitest run src/payroll/payroll.service.spec.ts`
Expected: FAIL — module `./payroll.service.js` introuvable.

- [ ] **Step 4: Implémenter `PayrollService` (partie préparation/édition)**

`apps/api/nestjs/src/payroll/payroll.service.ts` :

```typescript
import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service.js';
import { ActivityNotifierService } from '../notifications/activity-notifier.service.js';
import type { PreparePayrollRunDto, UpdatePayrollLineDto } from './dto/payroll.dto.js';

@Injectable()
export class PayrollService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly activityNotifier: ActivityNotifierService,
  ) {}

  list(establishmentId: string) {
    return this.prisma.payrollRun.findMany({
      where: { establishmentId },
      include: { lines: { include: { employee: { select: { id: true, lastName: true, firstName: true } } } } },
      orderBy: { periodStart: 'desc' },
    });
  }

  /** Une ligne par employé actif au moment de la préparation, `baseSalary` figé sur `Employee.weeklySalary` (un changement de salaire ultérieur ne réécrit jamais un bulletin déjà préparé). */
  async prepare(establishmentId: string, userId: string, dto: PreparePayrollRunDto) {
    const employees = await this.prisma.employee.findMany({
      where: { establishmentId, status: 'active' },
      select: { id: true, weeklySalary: true },
    });
    const run = await this.prisma.payrollRun.create({
      data: {
        establishmentId,
        periodStart: new Date(dto.periodStart),
        periodEnd: new Date(dto.periodEnd),
        status: 'prepared',
        preparedBy: userId,
        lines: {
          create: employees.map((e) => {
            const baseSalary = e.weeklySalary.toNumber();
            return { employeeId: e.id, baseSalary, advance: 0, adjustment: 0, netAmount: baseSalary };
          }),
        },
      },
      include: { lines: true },
    });
    return run;
  }

  private async getEditableLine(establishmentId: string, payrollRunId: string, lineId: string) {
    const line = await this.prisma.payrollLine.findFirst({
      where: { id: lineId, payrollRunId },
      include: { payrollRun: true },
    });
    if (!line || line.payrollRun.establishmentId !== establishmentId) {
      throw new NotFoundException('Ligne de paie introuvable pour cet établissement');
    }
    if (line.payrollRun.status !== 'prepared') {
      throw new BadRequestException('Cette paie n\'est plus modifiable (déjà validée, payée ou annulée)');
    }
    return line;
  }

  async updateLine(establishmentId: string, payrollRunId: string, lineId: string, dto: UpdatePayrollLineDto) {
    const line = await this.getEditableLine(establishmentId, payrollRunId, lineId);
    const netAmount = line.baseSalary.toNumber() - dto.advance + dto.adjustment;
    await this.prisma.payrollLine.update({
      where: { id: lineId },
      data: { advance: dto.advance, adjustment: dto.adjustment, netAmount },
    });
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd apps/api/nestjs && npx vitest run src/payroll/payroll.service.spec.ts`
Expected: PASS (3 tests)

- [ ] **Step 6: Commit**

```bash
git add apps/api/nestjs/src/payroll/dto/payroll.dto.ts apps/api/nestjs/src/payroll/payroll.service.ts apps/api/nestjs/src/payroll/payroll.service.spec.ts
git commit -m "feat(payroll): préparation d'une paie + édition avance/prime par ligne

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5 : Backend — validation, paiement (crée l'Expense de façon idempotente) et annulation

**Files:**
- Modify: `apps/api/nestjs/src/payroll/payroll.service.ts`, `apps/api/nestjs/src/payroll/payroll.service.spec.ts`
- Create: `apps/api/nestjs/src/payroll/payroll.controller.ts`, `apps/api/nestjs/src/payroll/payroll.module.ts`
- Modify: `apps/api/nestjs/src/app.module.ts`

- [ ] **Step 1: Ajouter les tests de transition d'état (échouent, méthodes inexistantes)**

Ajouter dans `payroll.service.spec.ts` :

```typescript
describe('PayrollService.validate / pay / cancel', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: PayrollService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new PayrollService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('validate() moves a prepared run to validated', async () => {
    (prisma.payrollRun as any).findFirst.mockResolvedValue({ id: 'run-1', establishmentId: 'est-1', status: 'prepared' });
    await service.validate('est-1', 'run-1', 'user-2');
    expect(prisma.payrollRun.update).toHaveBeenCalledWith({
      where: { id: 'run-1' },
      data: { status: 'validated', validatedBy: 'user-2', validatedAt: expect.any(Date) },
    });
  });

  it('validate() rejects a run that is not "prepared"', async () => {
    (prisma.payrollRun as any).findFirst.mockResolvedValue({ id: 'run-1', establishmentId: 'est-1', status: 'paid' });
    await expect(service.validate('est-1', 'run-1', 'user-2')).rejects.toBeInstanceOf(BadRequestException);
  });

  it('pay() creates one Expense summing all line netAmounts, linked via payrollRunId', async () => {
    (prisma.payrollRun as any).findFirst.mockResolvedValue({
      id: 'run-1',
      establishmentId: 'est-1',
      status: 'validated',
      periodEnd: new Date('2026-09-13'),
      lines: [{ netAmount: { toNumber: () => 30000 } }, { netAmount: { toNumber: () => 25000 } }],
    });
    (prisma.$transaction as any).mockImplementation((ops: any[]) => Promise.all(ops));
    await service.pay('est-1', 'run-1', 'user-3');
    expect(prisma.expense.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        establishmentId: 'est-1',
        label: 'Paiement des salaires',
        category: 'Salaires',
        amount: 55000,
        payrollRunId: 'run-1',
      }),
    });
  });

  it('pay() rejects a run that is not "validated" (never pays twice)', async () => {
    (prisma.payrollRun as any).findFirst.mockResolvedValue({ id: 'run-1', establishmentId: 'est-1', status: 'paid', lines: [] });
    await expect(service.pay('est-1', 'run-1', 'user-3')).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.expense.create).not.toHaveBeenCalled();
  });

  it('cancel() is allowed from "prepared" but not from "paid"', async () => {
    (prisma.payrollRun as any).findFirst.mockResolvedValue({ id: 'run-1', establishmentId: 'est-1', status: 'prepared' });
    await service.cancel('est-1', 'run-1');
    expect(prisma.payrollRun.update).toHaveBeenCalledWith({
      where: { id: 'run-1' },
      data: { status: 'cancelled', cancelledAt: expect.any(Date) },
    });

    (prisma.payrollRun as any).findFirst.mockResolvedValue({ id: 'run-2', establishmentId: 'est-1', status: 'paid' });
    await expect(service.cancel('est-1', 'run-2')).rejects.toBeInstanceOf(BadRequestException);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/api/nestjs && npx vitest run src/payroll/payroll.service.spec.ts`
Expected: FAIL — `service.validate is not a function` (et `pay`, `cancel`).

- [ ] **Step 3: Implémenter validate/pay/cancel**

Ajouter dans `payroll.service.ts`, à l'intérieur de la classe `PayrollService` :

```typescript
  private async getRun(establishmentId: string, payrollRunId: string) {
    const run = await this.prisma.payrollRun.findFirst({
      where: { id: payrollRunId, establishmentId },
      include: { lines: true },
    });
    if (!run) {
      throw new NotFoundException('Paie introuvable pour cet établissement');
    }
    return run;
  }

  async validate(establishmentId: string, payrollRunId: string, userId: string) {
    const run = await this.getRun(establishmentId, payrollRunId);
    if (run.status !== 'prepared') {
      throw new BadRequestException('Seule une paie "préparée" peut être validée');
    }
    await this.prisma.payrollRun.update({
      where: { id: payrollRunId },
      data: { status: 'validated', validatedBy: userId, validatedAt: new Date() },
    });
  }

  /**
   * Crée UNE dépense de nature "Salaires" pour l'ensemble de la paie, jamais
   * deux fois : (1) le contrôle `status !== 'validated'` bloque un second
   * appel une fois `status` passé à 'paid' ; (2) `Expense.payrollRunId`
   * porte une contrainte @unique en base — même en cas de double requête
   * concurrente, la seconde échouerait au niveau SQL plutôt que de dupliquer
   * la dépense (défense en profondeur, voir docs/api/expenses.md).
   */
  async pay(establishmentId: string, payrollRunId: string, userId: string) {
    const run = await this.getRun(establishmentId, payrollRunId);
    if (run.status !== 'validated') {
      throw new BadRequestException('Seule une paie "validée" peut être payée');
    }
    const total = run.lines.reduce((sum, l) => sum + l.netAmount.toNumber(), 0);
    const paidAt = new Date();

    await this.prisma.$transaction([
      this.prisma.payrollRun.update({
        where: { id: payrollRunId },
        data: { status: 'paid', paidBy: userId, paidAt },
      }),
      this.prisma.expense.create({
        data: {
          establishmentId,
          label: 'Paiement des salaires',
          category: 'Salaires',
          amount: total,
          expenseDate: run.periodEnd,
          periodicity: 'recurring',
          paymentMethod: 'cash',
          status: 'paid',
          payrollRunId,
        },
      }),
    ]);

    await this.activityNotifier.notify(
      establishmentId,
      'Salaires payés',
      `${total.toLocaleString('fr-FR')} FCFA versés pour ${run.lines.length} employé(s)`,
    );
  }

  async cancel(establishmentId: string, payrollRunId: string) {
    const run = await this.getRun(establishmentId, payrollRunId);
    if (run.status === 'paid') {
      throw new BadRequestException('Une paie déjà payée ne peut plus être annulée');
    }
    if (run.status === 'cancelled') {
      throw new BadRequestException('Cette paie est déjà annulée');
    }
    await this.prisma.payrollRun.update({
      where: { id: payrollRunId },
      data: { status: 'cancelled', cancelledAt: new Date() },
    });
  }

  /** Tableau de bord Salaires — voir docs/api/expenses.md. `year`/`month` en 1-12. */
  async dashboard(establishmentId: string, year: number, month: number) {
    const from = new Date(year, month - 1, 1);
    const to = new Date(year, month, 0, 23, 59, 59, 999);
    const [employeeCount, runs] = await Promise.all([
      this.prisma.employee.count({ where: { establishmentId, status: 'active' } }),
      this.prisma.payrollRun.findMany({
        where: { establishmentId, periodStart: { gte: from, lte: to }, status: { not: 'cancelled' } },
        include: { lines: true },
      }),
    ]);
    let massSalariale = 0;
    let totalPaid = 0;
    for (const run of runs) {
      const runTotal = run.lines.reduce((sum, l) => sum + l.netAmount.toNumber(), 0);
      massSalariale += runTotal;
      if (run.status === 'paid') totalPaid += runTotal;
    }
    return { employeeCount, massSalariale, totalPaid, remaining: massSalariale - totalPaid };
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/api/nestjs && npx vitest run src/payroll/payroll.service.spec.ts`
Expected: PASS (8 tests au total pour ce fichier)

- [ ] **Step 5: Contrôleur**

`apps/api/nestjs/src/payroll/payroll.controller.ts` :

```typescript
import { Body, Controller, Get, Param, Patch, Post, Query, Req, UseGuards } from '@nestjs/common';
import type { Request } from 'express';
import { PermissionsGuard } from '../auth/permissions.guard.js';
import { RequirePermissions } from '../auth/permissions.decorator.js';
import { SupabaseJwtGuard } from '../auth/supabase-jwt.guard.js';
import { PreparePayrollRunDto, UpdatePayrollLineDto } from './dto/payroll.dto.js';
import { PayrollService } from './payroll.service.js';

@Controller('establishments/:establishmentId/payroll')
@UseGuards(SupabaseJwtGuard, PermissionsGuard)
export class PayrollController {
  constructor(private readonly payroll: PayrollService) {}

  @Get('runs')
  @RequirePermissions('payroll.view')
  list(@Param('establishmentId') establishmentId: string) {
    return this.payroll.list(establishmentId);
  }

  @Get('dashboard')
  @RequirePermissions('payroll.view')
  dashboard(
    @Param('establishmentId') establishmentId: string,
    @Query('year') year: string,
    @Query('month') month: string,
  ) {
    return this.payroll.dashboard(establishmentId, Number(year), Number(month));
  }

  @Post('runs')
  @RequirePermissions('payroll.manage')
  prepare(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Body() dto: PreparePayrollRunDto) {
    return this.payroll.prepare(establishmentId, request.user!.sub, dto);
  }

  @Patch('runs/:runId/lines/:lineId')
  @RequirePermissions('payroll.manage')
  updateLine(
    @Param('establishmentId') establishmentId: string,
    @Param('runId') runId: string,
    @Param('lineId') lineId: string,
    @Body() dto: UpdatePayrollLineDto,
  ) {
    return this.payroll.updateLine(establishmentId, runId, lineId, dto);
  }

  @Post('runs/:runId/validate')
  @RequirePermissions('payroll.manage')
  validate(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Param('runId') runId: string) {
    return this.payroll.validate(establishmentId, runId, request.user!.sub);
  }

  @Post('runs/:runId/pay')
  @RequirePermissions('payroll.manage')
  pay(@Req() request: Request, @Param('establishmentId') establishmentId: string, @Param('runId') runId: string) {
    return this.payroll.pay(establishmentId, runId, request.user!.sub);
  }

  @Post('runs/:runId/cancel')
  @RequirePermissions('payroll.manage')
  cancel(@Param('establishmentId') establishmentId: string, @Param('runId') runId: string) {
    return this.payroll.cancel(establishmentId, runId);
  }
}
```

- [ ] **Step 6: Module + enregistrement dans `app.module.ts`**

`apps/api/nestjs/src/payroll/payroll.module.ts` :

```typescript
import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module.js';
import { ActivityNotifierModule } from '../notifications/activity-notifier.module.js';
import { EmployeesController } from './employees.controller.js';
import { EmployeesService } from './employees.service.js';
import { PayrollController } from './payroll.controller.js';
import { PayrollService } from './payroll.service.js';

@Module({
  imports: [AuthModule, ActivityNotifierModule],
  controllers: [EmployeesController, PayrollController],
  providers: [EmployeesService, PayrollService],
})
export class PayrollModule {}
```

Dans `apps/api/nestjs/src/app.module.ts` : ajouter `import { PayrollModule } from './payroll/payroll.module.js';` et `PayrollModule` dans le tableau `imports` (juste après `ExpensesModule`, ligne ~32).

- [ ] **Step 7: Build + test complets**

Run: `cd apps/api/nestjs && npm run build && npm test`
Expected: build ✅, tous les tests passent (les existants + les nouveaux fichiers `payroll/`).

- [ ] **Step 8: Commit**

```bash
git add apps/api/nestjs/src/payroll/payroll.service.ts apps/api/nestjs/src/payroll/payroll.service.spec.ts apps/api/nestjs/src/payroll/payroll.controller.ts apps/api/nestjs/src/payroll/payroll.module.ts apps/api/nestjs/src/app.module.ts
git commit -m "feat(payroll): valider/payer/annuler une paie — paiement crée automatiquement la dépense Salaires (idempotent)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6 : Backend — synthèse par période pour l'onglet « Vue d'ensemble »

**Files:**
- Modify: `apps/api/nestjs/src/expenses/expenses.service.ts`, `apps/api/nestjs/src/expenses/expenses.service.spec.ts`

- [ ] **Step 1: Écrire les tests de `summary()` (échouent, méthode inexistante)**

Ajouter dans `expenses.service.spec.ts` :

```typescript
describe('ExpensesService.summary', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: ExpensesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new ExpensesService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('resolves a "month" period to that calendar month\'s bounds', async () => {
    (prisma.expense as any).findMany.mockResolvedValue([]);
    const result = await service.summary('est-1', { period: 'month', year: 2026, month: 9 });
    expect(result.from.toISOString().slice(0, 10)).toBe('2026-09-01');
    expect(result.to.toISOString().slice(0, 10)).toBe('2026-09-30');
  });

  it('splits totals: total, Salaires, Marché, and "charges fixes" (everything else)', async () => {
    (prisma.expense as any).findMany.mockResolvedValue([
      { category: 'Salaires', amount: { toNumber: () => 620000 }, expenseDate: new Date('2026-09-08') },
      { category: 'Marché', amount: { toNumber: () => 280000 }, expenseDate: new Date('2026-09-12') },
      { category: 'Loyer', amount: { toNumber: () => 150000 }, expenseDate: new Date('2026-09-01') },
      { category: 'Eau', amount: { toNumber: () => 18500 }, expenseDate: new Date('2026-09-10') },
    ]);
    const result = await service.summary('est-1', { period: 'month', year: 2026, month: 9 });
    expect(result.totalAmount).toBe(1068500);
    expect(result.totalSalaries).toBe(620000);
    expect(result.totalMarket).toBe(280000);
    expect(result.totalFixedCharges).toBe(168500);
  });

  it('computes a percentage-change comparison against the equivalent previous period', async () => {
    (prisma.expense as any).findMany
      .mockResolvedValueOnce([{ category: 'Loyer', amount: { toNumber: () => 200000 }, expenseDate: new Date('2026-09-01') }])
      .mockResolvedValueOnce([{ category: 'Loyer', amount: { toNumber: () => 100000 }, expenseDate: new Date('2026-08-01') }]);
    const result = await service.summary('est-1', { period: 'month', year: 2026, month: 9 });
    expect(result.totalAmount).toBe(200000);
    expect(result.previousTotalAmount).toBe(100000);
    expect(result.changePercent).toBe(100);
  });

  it('groups a category breakdown for the donut chart', async () => {
    (prisma.expense as any).findMany.mockResolvedValue([
      { category: 'Loyer', amount: { toNumber: () => 150000 }, expenseDate: new Date('2026-09-01') },
      { category: 'Loyer', amount: { toNumber: () => 50000 }, expenseDate: new Date('2026-09-05') },
      { category: null, amount: { toNumber: () => 10000 }, expenseDate: new Date('2026-09-06') },
    ]);
    const result = await service.summary('est-1', { period: 'month', year: 2026, month: 9 });
    expect(result.byCategory).toEqual(
      expect.arrayContaining([
        { category: 'Loyer', amount: 200000 },
        { category: 'Autre', amount: 10000 },
      ]),
    );
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/api/nestjs && npx vitest run src/expenses/expenses.service.spec.ts -t summary`
Expected: FAIL — `service.summary is not a function`

- [ ] **Step 3: Implémenter `resolveExpensePeriodRange` et `summary()`**

Ajouter en tête de `expenses.service.ts` (avant la classe) et dans la classe :

```typescript
export interface ExpensePeriodQuery {
  period: 'year' | 'month' | 'week';
  year: number;
  /** 1-12, requis seulement pour period === 'month'. */
  month?: number;
  /** ISO date (n'importe quel jour de la semaine visée), requis seulement pour period === 'week'. */
  weekOf?: string;
}

export interface ExpensePeriodRange {
  from: Date;
  to: Date;
}

/**
 * Résolution de bornes propre à ce module — dupliquée depuis un besoin
 * similaire dans ReportsService.resolveRange plutôt que factorisée, pour ne
 * jamais toucher reports.service.ts (contrainte explicite : ne pas modifier
 * le comportement d'un autre module). Lundi..dimanche pour "week", même
 * convention que ChartsService.mondayOf.
 */
export function resolveExpensePeriodRange(query: ExpensePeriodQuery): ExpensePeriodRange {
  if (query.period === 'year') {
    return { from: new Date(query.year, 0, 1, 0, 0, 0, 0), to: new Date(query.year, 11, 31, 23, 59, 59, 999) };
  }
  if (query.period === 'month') {
    const month = query.month ?? 1;
    return { from: new Date(query.year, month - 1, 1, 0, 0, 0, 0), to: new Date(query.year, month, 0, 23, 59, 59, 999) };
  }
  const reference = query.weekOf ? new Date(query.weekOf) : new Date();
  const weekdayIndex = (reference.getDay() + 6) % 7; // lundi = 0
  const monday = new Date(reference);
  monday.setHours(0, 0, 0, 0);
  monday.setDate(monday.getDate() - weekdayIndex);
  const sunday = new Date(monday);
  sunday.setDate(sunday.getDate() + 6);
  sunday.setHours(23, 59, 59, 999);
  return { from: monday, to: sunday };
}

/** Période équivalente immédiatement précédente — même durée, bornée juste avant `range.from`. */
function previousRange({ from, to }: ExpensePeriodRange): ExpensePeriodRange {
  const durationMs = to.getTime() - from.getTime();
  const previousTo = new Date(from.getTime() - 1);
  const previousFrom = new Date(previousTo.getTime() - durationMs);
  return { from: previousFrom, to: previousTo };
}
```

Dans la classe `ExpensesService`, ajouter :

```typescript
  /**
   * Synthèse pour l'onglet "Vue d'ensemble" : 4 totaux (dépenses totales,
   * Salaires, Marché, "charges fixes" = tout le reste), comparaison à la
   * période équivalente précédente, et répartition par nature pour le
   * donut chart. `category` regroupe null/vide sous "Autre".
   */
  async summary(establishmentId: string, query: ExpensePeriodQuery) {
    const range = resolveExpensePeriodRange(query);
    const previous = previousRange(range);

    const [expenses, previousExpenses] = await Promise.all([
      this.prisma.expense.findMany({
        where: { establishmentId, expenseDate: { gte: range.from, lte: range.to } },
        // Tous les champs de `Expense.fromJson` côté Flutter (Task 9) sont
        // nécessaires ici : `recent` (ci-dessous) est directement désérialisé
        // en `List<Expense>`, pas juste { category, amount, expenseDate } —
        // un select trop étroit ferait planter `Expense.fromJson` (id/label
        // manquants) au premier rendu de "Dernières dépenses" (Task 12).
        select: {
          id: true,
          label: true,
          category: true,
          amount: true,
          expenseDate: true,
          periodicity: true,
          note: true,
          marketNumber: true,
          paymentMethod: true,
          status: true,
        },
      }),
      this.prisma.expense.findMany({
        where: { establishmentId, expenseDate: { gte: previous.from, lte: previous.to } },
        select: { amount: true },
      }),
    ]);

    const sum = (list: { amount: { toNumber(): number } }[]) => list.reduce((s, e) => s + e.amount.toNumber(), 0);
    const totalAmount = sum(expenses);
    const totalSalaries = sum(expenses.filter((e) => e.category === 'Salaires'));
    const totalMarket = sum(expenses.filter((e) => e.category === 'Marché'));
    const totalFixedCharges = totalAmount - totalSalaries - totalMarket;
    const previousTotalAmount = sum(previousExpenses);
    const changePercent = previousTotalAmount > 0 ? ((totalAmount - previousTotalAmount) / previousTotalAmount) * 100 : null;

    const byCategoryMap = new Map<string, number>();
    for (const e of expenses) {
      const key = e.category?.trim() || 'Autre';
      byCategoryMap.set(key, (byCategoryMap.get(key) ?? 0) + e.amount.toNumber());
    }
    const byCategory = [...byCategoryMap.entries()].map(([category, amount]) => ({ category, amount }));

    return {
      from: range.from,
      to: range.to,
      totalAmount,
      totalSalaries,
      totalMarket,
      totalFixedCharges,
      previousTotalAmount,
      changePercent,
      byCategory,
      recent: [...expenses]
        .sort((a, b) => b.expenseDate.getTime() - a.expenseDate.getTime())
        .slice(0, 8),
    };
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/api/nestjs && npx vitest run src/expenses/expenses.service.spec.ts`
Expected: PASS (tous les tests, anciens + nouveaux)

- [ ] **Step 5: Commit**

```bash
git add apps/api/nestjs/src/expenses/expenses.service.ts apps/api/nestjs/src/expenses/expenses.service.spec.ts
git commit -m "feat(expenses): ExpensesService.summary — KPI, comparaison, répartition par nature

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7 : Backend — historique paginé/filtré + export Excel

**Files:**
- Modify: `apps/api/nestjs/src/expenses/expenses.service.ts`, `apps/api/nestjs/src/expenses/expenses.service.spec.ts`, `apps/api/nestjs/src/expenses/dto/expense.dto.ts`

- [ ] **Step 1: Étendre les DTOs (paymentMethod/status) et ajouter le DTO de requête d'historique**

Dans `expense.dto.ts`, ajouter à `CreateExpenseDto` et `UpdateExpenseDto` :

```typescript
  @IsOptional()
  @IsIn(['cash', 'mobile_money', 'bank_transfer'])
  paymentMethod?: string;

  @IsOptional()
  @IsIn(['paid', 'pending', 'cancelled'])
  status?: string;
```

Et un nouveau DTO en fin de fichier :

```typescript
export class ExpenseHistoryQueryDto {
  @IsOptional()
  @IsIn(['year', 'month', 'week'])
  period?: 'year' | 'month' | 'week';

  @IsOptional()
  year?: number;

  @IsOptional()
  month?: number;

  @IsOptional()
  weekOf?: string;

  @IsOptional()
  @IsString()
  category?: string;

  @IsOptional()
  @IsIn(['paid', 'pending', 'cancelled'])
  status?: string;

  @IsOptional()
  @IsIn(['cash', 'mobile_money', 'bank_transfer'])
  paymentMethod?: string;

  @IsOptional()
  page?: number;

  @IsOptional()
  pageSize?: number;
}
```

(Les query params HTTP arrivent en string ; `@Type(() => Number)` de `class-transformer` doit décorer `year`/`month`/`page`/`pageSize` pour la coercition — ajouter `import { Type } from 'class-transformer';` en tête et `@Type(() => Number)` juste au-dessus de chacun de ces 4 champs.)

- [ ] **Step 2: Écrire les tests d'historique + export (échouent)**

Ajouter dans `expenses.service.spec.ts` :

```typescript
describe('ExpensesService.history', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: ExpensesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    (prisma.expense as any).count = vi.fn();
    service = new ExpensesService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('paginates and filters by category/status/paymentMethod', async () => {
    (prisma.expense as any).findMany.mockResolvedValue([]);
    (prisma.expense as any).count.mockResolvedValue(28);
    const result = await service.history('est-1', {
      period: 'week',
      weekOf: '2026-09-10',
      category: 'Marché',
      status: 'paid',
      paymentMethod: 'cash',
      page: 1,
      pageSize: 8,
    });
    expect(prisma.expense.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ establishmentId: 'est-1', category: 'Marché', status: 'paid', paymentMethod: 'cash' }),
        skip: 0,
        take: 8,
      }),
    );
    expect(result.total).toBe(28);
    expect(result.page).toBe(1);
    expect(result.pageSize).toBe(8);
  });
});

describe('ExpensesService.exportHistoryExcel', () => {
  let prisma: ReturnType<typeof makePrismaMock>;
  let service: ExpensesService;

  beforeEach(() => {
    prisma = makePrismaMock();
    service = new ExpensesService(prisma as unknown as PrismaService, activityNotifierMock);
  });

  it('generates a workbook containing every filtered row, unpaginated', async () => {
    (prisma.expense as any).findMany.mockResolvedValue([
      {
        label: 'Achat de vivres',
        category: 'Marché',
        amount: { toNumber: () => 125000 },
        expenseDate: new Date('2026-09-12'),
        periodicity: 'one_off',
        paymentMethod: 'cash',
        status: 'paid',
      },
    ]);
    const { buffer, filename } = await service.exportHistoryExcel('est-1', { period: 'week', weekOf: '2026-09-10' });
    expect(buffer.length).toBeGreaterThan(0);
    expect(filename).toContain('.xlsx');
    expect(prisma.expense.findMany).toHaveBeenCalledWith(
      expect.not.objectContaining({ skip: expect.anything(), take: expect.anything() }),
    );
  });
});
```

- [ ] **Step 3: Run test to verify it fails**

Run: `cd apps/api/nestjs && npx vitest run src/expenses/expenses.service.spec.ts -t "history\|exportHistoryExcel"`
Expected: FAIL — `service.history`/`service.exportHistoryExcel` ne sont pas des fonctions.

- [ ] **Step 4: Implémenter `history()` et `exportHistoryExcel()`**

Ajouter en tête de `expenses.service.ts` : `import ExcelJS from 'exceljs';` et `import type { ExpenseHistoryQueryDto } from './dto/expense.dto.js';`.

Ajouter dans la classe :

```typescript
  private historyWhere(establishmentId: string, query: ExpenseHistoryQueryDto) {
    const hasPeriod = query.period && query.year;
    const range = hasPeriod
      ? resolveExpensePeriodRange({ period: query.period!, year: query.year!, month: query.month, weekOf: query.weekOf })
      : undefined;
    return {
      establishmentId,
      ...(range ? { expenseDate: { gte: range.from, lte: range.to } } : {}),
      ...(query.category ? { category: query.category } : {}),
      ...(query.status ? { status: query.status } : {}),
      ...(query.paymentMethod ? { paymentMethod: query.paymentMethod } : {}),
    };
  }

  async history(establishmentId: string, query: ExpenseHistoryQueryDto) {
    const where = this.historyWhere(establishmentId, query);
    const page = query.page && query.page > 0 ? query.page : 1;
    const pageSize = query.pageSize && query.pageSize > 0 ? query.pageSize : 8;
    const [items, total] = await Promise.all([
      this.prisma.expense.findMany({ where, orderBy: { expenseDate: 'desc' }, skip: (page - 1) * pageSize, take: pageSize }),
      this.prisma.expense.count({ where }),
    ]);
    return { items, total, page, pageSize };
  }

  /** Même pattern que ReportsService.beveragesSoldExcel — respecte les filtres actifs, jamais paginé (l'export contient tout ce qui correspond au filtre). */
  async exportHistoryExcel(establishmentId: string, query: ExpenseHistoryQueryDto): Promise<{ buffer: Buffer; filename: string }> {
    const where = this.historyWhere(establishmentId, query);
    const expenses = await this.prisma.expense.findMany({ where, orderBy: { expenseDate: 'desc' } });

    const workbook = new ExcelJS.Workbook();
    const sheet = workbook.addWorksheet('Historique des dépenses');
    sheet.columns = [
      { header: 'Date', key: 'date', width: 14 },
      { header: 'Libellé', key: 'label', width: 30 },
      { header: 'Nature', key: 'category', width: 18 },
      { header: 'Montant (FCFA)', key: 'amount', width: 18 },
      { header: 'Type', key: 'periodicity', width: 14 },
      { header: 'Mode de paiement', key: 'paymentMethod', width: 18 },
      { header: 'Statut', key: 'status', width: 14 },
    ];
    sheet.getRow(1).font = { bold: true };
    let total = 0;
    for (const e of expenses) {
      const amount = e.amount.toNumber();
      total += amount;
      sheet.addRow({
        date: e.expenseDate.toISOString().slice(0, 10),
        label: e.label,
        category: e.category ?? 'Autre',
        amount,
        periodicity: e.periodicity === 'recurring' ? 'Récurrente' : 'Ponctuelle',
        paymentMethod: e.paymentMethod,
        status: e.status,
      });
    }
    const totalRow = sheet.addRow({ label: 'TOTAL', amount: total });
    totalRow.font = { bold: true };

    const buffer = (await workbook.xlsx.writeBuffer()) as ExcelJS.Buffer;
    const pad = (n: number) => String(n).padStart(2, '0');
    const now = new Date();
    const filename = `Historique depenses ${pad(now.getDate())}-${pad(now.getMonth() + 1)}-${now.getFullYear()}.xlsx`;
    return { buffer: Buffer.from(buffer), filename };
  }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd apps/api/nestjs && npx vitest run src/expenses/expenses.service.spec.ts`
Expected: PASS (tous les tests)

- [ ] **Step 6: Commit**

```bash
git add apps/api/nestjs/src/expenses/expenses.service.ts apps/api/nestjs/src/expenses/expenses.service.spec.ts apps/api/nestjs/src/expenses/dto/expense.dto.ts
git commit -m "feat(expenses): historique paginé/filtré + export Excel respectant les filtres

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8 : Backend — câblage des routes + build/tests complets

**Files:**
- Modify: `apps/api/nestjs/src/expenses/expenses.controller.ts`

- [ ] **Step 1: Ajouter les 3 nouvelles routes**

Dans `expenses.controller.ts`, ajouter les imports `Query, Res` (déjà `Query` importé), `import type { Response } from 'express';`, `import { ExpenseHistoryQueryDto } from './dto/expense.dto.js';`, puis dans la classe (avant `@Post()`) :

```typescript
  @Get('summary')
  summary(
    @Param('establishmentId') establishmentId: string,
    @Query('period') period: 'year' | 'month' | 'week',
    @Query('year') year: string,
    @Query('month') month?: string,
    @Query('weekOf') weekOf?: string,
  ) {
    return this.expenses.summary(establishmentId, {
      period,
      year: Number(year),
      month: month ? Number(month) : undefined,
      weekOf,
    });
  }

  @Get('history')
  history(@Param('establishmentId') establishmentId: string, @Query() query: ExpenseHistoryQueryDto) {
    return this.expenses.history(establishmentId, query);
  }

  @Get('history.xlsx')
  async historyExcel(
    @Param('establishmentId') establishmentId: string,
    @Query() query: ExpenseHistoryQueryDto,
    @Res({ passthrough: true }) res: Response,
  ) {
    const { buffer, filename } = await this.expenses.exportHistoryExcel(establishmentId, query);
    res.set({
      'Content-Type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'Content-Disposition': `attachment; filename="${filename}"`,
    });
    return buffer;
  }
```

Ces 3 routes héritent de `@RequirePermissions('expenses.manage')` au niveau du contrôleur (inchangé — aucun rôle n'a aujourd'hui besoin d'une lecture seule des dépenses, voir audit).

- [ ] **Step 2: Build + suite de tests complète (backend)**

Run: `cd apps/api/nestjs && npm run lint && npm run build && npm test`
Expected: lint sans nouvelle erreur, build ✅, tous les tests passent.

- [ ] **Step 3: Commit**

```bash
git add apps/api/nestjs/src/expenses/expenses.controller.ts
git commit -m "feat(expenses): expose GET summary/history/history.xlsx

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 9 : Flutter — modèles et repositories (Dépenses étendu + Employés + Paie)

**Files:**
- Modify: `apps/web/flutter/lib/expenses/{expense_models.dart, expenses_repository.dart}`
- Create: `apps/web/flutter/lib/expenses/expense_summary_models.dart`, `apps/web/flutter/lib/payroll/employee_models.dart`, `apps/web/flutter/lib/payroll/employees_repository.dart`, `apps/web/flutter/lib/payroll/payroll_models.dart`, `apps/web/flutter/lib/payroll/payroll_repository.dart`

- [ ] **Step 1: Étendre `Expense` (paymentMethod/status)**

Dans `expense_models.dart`, ajouter les deux enums et champs :

```dart
enum ExpensePaymentMethod {
  cash('cash', 'Espèces'),
  mobileMoney('mobile_money', 'Mobile Money'),
  bankTransfer('bank_transfer', 'Virement');

  const ExpensePaymentMethod(this.value, this.label);
  final String value;
  final String label;

  static ExpensePaymentMethod fromValue(String? value) =>
      ExpensePaymentMethod.values.firstWhere((p) => p.value == value, orElse: () => ExpensePaymentMethod.cash);
}

enum ExpenseStatus {
  paid('paid', 'Payée'),
  pending('pending', 'En attente'),
  cancelled('cancelled', 'Annulée');

  const ExpenseStatus(this.value, this.label);
  final String value;
  final String label;

  static ExpenseStatus fromValue(String? value) =>
      ExpenseStatus.values.firstWhere((p) => p.value == value, orElse: () => ExpenseStatus.paid);
}
```

Dans la classe `Expense`, ajouter les champs `paymentMethod` et `status` (constructeur + `fromJson`) :

```dart
class Expense {
  Expense({
    required this.id,
    required this.label,
    this.category,
    required this.amount,
    required this.expenseDate,
    this.periodicity = ExpensePeriodicity.oneOff,
    this.note,
    this.marketNumber,
    this.paymentMethod = ExpensePaymentMethod.cash,
    this.status = ExpenseStatus.paid,
  });

  final String id;
  final String label;
  final String? category;
  final double amount;
  final DateTime expenseDate;
  final ExpensePeriodicity periodicity;
  final String? note;
  final int? marketNumber;
  final ExpensePaymentMethod paymentMethod;
  final ExpenseStatus status;

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'] as String,
        label: json['label'] as String,
        category: json['category'] as String?,
        amount: (json['amount'] as num).toDouble(),
        expenseDate: DateTime.parse(json['expenseDate'] as String),
        periodicity: ExpensePeriodicity.fromValue(json['periodicity'] as String?),
        note: json['note'] as String?,
        marketNumber: (json['marketNumber'] as num?)?.toInt(),
        paymentMethod: ExpensePaymentMethod.fromValue(json['paymentMethod'] as String?),
        status: ExpenseStatus.fromValue(json['status'] as String?),
      );
}
```

- [ ] **Step 2: Modèles de synthèse/historique**

`apps/web/flutter/lib/expenses/expense_summary_models.dart` :

```dart
import 'expense_models.dart';

class ExpenseCategoryAmount {
  ExpenseCategoryAmount({required this.category, required this.amount});
  final String category;
  final double amount;

  factory ExpenseCategoryAmount.fromJson(Map<String, dynamic> json) =>
      ExpenseCategoryAmount(category: json['category'] as String, amount: (json['amount'] as num).toDouble());
}

class ExpenseSummary {
  ExpenseSummary({
    required this.from,
    required this.to,
    required this.totalAmount,
    required this.totalSalaries,
    required this.totalMarket,
    required this.totalFixedCharges,
    required this.previousTotalAmount,
    this.changePercent,
    required this.byCategory,
    required this.recent,
  });

  final DateTime from;
  final DateTime to;
  final double totalAmount;
  final double totalSalaries;
  final double totalMarket;
  final double totalFixedCharges;
  final double previousTotalAmount;
  final double? changePercent;
  final List<ExpenseCategoryAmount> byCategory;
  final List<Expense> recent;

  factory ExpenseSummary.fromJson(Map<String, dynamic> json) => ExpenseSummary(
        from: DateTime.parse(json['from'] as String),
        to: DateTime.parse(json['to'] as String),
        totalAmount: (json['totalAmount'] as num).toDouble(),
        totalSalaries: (json['totalSalaries'] as num).toDouble(),
        totalMarket: (json['totalMarket'] as num).toDouble(),
        totalFixedCharges: (json['totalFixedCharges'] as num).toDouble(),
        previousTotalAmount: (json['previousTotalAmount'] as num).toDouble(),
        changePercent: (json['changePercent'] as num?)?.toDouble(),
        byCategory: (json['byCategory'] as List<dynamic>)
            .map((e) => ExpenseCategoryAmount.fromJson(e as Map<String, dynamic>))
            .toList(),
        recent: (json['recent'] as List<dynamic>).map((e) => Expense.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class ExpenseHistoryPage {
  ExpenseHistoryPage({required this.items, required this.total, required this.page, required this.pageSize});
  final List<Expense> items;
  final int total;
  final int page;
  final int pageSize;

  factory ExpenseHistoryPage.fromJson(Map<String, dynamic> json) => ExpenseHistoryPage(
        items: (json['items'] as List<dynamic>).map((e) => Expense.fromJson(e as Map<String, dynamic>)).toList(),
        total: json['total'] as int,
        page: json['page'] as int,
        pageSize: json['pageSize'] as int,
      );
}
```

- [ ] **Step 3: Étendre `ExpensesRepository`**

Dans `expenses_repository.dart`, ajouter (après les imports existants, `import 'expense_summary_models.dart';`) et dans la classe :

```dart
  Future<ExpenseSummary> getSummary({
    required String period,
    required int year,
    int? month,
    String? weekOf,
  }) async {
    final json = await _api.get('$_base/summary', query: {
      'period': period,
      'year': '$year',
      'month': ?month?.toString(),
      'weekOf': ?weekOf,
    }) as Map<String, dynamic>;
    return ExpenseSummary.fromJson(json);
  }

  Future<ExpenseHistoryPage> listHistory({
    String? period,
    int? year,
    int? month,
    String? weekOf,
    String? category,
    String? status,
    String? paymentMethod,
    int page = 1,
    int pageSize = 8,
  }) async {
    final json = await _api.get('$_base/history', query: {
      'period': ?period,
      'year': ?year?.toString(),
      'month': ?month?.toString(),
      'weekOf': ?weekOf,
      'category': ?category,
      'status': ?status,
      'paymentMethod': ?paymentMethod,
      'page': '$page',
      'pageSize': '$pageSize',
    }) as Map<String, dynamic>;
    return ExpenseHistoryPage.fromJson(json);
  }

  Future<({List<int> bytes, String? filename})> exportHistoryExcel({
    String? period,
    int? year,
    int? month,
    String? weekOf,
    String? category,
    String? status,
    String? paymentMethod,
  }) {
    return _api.getBytes('$_base/history.xlsx', query: {
      'period': ?period,
      'year': ?year?.toString(),
      'month': ?month?.toString(),
      'weekOf': ?weekOf,
      'category': ?category,
      'status': ?status,
      'paymentMethod': ?paymentMethod,
    });
  }
```

Étendre aussi `createExpense` avec les 2 nouveaux paramètres optionnels `paymentMethod`/`status` (défauts `ExpensePaymentMethod.cash`/`ExpenseStatus.paid`), transmis dans le `body` (`'paymentMethod': paymentMethod.value, 'status': status.value`) — même style que `periodicity` déjà présent.

- [ ] **Step 4: Modèles + repository Employés**

`apps/web/flutter/lib/payroll/employee_models.dart` :

```dart
class Employee {
  Employee({
    required this.id,
    required this.lastName,
    required this.firstName,
    this.gender,
    this.birthDate,
    required this.phone,
    this.address,
    this.photoUrl,
    required this.position,
    required this.hireDate,
    this.contractType,
    required this.weeklySalary,
    this.team,
    this.registrationNumber,
    this.notes,
    this.status = 'active',
  });

  final String id;
  final String lastName;
  final String firstName;
  final String? gender;
  final DateTime? birthDate;
  final String phone;
  final String? address;
  final String? photoUrl;
  final String position;
  final DateTime hireDate;
  final String? contractType;
  final double weeklySalary;
  final String? team;
  final String? registrationNumber;
  final String? notes;
  final String status;

  String get fullName => '$lastName $firstName';
  bool get isActive => status == 'active';

  factory Employee.fromJson(Map<String, dynamic> json) => Employee(
        id: json['id'] as String,
        lastName: json['lastName'] as String,
        firstName: json['firstName'] as String,
        gender: json['gender'] as String?,
        birthDate: json['birthDate'] != null ? DateTime.parse(json['birthDate'] as String) : null,
        phone: json['phone'] as String,
        address: json['address'] as String?,
        photoUrl: json['photoUrl'] as String?,
        position: json['position'] as String,
        hireDate: DateTime.parse(json['hireDate'] as String),
        contractType: json['contractType'] as String?,
        weeklySalary: (json['weeklySalary'] as num).toDouble(),
        team: json['team'] as String?,
        registrationNumber: json['registrationNumber'] as String?,
        notes: json['notes'] as String?,
        status: json['status'] as String? ?? 'active',
      );
}
```

`apps/web/flutter/lib/payroll/employees_repository.dart` :

```dart
import '../api/api_client.dart';
import 'employee_models.dart';

/// Correspond à apps/api/nestjs/src/payroll/employees.controller.ts.
class EmployeesRepository {
  EmployeesRepository(this._api, this.establishmentId);

  final ApiClient _api;
  final String establishmentId;

  String get _base => '/establishments/$establishmentId/employees';

  Future<List<Employee>> listEmployees() async {
    final json = await _api.get(_base) as List<dynamic>;
    return json.map((e) => Employee.fromJson(e as Map<String, dynamic>)).toList();
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<Employee> createEmployee({
    required String lastName,
    required String firstName,
    String? gender,
    DateTime? birthDate,
    required String phone,
    String? address,
    required String position,
    required DateTime hireDate,
    String? contractType,
    required double weeklySalary,
    String? team,
    String? registrationNumber,
    String? notes,
  }) async {
    final json = await _api.post(_base, body: {
      'lastName': lastName,
      'firstName': firstName,
      'gender': ?gender,
      'birthDate': ?(birthDate != null ? _dateOnly(birthDate) : null),
      'phone': phone,
      'address': ?address,
      'position': position,
      'hireDate': _dateOnly(hireDate),
      'contractType': ?contractType,
      'weeklySalary': weeklySalary,
      'team': ?team,
      'registrationNumber': ?registrationNumber,
      'notes': ?notes,
    }) as Map<String, dynamic>;
    return Employee.fromJson(json);
  }

  Future<Employee> updateEmployee(String employeeId, Map<String, dynamic> data) async {
    final json = await _api.patch('$_base/$employeeId', body: data) as Map<String, dynamic>;
    return Employee.fromJson(json);
  }

  Future<Employee> setStatus(String employeeId, String status) => updateEmployee(employeeId, {'status': status});
}
```

- [ ] **Step 5: Modèles + repository Paie**

`apps/web/flutter/lib/payroll/payroll_models.dart` :

```dart
class PayrollDashboard {
  PayrollDashboard({
    required this.employeeCount,
    required this.massSalariale,
    required this.totalPaid,
    required this.remaining,
  });
  final int employeeCount;
  final double massSalariale;
  final double totalPaid;
  final double remaining;

  factory PayrollDashboard.fromJson(Map<String, dynamic> json) => PayrollDashboard(
        employeeCount: json['employeeCount'] as int,
        massSalariale: (json['massSalariale'] as num).toDouble(),
        totalPaid: (json['totalPaid'] as num).toDouble(),
        remaining: (json['remaining'] as num).toDouble(),
      );
}

class PayrollLine {
  PayrollLine({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.baseSalary,
    required this.advance,
    required this.adjustment,
    required this.netAmount,
  });
  final String id;
  final String employeeId;
  final String employeeName;
  final double baseSalary;
  final double advance;
  final double adjustment;
  final double netAmount;

  factory PayrollLine.fromJson(Map<String, dynamic> json) {
    final employee = json['employee'] as Map<String, dynamic>;
    return PayrollLine(
      id: json['id'] as String,
      employeeId: json['employeeId'] as String,
      employeeName: '${employee['lastName']} ${employee['firstName']}',
      baseSalary: (json['baseSalary'] as num).toDouble(),
      advance: (json['advance'] as num).toDouble(),
      adjustment: (json['adjustment'] as num).toDouble(),
      netAmount: (json['netAmount'] as num).toDouble(),
    );
  }
}

/// 'prepared' | 'validated' | 'paid' | 'cancelled'.
class PayrollRun {
  PayrollRun({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    required this.status,
    required this.lines,
  });
  final String id;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String status;
  final List<PayrollLine> lines;

  double get total => lines.fold(0, (sum, l) => sum + l.netAmount);

  factory PayrollRun.fromJson(Map<String, dynamic> json) => PayrollRun(
        id: json['id'] as String,
        periodStart: DateTime.parse(json['periodStart'] as String),
        periodEnd: DateTime.parse(json['periodEnd'] as String),
        status: json['status'] as String,
        lines: (json['lines'] as List<dynamic>).map((e) => PayrollLine.fromJson(e as Map<String, dynamic>)).toList(),
      );
}
```

`apps/web/flutter/lib/payroll/payroll_repository.dart` :

```dart
import '../api/api_client.dart';
import 'payroll_models.dart';

/// Correspond à apps/api/nestjs/src/payroll/payroll.controller.ts.
class PayrollRepository {
  PayrollRepository(this._api, this.establishmentId);

  final ApiClient _api;
  final String establishmentId;

  String get _base => '/establishments/$establishmentId/payroll';

  Future<PayrollDashboard> getDashboard({required int year, required int month}) async {
    final json = await _api.get('$_base/dashboard', query: {'year': '$year', 'month': '$month'}) as Map<String, dynamic>;
    return PayrollDashboard.fromJson(json);
  }

  Future<List<PayrollRun>> listRuns() async {
    final json = await _api.get('$_base/runs') as List<dynamic>;
    return json.map((e) => PayrollRun.fromJson(e as Map<String, dynamic>)).toList();
  }

  String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<PayrollRun> prepare({required DateTime periodStart, required DateTime periodEnd}) async {
    final json = await _api.post('$_base/runs', body: {
      'periodStart': _dateOnly(periodStart),
      'periodEnd': _dateOnly(periodEnd),
    }) as Map<String, dynamic>;
    return PayrollRun.fromJson(json);
  }

  Future<void> updateLine(String runId, String lineId, {required double advance, required double adjustment}) {
    return _api.patch('$_base/runs/$runId/lines/$lineId', body: {'advance': advance, 'adjustment': adjustment});
  }

  Future<void> validate(String runId) => _api.post('$_base/runs/$runId/validate');

  Future<void> pay(String runId) => _api.post('$_base/runs/$runId/pay');

  Future<void> cancel(String runId) => _api.post('$_base/runs/$runId/cancel');
}
```

- [ ] **Step 6: Vérifier l'analyse statique**

Run: `cd apps/web/flutter && export PATH="$PATH:/c/Users/Yuzki/Downloads/flutter_sdk/bin" && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add apps/web/flutter/lib/expenses/expense_models.dart apps/web/flutter/lib/expenses/expenses_repository.dart apps/web/flutter/lib/expenses/expense_summary_models.dart apps/web/flutter/lib/payroll/
git commit -m "feat(expenses,payroll): modèles et repositories Flutter (synthèse, historique, employés, paie)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 10 : Flutter — `ExpensesPage` en coquille à 4 onglets (extraction verbatim)

**Files:**
- Create: `apps/web/flutter/lib/expenses/expenses_form_tab.dart`
- Modify: `apps/web/flutter/lib/expenses/expenses_page.dart`
- Modify: `apps/web/flutter/test/expenses_page_test.dart`

- [ ] **Step 1: Extraire le corps actuel de `ExpensesPage` tel quel dans `ExpensesFormTab`**

Créer `expenses_form_tab.dart` en copiant **intégralement** le contenu actuel de `expenses_page.dart` (lignes 1-289), avec deux seuls changements mécaniques :
1. Renommer `ExpensesPage` → `ExpensesFormTab` et `_ExpensesPageState` → `_ExpensesFormTabState` (partout, y compris `createState()`).
2. Retirer le `Scaffold`/`AppBar` englobants dans `build()` : remplacer

```dart
    return Scaffold(
      appBar: AppBar(title: const Text('Dépenses')),
      body: Column(
```

par

```dart
    return Column(
```

et supprimer les deux fermetures correspondantes en fin de méthode (`),\n      floatingActionButton: FloatingActionButton(onPressed: _addExpense, child: const Icon(Icons.add)),\n    );` → remplacer par un `Stack` avec un `Align` pour le FAB, puisqu'un onglet n'a pas son propre `Scaffold` :

```dart
  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    return Stack(
      children: [
        Column(
          children: [
            SyncStatusBar(syncQueue: _syncQueue),
            Expanded(
              child: FutureBuilder<List<Expense>>(
                future: _future,
                builder: (context, snapshot) {
                  // ... corps inchangé, voir ci-dessous ...
                },
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(onPressed: _addExpense, child: const Icon(Icons.add)),
        ),
      ],
    );
  }
```

Le contenu du `FutureBuilder.builder` (état vide, liste, dialogue `_addExpense`, `_deleteExpense`) reste identique caractère pour caractère — **aucune autre ligne ne change**, garantissant zéro régression comportementale sur cet onglet.

- [ ] **Step 2: Réécrire `ExpensesPage` comme coquille à 4 onglets**

`apps/web/flutter/lib/expenses/expenses_page.dart` (remplace tout le fichier) :

```dart
import 'package:flutter/material.dart';

import 'expenses_form_tab.dart';
import 'expenses_history_tab.dart';
import 'expenses_overview_tab.dart';
import '../payroll/payroll_tab.dart';

/// Module Dépenses restructuré en 4 sous-onglets (demande utilisateur du
/// 2026-09-12, voir docs/api/expenses.md) : Vue d'ensemble, Dépenses,
/// Salaires, Historique. `ExpensesFormTab` est une extraction verbatim de
/// l'ancien écran (aucun changement de comportement).
class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dépenses'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: "Vue d'ensemble"),
            Tab(text: 'Dépenses'),
            Tab(text: 'Salaires'),
            Tab(text: 'Historique'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          ExpensesOverviewTab(establishmentId: widget.establishmentId),
          ExpensesFormTab(establishmentId: widget.establishmentId),
          PayrollTab(establishmentId: widget.establishmentId),
          ExpensesHistoryTab(establishmentId: widget.establishmentId),
        ],
      ),
    );
  }
}
```

(Note : `ExpensesFormTab` garde `establishmentId` comme paramètre nommé requis, identique à l'ancien `ExpensesPage`.)

- [ ] **Step 3: Adapter le test existant à la nouvelle structure**

Dans `apps/web/flutter/test/expenses_page_test.dart`, chaque test qui pompait directement `ExpensesPage` doit maintenant soit :
- naviguer vers l'onglet "Dépenses" avant d'interagir (`await tester.tap(find.text('Dépenses')); await tester.pumpAndSettle();`), soit
- être déplacé pour tester `ExpensesFormTab` directement (`pumpWidget(MaterialApp(home: Scaffold(body: ExpensesFormTab(establishmentId: 'est-1'))))`) plutôt que `ExpensesPage`.

Choisir la seconde option (plus simple, isole le test de la coquille à onglets) : remplacer partout `ExpensesPage(establishmentId: ...)` par `ExpensesFormTab(establishmentId: ...)` et l'import correspondant (`import 'package:chez_yasmine/expenses/expenses_form_tab.dart';` au lieu de `expenses_page.dart`).

- [ ] **Step 4: Placeholders temporaires pour les 3 nouveaux onglets (retirés aux tâches suivantes)**

Pour que le projet compile avant l'implémentation réelle des Tasks 11-15, créer temporairement (contenu minimal, remplacé task par task) :

`apps/web/flutter/lib/expenses/expenses_overview_tab.dart` :
```dart
import 'package:flutter/material.dart';

class ExpensesOverviewTab extends StatelessWidget {
  const ExpensesOverviewTab({super.key, required this.establishmentId});
  final String establishmentId;

  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}
```

`apps/web/flutter/lib/expenses/expenses_history_tab.dart` : même contenu, classe `ExpensesHistoryTab`.

`apps/web/flutter/lib/payroll/payroll_tab.dart` : même contenu, classe `PayrollTab`.

(Ces 3 fichiers sont réécrits avec leur vraie implémentation dans les Tasks 12, 13, 14 respectivement.)

- [ ] **Step 5: Vérifier**

Run: `cd apps/web/flutter && export PATH="$PATH:/c/Users/Yuzki/Downloads/flutter_sdk/bin" && flutter analyze && flutter test test/expenses_page_test.dart`
Expected: `No issues found!`, tous les tests passent.

- [ ] **Step 6: Commit**

```bash
git add apps/web/flutter/lib/expenses/ apps/web/flutter/lib/payroll/payroll_tab.dart apps/web/flutter/test/expenses_page_test.dart
git commit -m "refactor(expenses): ExpensesPage en coquille à 4 onglets, formulaire existant extrait verbatim

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 11 : Flutter — widget donut chart (répartition par nature)

**Files:**
- Create: `apps/web/flutter/lib/expenses/expense_category_donut_chart.dart`
- Test: `apps/web/flutter/test/expense_category_donut_chart_test.dart`

- [ ] **Step 1: Écrire le test (échoue, widget inexistant)**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chez_yasmine/expenses/expense_category_donut_chart.dart';
import 'package:chez_yasmine/expenses/expense_summary_models.dart';

void main() {
  testWidgets('shows an empty state when there is no data', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ExpenseCategoryDonutChart(items: []))),
    );
    expect(find.text('Aucune donnée pour cette période'), findsOneWidget);
  });

  testWidgets('shows one legend entry per category with its percentage', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpenseCategoryDonutChart(
            items: [
              ExpenseCategoryAmount(category: 'Salaires', amount: 620000),
              ExpenseCategoryAmount(category: 'Marché', amount: 280000),
            ],
          ),
        ),
      ),
    );
    expect(find.textContaining('Salaires'), findsOneWidget);
    expect(find.textContaining('69'), findsOneWidget); // 620000 / 900000 ≈ 68.9%
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/web/flutter && flutter test test/expense_category_donut_chart_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:chez_yasmine/expenses/expense_category_donut_chart.dart'`

- [ ] **Step 3: Implémenter le widget**

```dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../common/formatting.dart';
import '../theme/app_theme.dart';
import 'expense_summary_models.dart';

const _paletteColors = [
  AppColors.green,
  AppColors.orange,
  Color(0xFF3B82F6),
  Color(0xFFA855F7),
  Color(0xFFEAB308),
  AppColors.alert,
  Color(0xFF14B8A6),
  Color(0xFF6B7280),
];

/// Répartition des dépenses par nature (Vue d'ensemble) — anneau via
/// `fl_chart` (déjà en dépendance, `PieChart`), avec légende manuelle
/// (montant + pourcentage), pas de camembert/anneau réutilisable ailleurs
/// dans l'app à ce jour.
class ExpenseCategoryDonutChart extends StatelessWidget {
  const ExpenseCategoryDonutChart({super.key, required this.items});

  final List<ExpenseCategoryAmount> items;

  @override
  Widget build(BuildContext context) {
    final total = items.fold<double>(0, (sum, i) => sum + i.amount);
    if (items.isEmpty || total <= 0) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('Aucune donnée pour cette période')),
      );
    }
    final sorted = [...items]..sort((a, b) => b.amount.compareTo(a.amount));

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 48,
              sections: [
                for (var i = 0; i < sorted.length; i++)
                  PieChartSectionData(
                    value: sorted[i].amount,
                    color: _paletteColors[i % _paletteColors.length],
                    title: '',
                    radius: 36,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < sorted.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(width: 10, height: 10, color: _paletteColors[i % _paletteColors.length]),
                const SizedBox(width: 8),
                Expanded(child: Text(sorted[i].category)),
                Text(
                  '${formatAmount(sorted[i].amount)} FCFA — ${(sorted[i].amount / total * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/web/flutter && flutter test test/expense_category_donut_chart_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add apps/web/flutter/lib/expenses/expense_category_donut_chart.dart apps/web/flutter/test/expense_category_donut_chart_test.dart
git commit -m "feat(expenses): donut chart de répartition par nature (fl_chart)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 12 : Flutter — onglet « Vue d'ensemble »

**Files:**
- Modify: `apps/web/flutter/lib/expenses/expenses_overview_tab.dart` (remplace le placeholder de Task 10)
- Test: `apps/web/flutter/test/expenses_overview_tab_test.dart`

- [ ] **Step 1: Écrire un test de sélection de période (échoue, comportement placeholder)**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chez_yasmine/expenses/expenses_overview_tab.dart';

void main() {
  testWidgets('shows an error state without crashing when no backend is reachable in test', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ExpensesOverviewTab(establishmentId: 'est-1'))),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('defaults to "Mois" and offers Année/Mois/Semaine', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ExpensesOverviewTab(establishmentId: 'est-1'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Année'), findsOneWidget);
    expect(find.text('Mois'), findsOneWidget);
    expect(find.text('Semaine'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/web/flutter && flutter test test/expenses_overview_tab_test.dart`
Expected: FAIL — le placeholder n'affiche ni "Année" ni "Mois"/"Semaine" (spinner infini, pas d'appel réseau réel en test → `CircularProgressIndicator` reste affiché indéfiniment).

- [ ] **Step 3: Implémenter `ExpensesOverviewTab`**

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../common/formatting.dart';
import '../theme/app_theme.dart';
import 'expense_category_donut_chart.dart';
import 'expense_summary_models.dart';
import 'expenses_repository.dart';

const _weekdayLabels = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

DateTime _mondayOf(DateTime date) {
  final weekdayIndex = (date.weekday - 1) % 7; // lundi = 0
  return DateTime(date.year, date.month, date.day).subtract(Duration(days: weekdayIndex));
}

/// Tableau de bord analytique des dépenses (demande utilisateur du
/// 2026-09-12) : filtre Année/Mois/Semaine avec navigation précédent/suivant,
/// 4 KPI, donut de répartition par nature, dernières dépenses.
class ExpensesOverviewTab extends StatefulWidget {
  const ExpensesOverviewTab({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<ExpensesOverviewTab> createState() => _ExpensesOverviewTabState();
}

class _ExpensesOverviewTabState extends State<ExpensesOverviewTab> {
  late final ExpensesRepository _repository = ExpensesRepository(ApiClient(), widget.establishmentId);

  String _period = 'month';
  var _year = DateTime.now().year;
  var _month = DateTime.now().month;
  var _weekOf = _mondayOf(DateTime.now());

  late Future<ExpenseSummary> _future = _load();

  Future<ExpenseSummary> _load() {
    return _repository.getSummary(
      period: _period,
      year: _year,
      month: _period == 'month' ? _month : null,
      weekOf: _period == 'week' ? _weekOf.toIso8601String().slice0to10() : null,
    );
  }

  void _reload() {
    final future = _load();
    future.ignore();
    setState(() => _future = future);
  }

  void _changePeriod(String period) {
    _period = period;
    _reload();
  }

  void _shift(int direction) {
    switch (_period) {
      case 'year':
        _year += direction;
        break;
      case 'month':
        final next = DateTime(_year, _month + direction, 1);
        _year = next.year;
        _month = next.month;
        break;
      case 'week':
        _weekOf = _weekOf.add(Duration(days: 7 * direction));
        break;
    }
    _reload();
  }

  String get _periodLabel {
    switch (_period) {
      case 'year':
        return '$_year';
      case 'month':
        const months = [
          'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
          'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
        ];
        return '${months[_month - 1]} $_year';
      default:
        final sunday = _weekOf.add(const Duration(days: 6));
        final fmt = DateFormat('dd/MM/yyyy');
        return 'Du ${fmt.format(_weekOf)} au ${fmt.format(sunday)}';
    }
  }

  Widget _kpiCard(String label, double value, {double? changePercent, Color color = AppColors.green}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            const SizedBox(height: 6),
            Text('${formatAmount(value)} F', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            if (changePercent != null) ...[
              const SizedBox(height: 2),
              Text(
                '${changePercent >= 0 ? '↑ +' : '↓ '}${changePercent.toStringAsFixed(1)} % vs période précédente',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: changePercent >= 0 ? AppColors.green : AppColors.alert,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'year', label: Text('Année')),
              ButtonSegment(value: 'month', label: Text('Mois')),
              ButtonSegment(value: 'week', label: Text('Semaine')),
            ],
            selected: {_period},
            onSelectionChanged: (s) => _changePeriod(s.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _shift(-1)),
              Expanded(child: Center(child: Text(_periodLabel, style: const TextStyle(fontWeight: FontWeight.w600)))),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _shift(1)),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<ExpenseSummary>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : '${snapshot.error}';
                return Center(child: Text(message));
              }
              final s = snapshot.data!;
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    GridView(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        mainAxisExtent: 92,
                      ),
                      children: [
                        _kpiCard('Total des dépenses', s.totalAmount, changePercent: s.changePercent, color: AppColors.green),
                        _kpiCard('Total des salaires', s.totalSalaries, color: AppColors.orange),
                        _kpiCard('Achats / Marché', s.totalMarket, color: AppColors.green),
                        _kpiCard('Charges fixes', s.totalFixedCharges, color: AppColors.orange),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Text('RÉPARTITION PAR NATURE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    Card(child: Padding(padding: const EdgeInsets.all(12), child: ExpenseCategoryDonutChart(items: s.byCategory))),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('DERNIÈRES DÉPENSES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textSecondary)),
                        TextButton(
                          onPressed: () => DefaultTabController.of(context).animateTo(3),
                          child: const Text('Voir tout →'),
                        ),
                      ],
                    ),
                    if (s.recent.isEmpty)
                      const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Aucune dépense sur cette période.'))
                    else
                      Card(
                        child: Column(
                          children: [
                            for (final e in s.recent)
                              ListTile(
                                title: Text(e.label),
                                subtitle: Text('${e.category ?? 'Autre'} — ${DateFormat('dd/MM/yyyy').format(e.expenseDate)}'),
                                trailing: Text('${formatAmount(e.amount)} F', style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

extension on String {
  String slice0to10() => length > 10 ? substring(0, 10) : this;
}
```

**Note d'implémentation** : `DefaultTabController.of(context).animateTo(3)` suppose que `ExpensesPage` (Task 10) enveloppe son `TabBarView` dans un `DefaultTabController` accessible aux enfants — **corriger Task 10** : remplacer, dans `_ExpensesPageState`, la gestion manuelle du `TabController` par `DefaultTabController` (retirer `with SingleTickerProviderStateMixin`, `late final TabController _tabController = ...`, `dispose()`, et dans `build()` englober `Scaffold` dans `DefaultTabController(length: 4, child: Scaffold(...))`, puis remplacer `controller: _tabController` par rien — `TabBar`/`TabBarView` prennent le contrôleur par défaut automatiquement via `DefaultTabController.of(context)`).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/web/flutter && flutter test test/expenses_overview_tab_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Analyse + build**

Run: `cd apps/web/flutter && flutter analyze && flutter build web`
Expected: `No issues found!`, build réussi.

- [ ] **Step 6: Commit**

```bash
git add apps/web/flutter/lib/expenses/expenses_overview_tab.dart apps/web/flutter/lib/expenses/expenses_page.dart apps/web/flutter/test/expenses_overview_tab_test.dart
git commit -m "feat(expenses): onglet Vue d'ensemble — filtres Année/Mois/Semaine, KPI, donut, dernières dépenses

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 13 : Flutter — onglet « Historique »

**Files:**
- Modify: `apps/web/flutter/lib/expenses/expenses_history_tab.dart` (remplace le placeholder de Task 10)
- Test: `apps/web/flutter/test/expenses_history_tab_test.dart`

- [ ] **Step 1: Écrire un test de pagination/état vide (échoue, placeholder)**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chez_yasmine/expenses/expenses_history_tab.dart';

void main() {
  testWidgets('shows a "Filtrer" action and an "Exporter Excel" button', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ExpensesHistoryTab(establishmentId: 'est-1'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Filtrer'), findsOneWidget);
    expect(find.text('Exporter Excel'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/web/flutter && flutter test test/expenses_history_tab_test.dart`
Expected: FAIL — le placeholder n'affiche ni "Filtrer" ni "Exporter Excel".

- [ ] **Step 3: Implémenter `ExpensesHistoryTab`**

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../common/browser_download.dart';
import '../common/formatting.dart';
import '../theme/app_theme.dart';
import 'expense_models.dart';
import 'expense_summary_models.dart';
import 'expenses_repository.dart';

/// Historique paginé/filtré (demande utilisateur du 2026-09-12) — filtres
/// Nature/Statut/Mode de paiement, export Excel respectant les filtres actifs.
class ExpensesHistoryTab extends StatefulWidget {
  const ExpensesHistoryTab({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<ExpensesHistoryTab> createState() => _ExpensesHistoryTabState();
}

class _ExpensesHistoryTabState extends State<ExpensesHistoryTab> {
  late final ExpensesRepository _repository = ExpensesRepository(ApiClient(), widget.establishmentId);

  String? _category;
  String? _status;
  String? _paymentMethod;
  var _page = 1;
  static const _pageSize = 8;

  late Future<ExpenseHistoryPage> _future = _load();

  Future<ExpenseHistoryPage> _load() {
    return _repository.listHistory(
      category: _category,
      status: _status,
      paymentMethod: _paymentMethod,
      page: _page,
      pageSize: _pageSize,
    );
  }

  void _reload() {
    final future = _load();
    future.ignore();
    setState(() => _future = future);
  }

  Future<void> _openFilters() async {
    var category = _category;
    var status = _status;
    var paymentMethod = _paymentMethod;
    final applied = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Filtrer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String?>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Nature'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Toutes')),
                  ...kPredefinedExpenseCategories,
                ].map((c) => c is String ? DropdownMenuItem(value: c, child: Text(c)) : c as DropdownMenuItem<String?>).toList(),
                onChanged: (v) => setDialogState(() => category = v),
              ),
              DropdownButtonFormField<String?>(
                initialValue: status,
                decoration: const InputDecoration(labelText: 'Statut'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tous')),
                  for (final s in ExpenseStatus.values) DropdownMenuItem(value: s.value, child: Text(s.label)),
                ],
                onChanged: (v) => setDialogState(() => status = v),
              ),
              DropdownButtonFormField<String?>(
                initialValue: paymentMethod,
                decoration: const InputDecoration(labelText: 'Mode de paiement'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Tous')),
                  for (final m in ExpensePaymentMethod.values) DropdownMenuItem(value: m.value, child: Text(m.label)),
                ],
                onChanged: (v) => setDialogState(() => paymentMethod = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Appliquer')),
          ],
        ),
      ),
    );
    if (applied != true) return;
    setState(() {
      _category = category;
      _status = status;
      _paymentMethod = paymentMethod;
      _page = 1;
    });
    _reload();
  }

  Future<void> _export() async {
    try {
      final result = await _repository.exportHistoryExcel(
        category: _category,
        status: _status,
        paymentMethod: _paymentMethod,
      );
      downloadBytes(result.bytes, result.filename ?? 'Historique depenses.xlsx');
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              OutlinedButton.icon(onPressed: _openFilters, icon: const Icon(Icons.filter_list), label: const Text('Filtrer')),
              const Spacer(),
              FilledButton.icon(onPressed: _export, icon: const Icon(Icons.download_outlined), label: const Text('Exporter Excel')),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<ExpenseHistoryPage>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : '${snapshot.error}';
                return Center(child: Text(message));
              }
              final page = snapshot.data!;
              if (page.items.isEmpty) {
                return const Center(child: Text('Aucune dépense pour ce filtre.'));
              }
              final lastPage = (page.total / page.pageSize).ceil().clamp(1, 1 << 30);
              return Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('N°')),
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Libellé')),
                          DataColumn(label: Text('Nature')),
                          DataColumn(label: Text('Montant'), numeric: true),
                          DataColumn(label: Text('Type')),
                          DataColumn(label: Text('Mode de paiement')),
                          DataColumn(label: Text('Statut')),
                        ],
                        rows: [
                          for (var i = 0; i < page.items.length; i++)
                            DataRow(
                              cells: [
                                DataCell(Text('${(page.page - 1) * page.pageSize + i + 1}')),
                                DataCell(Text(dateFormat.format(page.items[i].expenseDate))),
                                DataCell(Text(page.items[i].label)),
                                DataCell(Text(page.items[i].category ?? 'Autre')),
                                DataCell(Text('${formatAmount(page.items[i].amount)} F')),
                                DataCell(Text(page.items[i].periodicity.label)),
                                DataCell(Text(page.items[i].paymentMethod.label)),
                                DataCell(Text(page.items[i].status.label)),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Affichage de ${(page.page - 1) * page.pageSize + 1} à '
                          '${((page.page - 1) * page.pageSize + page.items.length)} sur ${page.total} enregistrements',
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: page.page > 1 ? () { setState(() => _page--); _reload(); } : null,
                        ),
                        Text('${page.page} / $lastPage'),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: page.page < lastPage ? () { setState(() => _page++); _reload(); } : null,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/web/flutter && flutter test test/expenses_history_tab_test.dart`
Expected: PASS

- [ ] **Step 5: Analyse + build**

Run: `cd apps/web/flutter && flutter analyze && flutter build web`
Expected: `No issues found!`, build réussi.

- [ ] **Step 6: Commit**

```bash
git add apps/web/flutter/lib/expenses/expenses_history_tab.dart apps/web/flutter/test/expenses_history_tab_test.dart
git commit -m "feat(expenses): onglet Historique — filtres, pagination, export Excel

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 14 : Flutter — onglet « Salaires » (dashboard + CRUD employés)

**Files:**
- Modify: `apps/web/flutter/lib/payroll/payroll_tab.dart` (remplace le placeholder de Task 10)
- Create: `apps/web/flutter/lib/payroll/employee_form_dialog.dart`
- Test: `apps/web/flutter/test/employee_form_dialog_test.dart`

- [ ] **Step 1: Écrire un test de validation du formulaire employé (échoue, fichier inexistant)**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chez_yasmine/payroll/employee_form_dialog.dart';

void main() {
  testWidgets('rejects submit with an invalid Côte d\'Ivoire phone number', (tester) async {
    late Future<Map<String, dynamic>?> result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => result = showEmployeeFormDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Nom *'), 'Koffi');
    await tester.enterText(find.widgetWithText(TextFormField, 'Prénoms *'), 'Awa');
    await tester.enterText(find.widgetWithText(TextFormField, 'Téléphone *'), '123');
    await tester.enterText(find.widgetWithText(TextFormField, 'Poste *'), 'Cuisinière');
    await tester.enterText(find.widgetWithText(TextFormField, 'Salaire hebdomadaire *'), '30000');
    await tester.tap(find.text('Enregistrer'));
    await tester.pump();

    expect(find.textContaining('téléphone'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/web/flutter && flutter test test/employee_form_dialog_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implémenter `employee_form_dialog.dart`**

```dart
import 'package:flutter/material.dart';

final _ciPhoneRegex = RegExp(r'^0\d{9}$');

/// Formulaire de création d'un employé — champs alignés sur
/// apps/api/nestjs/src/payroll/dto/employee.dto.ts. Retourne un `Map` prêt à
/// passer à `EmployeesRepository.createEmployee`, ou `null` si annulé.
Future<Map<String, dynamic>?> showEmployeeFormDialog(BuildContext context) {
  final lastNameController = TextEditingController();
  final firstNameController = TextEditingController();
  final phoneController = TextEditingController();
  final addressController = TextEditingController();
  final positionController = TextEditingController();
  final weeklySalaryController = TextEditingController();
  final teamController = TextEditingController();
  final registrationNumberController = TextEditingController();
  final notesController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  String? gender;
  var hireDate = DateTime.now();
  String? contractType;

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Ajouter un employé'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: lastNameController,
                    decoration: const InputDecoration(labelText: 'Nom *'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Nom requis' : null,
                  ),
                  TextFormField(
                    controller: firstNameController,
                    decoration: const InputDecoration(labelText: 'Prénoms *'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Prénoms requis' : null,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: gender,
                    decoration: const InputDecoration(labelText: 'Sexe'),
                    items: const [
                      DropdownMenuItem(value: 'F', child: Text('Féminin')),
                      DropdownMenuItem(value: 'M', child: Text('Masculin')),
                    ],
                    onChanged: (v) => setDialogState(() => gender = v),
                  ),
                  TextFormField(
                    controller: phoneController,
                    decoration: const InputDecoration(labelText: 'Téléphone *', hintText: '07 08 09 10 11'),
                    validator: (v) {
                      final digits = (v ?? '').replaceAll(RegExp(r'[\s.-]'), '');
                      if (!_ciPhoneRegex.hasMatch(digits)) {
                        return 'Numéro de téléphone invalide (10 chiffres, ex. 0708091011)';
                      }
                      return null;
                    },
                  ),
                  TextFormField(controller: addressController, decoration: const InputDecoration(labelText: 'Adresse')),
                  TextFormField(
                    controller: positionController,
                    decoration: const InputDecoration(labelText: 'Poste *'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Poste requis' : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: hireDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          helpText: "Date d'embauche",
                        );
                        if (picked != null) setDialogState(() => hireDate = picked);
                      },
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text("Embauché le ${hireDate.day.toString().padLeft(2, '0')}/${hireDate.month.toString().padLeft(2, '0')}/${hireDate.year}"),
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: contractType,
                    decoration: const InputDecoration(labelText: 'Type de contrat'),
                    items: const [
                      DropdownMenuItem(value: 'cdi', child: Text('CDI')),
                      DropdownMenuItem(value: 'cdd', child: Text('CDD')),
                      DropdownMenuItem(value: 'journalier', child: Text('Journalier')),
                    ],
                    onChanged: (v) => setDialogState(() => contractType = v),
                  ),
                  TextFormField(
                    controller: weeklySalaryController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Salaire hebdomadaire *'),
                    validator: (v) {
                      final value = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                      return (value == null || value <= 0) ? 'Salaire invalide' : null;
                    },
                  ),
                  TextFormField(controller: teamController, decoration: const InputDecoration(labelText: 'Service / Équipe')),
                  TextFormField(controller: registrationNumberController, decoration: const InputDecoration(labelText: 'Matricule')),
                  TextFormField(controller: notesController, decoration: const InputDecoration(labelText: 'Notes')),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.of(context).pop({
                'lastName': lastNameController.text.trim(),
                'firstName': firstNameController.text.trim(),
                'gender': gender,
                'phone': phoneController.text.replaceAll(RegExp(r'[\s.-]'), ''),
                'address': addressController.text.trim(),
                'position': positionController.text.trim(),
                'hireDate': hireDate,
                'contractType': contractType,
                'weeklySalary': double.parse(weeklySalaryController.text.trim().replaceAll(',', '.')),
                'team': teamController.text.trim(),
                'registrationNumber': registrationNumberController.text.trim(),
                'notes': notesController.text.trim(),
              });
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/web/flutter && flutter test test/employee_form_dialog_test.dart`
Expected: PASS

- [ ] **Step 5: Implémenter `PayrollTab` (dashboard + tableau employés)**

```dart
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../common/formatting.dart';
import '../theme/app_theme.dart';
import 'employee_form_dialog.dart';
import 'employee_models.dart';
import 'employees_repository.dart';
import 'payroll_models.dart';
import 'payroll_repository.dart';
import 'payroll_run_page.dart';

/// Sous-onglet Salaires (demande utilisateur du 2026-09-12) : dashboard +
/// liste des employés + accès à la préparation de paie.
class PayrollTab extends StatefulWidget {
  const PayrollTab({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<PayrollTab> createState() => _PayrollTabState();
}

class _PayrollTabState extends State<PayrollTab> {
  late final EmployeesRepository _employees = EmployeesRepository(ApiClient(), widget.establishmentId);
  late final PayrollRepository _payroll = PayrollRepository(ApiClient(), widget.establishmentId);

  late Future<(PayrollDashboard, List<Employee>)> _future = _load();

  Future<(PayrollDashboard, List<Employee>)> _load() async {
    final now = DateTime.now();
    final results = await (
      _payroll.getDashboard(year: now.year, month: now.month),
      _employees.listEmployees(),
    ).wait;
    return (results.$1, results.$2);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _addEmployee() async {
    final data = await showEmployeeFormDialog(context);
    if (data == null) return;
    try {
      await _employees.createEmployee(
        lastName: data['lastName'] as String,
        firstName: data['firstName'] as String,
        gender: data['gender'] as String?,
        phone: data['phone'] as String,
        address: (data['address'] as String).isEmpty ? null : data['address'] as String,
        position: data['position'] as String,
        hireDate: data['hireDate'] as DateTime,
        contractType: data['contractType'] as String?,
        weeklySalary: data['weeklySalary'] as double,
        team: (data['team'] as String).isEmpty ? null : data['team'] as String,
        registrationNumber:
            (data['registrationNumber'] as String).isEmpty ? null : data['registrationNumber'] as String,
        notes: (data['notes'] as String).isEmpty ? null : data['notes'] as String,
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _openPayrollRun() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PayrollRunPage(establishmentId: widget.establishmentId)),
    );
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(PayrollDashboard, List<Employee>)>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : '${snapshot.error}';
          return Center(child: Text(message));
        }
        final (dashboard, employees) = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  mainAxisExtent: 84,
                ),
                children: [
                  _statCard("Nombre d'employés", '${dashboard.employeeCount}', AppColors.green),
                  _statCard('Masse salariale (mois)', '${formatAmount(dashboard.massSalariale)} F', AppColors.orange),
                  _statCard('Total payé', '${formatAmount(dashboard.totalPaid)} F', AppColors.green),
                  _statCard('Reste à payer', '${formatAmount(dashboard.remaining)} F', AppColors.alert),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  FilledButton.icon(onPressed: _addEmployee, icon: const Icon(Icons.person_add_alt), label: const Text('Ajouter un employé')),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(onPressed: _openPayrollRun, icon: const Icon(Icons.payments_outlined), label: const Text('Préparer la paie')),
                ],
              ),
              const SizedBox(height: 16),
              if (employees.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('Aucun employé — ajoutez-en un.')))
              else
                Card(
                  child: Column(
                    children: [
                      for (final e in employees)
                        ListTile(
                          leading: CircleAvatar(backgroundColor: AppColors.greenLight, child: Icon(Icons.person_outline, color: AppColors.green)),
                          title: Text(e.fullName),
                          subtitle: Text('${e.position} — ${e.phone}'),
                          trailing: Text('${formatAmount(e.weeklySalary)} F/sem.', style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 6: Analyse (le fichier `payroll_run_page.dart` référencé n'existe pas encore — créé Task 15 ; pour que ce commit compile isolément, créer un placeholder minimal)**

Créer `apps/web/flutter/lib/payroll/payroll_run_page.dart` (placeholder, réécrit Task 15) :

```dart
import 'package:flutter/material.dart';

class PayrollRunPage extends StatelessWidget {
  const PayrollRunPage({super.key, required this.establishmentId});
  final String establishmentId;

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Préparer la paie')));
}
```

- [ ] **Step 7: Run + build**

Run: `cd apps/web/flutter && flutter analyze && flutter test test/employee_form_dialog_test.dart && flutter build web`
Expected: `No issues found!`, test PASS, build réussi.

- [ ] **Step 8: Commit**

```bash
git add apps/web/flutter/lib/payroll/
git commit -m "feat(payroll): onglet Salaires — dashboard, liste employés, formulaire de création

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 15 : Flutter — écran de préparation/validation/paiement d'une paie

**Files:**
- Modify: `apps/web/flutter/lib/payroll/payroll_run_page.dart` (remplace le placeholder de Task 14)
- Test: `apps/web/flutter/test/payroll_run_page_test.dart`

- [ ] **Step 1: Écrire un test de confirmation avant paiement (échoue, écran placeholder)**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chez_yasmine/payroll/payroll_run_page.dart';

void main() {
  testWidgets('shows a period picker to prepare a new payroll run', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PayrollRunPage(establishmentId: 'est-1')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Préparer'), findsWidgets);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/web/flutter && flutter test test/payroll_run_page_test.dart`
Expected: FAIL — le placeholder n'affiche qu'un `AppBar` vide, aucun texte "Préparer".

- [ ] **Step 3: Implémenter l'écran complet**

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/api_client.dart';
import '../common/formatting.dart';
import 'payroll_models.dart';
import 'payroll_repository.dart';

DateTime _mondayOf(DateTime date) {
  final weekdayIndex = (date.weekday - 1) % 7;
  return DateTime(date.year, date.month, date.day).subtract(Duration(days: weekdayIndex));
}

/// Workflow préparé → validé → payé → annulé (demande utilisateur du
/// 2026-09-12). Le paiement crée automatiquement, côté serveur, une dépense
/// "Salaires" — voir PayrollService.pay.
class PayrollRunPage extends StatefulWidget {
  const PayrollRunPage({super.key, required this.establishmentId});

  final String establishmentId;

  @override
  State<PayrollRunPage> createState() => _PayrollRunPageState();
}

class _PayrollRunPageState extends State<PayrollRunPage> {
  late final PayrollRepository _repository = PayrollRepository(ApiClient(), widget.establishmentId);
  late Future<List<PayrollRun>> _future = _repository.listRuns();
  bool _isBusy = false;

  void _reload() => setState(() => _future = _repository.listRuns());

  Future<void> _prepare() async {
    final monday = _mondayOf(DateTime.now());
    final sunday = monday.add(const Duration(days: 6));
    setState(() => _isBusy = true);
    try {
      await _repository.prepare(periodStart: monday, periodEnd: sunday);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _editLine(PayrollRun run, PayrollLine line) async {
    final advanceController = TextEditingController(text: line.advance.toStringAsFixed(0));
    final adjustmentController = TextEditingController(text: line.adjustment.toStringAsFixed(0));
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(line.employeeName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: advanceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Avance'),
            ),
            TextField(
              controller: adjustmentController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Prime (+) / Retenue (-)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await _repository.updateLine(
        run.id,
        line.id,
        advance: double.tryParse(advanceController.text.replaceAll(',', '.')) ?? 0,
        adjustment: double.tryParse(adjustmentController.text.replaceAll(',', '.')) ?? 0,
      );
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _validate(PayrollRun run) async {
    try {
      await _repository.validate(run.id);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _pay(PayrollRun run) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmer le paiement'),
        content: Text(
          'Payer ${formatAmount(run.total)} FCFA pour ${run.lines.length} employé(s) ? '
          'Une dépense "Salaires" sera créée automatiquement et cette action ne pourra plus être annulée.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Payer')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repository.pay(run.id);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _cancel(PayrollRun run) async {
    try {
      await _repository.cancel(run.id);
      _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _statusLabel(String status) => switch (status) {
        'prepared' => 'Préparée',
        'validated' => 'Validée',
        'paid' => 'Payée',
        'cancelled' => 'Annulée',
        _ => status,
      };

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy');
    return Scaffold(
      appBar: AppBar(title: const Text('Préparer la paie')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isBusy ? null : _prepare,
        icon: const Icon(Icons.add),
        label: const Text('Préparer la semaine en cours'),
      ),
      body: FutureBuilder<List<PayrollRun>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final message = snapshot.error is ApiException ? (snapshot.error as ApiException).message : '${snapshot.error}';
            return Center(child: Text(message));
          }
          final runs = snapshot.data!;
          if (runs.isEmpty) {
            return const Center(child: Text('Aucune paie préparée — utilisez le bouton "Préparer".'));
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final run in runs)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Du ${fmt.format(run.periodStart)} au ${fmt.format(run.periodEnd)}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Chip(label: Text(_statusLabel(run.status))),
                          ],
                        ),
                        for (final line in run.lines)
                          ListTile(
                            dense: true,
                            title: Text(line.employeeName),
                            subtitle: Text('Base ${formatAmount(line.baseSalary)} — Avance ${formatAmount(line.advance)} — Ajust. ${formatAmount(line.adjustment)}'),
                            trailing: Text('${formatAmount(line.netAmount)} F', style: const TextStyle(fontWeight: FontWeight.w600)),
                            onTap: run.status == 'prepared' ? () => _editLine(run, line) : null,
                          ),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Total : ${formatAmount(run.total)} FCFA', style: const TextStyle(fontWeight: FontWeight.bold)),
                            Row(
                              children: [
                                if (run.status == 'prepared') ...[
                                  TextButton(onPressed: () => _cancel(run), child: const Text('Annuler')),
                                  FilledButton(onPressed: () => _validate(run), child: const Text('Valider')),
                                ],
                                if (run.status == 'validated') ...[
                                  TextButton(onPressed: () => _cancel(run), child: const Text('Annuler')),
                                  FilledButton(onPressed: () => _pay(run), child: const Text('Payer')),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/web/flutter && flutter test test/payroll_run_page_test.dart`
Expected: PASS

- [ ] **Step 5: Analyse + build + suite de tests Flutter complète**

Run: `cd apps/web/flutter && flutter analyze && flutter test && flutter build web`
Expected: `No issues found!`, tous les tests passent, build réussi.

- [ ] **Step 6: Commit**

```bash
git add apps/web/flutter/lib/payroll/payroll_run_page.dart apps/web/flutter/test/payroll_run_page_test.dart
git commit -m "feat(payroll): écran de paie — préparer/éditer/valider/payer/annuler

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 16 : Intégration finale, non-régression, revue de code de bout en bout

**Files:** aucun fichier propre à cette tâche — vérifications transversales.

- [ ] **Step 1: Non-régression backend**

Run: `cd apps/api/nestjs && npm run lint && npm run build && npm test`
Expected: aucune erreur, tous les tests passent (anciens modules **inchangés** : `reports.service.spec.ts`, `charts.service.spec.ts` doivent afficher exactement le même nombre de tests qu'avant ce plan).

- [ ] **Step 2: Non-régression Flutter**

Run: `cd apps/web/flutter && flutter analyze && flutter test && flutter build web`
Expected: `No issues found!`, tous les tests passent (y compris les anciens : `pos_page_test.dart`, `table_order_page_test.dart`, `stock_movement_dialog_test.dart`, etc. — aucun d'eux ne doit avoir changé de comportement).

- [ ] **Step 3: Vérification manuelle des points de la spec (§16 « Non-régression » du prompt utilisateur)**

Checklist à cocher une par une en conditions réelles (build web + backend démarré localement, `node dist/main`) :
1. Les anciennes dépenses restent visibles dans l'onglet "Dépenses" et "Historique" (statut par défaut "Payée", mode de paiement "Espèces").
2. `category`/`periodicity`/`marketNumber` inchangés pour les dépenses existantes.
3. Une dépense "Marché" conserve son `marketNumber` dans tous les onglets.
4. Une dépense récurrente s'affiche toujours avec l'étiquette "Récurrente".
5. Payer une paie crée exactement UNE dépense "Salaires" (vérifier `SELECT count(*) FROM expenses WHERE payroll_run_id = '<id>'` = 1 même après un double-clic sur "Payer" — le bouton doit d'ailleurs être désactivé pendant l'appel, voir Step 4 ci-dessous si un bug apparaît ici).
6. Les KPI de "Vue d'ensemble" correspondent aux données réelles (recalculer à la main pour une période test).
7. Les filtres Année/Mois/Semaine ne mélangent jamais les données d'une autre période.
8. L'export Excel de l'Historique respecte le filtre actif (comparer le nombre de lignes du fichier au total affiché à l'écran).
9. La pagination de l'Historique affiche le bon total et navigue correctement.
10. Les permissions sont respectées : un utilisateur avec seulement `payroll.view` (pas `payroll.manage`) ne voit aucun bouton de mutation (Ajouter un employé, Préparer/Valider/Payer/Annuler) fonctionnel — à vérifier en testant manuellement un rôle sans `payroll.manage` (créer un rôle de test temporaire si besoin, ou inspecter que les endpoints POST/PATCH renvoient bien 403).
11. Affichage responsive correct sur desktop (le format principal ciblé par la spec) — redimensionner la fenêtre du navigateur pour confirmer que `DataTable`/`GridView` ne débordent pas.

- [ ] **Step 4: Dispatcher une revue de code de bout en bout (skill `requesting-code-review`)**

Récupérer les SHA de début/fin de plan :
```bash
BASE_SHA=$(git log --oneline | grep "sépare la lecture (products.view)" | tail -1 | awk '{print $1}')
HEAD_SHA=$(git rev-parse HEAD)
```
Dispatcher un subagent `general-purpose` avec le template `code-reviewer.md` (skill `requesting-code-review`), `DESCRIPTION`: "Refonte Dépenses (4 onglets) + sous-module Salaires/Paie complet", `PLAN_OR_REQUIREMENTS`: ce fichier de plan. Corriger tout finding Critique/Important avant de considérer la tâche terminée.

- [ ] **Step 5: Documentation**

Créer `docs/api/expenses.md` (ou l'étendre s'il existe déjà) documentant : le modèle `Expense` étendu (paymentMethod/status/payrollRunId), le nouveau module `payroll/` (Employee/PayrollRun/PayrollLine, state machine, garantie d'idempotence du lien Expense↔PayrollRun), les nouvelles routes, les permissions `payroll.manage`/`payroll.view`, et la décision de différer l'upload de photo employé (avec la raison : bucket Storage `product-images` codé en dur, RLS non auditées pour ce nouveau cas d'usage).

Mettre à jour `CHANGELOG.md` (section `[Unreleased]`, nouvelle entrée datée) résumant la fonctionnalité livrée.

- [ ] **Step 6: Commit final**

```bash
git add docs/api/expenses.md CHANGELOG.md
git commit -m "docs(expenses,payroll): documente la refonte Dépenses + sous-module Salaires

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Déploiement**

```bash
git push origin main
```
Puis surveiller `gh run watch <run-id> --exit-status`, vérifier la fraîcheur Vercel (`curl -sI https://chez-yasmine-two.vercel.app/main.dart.js`) et Render (`curl -s -o /dev/null -w "%{http_code}" https://chez-yasmine-api.onrender.com/establishments/x/employees` → 401 attendu une fois déployé), comme pour chaque déploiement précédent de ce projet.

---

## Self-Review (effectué par l'auteur du plan)

**Couverture de la spec** :
- §1 Structure 4 onglets → Task 10. §2 Vue d'ensemble (filtres/KPI/graphique/répartition/dernières dépenses) → Tasks 6, 11, 12. §3 Dépenses (champs conservés, pas de "Justificatif") → Task 10 Step 1 (extraction verbatim — le champ n'existe déjà pas, rien à retirer). §4 Cas Salaires (montant automatique, idempotence) → Task 5. §5 Sous-onglet Salaires → Tasks 3, 4, 5, 9, 14, 15. §6 Historique (filtres/statuts/pagination/export) → Tasks 7, 9, 13. §7 Cohérence transverse → garantie par le fait que les 4 onglets partagent le même backend (`ExpensesService`/`PayrollService`) et se rechargent (`_reload()`) après toute mutation. §8 Gestion des périodes → Task 6 (`resolveExpensePeriodRange`). §9 Modèle de données → Task 1. §11 Validations → DTOs (Tasks 3, 6, 7) + formulaires Flutter (Tasks 10, 14). §12 État vide → chaque onglet a son état vide dédié (Tasks 12, 13, 14, 15). §13 Responsive → `GridView`/`DataTable` avec défilement horizontal, cohérent avec le reste de l'app. §15 Permissions → Task 2 + `@RequirePermissions` partout. §16 Non-régression → Task 16.
- Aucun gap identifié.

**Placeholders** : aucun "TODO"/"à compléter" dans le code livré — les 2 seuls placeholders intentionnels (Task 10 Step 4, Task 14 Step 6) sont explicitement des stubs de compilation temporaires, remplacés par du code réel dans une tâche ultérieure nommée, jamais laissés tels quels en fin de plan.

**Cohérence des types** : `PayrollRun.status` ('prepared'/'validated'/'paid'/'cancelled') utilisé identiquement dans `payroll.service.ts`, `payroll_models.dart`, `payroll_run_page.dart`. `ExpensePeriodQuery`/`resolveExpensePeriodRange` définis Task 6, réutilisés tels quels Task 7 (`historyWhere`). `ExpenseCategoryAmount`/`ExpenseSummary`/`ExpenseHistoryPage` définis Task 9, consommés identiquement Tasks 11-13.
