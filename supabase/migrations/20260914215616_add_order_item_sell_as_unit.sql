alter table order_items add column if not exists sell_as_unit boolean not null default false;
