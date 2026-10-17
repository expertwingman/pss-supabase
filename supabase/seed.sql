-- =====================================================================
-- Seed data dummy untuk pengembangan lokal (supabase db reset menjalankan ini)
-- Angka tier, harga, kuota: permisalan, dikalibrasi nanti.
-- =====================================================================

insert into tiers (nama, min_loyalitas, maks_tiket, offset_hari, urutan) values
  ('Suporter', 0,   1, 1, 4),
  ('Hijau',    100, 2, 2, 3),
  ('Elang',    400, 3, 3, 2),
  ('Sembada',  700, 4, 4, 1);

-- Laga: PSS vs Arema FC, Jumat 20 Nov 2026 15.30 WIB
insert into matches (id, lawan, kickoff, tier_aktif) values
  ('11111111-1111-1111-1111-111111111111', 'Arema FC', '2026-11-20 15:30:00+07', true);

insert into tribunes (match_id, nama, harga, harga_anak, kuota, kuota_terkunci) values
  ('11111111-1111-1111-1111-111111111111', 'Tribun Barat (VIP)', 150000, 75000, 3000,  600),
  ('11111111-1111-1111-1111-111111111111', 'Tribun Timur',       100000, 50000, 9000,  1800),
  ('11111111-1111-1111-1111-111111111111', 'Tribun Selatan',      75000, 40000, 8000,  1600),
  ('11111111-1111-1111-1111-111111111111', 'Tribun Utara',        75000, 40000, 8000,  1600);

-- Jendela penjualan
-- Sembada H-4 (Senin 16 Nov), Elang H-3 (Selasa 17 Nov): satu jendela penuh hari
insert into sale_windows (match_id, tier_id, label, mulai, selesai, kapasitas) values
  ('11111111-1111-1111-1111-111111111111', (select id from tiers where nama='Sembada'), 'Sembada · H-4', '2026-11-16 08:00+07', '2026-11-16 22:00+07', 5000),
  ('11111111-1111-1111-1111-111111111111', (select id from tiers where nama='Elang'),   'Elang · H-3',   '2026-11-17 08:00+07', '2026-11-17 22:00+07', 5000);

-- Hijau H-2 (Rabu 18 Nov): 4 shift
insert into sale_windows (match_id, tier_id, label, mulai, selesai, kapasitas) values
  ('11111111-1111-1111-1111-111111111111', (select id from tiers where nama='Hijau'), 'Hijau · 08–10', '2026-11-18 08:00+07', '2026-11-18 10:00+07', 1200),
  ('11111111-1111-1111-1111-111111111111', (select id from tiers where nama='Hijau'), 'Hijau · 11–13', '2026-11-18 11:00+07', '2026-11-18 13:00+07', 1200),
  ('11111111-1111-1111-1111-111111111111', (select id from tiers where nama='Hijau'), 'Hijau · 16–18', '2026-11-18 16:00+07', '2026-11-18 18:00+07', 1200),
  ('11111111-1111-1111-1111-111111111111', (select id from tiers where nama='Hijau'), 'Hijau · 20–22', '2026-11-18 20:00+07', '2026-11-18 22:00+07', 1200);

-- Suporter H-1 (Kamis 19 Nov): 4 shift
insert into sale_windows (match_id, tier_id, label, mulai, selesai, kapasitas) values
  ('11111111-1111-1111-1111-111111111111', (select id from tiers where nama='Suporter'), 'Suporter · 08–10', '2026-11-19 08:00+07', '2026-11-19 10:00+07', 1200),
  ('11111111-1111-1111-1111-111111111111', (select id from tiers where nama='Suporter'), 'Suporter · 11–13', '2026-11-19 11:00+07', '2026-11-19 13:00+07', 1200),
  ('11111111-1111-1111-1111-111111111111', (select id from tiers where nama='Suporter'), 'Suporter · 16–18', '2026-11-19 16:00+07', '2026-11-19 18:00+07', 1200),
  ('11111111-1111-1111-1111-111111111111', (select id from tiers where nama='Suporter'), 'Suporter · 20–22', '2026-11-19 20:00+07', '2026-11-19 22:00+07', 1200);

-- Shift susulan (Kamis 06–07) dan sapu bersih H-6 jam (Jumat 09.30–11.30): semua tier
insert into sale_windows (match_id, tier_id, label, mulai, selesai, kapasitas, susulan) values
  ('11111111-1111-1111-1111-111111111111', null, 'Susulan · Kamis 06–07', '2026-11-19 06:00+07', '2026-11-19 07:00+07', 800,  true),
  ('11111111-1111-1111-1111-111111111111', null, 'Sapu bersih · H-6 jam', '2026-11-20 09:30+07', '2026-11-20 11:30+07', 3000, true);

-- Pernyataan resmi contoh
insert into official_statements (judul, isi, published) values
  ('Selamat datang di PSS App', 'Ini versi alpha. Semua data laga dan tiket di sini masih contoh.', true);
