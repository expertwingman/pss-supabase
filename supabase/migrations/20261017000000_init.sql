-- =====================================================================
-- PSS Sleman Super App — migrasi awal
-- Jalankan dengan: supabase db reset
-- Semua aturan tiket ada di sini (fungsi RPC), bukan di aplikasi.
-- Angka tier, kuota, dan harga adalah DUMMY; dikalibrasi lewat dashboard.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- Tipe ----------
create type kyc_status     as enum ('belum', 'menunggu', 'terverifikasi', 'ditolak');
create type badge_status   as enum ('tidak_ada', 'diajukan', 'terverifikasi', 'dicabut');
create type booking_status as enum ('dipesan', 'dipakai', 'terlewat', 'dibatalkan');
create type order_status   as enum ('menunggu_bayar', 'lunas', 'kedaluwarsa', 'dibatalkan', 'refund');
create type ledger_status  as enum ('menunggu', 'terverifikasi', 'dibatalkan');
create type admin_role     as enum ('admin', 'monitor', 'superadmin');

-- ---------- Profil pengguna ----------
create table profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  nama          text,
  hp            text,
  nik_hash      text unique,                 -- sha256(nik + pepper), dihitung di Edge Function
  kyc           kyc_status   not null default 'belum',
  pin_hash      text,                        -- bcrypt, dicek di aplikasi secara offline juga
  komunitas     text,                        -- nama komunitas yang dipilih
  badge         badge_status not null default 'tidak_ada',
  loyalitas     int          not null default 0,
  poin          int          not null default 0,
  created_at    timestamptz  not null default now()
);

-- Profil dibuat otomatis saat pengguna mendaftar
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, hp) values (new.id, new.phone);
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ---------- Peran dashboard ----------
create table admin_users (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  role       admin_role not null,
  created_at timestamptz not null default now()
);

-- ---------- Tier (angka dummy) ----------
create table tiers (
  id            serial primary key,
  nama          text not null,
  min_loyalitas int  not null,
  maks_tiket    int  not null,
  offset_hari   int  not null,   -- H-n: jendela beli tier ini dibuka n hari sebelum laga
  urutan        int  not null
);

-- ---------- Laga ----------
create table matches (
  id          uuid primary key default gen_random_uuid(),
  lawan       text not null,
  kickoff     timestamptz not null,
  stadion     text not null default 'Stadion Maguwoharjo',
  kompetisi   text not null default 'Super League',
  tier_aktif  boolean not null default true,   -- false = laga sepi, semua bisa beli sejak H-4
  tier_manual boolean not null default false,  -- true = diputuskan admin, bukan otomatis
  rsvp_ya     int not null default 0,
  status      text not null default 'dijadwalkan',
  created_at  timestamptz not null default now()
);

create table tribunes (
  id              uuid primary key default gen_random_uuid(),
  match_id        uuid not null references matches(id) on delete cascade,
  nama            text not null,
  harga           int  not null,
  harga_anak      int  not null default 0,
  kuota           int  not null,
  terjual         int  not null default 0,
  kuota_terkunci  int  not null default 0   -- jatah yang hanya boleh dipakai tier bawah
);

-- ---------- Jendela penjualan dan booking shift ----------
create table sale_windows (
  id        uuid primary key default gen_random_uuid(),
  match_id  uuid not null references matches(id) on delete cascade,
  tier_id   int references tiers(id),             -- null = sapu bersih, semua tier
  label     text not null,
  mulai     timestamptz not null,
  selesai   timestamptz not null,
  kapasitas int not null default 1200,
  terisi    int not null default 0,
  susulan   boolean not null default false
);

create table window_bookings (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles(id) on delete cascade,
  window_id  uuid not null references sale_windows(id) on delete cascade,
  status     booking_status not null default 'dipesan',
  created_at timestamptz not null default now(),
  unique (user_id, window_id)
);

-- ---------- Rombongan Saya ----------
create table companions (
  id            uuid primary key default gen_random_uuid(),
  owner_id      uuid not null references profiles(id) on delete cascade,
  nama          text not null,
  hp            text,
  nik_hash      text,                    -- wajib untuk dewasa, opsional untuk anak
  is_anak       boolean not null default false,
  tahun_lahir   int,
  terverifikasi boolean not null default false,
  created_at    timestamptz not null default now()
);

-- ---------- Order dan tiket ----------
create table orders (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references profiles(id),
  match_id       uuid not null references matches(id),
  tribune_id     uuid not null references tribunes(id),
  status         order_status not null default 'menunggu_bayar',
  total          int not null,
  kedaluwarsa_at timestamptz not null,
  payment_ref    text,
  created_at     timestamptz not null default now()
);

create table tickets (
  id               uuid primary key default gen_random_uuid(),
  order_id         uuid not null references orders(id) on delete cascade,
  match_id         uuid not null references matches(id),
  tribune_id       uuid not null references tribunes(id),
  holder_name      text not null,
  nik_hash         text,
  is_anak          boolean not null default false,
  parent_ticket_id uuid references tickets(id),
  qr_secret        text not null default encode(gen_random_bytes(32), 'hex'),
  kode             text not null,
  scanned_at       timestamptz,
  gate             text,
  created_at       timestamptz not null default now()
);

-- Registri NIK per laga: satu NIK satu tiket, lintas aplikasi (PSS app dan BCS app)
create table nik_match_registry (
  nik_hash  text not null,
  match_id  uuid not null references matches(id) on delete cascade,
  ticket_id uuid references tickets(id) on delete cascade,
  sumber    text not null default 'pss_app',
  primary key (nik_hash, match_id)
);

-- ---------- Loyalitas dan poin ----------
create table loyalty_ledger (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles(id) on delete cascade,
  jumlah     int  not null,
  sumber     text not null,                -- kyc, komunitas, hadir, game, decay, ...
  match_id   uuid references matches(id),
  status     ledger_status not null default 'terverifikasi',
  keterangan text,
  created_at timestamptz not null default now()
);

create table points_ledger (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles(id) on delete cascade,
  jumlah     int  not null,
  sumber     text not null,                -- cashback_tiket, cashback_merch, tukar_voucher
  referensi  uuid,
  created_at timestamptz not null default now()
);

-- ---------- Pernyataan resmi dan audit ----------
create table official_statements (
  id           uuid primary key default gen_random_uuid(),
  judul        text not null,
  isi          text not null,
  dibuat_oleh  uuid references auth.users(id),
  published    boolean not null default false,
  created_at   timestamptz not null default now()
);

create table admin_audit_log (
  id         bigserial primary key,
  actor      uuid,
  role       admin_role,
  aksi       text not null,
  target     text,
  sebelum    jsonb,
  sesudah    jsonb,
  created_at timestamptz not null default now()
);

-- =====================================================================
-- Fungsi bantu
-- =====================================================================

-- Tier pengguna saat ini
create or replace function current_tier(p_user uuid) returns tiers
language sql stable security definer set search_path = public as $$
  select t.* from tiers t
  join profiles p on p.id = p_user
  where t.min_loyalitas <= p.loyalitas
  order by t.min_loyalitas desc
  limit 1
$$;

-- Jatah tiket dewasa: badge BCS terverifikasi selalu 1 di PSS app
create or replace function ticket_allowance(p_user uuid) returns int
language plpgsql stable security definer set search_path = public as $$
declare p profiles; t tiers;
begin
  select * into p from profiles where id = p_user;
  if p.badge = 'terverifikasi' and p.komunitas = 'Brigata Curva Sud' then
    return 1;
  end if;
  select * into t from current_tier(p_user);
  return coalesce(t.maks_tiket, 1);
end $$;

-- =====================================================================
-- RPC: booking shift
-- =====================================================================
create or replace function book_window(p_window uuid) returns window_bookings
language plpgsql security definer set search_path = public as $$
declare w sale_windows; p profiles; t tiers; b window_bookings; m matches;
begin
  select * into p from profiles where id = auth.uid();
  if p.id is null then raise exception 'Profil tidak ditemukan'; end if;

  select * into w from sale_windows where id = p_window for update;
  if w.id is null then raise exception 'Jendela tidak ditemukan'; end if;
  if w.selesai < now() then raise exception 'Jendela sudah lewat'; end if;

  select * into m from matches where id = w.match_id;
  select * into t from current_tier(p.id);

  -- Laga ramai: jendela harus sesuai tier, kecuali sapu bersih/susulan
  if m.tier_aktif and w.tier_id is not null and not w.susulan and w.tier_id <> t.id then
    raise exception 'Jendela ini bukan untuk tier Anda';
  end if;
  if w.terisi >= w.kapasitas then raise exception 'Shift penuh, pilih shift lain'; end if;

  if exists (
    select 1 from window_bookings wb
    join sale_windows s on s.id = wb.window_id
    where wb.user_id = p.id and s.match_id = w.match_id and wb.status = 'dipesan'
  ) then
    raise exception 'Anda sudah punya jadwal beli untuk laga ini';
  end if;

  update sale_windows set terisi = terisi + 1 where id = w.id;
  insert into window_bookings (user_id, window_id) values (p.id, w.id) returning * into b;
  return b;
end $$;

-- Batalkan jadwal (tanpa penalti jika > 1 jam sebelum shift)
create or replace function cancel_window_booking(p_booking uuid) returns void
language plpgsql security definer set search_path = public as $$
declare b window_bookings; w sale_windows;
begin
  select * into b from window_bookings where id = p_booking and user_id = auth.uid() for update;
  if b.id is null then raise exception 'Booking tidak ditemukan'; end if;
  if b.status <> 'dipesan' then raise exception 'Booking sudah tidak aktif'; end if;
  select * into w from sale_windows where id = b.window_id;
  if w.mulai - interval '1 hour' < now() then
    raise exception 'Pembatalan hanya bisa lebih dari 1 jam sebelum shift';
  end if;
  update window_bookings set status = 'dibatalkan' where id = b.id;
  update sale_windows set terisi = greatest(terisi - 1, 0) where id = w.id;
end $$;

-- =====================================================================
-- RPC: buat order (dipanggil saat shift pengguna sedang berjalan)
-- p_items: [{"nama":"Budi","nik_hash":"...","is_anak":false}, {"nama":"Raka","is_anak":true,"tahun_lahir":2017}]
-- Pemesan sendiri otomatis jadi tiket pertama, tidak perlu ada di p_items.
-- =====================================================================
create or replace function create_order(p_match uuid, p_tribune uuid, p_items jsonb)
returns orders
language plpgsql security definer set search_path = public as $$
declare
  p profiles; m matches; tr tribunes; w sale_windows; o orders;
  n_dewasa int := 1; n_anak int := 0; allowance int; item jsonb;
  total int := 0; parent_id uuid; tk tickets; seq int := 0;
begin
  select * into p from profiles where id = auth.uid();
  if p.id is null then raise exception 'Profil tidak ditemukan'; end if;
  if p.kyc <> 'terverifikasi' then raise exception 'Verifikasi data diri dulu untuk membeli tiket'; end if;

  select * into m from matches where id = p_match;
  if m.id is null then raise exception 'Laga tidak ditemukan'; end if;
  if m.kickoff < now() then raise exception 'Laga sudah dimulai'; end if;

  -- Jendela beli: pengguna harus punya booking pada shift yang sedang berjalan,
  -- kecuali laga sepi (tier mati) di mana semua bebas beli sejak H-4
  if m.tier_aktif then
    select s.* into w
    from window_bookings wb join sale_windows s on s.id = wb.window_id
    where wb.user_id = p.id and s.match_id = p_match and wb.status = 'dipesan'
      and now() between s.mulai and s.selesai;
    if w.id is null then raise exception 'Belum masuk jendela beli Anda'; end if;
  else
    if now() < m.kickoff - interval '4 days' then raise exception 'Penjualan belum dibuka'; end if;
  end if;

  -- Hitung item dan validasi jatah
  for item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    if (item->>'is_anak')::boolean then n_anak := n_anak + 1; else n_dewasa := n_dewasa + 1; end if;
  end loop;
  allowance := ticket_allowance(p.id);
  if n_dewasa > allowance then raise exception 'Jatah Anda % tiket dewasa', allowance; end if;
  if n_anak > 2 then raise exception 'Maksimal 2 tiket anak'; end if;

  -- Satu NIK satu tiket per laga (pemesan dan semua pendamping dewasa)
  if exists (select 1 from nik_match_registry where match_id = p_match and nik_hash = p.nik_hash) then
    raise exception 'NIK Anda sudah punya tiket untuk laga ini';
  end if;
  for item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    if not (item->>'is_anak')::boolean then
      if item->>'nik_hash' is null then raise exception 'Pendamping dewasa wajib NIK'; end if;
      if exists (select 1 from nik_match_registry where match_id = p_match and nik_hash = item->>'nik_hash') then
        raise exception 'NIK % sudah punya tiket untuk laga ini', item->>'nama';
      end if;
    end if;
  end loop;

  -- Kuota tribun (kunci baris)
  select * into tr from tribunes where id = p_tribune and match_id = p_match for update;
  if tr.id is null then raise exception 'Tribun tidak ditemukan'; end if;
  if tr.kuota - tr.terjual < n_dewasa + n_anak then raise exception 'Tiket tribun ini tidak cukup'; end if;
  update tribunes set terjual = terjual + n_dewasa + n_anak where id = tr.id;

  total := n_dewasa * tr.harga + n_anak * tr.harga_anak;

  insert into orders (user_id, match_id, tribune_id, total, kedaluwarsa_at)
  values (p.id, p_match, p_tribune, total, now() + interval '15 minutes')
  returning * into o;

  -- Tiket pemesan
  seq := seq + 1;
  insert into tickets (order_id, match_id, tribune_id, holder_name, nik_hash, kode)
  values (o.id, p_match, p_tribune, p.nama, p.nik_hash, 'PSS-' || upper(left(o.id::text, 6)) || '-' || seq)
  returning * into tk;
  parent_id := tk.id;
  insert into nik_match_registry (nik_hash, match_id, ticket_id) values (p.nik_hash, p_match, tk.id);

  -- Tiket pendamping dan anak
  for item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) loop
    seq := seq + 1;
    if (item->>'is_anak')::boolean then
      insert into tickets (order_id, match_id, tribune_id, holder_name, nik_hash, is_anak, parent_ticket_id, kode)
      values (o.id, p_match, p_tribune, item->>'nama', item->>'nik_hash', true, parent_id,
              'PSS-' || upper(left(o.id::text, 6)) || '-' || seq || 'A');
    else
      insert into tickets (order_id, match_id, tribune_id, holder_name, nik_hash, kode)
      values (o.id, p_match, p_tribune, item->>'nama', item->>'nik_hash',
              'PSS-' || upper(left(o.id::text, 6)) || '-' || seq)
      returning * into tk;
      insert into nik_match_registry (nik_hash, match_id, ticket_id) values (item->>'nik_hash', p_match, tk.id);
    end if;
  end loop;

  return o;
end $$;

-- =====================================================================
-- Order kedaluwarsa: lepas kuota dan registri (dijalankan tiap menit)
-- =====================================================================
create or replace function expire_orders() returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  with ex as (
    update orders set status = 'kedaluwarsa'
    where status = 'menunggu_bayar' and kedaluwarsa_at < now()
    returning id, tribune_id
  ), cnt as (
    select e.tribune_id, count(t.id) as jml from ex e join tickets t on t.order_id = e.id group by e.tribune_id
  ), rel as (
    update tribunes tr set terjual = greatest(tr.terjual - c.jml, 0) from cnt c where tr.id = c.tribune_id
  ), reg as (
    delete from nik_match_registry r using tickets t, ex e where r.ticket_id = t.id and t.order_id = e.id
  )
  select count(*) into n from ex;
  return n;
end $$;

-- =====================================================================
-- Tandai lunas (dipanggil webhook payment gateway lewat service role)
-- =====================================================================
create or replace function mark_order_paid(p_order uuid, p_ref text) returns void
language plpgsql security definer set search_path = public as $$
declare o orders;
begin
  select * into o from orders where id = p_order for update;
  if o.id is null then raise exception 'Order tidak ditemukan'; end if;
  if o.status = 'lunas' then return; end if;
  if o.status <> 'menunggu_bayar' then raise exception 'Order sudah %', o.status; end if;
  update orders set status = 'lunas', payment_ref = p_ref where id = o.id;
  -- Poin cashback 2% (dummy)
  insert into points_ledger (user_id, jumlah, sumber, referensi) values (o.user_id, o.total / 50, 'cashback_tiket', o.id);
  update profiles set poin = poin + o.total / 50 where id = o.user_id;
end $$;

-- =====================================================================
-- Kehadiran: dikreditkan H+1 secara batch (dummy: 50 loyalitas)
-- =====================================================================
create or replace function credit_attendance(p_match uuid) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  with hadir as (
    select distinct o.user_id
    from tickets t join orders o on o.id = t.order_id
    where t.match_id = p_match and t.scanned_at is not null and not t.is_anak
      and t.nik_hash = (select nik_hash from profiles where id = o.user_id)
      and not exists (select 1 from loyalty_ledger l where l.user_id = o.user_id and l.match_id = p_match and l.sumber = 'hadir')
  ), ins as (
    insert into loyalty_ledger (user_id, jumlah, sumber, match_id, keterangan)
    select user_id, 50, 'hadir', p_match, 'Kehadiran laga kandang' from hadir returning user_id
  )
  update profiles p set loyalitas = loyalitas + 50 from ins where p.id = ins.user_id;
  get diagnostics n = row_count;
  return n;
end $$;

-- =====================================================================
-- RLS
-- =====================================================================
alter table profiles            enable row level security;
alter table admin_users         enable row level security;
alter table tiers               enable row level security;
alter table matches             enable row level security;
alter table tribunes            enable row level security;
alter table sale_windows        enable row level security;
alter table window_bookings     enable row level security;
alter table companions          enable row level security;
alter table orders              enable row level security;
alter table tickets             enable row level security;
alter table nik_match_registry  enable row level security;
alter table loyalty_ledger      enable row level security;
alter table points_ledger       enable row level security;
alter table official_statements enable row level security;
alter table admin_audit_log     enable row level security;

create policy "profil sendiri"        on profiles for select using (id = auth.uid());
create policy "ubah profil sendiri"   on profiles for update using (id = auth.uid())
  with check (id = auth.uid() and nik_hash is not distinct from (select nik_hash from profiles where id = auth.uid()));

create policy "tier publik"           on tiers        for select to authenticated using (true);
create policy "laga publik"           on matches      for select to authenticated using (true);
create policy "tribun publik"         on tribunes     for select to authenticated using (true);
create policy "jendela publik"        on sale_windows for select to authenticated using (true);
create policy "pernyataan publik"     on official_statements for select to authenticated using (published);

create policy "booking sendiri"       on window_bookings for select using (user_id = auth.uid());
create policy "order sendiri"         on orders  for select using (user_id = auth.uid());
create policy "tiket sendiri"         on tickets for select using (exists (select 1 from orders o where o.id = order_id and o.user_id = auth.uid()));
create policy "loyalitas sendiri"     on loyalty_ledger for select using (user_id = auth.uid());
create policy "poin sendiri"          on points_ledger  for select using (user_id = auth.uid());

create policy "rombongan baca"        on companions for select using (owner_id = auth.uid());
create policy "rombongan tambah"      on companions for insert with check (owner_id = auth.uid());
create policy "rombongan ubah"        on companions for update using (owner_id = auth.uid());
create policy "rombongan hapus"       on companions for delete using (owner_id = auth.uid());

-- nik_match_registry, admin_audit_log, admin_users: tidak ada policy untuk klien,
-- hanya bisa diakses lewat fungsi security definer dan service role.

grant execute on function book_window(uuid)                 to authenticated;
grant execute on function cancel_window_booking(uuid)       to authenticated;
grant execute on function create_order(uuid, uuid, jsonb)   to authenticated;
revoke execute on function expire_orders()                  from public, authenticated;
revoke execute on function mark_order_paid(uuid, text)      from public, authenticated;
revoke execute on function credit_attendance(uuid)          from public, authenticated;

-- =====================================================================
-- Penjadwalan (butuh ekstensi pg_cron; di cloud aktifkan dari Dashboard → Extensions)
-- =====================================================================
-- select cron.schedule('expire-orders', '* * * * *', $$select expire_orders()$$);
