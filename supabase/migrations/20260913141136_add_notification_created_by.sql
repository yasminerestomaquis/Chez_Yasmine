alter table notifications add column if not exists created_by uuid references user_profiles(id);
create index if not exists notifications_created_by_idx on notifications(created_by);
