-- Supports Phase 7 (POS) cancellation/refund: a sale is never deleted, only
-- marked voided (audit trail preserved, matches prompt maître §31/§44).
alter table sales add column voided_at timestamptz;
create index sales_voided_at_idx on sales(voided_at) where voided_at is null;
