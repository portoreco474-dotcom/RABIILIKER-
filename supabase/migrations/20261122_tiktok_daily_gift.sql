-- RABIILIKER: secure daily TikTok tap gift counter
-- Daily reset uses Africa/Casablanca local calendar date.
-- Run once in Supabase SQL Editor. This tracks internal RABIILIKER taps only;
-- it does not click, like, follow, or view anything on TikTok.

create table if not exists public.tiktok_daily_gifts (
  user_id uuid not null references auth.users(id) on delete cascade,
  gift_date date not null default (now() at time zone 'Africa/Casablanca')::date,
  granted_count integer not null default 20000 check (granted_count = 20000),
  used_count integer not null default 0 check (used_count >= 0 and used_count <= granted_count),
  claimed_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, gift_date)
);

alter table public.tiktok_daily_gifts enable row level security;
revoke all on table public.tiktok_daily_gifts from anon, authenticated;

create or replace function public.claim_tiktok_daily_gift()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_date date := (now() at time zone 'Africa/Casablanca')::date;
  v_row public.tiktok_daily_gifts%rowtype;
begin
  if v_uid is null then
    raise exception 'يجب تسجيل الدخول أولاً';
  end if;

  insert into public.tiktok_daily_gifts(user_id, gift_date)
  values (v_uid, v_date)
  on conflict (user_id, gift_date) do nothing;

  select * into v_row
  from public.tiktok_daily_gifts
  where user_id = v_uid and gift_date = v_date;

  return jsonb_build_object(
    'claimed', true,
    'granted', v_row.granted_count,
    'used', v_row.used_count,
    'remaining', v_row.granted_count - v_row.used_count,
    'gift_date', v_row.gift_date
  );
end;
$$;

create or replace function public.use_tiktok_gift_tap()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_date date := (now() at time zone 'Africa/Casablanca')::date;
  v_row public.tiktok_daily_gifts%rowtype;
begin
  if v_uid is null then
    raise exception 'يجب تسجيل الدخول أولاً';
  end if;

  update public.tiktok_daily_gifts
  set used_count = used_count + 1,
      updated_at = now()
  where user_id = v_uid
    and gift_date = v_date
    and used_count < granted_count
  returning * into v_row;

  if not found then
    select * into v_row
    from public.tiktok_daily_gifts
    where user_id = v_uid and gift_date = v_date;

    if not found then
      raise exception 'استلم هدية اليوم أولاً';
    end if;
    raise exception 'انتهت تكبيسات هدية اليوم';
  end if;

  return jsonb_build_object(
    'claimed', true,
    'granted', v_row.granted_count,
    'used', v_row.used_count,
    'remaining', v_row.granted_count - v_row.used_count,
    'gift_date', v_row.gift_date
  );
end;
$$;

revoke all on function public.claim_tiktok_daily_gift() from public, anon;
revoke all on function public.use_tiktok_gift_tap() from public, anon;
grant execute on function public.claim_tiktok_daily_gift() to authenticated;
grant execute on function public.use_tiktok_gift_tap() to authenticated;

create or replace function public.get_tiktok_daily_gift_status()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_date date := (now() at time zone 'Africa/Casablanca')::date;
  v_row public.tiktok_daily_gifts%rowtype;
begin
  if v_uid is null then raise exception 'يجب تسجيل الدخول أولاً'; end if;
  select * into v_row from public.tiktok_daily_gifts
  where user_id = v_uid and gift_date = v_date;
  if not found then
    return jsonb_build_object('claimed', false, 'granted', 20000, 'used', 0, 'remaining', 20000, 'gift_date', v_date);
  end if;
  return jsonb_build_object('claimed', true, 'granted', v_row.granted_count, 'used', v_row.used_count,
    'remaining', v_row.granted_count - v_row.used_count, 'gift_date', v_row.gift_date);
end;
$$;
revoke all on function public.get_tiktok_daily_gift_status() from public, anon;
grant execute on function public.get_tiktok_daily_gift_status() to authenticated;
