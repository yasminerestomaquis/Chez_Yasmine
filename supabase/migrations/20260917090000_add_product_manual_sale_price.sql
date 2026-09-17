alter table products add column if not exists requires_price_at_sale boolean not null default false;
alter table products add column if not exists reference_sale_price numeric(12,2);
