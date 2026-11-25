-- 我们的小日子：同步用的数据库设置（在 Supabase 的 SQL Editor 里整段运行一次）
-- 数据只能通过下面三个函数、凭“情侣暗号”读写；表本身对外不可直接访问。

create table if not exists public.items (
  room text not null,
  id text not null,
  kind text not null,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default clock_timestamp(),
  primary key (room, id)
);
create index if not exists items_room_updated on public.items (room, updated_at);

alter table public.items enable row level security;
revoke all on public.items from anon, authenticated;

create or replace function public.room_items(p_room text, p_since timestamptz default null)
returns setof public.items
language sql stable security definer set search_path = public as $$
  select * from public.items
  where room = p_room and length(p_room) >= 20
    and (p_since is null or updated_at > p_since)
  order by updated_at;
$$;

create or replace function public.room_put(p_room text, p_id text, p_kind text, p_data jsonb)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if length(p_room) < 20 or length(p_id) > 64 or length(p_kind) > 16 then
    raise exception 'bad request';
  end if;
  if pg_column_size(p_data) > 900000 then
    raise exception 'too large';
  end if;
  if (select count(*) from public.items where room = p_room) > 3000 then
    raise exception 'room full';
  end if;
  insert into public.items (room, id, kind, data, updated_at)
  values (p_room, p_id, p_kind, p_data, clock_timestamp())
  on conflict (room, id) do update
    set kind = excluded.kind, data = excluded.data, updated_at = clock_timestamp();
end;
$$;

revoke all on function public.room_items(text, timestamptz) from public;
revoke all on function public.room_put(text, text, text, jsonb) from public;
grant execute on function public.room_items(text, timestamptz) to anon, authenticated;
grant execute on function public.room_put(text, text, text, jsonb) to anon, authenticated;
