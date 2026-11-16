-- ============================================================================
-- PERPUSTAKAAN INFORMATIKA - CONTOH ANALISIS (fungsi Oracle SQL)
-- Jalankan setelah perpustakaan_ddl_data.sql dimuat (berkas utama maupun versi-lengkap/).
-- Status: belum pernah dijalankan pada Oracle Database; diuji pada PostgreSQL + orafce
-- (lihat README.md bagian 6). Bila ada query yang gagal, catat kodenya, misalnya [J19].
-- Tanggal acuan data: 2026-11-05 (ganti DATE '2026-11-05' dengan SYSDATE
-- bila ingin relatif terhadap hari berjalan). Penjelasan tiap query ada di README.md.
-- ============================================================================


-- ######## A. Analisis operasional perpustakaan ########

-- [A1] Buku yang sedang dipinjam dan sudah terlambat (denda simulasi Rp1.000/hari)
SELECT a.nama, b.judul, p.tanggal_pinjam, p.batas_pengembalian,
       TRUNC(DATE '2026-11-05') - p.batas_pengembalian           AS hari_terlambat,
       (TRUNC(DATE '2026-11-05') - p.batas_pengembalian) * 1000  AS denda
FROM   peminjaman p
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
JOIN   anggota a      ON a.nik = p.anggota_nik
WHERE  p.tanggal_pengembalian IS NULL AND p.batas_pengembalian < DATE '2026-11-05'
ORDER  BY hari_terlambat DESC;

-- [A2] Sepuluh judul terpopuler beserta genrenya
SELECT * FROM (
  SELECT b.judul, g.nama AS genre, COUNT(*) AS jumlah_pinjam
  FROM   peminjaman p
  JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
  JOIN   buku b         ON b.isbn = k.buku_isbn
  JOIN   genre g        ON g.id = b.genre_id
  GROUP  BY b.judul, g.nama
  ORDER  BY jumlah_pinjam DESC)
WHERE ROWNUM <= 10;

-- [A3] Ketersediaan eksemplar per judul (tidak sedang dipinjam, kondisi layak)
SELECT b.judul,
       COUNT(k.id)                                                   AS total_eksemplar,
       SUM(CASE WHEN p.buku_koleksi_id IS NOT NULL THEN 1 ELSE 0 END) AS sedang_dipinjam,
       SUM(CASE WHEN p.buku_koleksi_id IS NULL
                 AND k.kondisi IN ('BAIK', 'RUSAK RINGAN') THEN 1 ELSE 0 END) AS tersedia
FROM   buku b
JOIN   buku_koleksi k ON k.buku_isbn = b.isbn
LEFT   JOIN peminjaman p ON p.buku_koleksi_id = k.id AND p.tanggal_pengembalian IS NULL
GROUP  BY b.isbn, b.judul
ORDER  BY tersedia, b.judul;

-- [A4] Anggota dengan total hari keterlambatan terbanyak
SELECT a.nama, COUNT(*) AS kali_terlambat,
       SUM(p.tanggal_pengembalian - p.batas_pengembalian) AS total_hari_terlambat
FROM   peminjaman p JOIN anggota a ON a.nik = p.anggota_nik
WHERE  p.tanggal_pengembalian > p.batas_pengembalian
GROUP  BY a.nama
ORDER  BY total_hari_terlambat DESC
FETCH FIRST 10 ROWS ONLY;

-- [A5] Tren peminjaman per bulan
SELECT TO_CHAR(tanggal_pinjam, 'YYYY-MM') AS bulan, COUNT(*) AS jumlah,
       SUM(CASE WHEN tanggal_pengembalian > batas_pengembalian THEN 1 ELSE 0 END) AS terlambat
FROM   peminjaman
GROUP  BY TO_CHAR(tanggal_pinjam, 'YYYY-MM')
ORDER  BY bulan;

-- [A6] Judul yang belum pernah dipinjam, per genre
SELECT g.nama AS genre, b.judul, b.tahun_terbit
FROM   buku b JOIN genre g ON g.id = b.genre_id
WHERE  NOT EXISTS (SELECT 1 FROM peminjaman p JOIN buku_koleksi k ON k.id = p.buku_koleksi_id
                   WHERE  k.buku_isbn = b.isbn)
ORDER  BY g.nama, b.judul;

-- [A7] Daftar penulis per buku dalam satu baris
SELECT b.judul, LISTAGG(pn.nama, '; ') WITHIN GROUP (ORDER BY pn.nama) AS penulis
FROM   buku b
JOIN   buku_penulis bp ON bp.buku_isbn = b.isbn
JOIN   penulis pn      ON pn.nik = bp.penulis_id
GROUP  BY b.isbn, b.judul
ORDER  BY b.judul;

-- [A8] Siapa sedang memegang buku apa: pinjaman aktif per anggota
SELECT a.nama,
       a.hp,
       COUNT(*)                                                       AS buku_dipegang,
       MIN(p.batas_pengembalian)                                      AS batas_terdekat,
       LISTAGG(b.judul || ' (s.d. ' || TO_CHAR(p.batas_pengembalian, 'DD/MM') || ')', '; ')
           WITHIN GROUP (ORDER BY p.batas_pengembalian, b.judul)      AS daftar_buku
FROM   peminjaman p
JOIN   anggota a      ON a.nik = p.anggota_nik
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
WHERE  p.tanggal_pengembalian IS NULL
GROUP  BY a.nik, a.nama, a.hp
ORDER  BY buku_dipegang DESC, batas_terdekat, a.nama;

-- [A9] Eksemplar hilang dan anggota yang bertanggung jawab
SELECT k.id                              AS eksemplar,
       b.judul,
       a.nama                            AS peminjam_terakhir,
       a.hp,
       p.tanggal_pinjam,
       p.batas_pengembalian,
       DATE '2026-11-05' - p.batas_pengembalian    AS hari_lewat_batas
FROM   buku_koleksi k
JOIN   buku b         ON b.isbn = k.buku_isbn
JOIN   peminjaman p   ON p.buku_koleksi_id = k.id AND p.tanggal_pengembalian IS NULL
JOIN   anggota a      ON a.nik = p.anggota_nik
WHERE  k.kondisi = 'HILANG'
ORDER  BY hari_lewat_batas DESC;

-- [A10] Status koleksi per genre: tersedia, dipinjam, rusak berat, hilang
SELECT g.nama                                                     AS genre,
       COUNT(DISTINCT e.isbn)                                     AS judul,
       COUNT(*)                                                   AS eksemplar,
       SUM(CASE WHEN e.status = 'Tersedia'    THEN 1 ELSE 0 END)  AS tersedia,
       SUM(CASE WHEN e.status = 'Dipinjam'    THEN 1 ELSE 0 END)  AS dipinjam,
       SUM(CASE WHEN e.status = 'Rusak berat' THEN 1 ELSE 0 END)  AS rusak_berat,
       SUM(CASE WHEN e.status = 'Hilang'      THEN 1 ELSE 0 END)  AS hilang,
       ROUND(100 * SUM(CASE WHEN e.status = 'Tersedia' THEN 1 ELSE 0 END) / COUNT(*), 1) AS persen_tersedia
FROM  (SELECT k.id, k.buku_isbn AS isbn, b.genre_id,
              CASE WHEN k.kondisi = 'HILANG'            THEN 'Hilang'
                   WHEN p.buku_koleksi_id IS NOT NULL   THEN 'Dipinjam'
                   WHEN k.kondisi = 'RUSAK BERAT'       THEN 'Rusak berat'
                   ELSE 'Tersedia'
              END AS status
       FROM   buku_koleksi k
       JOIN   buku b ON b.isbn = k.buku_isbn
       LEFT   JOIN peminjaman p ON p.buku_koleksi_id = k.id AND p.tanggal_pengembalian IS NULL) e
JOIN   genre g ON g.id = e.genre_id
GROUP  BY g.id, g.nama
ORDER  BY g.id;

-- [A11] Judul dengan ketersediaan kritis (paling banyak satu eksemplar layak di rak)
WITH status_eksemplar AS (
  SELECT k.id, k.buku_isbn,
         CASE WHEN k.kondisi = 'HILANG'          THEN 'Hilang'
              WHEN p.buku_koleksi_id IS NOT NULL THEN 'Dipinjam'
              WHEN k.kondisi = 'RUSAK BERAT'     THEN 'Rusak berat'
              ELSE 'Tersedia'
         END AS status
  FROM   buku_koleksi k
  LEFT   JOIN peminjaman p ON p.buku_koleksi_id = k.id AND p.tanggal_pengembalian IS NULL),
popularitas AS (
  SELECT k.buku_isbn, COUNT(*) AS kali_dipinjam
  FROM   peminjaman p
  JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
  GROUP  BY k.buku_isbn)
SELECT b.judul,
       COUNT(*)                                                                AS eksemplar,
       SUM(CASE WHEN e.status = 'Dipinjam' THEN 1 ELSE 0 END)                   AS sedang_dipinjam,
       SUM(CASE WHEN e.status IN ('Rusak berat', 'Hilang') THEN 1 ELSE 0 END)   AS tidak_layak,
       SUM(CASE WHEN e.status = 'Tersedia' THEN 1 ELSE 0 END)                   AS layak_di_rak,
       NVL(pop.kali_dipinjam, 0)                                                AS total_pernah_dipinjam
FROM   status_eksemplar e
JOIN   buku b           ON b.isbn = e.buku_isbn
LEFT   JOIN popularitas pop ON pop.buku_isbn = b.isbn
GROUP  BY b.isbn, b.judul, pop.kali_dipinjam
HAVING SUM(CASE WHEN e.status = 'Tersedia' THEN 1 ELSE 0 END) <= 1
ORDER  BY total_pernah_dipinjam DESC, b.judul
FETCH FIRST 15 ROWS ONLY;

-- [A12] Anggota teladan: tidak pernah terlambat dan tidak sedang menunggak
SELECT a.nama,
       COUNT(*)              AS jumlah_pinjam,
       MIN(p.tanggal_pinjam) AS pinjam_pertama,
       MAX(p.tanggal_pinjam) AS pinjam_terakhir
FROM   anggota a
JOIN   peminjaman p ON p.anggota_nik = a.nik
WHERE  NOT EXISTS (SELECT 1
                   FROM   peminjaman x
                   WHERE  x.anggota_nik = a.nik
                     AND (x.tanggal_pengembalian > x.batas_pengembalian
                          OR (x.tanggal_pengembalian IS NULL AND x.batas_pengembalian < DATE '2026-11-05')))
GROUP  BY a.nik, a.nama
HAVING COUNT(*) >= 3
ORDER  BY jumlah_pinjam DESC, a.nama;

-- [A13] Kartu riwayat anggota teraktif dengan status tiap transaksi
SELECT p.tanggal_pinjam,
       b.judul,
       p.batas_pengembalian,
       p.tanggal_pengembalian,
       CASE WHEN p.tanggal_pengembalian IS NULL AND p.batas_pengembalian < DATE '2026-11-05' THEN 'MENUNGGAK'
            WHEN p.tanggal_pengembalian IS NULL                                     THEN 'DIPINJAM'
            WHEN p.tanggal_pengembalian > p.batas_pengembalian
                 THEN 'TERLAMBAT ' || (p.tanggal_pengembalian - p.batas_pengembalian) || ' hari'
            ELSE 'TEPAT WAKTU'
       END AS status
FROM   peminjaman p
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
WHERE  p.anggota_nik = (SELECT anggota_nik
                        FROM   peminjaman
                        GROUP  BY anggota_nik
                        ORDER  BY COUNT(*) DESC, anggota_nik
                        FETCH FIRST 1 ROW ONLY)
ORDER  BY p.tanggal_pinjam DESC
FETCH FIRST 15 ROWS ONLY;

-- [A14] Peminjaman per genre per tahun dalam bentuk tabel silang (PIVOT)
SELECT *
FROM  (SELECT g.nama AS genre, EXTRACT(YEAR FROM p.tanggal_pinjam) AS tahun
       FROM   peminjaman p
       JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
       JOIN   buku b         ON b.isbn = k.buku_isbn
       JOIN   genre g        ON g.id = b.genre_id)
PIVOT (COUNT(*) FOR tahun IN (2024 AS thn_2024, 2025 AS thn_2025, 2026 AS thn_2026))
ORDER  BY genre;

-- [A15] Pengadaan koleksi per tahun: eksemplar, judul, cara masuk, dan kumulatif
SELECT EXTRACT(YEAR FROM k.tanggal_masuk)                                   AS tahun,
       COUNT(*)                                                             AS eksemplar_masuk,
       COUNT(DISTINCT k.buku_isbn)                                          AS judul,
       SUM(CASE WHEN k.cara_masuk = 'PEMBELIAN' THEN 1 ELSE 0 END)           AS pembelian,
       SUM(CASE WHEN k.cara_masuk = 'HIBAH' THEN 1 ELSE 0 END)               AS hibah,
       SUM(CASE WHEN k.cara_masuk IN ('SUMBANGAN', 'TUKAR') THEN 1 ELSE 0 END) AS lainnya,
       SUM(COUNT(*)) OVER (ORDER BY EXTRACT(YEAR FROM k.tanggal_masuk))      AS kumulatif
FROM   buku_koleksi k
GROUP  BY EXTRACT(YEAR FROM k.tanggal_masuk)
ORDER  BY tahun;

-- [A16] Laporan denda per bulan pengembalian (tarif Rp1.000/hari)
SELECT TO_CHAR(tanggal_pengembalian, 'YYYY-MM')              AS bulan_kembali,
       COUNT(*)                                               AS pengembalian,
       SUM(CASE WHEN tanggal_pengembalian > batas_pengembalian THEN 1 ELSE 0 END) AS terlambat,
       SUM(GREATEST(tanggal_pengembalian - batas_pengembalian, 0))                AS total_hari_terlambat,
       SUM(GREATEST(tanggal_pengembalian - batas_pengembalian, 0)) * 1000         AS denda_rupiah,
       ROUND(AVG(CASE WHEN tanggal_pengembalian > batas_pengembalian
                      THEN tanggal_pengembalian - batas_pengembalian END), 1)      AS rata_hari_jika_terlambat,
       MAX(tanggal_pengembalian - batas_pengembalian)                             AS terlambat_terlama
FROM   peminjaman
WHERE  tanggal_pengembalian IS NOT NULL
GROUP  BY TO_CHAR(tanggal_pengembalian, 'YYYY-MM')
ORDER  BY bulan_kembali;

-- [A17] Daftar pengingat: pinjaman yang jatuh tempo hari ini sampai 7 hari ke depan
SELECT p.batas_pengembalian,
       p.batas_pengembalian - DATE '2026-11-05'                AS sisa_hari,
       a.nama,
       a.hp,
       b.judul,
       p.tanggal_pinjam
FROM   peminjaman p
JOIN   anggota a      ON a.nik = p.anggota_nik
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
WHERE  p.tanggal_pengembalian IS NULL
  AND  p.batas_pengembalian BETWEEN DATE '2026-11-05' AND DATE '2026-11-05' + 7
ORDER  BY p.batas_pengembalian, a.nama;

-- [A18] Penulis yang karyanya paling sering dipinjam (join lima tabel)
SELECT pn.nama                                   AS penulis,
       COUNT(DISTINCT b.isbn)                    AS judul_dipinjam,
       COUNT(*)                                  AS total_pinjaman,
       MIN(p.tanggal_pinjam)                     AS pertama_dipinjam,
       MAX(p.tanggal_pinjam)                     AS terakhir_dipinjam
FROM   peminjaman p
JOIN   buku_koleksi k  ON k.id = p.buku_koleksi_id
JOIN   buku b          ON b.isbn = k.buku_isbn
JOIN   buku_penulis bp ON bp.buku_isbn = b.isbn
JOIN   penulis pn      ON pn.nik = bp.penulis_id
GROUP  BY pn.nik, pn.nama
ORDER  BY total_pinjaman DESC, penulis
FETCH FIRST 10 ROWS ONLY;

-- [A19] Utilisasi koleksi per penerbit: pinjaman per eksemplar
SELECT pb.nama                                              AS penerbit,
       COUNT(DISTINCT b.isbn)                               AS judul,
       COUNT(DISTINCT k.id)                                 AS eksemplar,
       COUNT(p.tanggal_pinjam)                              AS pinjaman,
       ROUND(COUNT(p.tanggal_pinjam) / COUNT(DISTINCT k.id), 2) AS pinjaman_per_eksemplar
FROM   penerbit pb
JOIN   buku b            ON b.penerbit_id = pb.id
JOIN   buku_koleksi k    ON k.buku_isbn = b.isbn
LEFT   JOIN peminjaman p ON p.buku_koleksi_id = k.id
GROUP  BY pb.id, pb.nama
HAVING COUNT(DISTINCT k.id) >= 15
ORDER  BY pinjaman_per_eksemplar DESC, penerbit;

-- [A20] Buku berbahasa Indonesia vs Inggris: koleksi dan peminjaman
SELECT CASE WHEN SUBSTR(b.isbn, 1, 6) IN ('978602', '978979') THEN 'Indonesia' ELSE 'Inggris' END AS bahasa,
       COUNT(DISTINCT b.isbn)                                        AS judul,
       COUNT(DISTINCT k.id)                                          AS eksemplar,
       COUNT(p.tanggal_pinjam)                                       AS pinjaman,
       ROUND(100 * COUNT(p.tanggal_pinjam) / SUM(COUNT(p.tanggal_pinjam)) OVER (), 1) AS persen_pinjaman,
       ROUND(COUNT(p.tanggal_pinjam) / COUNT(DISTINCT k.id), 2)      AS pinjaman_per_eksemplar,
       ROUND(AVG(b.tahun_terbit))                                    AS rata_tahun_terbit
FROM   buku b
JOIN   buku_koleksi k    ON k.buku_isbn = b.isbn
LEFT   JOIN peminjaman p ON p.buku_koleksi_id = k.id
GROUP  BY CASE WHEN SUBSTR(b.isbn, 1, 6) IN ('978602', '978979') THEN 'Indonesia' ELSE 'Inggris' END
ORDER  BY bahasa;

-- [A21] Ragam minat anggota: jumlah genre berbeda dan genre favorit
SELECT a.nama,
       COUNT(*)                     AS pinjaman,
       COUNT(DISTINCT g.id)         AS genre_berbeda,
       STATS_MODE(g.nama)           AS genre_favorit,
       MIN(g.nama)                  AS genre_pertama_abjad
FROM   peminjaman p
JOIN   anggota a      ON a.nik = p.anggota_nik
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
JOIN   genre g        ON g.id = b.genre_id
GROUP  BY a.nik, a.nama
HAVING COUNT(*) >= 15
ORDER  BY genre_berbeda DESC, pinjaman DESC, a.nama
FETCH FIRST 12 ROWS ONLY;

-- [A22] Pemanfaatan koleksi per genre: eksemplar yang pernah dan tidak pernah dipinjam
SELECT g.nama                                                                        AS genre,
       COUNT(DISTINCT k.id)                                                          AS eksemplar,
       COUNT(DISTINCT CASE WHEN p.tanggal_pinjam IS NOT NULL THEN k.id END)          AS pernah_dipinjam,
       COUNT(DISTINCT k.id)
         - COUNT(DISTINCT CASE WHEN p.tanggal_pinjam IS NOT NULL THEN k.id END)      AS belum_pernah,
       ROUND(100 * COUNT(DISTINCT CASE WHEN p.tanggal_pinjam IS NOT NULL THEN k.id END)
                 / COUNT(DISTINCT k.id), 1)                                          AS persen_terpakai,
       ROUND(COUNT(p.tanggal_pinjam) / COUNT(DISTINCT k.id), 2)                      AS pinjaman_per_eksemplar
FROM   genre g
JOIN   buku b            ON b.genre_id = g.id
JOIN   buku_koleksi k    ON k.buku_isbn = b.isbn
LEFT   JOIN peminjaman p ON p.buku_koleksi_id = k.id
GROUP  BY g.id, g.nama
ORDER  BY persen_terpakai DESC;

-- [A23] Anggota tidak aktif: pinjaman terakhir lebih dari 6 bulan lalu
SELECT a.nama,
       a.hp,
       COUNT(*)                                                  AS total_pinjaman,
       MAX(p.tanggal_pinjam)                                     AS pinjaman_terakhir,
       DATE '2026-11-05' - MAX(p.tanggal_pinjam)                           AS hari_tidak_aktif,
       ROUND(MONTHS_BETWEEN(DATE '2026-11-05', MAX(p.tanggal_pinjam)), 1)  AS bulan_tidak_aktif
FROM   anggota a
JOIN   peminjaman p ON p.anggota_nik = a.nik
GROUP  BY a.nik, a.nama, a.hp
HAVING MAX(p.tanggal_pinjam) < DATE '2026-11-05' - 180
ORDER  BY pinjaman_terakhir, a.nama;

-- [A24] Tingkat keterlambatan menurut durasi pinjam dan kelompok anggota
SELECT CASE WHEN CASE WHEN TO_NUMBER(SUBSTR(a.nik, 11, 2)) >= 50 THEN 1900 ELSE 2000 END
                 + TO_NUMBER(SUBSTR(a.nik, 11, 2)) < 1999
            THEN 'Dosen/Staf' ELSE 'Mahasiswa' END                                           AS kelompok,
       COUNT(*)                                                                               AS pinjaman_selesai,
       SUM(CASE WHEN p.batas_pengembalian - p.tanggal_pinjam = 7  THEN 1 ELSE 0 END)          AS durasi_7,
       SUM(CASE WHEN p.batas_pengembalian - p.tanggal_pinjam = 7
                 AND p.tanggal_pengembalian > p.batas_pengembalian THEN 1 ELSE 0 END)          AS terlambat_7,
       SUM(CASE WHEN p.batas_pengembalian - p.tanggal_pinjam = 14 THEN 1 ELSE 0 END)          AS durasi_14,
       SUM(CASE WHEN p.batas_pengembalian - p.tanggal_pinjam = 14
                 AND p.tanggal_pengembalian > p.batas_pengembalian THEN 1 ELSE 0 END)          AS terlambat_14,
       ROUND(100 * SUM(CASE WHEN p.tanggal_pengembalian > p.batas_pengembalian THEN 1 ELSE 0 END)
                 / COUNT(*), 1)                                                                AS persen_terlambat
FROM   peminjaman p
JOIN   anggota a ON a.nik = p.anggota_nik
WHERE  p.tanggal_pengembalian IS NOT NULL
GROUP  BY CASE WHEN CASE WHEN TO_NUMBER(SUBSTR(a.nik, 11, 2)) >= 50 THEN 1900 ELSE 2000 END
                    + TO_NUMBER(SUBSTR(a.nik, 11, 2)) < 1999
               THEN 'Dosen/Staf' ELSE 'Mahasiswa' END
ORDER  BY kelompok;

-- [A25] Eksemplar paling sering dipinjam dan kondisinya (indikasi keausan)
SELECT k.id                                                          AS eksemplar,
       b.judul,
       k.kondisi,
       k.tanggal_masuk,
       COUNT(p.tanggal_pinjam)                                       AS kali_dipinjam,
       ROUND(MONTHS_BETWEEN(DATE '2026-11-05', k.tanggal_masuk) / 12, 1)       AS usia_tahun,
       ROUND(COUNT(p.tanggal_pinjam)
             / GREATEST(MONTHS_BETWEEN(DATE '2026-11-05', k.tanggal_masuk) / 12, 0.5), 1) AS pinjaman_per_tahun
FROM   buku_koleksi k
JOIN   buku b            ON b.isbn = k.buku_isbn
LEFT   JOIN peminjaman p ON p.buku_koleksi_id = k.id
GROUP  BY k.id, b.judul, k.kondisi, k.tanggal_masuk
ORDER  BY kali_dipinjam DESC, pinjaman_per_tahun DESC
FETCH FIRST 10 ROWS ONLY;


-- ######## B. Dasar SELECT, penyaringan, dan pengurutan ########

-- [B1] Alias, konkatenasi, aritmetika, dan DISTINCT
SELECT DISTINCT
       b.tahun_terbit                                              AS "Tahun Terbit",
       EXTRACT(YEAR FROM DATE '2026-11-05') - b.tahun_terbit                 AS usia_terbitan,
       'Terbit ' || b.tahun_terbit || ', usia '
         || (EXTRACT(YEAR FROM DATE '2026-11-05') - b.tahun_terbit) || ' tahun'  AS keterangan
FROM   buku b
WHERE  b.genre_id = 2
ORDER  BY b.tahun_terbit DESC;

-- [B2] Prioritas operator aritmetika dan penularan NULL
SELECT a.nama,
       p.tanggal_pinjam,
       p.tanggal_pengembalian,
       p.tanggal_pengembalian - p.tanggal_pinjam                      AS lama_hari,
       (p.tanggal_pengembalian - p.tanggal_pinjam) * 500              AS biaya_null,
       NVL(p.tanggal_pengembalian - p.tanggal_pinjam, 0) * 500        AS biaya_nvl,
       NVL(p.tanggal_pengembalian, DATE '2026-11-05') - p.tanggal_pinjam        AS lama_sampai_hari_ini,
       10 + 5 * 2                                                     AS tanpa_kurung,
       (10 + 5) * 2                                                   AS dengan_kurung
FROM   peminjaman p
JOIN   anggota a ON a.nik = p.anggota_nik
WHERE  p.tanggal_pinjam >= DATE '2026-10-28'
ORDER  BY p.tanggal_pinjam, a.nama
FETCH FIRST 10 ROWS ONLY;

-- [B3] Menyaring dengan BETWEEN, IN, LIKE, dan AND
SELECT b.judul, b.tahun_terbit, g.nama AS genre
FROM   buku b
JOIN   genre g ON g.id = b.genre_id
WHERE  b.tahun_terbit BETWEEN 2015 AND 2019
  AND  b.genre_id IN (1, 7, 9)
  AND  UPPER(b.judul) LIKE '%PYTHON%'
ORDER  BY b.tahun_terbit DESC, b.judul;

-- [B4] LIKE dengan karakter wildcard literal (ESCAPE) dan pola posisi (_)
SELECT judul,
       CASE WHEN judul LIKE '%\%%' ESCAPE '\' THEN 'mengandung %' ELSE 'pola C__' END AS cocok_karena
FROM   buku
WHERE  judul LIKE '%\%%' ESCAPE '\'
   OR  judul LIKE 'C__ %'
ORDER  BY cocok_karena, judul;

-- [B5] Prioritas AND di atas OR: hasil berbeda tanpa dan dengan kurung
SELECT 'genre_id = 1 OR genre_id = 9 AND tahun_terbit >= 2015'   AS kondisi, COUNT(*) AS judul
FROM   buku
WHERE  genre_id = 1 OR genre_id = 9 AND tahun_terbit >= 2015
UNION ALL
SELECT '(genre_id = 1 OR genre_id = 9) AND tahun_terbit >= 2015', COUNT(*)
FROM   buku
WHERE  (genre_id = 1 OR genre_id = 9) AND tahun_terbit >= 2015;

-- [B6] Tiga cara anti-join: NOT IN, NOT EXISTS, LEFT JOIN ... IS NULL
SELECT 'NOT IN' AS cara, COUNT(*) AS eksemplar_belum_pernah_dipinjam
FROM   buku_koleksi k
WHERE  k.id NOT IN (SELECT buku_koleksi_id FROM peminjaman)
UNION ALL
SELECT 'NOT EXISTS', COUNT(*)
FROM   buku_koleksi k
WHERE  NOT EXISTS (SELECT 1 FROM peminjaman p WHERE p.buku_koleksi_id = k.id)
UNION ALL
SELECT 'LEFT JOIN ... IS NULL', COUNT(*)
FROM   buku_koleksi k
LEFT   JOIN peminjaman p ON p.buku_koleksi_id = k.id
WHERE  p.buku_koleksi_id IS NULL;

-- [B7] ORDER BY: beberapa kunci, DESC, NULLS FIRST, posisi kolom, dan ekspresi di luar SELECT
SELECT a.nama, p.tanggal_pinjam, p.tanggal_pengembalian, p.batas_pengembalian
FROM   peminjaman p
JOIN   anggota a ON a.nik = p.anggota_nik
WHERE  p.tanggal_pinjam >= DATE '2026-10-20'
ORDER  BY p.tanggal_pengembalian DESC NULLS FIRST,
          2 DESC,
          LENGTH(a.nama)
FETCH FIRST 12 ROWS ONLY;

-- [B8] Membatasi baris: FETCH FIRST ... WITH TIES dan paginasi dengan OFFSET
SELECT b.judul, COUNT(*) AS pinjaman
FROM   peminjaman p
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
GROUP  BY b.isbn, b.judul
ORDER  BY pinjaman DESC
FETCH FIRST 5 ROWS WITH TIES;

SELECT b.judul, COUNT(*) AS pinjaman
FROM   peminjaman p
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
GROUP  BY b.isbn, b.judul
ORDER  BY pinjaman DESC, b.judul
OFFSET 10 ROWS FETCH NEXT 10 ROWS ONLY;

-- [B9] COUNT dengan DISTINCT pada kolom, ekspresi, dan gabungan kolom
SELECT COUNT(*)                                                        AS total_pinjaman,
       COUNT(DISTINCT anggota_nik)                                     AS anggota_berbeda,
       COUNT(DISTINCT buku_koleksi_id)                                 AS eksemplar_berbeda,
       COUNT(DISTINCT TRUNC(tanggal_pinjam, 'MM'))                     AS bulan_berbeda,
       COUNT(DISTINCT TO_CHAR(tanggal_pinjam, 'YYYY-MM') || '|' || anggota_nik) AS pasangan_bulan_anggota
FROM   peminjaman;

-- [B10] Tanda kutip tunggal di dalam teks: kutip ganda ('') dan operator q'[...]'
SELECT pb.nama                                                                  AS penerbit,
       'Terbitan ' || pb.nama || ' berjudul ''' || b.judul || ''''                AS dengan_kutip_ganda,
       q'[Terbitan ]' || pb.nama || q'[ berjudul ']' || b.judul || q'[']'         AS dengan_operator_q
FROM   buku b
JOIN   penerbit pb ON pb.id = b.penerbit_id
WHERE  pb.nama LIKE 'O''Reilly%'
ORDER  BY b.judul
FETCH FIRST 5 ROWS ONLY;


-- ######## C. Fungsi baris tunggal: karakter (teks) ########

-- [C1] Mengubah huruf dan menghitung panjang nama anggota
SELECT nama,
       UPPER(nama)          AS huruf_besar,
       LOWER(nama)          AS huruf_kecil,
       INITCAP(UPPER(nama)) AS kapital_awal,
       LENGTH(nama)         AS panjang
FROM   anggota
ORDER  BY panjang DESC, nama
FETCH FIRST 10 ROWS ONLY;

-- [C2] Memisahkan nama depan, nama belakang, dan inisial dengan SUBSTR + INSTR
SELECT nama,
       INSTR(nama, ' ')                                                  AS spasi_pertama,
       INSTR(nama, ' ', -1)                                              AS spasi_terakhir,
       SUBSTR(nama, 1, INSTR(nama, ' ') - 1)                             AS nama_depan,
       SUBSTR(nama, INSTR(nama, ' ', -1) + 1)                            AS nama_belakang,
       SUBSTR(nama, 1, 1) || SUBSTR(nama, INSTR(nama, ' ', -1) + 1, 1)   AS inisial,
       SUBSTR(nama, -4)                                                  AS empat_huruf_akhir
FROM   anggota
ORDER  BY nama_belakang, nama_depan
FETCH FIRST 10 ROWS ONLY;

-- [C3] Kode eksemplar dan label punggung buku dengan LPAD/RPAD
SELECT 'EKS-' || LPAD(TO_CHAR(k.id), 5, '0')                   AS kode_eksemplar,
       RPAD(SUBSTR(b.judul, 1, 40), 43, '.') || b.tahun_terbit  AS label_punggung,
       LPAD(TO_CHAR(b.tahun_terbit), 8, '*')                     AS tahun_rata_kanan,
       RPAD(k.kondisi, 12) || '|'                                AS kondisi_rata_kiri
FROM   buku_koleksi k
JOIN   buku b ON b.isbn = k.buku_isbn
WHERE  k.id BETWEEN 1 AND 10
ORDER  BY k.id;

-- [C4] TRIM, LTRIM, RTRIM: perhatikan argumen kedua adalah HIMPUNAN karakter
SELECT isbn,
       LTRIM(isbn, '978')                     AS ltrim_himpunan_978,
       SUBSTR(isbn, 4)                        AS tanpa_prefiks_978,
       RTRIM(isbn, '0123456789')              AS rtrim_semua_digit,
       TRIM(LEADING '9' FROM isbn)            AS trim_leading_9,
       LENGTH('   ' || judul || '   ')        AS panjang_dengan_spasi,
       LENGTH(TRIM('   ' || judul || '   ')) AS panjang_tanpa_spasi
FROM   buku
WHERE  isbn LIKE '978979%'
ORDER  BY isbn
FETCH FIRST 5 ROWS ONLY;

-- [C5] Menyamarkan nomor HP dan menormalkan teks dengan REPLACE dan TRANSLATE
SELECT nama,
       hp,
       '+62' || SUBSTR(hp, 2)                                                   AS hp_internasional,
       SUBSTR(hp, 1, 4) || TRANSLATE(SUBSTR(hp, 5), '0123456789', '**********') AS hp_tersamar,
       REPLACE(nama, ' ', '_')                                                  AS nama_garis_bawah,
       REPLACE(LOWER(nama), ' ', '.') || '@kampus.ac.id'                        AS email_usulan,
       TRANSLATE(UPPER(nama), 'AIUEO', '41930')                                 AS gaya_leet
FROM   anggota
ORDER  BY nama
FETCH FIRST 8 ROWS ONLY;

-- [C6] Menggabungkan teks dengan CONCAT, ||, CHR dan membaca kode ASCII
SELECT CONCAT(CONCAT(b.judul, ' -- '), p.nama)                   AS judul_penerbit,
       b.judul || CHR(10) || p.nama || CHR(10) || b.tahun_terbit    AS label_tiga_baris,
       ASCII(SUBSTR(b.judul, 1, 1))                                 AS kode_ascii_huruf_awal,
       CHR(ASCII(SUBSTR(b.judul, 1, 1)) + 1)                        AS huruf_berikutnya,
       CHR(65 + MOD(b.tahun_terbit, 26))                            AS huruf_dari_tahun
FROM   buku b
JOIN   penerbit p ON p.id = b.penerbit_id
WHERE  b.genre_id = 3
ORDER  BY b.judul
FETCH FIRST 5 ROWS ONLY;

-- [C7] Ekspresi reguler: REGEXP_COUNT, REGEXP_SUBSTR, REGEXP_INSTR, REGEXP_REPLACE
SELECT judul,
       REGEXP_COUNT(judul, '[[:digit:]]+')                                       AS jumlah_angka,
       REGEXP_SUBSTR(judul, '[[:digit:]]+')                                      AS angka_pertama,
       REGEXP_SUBSTR(judul, '[[:digit:]]+', 1, 2)                                AS angka_kedua,
       REGEXP_INSTR(judul, '[[:digit:]]')                                        AS posisi_angka_pertama,
       REGEXP_REPLACE(judul, '[^[:alnum:] ]', '')                                AS tanpa_tanda_baca,
       REGEXP_REPLACE(judul, '^([[:alpha:]]+) ([[:alpha:]]+)', '\2 \1')          AS dua_kata_pertama_ditukar
FROM   buku
WHERE  REGEXP_LIKE(judul, '[[:digit:]]')
ORDER  BY jumlah_angka DESC, judul
FETCH FIRST 10 ROWS ONLY;

-- [C8] REGEXP_LIKE sebagai kondisi pencarian (kata utuh, awalan, validasi format)
SELECT 'Judul mengandung kata utuh SQL'           AS kriteria, COUNT(*) AS jumlah
FROM   buku
WHERE  REGEXP_LIKE(judul, '(^|[^[:alnum:]])SQL([^[:alnum:]]|$)', 'i')
UNION ALL
SELECT 'Judul diawali angka', COUNT(*)
FROM   buku
WHERE  REGEXP_LIKE(judul, '^[[:digit:]]')
UNION ALL
SELECT 'Judul mengandung C++ atau C#', COUNT(*)
FROM   buku
WHERE  REGEXP_LIKE(judul, 'C(\+\+|#)')
UNION ALL
SELECT 'Nomor HP valid (08 diikuti 10 digit)', COUNT(*)
FROM   anggota
WHERE  REGEXP_LIKE(hp, '^08[[:digit:]]{10}$')
UNION ALL
SELECT 'Nama anggota tiga kata atau lebih', COUNT(*)
FROM   anggota
WHERE  REGEXP_LIKE(nama, '^[^ ]+ [^ ]+ [^ ]+');

-- [C9] Mencari nama yang bunyinya mirip dengan SOUNDEX
SELECT nama, SOUNDEX(nama) AS kode_soundex
FROM   penulis
WHERE  SOUNDEX(nama) IN (SOUNDEX('Budi Rahardjo'), SOUNDEX('Rinaldi Moenir'), SOUNDEX('Abdoel Kadir'))
ORDER  BY kode_soundex, nama;

-- [C10] Validasi check digit ISBN-13 dengan SUBSTR, TO_NUMBER, dan MOD
SELECT status_isbn, COUNT(*) AS judul
FROM  (SELECT isbn,
              CASE
                WHEN LENGTH(isbn) <> 13 OR NOT REGEXP_LIKE(isbn, '^[[:digit:]]{13}$') THEN 'FORMAT SALAH'
                WHEN MOD(10 - MOD(  TO_NUMBER(SUBSTR(isbn, 1, 1))     + TO_NUMBER(SUBSTR(isbn, 2, 1)) * 3
                                  + TO_NUMBER(SUBSTR(isbn, 3, 1))     + TO_NUMBER(SUBSTR(isbn, 4, 1)) * 3
                                  + TO_NUMBER(SUBSTR(isbn, 5, 1))     + TO_NUMBER(SUBSTR(isbn, 6, 1)) * 3
                                  + TO_NUMBER(SUBSTR(isbn, 7, 1))     + TO_NUMBER(SUBSTR(isbn, 8, 1)) * 3
                                  + TO_NUMBER(SUBSTR(isbn, 9, 1))     + TO_NUMBER(SUBSTR(isbn, 10, 1)) * 3
                                  + TO_NUMBER(SUBSTR(isbn, 11, 1))    + TO_NUMBER(SUBSTR(isbn, 12, 1)) * 3, 10), 10)
                     = TO_NUMBER(SUBSTR(isbn, 13, 1))                                          THEN 'VALID'
                ELSE 'CHECK DIGIT SALAH'
              END AS status_isbn
       FROM   buku)
GROUP  BY status_isbn
ORDER  BY status_isbn;


-- ######## D. Fungsi baris tunggal: angka ########

-- [D1] Membulatkan rata-rata lama pinjam: ROUND, TRUNC, CEIL, FLOOR
SELECT a.nama,
       COUNT(*)                                                   AS jumlah_pinjam,
       AVG(p.tanggal_pengembalian - p.tanggal_pinjam)             AS rata_hari_mentah,
       ROUND(AVG(p.tanggal_pengembalian - p.tanggal_pinjam), 2)   AS rata_2_desimal,
       ROUND(AVG(p.tanggal_pengembalian - p.tanggal_pinjam))      AS rata_bulat,
       TRUNC(AVG(p.tanggal_pengembalian - p.tanggal_pinjam), 1)   AS rata_potong_1_desimal,
       CEIL(AVG(p.tanggal_pengembalian - p.tanggal_pinjam))       AS pembulatan_atas,
       FLOOR(AVG(p.tanggal_pengembalian - p.tanggal_pinjam))      AS pembulatan_bawah
FROM   peminjaman p
JOIN   anggota a ON a.nik = p.anggota_nik
WHERE  p.tanggal_pengembalian IS NOT NULL
GROUP  BY a.nama
ORDER  BY jumlah_pinjam DESC
FETCH FIRST 10 ROWS ONLY;

-- [D2] Denda keterlambatan: MOD, TRUNC/ROUND dengan desimal negatif, CEIL untuk kelipatan
SELECT a.nama,
       b.judul,
       p.tanggal_pengembalian - p.batas_pengembalian                        AS hari_terlambat,
       TRUNC((p.tanggal_pengembalian - p.batas_pengembalian) / 7)           AS minggu_penuh,
       MOD(p.tanggal_pengembalian - p.batas_pengembalian, 7)                AS sisa_hari,
       (p.tanggal_pengembalian - p.batas_pengembalian) * 1500               AS denda,
       ROUND((p.tanggal_pengembalian - p.batas_pengembalian) * 1500, -3)    AS denda_bulat_ribuan,
       TRUNC((p.tanggal_pengembalian - p.batas_pengembalian) * 1500, -3)    AS denda_potong_ribuan,
       CEIL((p.tanggal_pengembalian - p.batas_pengembalian) * 1500 / 5000) * 5000 AS denda_kelipatan_5000
FROM   peminjaman p
JOIN   anggota a      ON a.nik = p.anggota_nik
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
WHERE  p.tanggal_pengembalian > p.batas_pengembalian
ORDER  BY hari_terlambat DESC, a.nama
FETCH FIRST 10 ROWS ONLY;

-- [D3] ABS, SIGN, GREATEST, LEAST pada selisih tanggal kembali terhadap batas
SELECT a.nama,
       p.tanggal_pinjam,
       p.batas_pengembalian,
       p.tanggal_pengembalian,
       p.tanggal_pengembalian - p.batas_pengembalian                        AS selisih,
       ABS(p.tanggal_pengembalian - p.batas_pengembalian)                   AS selisih_absolut,
       SIGN(p.tanggal_pengembalian - p.batas_pengembalian)                  AS tanda,
       GREATEST(p.tanggal_pengembalian - p.batas_pengembalian, 0)           AS hari_denda,
       LEAST(GREATEST(p.tanggal_pengembalian - p.batas_pengembalian, 0), 30) AS hari_denda_maks_30
FROM   peminjaman p
JOIN   anggota a ON a.nik = p.anggota_nik
WHERE  p.tanggal_pengembalian IS NOT NULL
  AND  p.tanggal_pinjam >= DATE '2026-10-01'
ORDER  BY p.tanggal_pinjam, a.nama
FETCH FIRST 12 ROWS ONLY;

-- [D4] POWER, SQRT, LN, LOG, EXP: simpangan baku dihitung manual vs STDDEV_POP
SELECT g.nama                                                                      AS genre,
       COUNT(*)                                                                    AS jumlah_judul,
       ROUND(AVG(b.tahun_terbit), 2)                                               AS rata_tahun,
       ROUND(SQRT(AVG(POWER(b.tahun_terbit, 2)) - POWER(AVG(b.tahun_terbit), 2)), 2) AS simpangan_baku_manual,
       ROUND(STDDEV_POP(b.tahun_terbit), 2)                                        AS stddev_pop,
       ROUND(LOG(10, COUNT(*)), 3)                                                 AS log10_jumlah,
       ROUND(LN(COUNT(*)), 3)                                                      AS ln_jumlah,
       ROUND(EXP(LN(COUNT(*))))                                                    AS exp_ln_kembali_ke_jumlah,
       POWER(2, CEIL(LOG(2, COUNT(*))))                                            AS pangkat_dua_terdekat
FROM   buku b
JOIN   genre g ON g.id = b.genre_id
GROUP  BY g.nama
ORDER  BY jumlah_judul DESC;

-- [D5] Histogram lama pinjam dengan WIDTH_BUCKET dan grafik batang RPAD
SELECT WIDTH_BUCKET(tanggal_pengembalian - tanggal_pinjam, 0, 40, 4) AS kelas,
       MIN(tanggal_pengembalian - tanggal_pinjam)                      AS hari_min,
       MAX(tanggal_pengembalian - tanggal_pinjam)                      AS hari_maks,
       COUNT(*)                                                        AS jumlah,
       RPAD('#', CAST(COUNT(*) / 25 AS INTEGER), '#')                  AS grafik
FROM   peminjaman
WHERE  tanggal_pengembalian IS NOT NULL
GROUP  BY WIDTH_BUCKET(tanggal_pengembalian - tanggal_pinjam, 0, 40, 4)
ORDER  BY kelas;

-- [D6] Normalisasi skor popularitas 0-100 (min-max) dan pembulatan ke kelipatan
SELECT judul,
       pinjaman,
       ROUND(100 * (pinjaman - MIN(pinjaman) OVER ())
                 / (MAX(pinjaman) OVER () - MIN(pinjaman) OVER ()), 1)   AS skor_0_100,
       ROUND(100 * (pinjaman - MIN(pinjaman) OVER ())
                 / (MAX(pinjaman) OVER () - MIN(pinjaman) OVER ()) / 5) * 5 AS skor_kelipatan_5,
       FLOOR(100 * (pinjaman - MIN(pinjaman) OVER ())
                 / (MAX(pinjaman) OVER () - MIN(pinjaman) OVER ()) / 10) * 10 AS skor_puluhan
FROM  (SELECT b.judul, COUNT(*) AS pinjaman
       FROM   peminjaman p
       JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
       JOIN   buku b         ON b.isbn = k.buku_isbn
       GROUP  BY b.isbn, b.judul)
ORDER  BY pinjaman DESC, judul
FETCH FIRST 10 ROWS ONLY;


-- ######## E. Fungsi baris tunggal: tanggal ########

-- [E1] Tanggal dan waktu sesi: SYSDATE, SYSTIMESTAMP, CURRENT_DATE, aritmetika dasar
SELECT SYSDATE                                    AS sysdate_server,
       SYSTIMESTAMP                               AS systimestamp_server,
       CURRENT_DATE                               AS current_date_sesi,
       SESSIONTIMEZONE                            AS zona_waktu_sesi,
       SYSDATE + 7                                AS seminggu_lagi,
       SYSDATE - 30                               AS tiga_puluh_hari_lalu,
       TRUNC(SYSDATE)                             AS hari_ini_pukul_00,
       ROUND((SYSDATE - TRUNC(SYSDATE)) * 24, 2)  AS jam_berjalan_hari_ini,
       TRUNC(SYSDATE - DATE '2024-01-03')         AS hari_sejak_transaksi_pertama
FROM   dual;

-- [E2] Usia koleksi dan jadwal: ADD_MONTHS, MONTHS_BETWEEN, LAST_DAY, NEXT_DAY
SELECT k.id,
       k.tanggal_masuk,
       ADD_MONTHS(k.tanggal_masuk, 12)                                 AS akhir_garansi_12_bulan,
       ADD_MONTHS(k.tanggal_masuk, -1)                                 AS sebulan_sebelumnya,
       ROUND(MONTHS_BETWEEN(DATE '2026-11-05', k.tanggal_masuk), 1)    AS usia_koleksi_bulan,
       TRUNC(MONTHS_BETWEEN(DATE '2026-11-05', k.tanggal_masuk) / 12)  AS usia_koleksi_tahun,
       LAST_DAY(k.tanggal_masuk)                                       AS akhir_bulan_masuk,
       LAST_DAY(k.tanggal_masuk) - k.tanggal_masuk                     AS sisa_hari_bulan_itu,
       NEXT_DAY(k.tanggal_masuk, 'MONDAY')                             AS senin_berikutnya,
       NEXT_DAY(LAST_DAY(k.tanggal_masuk), 'FRIDAY')                   AS jumat_pertama_bulan_depan
FROM   buku_koleksi k
WHERE  k.id BETWEEN 1 AND 8
ORDER  BY k.id;

-- [E3] Memotong dan membulatkan tanggal: TRUNC dan ROUND dengan format
SELECT tanggal_pinjam,
       TRUNC(tanggal_pinjam, 'MM')    AS trunc_bulan,
       ROUND(tanggal_pinjam, 'MM')    AS round_bulan,
       TRUNC(tanggal_pinjam, 'YYYY')  AS trunc_tahun,
       ROUND(tanggal_pinjam, 'YYYY')  AS round_tahun,
       TRUNC(tanggal_pinjam, 'Q')     AS awal_kuartal,
       TRUNC(tanggal_pinjam, 'IW')    AS senin_minggu_iso,
       TO_CHAR(tanggal_pinjam, 'IW')  AS minggu_iso_ke,
       TO_CHAR(tanggal_pinjam, 'DDD') AS hari_ke_dalam_tahun
FROM   peminjaman
WHERE  buku_koleksi_id = (SELECT buku_koleksi_id
                          FROM   peminjaman
                          GROUP  BY buku_koleksi_id
                          ORDER  BY COUNT(*) DESC, buku_koleksi_id
                          FETCH FIRST 1 ROW ONLY)
ORDER  BY tanggal_pinjam;

-- [E4] Rekap bulanan 12 bulan terakhir: TRUNC(tanggal, 'MM') dan EXTRACT sebagai kunci GROUP BY
SELECT TRUNC(tanggal_pinjam, 'MM')            AS awal_bulan,
       TO_CHAR(tanggal_pinjam, 'YYYY "Q"Q')   AS kuartal,
       EXTRACT(YEAR FROM tanggal_pinjam)      AS tahun,
       EXTRACT(MONTH FROM tanggal_pinjam)     AS bulan,
       COUNT(*)                               AS jumlah_pinjam,
       MIN(tanggal_pinjam)                    AS pinjam_pertama,
       MAX(tanggal_pinjam)                    AS pinjam_terakhir
FROM   peminjaman
WHERE  tanggal_pinjam >= ADD_MONTHS(TRUNC(DATE '2026-11-05', 'MM'), -11)
GROUP  BY TRUNC(tanggal_pinjam, 'MM'), TO_CHAR(tanggal_pinjam, 'YYYY "Q"Q'),
          EXTRACT(YEAR FROM tanggal_pinjam), EXTRACT(MONTH FROM tanggal_pinjam)
ORDER  BY awal_bulan;

-- [E5] Aritmetika tanggal pada pinjaman aktif: + n hari, INTERVAL, NUMTODSINTERVAL, ADD_MONTHS
SELECT a.nama,
       p.tanggal_pinjam,
       p.batas_pengembalian,
       p.batas_pengembalian - p.tanggal_pinjam                                AS lama_pinjam_hari,
       (p.batas_pengembalian - p.tanggal_pinjam) * 24                         AS lama_pinjam_jam,
       p.batas_pengembalian - 2                                               AS pengingat_h_minus_2,
       p.batas_pengembalian + INTERVAL '7' DAY                                AS jika_diperpanjang_7_hari,
       p.tanggal_pinjam + NUMTODSINTERVAL(p.batas_pengembalian - p.tanggal_pinjam, 'DAY') AS batas_hitung_ulang,
       ADD_MONTHS(p.tanggal_pinjam, 1)                                        AS sebulan_setelah_pinjam,
       DATE '2026-11-05' - p.batas_pengembalian                               AS hari_lewat_batas
FROM   peminjaman p
JOIN   anggota a ON a.nik = p.anggota_nik
WHERE  p.tanggal_pengembalian IS NULL
ORDER  BY p.batas_pengembalian, a.nama
FETCH FIRST 10 ROWS ONLY;

-- [E6] Menampilkan tanggal dalam berbagai format TO_CHAR, termasuk bahasa Indonesia
SELECT tanggal_pinjam,
       TO_CHAR(tanggal_pinjam, 'DD/MM/YYYY')                                            AS format_id,
       TO_CHAR(tanggal_pinjam, 'DD-MON-RR')                                             AS format_oracle_klasik,
       TO_CHAR(tanggal_pinjam, 'fmDay, DD Month YYYY')                                  AS panjang_inggris,
       TO_CHAR(tanggal_pinjam, 'fmDay, DD Month YYYY', 'NLS_DATE_LANGUAGE=INDONESIAN')  AS panjang_indonesia,
       TO_CHAR(tanggal_pinjam, 'Dy', 'NLS_DATE_LANGUAGE=INDONESIAN')                    AS hari_singkat,
       TO_CHAR(tanggal_pinjam, 'Q')                                                     AS kuartal,
       TO_CHAR(tanggal_pinjam, 'IW')                                                    AS minggu_iso,
       TO_CHAR(tanggal_pinjam, 'DDD')                                                   AS hari_ke,
       TO_CHAR(tanggal_pinjam, 'J')                                                     AS hari_julian,
       TO_CHAR(tanggal_pinjam, 'YYYY-MM-DD"T"HH24:MI:SS')                               AS iso_8601,
       TO_CHAR(tanggal_pinjam, 'Ddspth Month YYYY')                                     AS ejaan_ordinal
FROM   peminjaman
WHERE  anggota_nik = (SELECT MIN(nik) FROM anggota)
ORDER  BY tanggal_pinjam
FETCH FIRST 6 ROWS ONLY;

-- [E7] Menyaring berdasarkan periode: hari ini, minggu/bulan/kuartal berjalan, n hari terakhir
SELECT 'Hari ini (5 Nov 2026)'        AS periode, COUNT(*) AS jumlah
FROM   peminjaman WHERE tanggal_pinjam = DATE '2026-11-05'
UNION ALL
SELECT 'Minggu ISO berjalan', COUNT(*)
FROM   peminjaman WHERE TRUNC(tanggal_pinjam, 'IW') = TRUNC(DATE '2026-11-05', 'IW')
UNION ALL
SELECT 'Bulan berjalan', COUNT(*)
FROM   peminjaman WHERE TRUNC(tanggal_pinjam, 'MM') = TRUNC(DATE '2026-11-05', 'MM')
UNION ALL
SELECT '30 hari terakhir', COUNT(*)
FROM   peminjaman WHERE tanggal_pinjam > DATE '2026-11-05' - 30
UNION ALL
SELECT 'Kuartal berjalan', COUNT(*)
FROM   peminjaman WHERE TRUNC(tanggal_pinjam, 'Q') = TRUNC(DATE '2026-11-05', 'Q')
UNION ALL
SELECT 'Tahun berjalan', COUNT(*)
FROM   peminjaman WHERE EXTRACT(YEAR FROM tanggal_pinjam) = EXTRACT(YEAR FROM DATE '2026-11-05')
UNION ALL
SELECT 'Semua hari Sabtu', COUNT(*)
FROM   peminjaman WHERE TO_CHAR(tanggal_pinjam, 'DY', 'NLS_DATE_LANGUAGE=ENGLISH') = 'SAT'
UNION ALL
SELECT 'Semua bulan Januari', COUNT(*)
FROM   peminjaman WHERE EXTRACT(MONTH FROM tanggal_pinjam) = 1;

-- [E8] Kalender harian bulan berjalan termasuk hari tanpa transaksi (CONNECT BY LEVEL)
SELECT kal.tanggal,
       TO_CHAR(kal.tanggal, 'Dy', 'NLS_DATE_LANGUAGE=INDONESIAN') AS hari,
       NVL(SUM(h.pinjaman), 0)                                    AS pinjaman,
       NVL(SUM(h.kembali), 0)                                     AS pengembalian
FROM  (SELECT TRUNC(DATE '2026-11-05', 'MM') + LEVEL - 1 AS tanggal
       FROM   dual
       CONNECT BY LEVEL <= EXTRACT(DAY FROM LAST_DAY(DATE '2026-11-05'))) kal
LEFT   JOIN (SELECT tanggal_pinjam AS tanggal, COUNT(*) AS pinjaman, NULL AS kembali
             FROM   peminjaman
             GROUP  BY tanggal_pinjam
             UNION ALL
             SELECT tanggal_pengembalian, NULL, COUNT(*)
             FROM   peminjaman
             WHERE  tanggal_pengembalian IS NOT NULL
             GROUP  BY tanggal_pengembalian) h ON h.tanggal = kal.tanggal
WHERE  kal.tanggal <= DATE '2026-11-05'
GROUP  BY kal.tanggal
ORDER  BY kal.tanggal;

-- [E9] Rekap per tahun akademik dan semester (ganjil Agustus-Januari, genap Februari-Juli)
SELECT CASE WHEN EXTRACT(MONTH FROM tanggal_pinjam) >= 8
                 THEN EXTRACT(YEAR FROM tanggal_pinjam) || '/' || (EXTRACT(YEAR FROM tanggal_pinjam) + 1)
            WHEN EXTRACT(MONTH FROM tanggal_pinjam) = 1
                 THEN (EXTRACT(YEAR FROM tanggal_pinjam) - 1) || '/' || EXTRACT(YEAR FROM tanggal_pinjam)
            ELSE (EXTRACT(YEAR FROM tanggal_pinjam) - 1) || '/' || EXTRACT(YEAR FROM tanggal_pinjam)
       END                                                                           AS tahun_akademik,
       CASE WHEN EXTRACT(MONTH FROM tanggal_pinjam) BETWEEN 2 AND 7 THEN 'Genap' ELSE 'Ganjil' END AS semester,
       MIN(tanggal_pinjam)                                                           AS pinjam_pertama,
       MAX(tanggal_pinjam)                                                           AS pinjam_terakhir,
       COUNT(*)                                                                      AS pinjaman,
       COUNT(DISTINCT anggota_nik)                                                   AS anggota_aktif
FROM   peminjaman
GROUP  BY CASE WHEN EXTRACT(MONTH FROM tanggal_pinjam) >= 8
                 THEN EXTRACT(YEAR FROM tanggal_pinjam) || '/' || (EXTRACT(YEAR FROM tanggal_pinjam) + 1)
            WHEN EXTRACT(MONTH FROM tanggal_pinjam) = 1
                 THEN (EXTRACT(YEAR FROM tanggal_pinjam) - 1) || '/' || EXTRACT(YEAR FROM tanggal_pinjam)
            ELSE (EXTRACT(YEAR FROM tanggal_pinjam) - 1) || '/' || EXTRACT(YEAR FROM tanggal_pinjam)
          END,
          CASE WHEN EXTRACT(MONTH FROM tanggal_pinjam) BETWEEN 2 AND 7 THEN 'Genap' ELSE 'Ganjil' END
ORDER  BY pinjam_pertama;


-- ######## F. Fungsi konversi tipe data ########

-- [F1] Format angka dengan TO_CHAR: pemisah ribuan, desimal, Rupiah, nol di depan, notasi ilmiah, angka Romawi
SELECT a.nama,
       SUM(p.tanggal_pengembalian - p.batas_pengembalian) * 1500                                   AS denda_angka,
       TO_CHAR(SUM(p.tanggal_pengembalian - p.batas_pengembalian) * 1500, '999G999G999')          AS pemisah_ribuan,
       TO_CHAR(SUM(p.tanggal_pengembalian - p.batas_pengembalian) * 1500, 'FM999G999G999D00')     AS dua_desimal,
       TO_CHAR(SUM(p.tanggal_pengembalian - p.batas_pengembalian) * 1500, 'FML999G999G999',
               'NLS_CURRENCY=''Rp'' NLS_NUMERIC_CHARACTERS='',.''')                               AS rupiah,
       TO_CHAR(SUM(p.tanggal_pengembalian - p.batas_pengembalian) * 1500, '0000000000')           AS nol_di_depan,
       TO_CHAR(SUM(p.tanggal_pengembalian - p.batas_pengembalian) * 1500, '9.99EEEE')             AS notasi_ilmiah,
       TO_CHAR(COUNT(*), 'RN')                                                                     AS kali_terlambat_romawi,
       TO_CHAR(AVG(p.tanggal_pengembalian - p.batas_pengembalian), 'FM990D0')                      AS rata_hari_1_desimal
FROM   peminjaman p
JOIN   anggota a ON a.nik = p.anggota_nik
WHERE  p.tanggal_pengembalian > p.batas_pengembalian
GROUP  BY a.nama
ORDER  BY denda_angka DESC
FETCH FIRST 8 ROWS ONLY;

-- [F2] Format tanda bilangan dan heksadesimal: S, MI, PR, 0, X
SELECT tanggal_pengembalian - batas_pengembalian                 AS selisih,
       TO_CHAR(tanggal_pengembalian - batas_pengembalian, 'S999')   AS selalu_bertanda,
       TO_CHAR(tanggal_pengembalian - batas_pengembalian, '999MI')  AS tanda_di_belakang,
       TO_CHAR(tanggal_pengembalian - batas_pengembalian, '999PR')  AS negatif_dalam_kurung,
       TO_CHAR(ABS(tanggal_pengembalian - batas_pengembalian), '000') AS tiga_digit,
       TO_CHAR(ABS(tanggal_pengembalian - batas_pengembalian), 'XXX') AS heksadesimal
FROM   peminjaman
WHERE  tanggal_pengembalian IS NOT NULL
  AND  tanggal_pinjam BETWEEN DATE '2026-10-01' AND DATE '2026-10-03'
ORDER  BY selisih;

-- [F3] TO_NUMBER dengan format dan NLS, serta konversi implisit teks-angka
SELECT TO_NUMBER('1.234.567,89', '9G999G999D99', 'NLS_NUMERIC_CHARACTERS='',.''')               AS dari_format_indonesia,
       TO_NUMBER('Rp2.500.000', 'L9G999G999', 'NLS_CURRENCY=''Rp'' NLS_NUMERIC_CHARACTERS='',.''') AS dari_rupiah,
       TO_NUMBER('  42  ')                                                                      AS spasi_diabaikan,
       TO_NUMBER('1E3')                                                                         AS notasi_ilmiah,
       TO_NUMBER('FF', 'XX')                                                                    AS dari_heksadesimal,
       '10' + 5                                                                                 AS implisit_teks_ke_angka,
       '10' || 5                                                                                AS implisit_angka_ke_teks
FROM   dual;

-- [F4] Konversi implisit pada kondisi WHERE (bekerja, tetapi sebaiknya dihindari)
SELECT b.judul, b.tahun_terbit, b.genre_id
FROM   buku b
WHERE  b.tahun_terbit = '2015'
  AND  b.genre_id IN ('1', '9')
ORDER  BY b.judul
FETCH FIRST 6 ROWS ONLY;

-- [F5] Membaca tanggal lahir dari NIK: SUBSTR + TO_NUMBER + MOD + TO_DATE('DDMMRR')
WITH lahir AS (
  SELECT nik, nama,
         CASE WHEN TO_NUMBER(SUBSTR(nik, 7, 2)) > 40 THEN 'Perempuan' ELSE 'Laki-laki' END AS jenis_kelamin,
         TO_DATE(LPAD(TO_CHAR(MOD(TO_NUMBER(SUBSTR(nik, 7, 2)), 40)), 2, '0') || SUBSTR(nik, 9, 4), 'DDMMRR') AS tgl_lahir
  FROM   anggota)
SELECT nik,
       nama,
       jenis_kelamin,
       TO_CHAR(tgl_lahir, 'DD fmMonth YYYY', 'NLS_DATE_LANGUAGE=INDONESIAN') AS tanggal_lahir,
       TO_CHAR(tgl_lahir, 'fmDay', 'NLS_DATE_LANGUAGE=INDONESIAN')          AS hari_lahir,
       TRUNC(MONTHS_BETWEEN(DATE '2026-11-05', tgl_lahir) / 12)              AS usia_tahun,
       CASE WHEN EXTRACT(YEAR FROM tgl_lahir) >= 1999 THEN 'Mahasiswa' ELSE 'Dosen/Staf' END AS kelompok
FROM   lahir
ORDER  BY tgl_lahir
FETCH FIRST 10 ROWS ONLY;

-- [F6] TO_DATE dan TO_TIMESTAMP dengan berbagai format; RR vs YY; literal DATE/TIMESTAMP; CAST antar tipe tanggal
SELECT TO_DATE('17/08/1945', 'DD/MM/YYYY')                                            AS proklamasi,
       TO_DATE('05-NOV-26', 'DD-MON-RR')                                               AS rr_26_jadi_2026,
       TO_DATE('05-NOV-75', 'DD-MON-RR')                                               AS rr_75_jadi_1975,
       TO_DATE('05-NOV-75', 'DD-MON-YY')                                               AS yy_75_jadi_2075,
       TO_DATE('5 November 2026', 'DD Month YYYY', 'NLS_DATE_LANGUAGE=INDONESIAN')     AS dari_teks_indonesia,
       TO_DATE('2026-11-05 14:30', 'YYYY-MM-DD HH24:MI')                                AS dengan_jam_menit,
       TO_TIMESTAMP('2026-11-05 14:30:15.250', 'YYYY-MM-DD HH24:MI:SS.FF3')             AS timestamp_milidetik,
       DATE '2026-11-05'                                                                AS literal_date_ansi,
       TIMESTAMP '2026-11-05 14:30:15'                                                  AS literal_timestamp_ansi,
       CAST(DATE '2026-11-05' AS TIMESTAMP)                                             AS cast_date_ke_timestamp,
       CAST(TIMESTAMP '2026-11-05 14:30:15' AS DATE)                                    AS cast_timestamp_ke_date
FROM   dual;

-- [F7] CAST ke VARCHAR2, NUMBER, INTEGER, TIMESTAMP dan konversi implisit NUMBER ke teks
SELECT k.id,
       CAST(k.id AS VARCHAR2(10))                           AS id_sebagai_teks,
       CAST(b.tahun_terbit AS VARCHAR2(4)) || '-' || b.isbn  AS kunci_gabungan,
       CAST('2015' AS NUMBER)                               AS teks_ke_number,
       CAST(ROUND(k.id / 7, 3) AS NUMBER(10, 1))            AS number_1_desimal,
       CAST(SUBSTR(b.isbn, 1, 3) AS INTEGER) + 1            AS prefiks_isbn_plus_1,
       CAST(k.tanggal_masuk AS TIMESTAMP)                   AS date_ke_timestamp,
       TO_CHAR(k.tanggal_masuk)                             AS tanggal_format_sesi,
       TO_CHAR(k.tanggal_masuk, 'YYYY-MM-DD')               AS tanggal_format_tetap,
       LENGTH(k.id)                                         AS panjang_digit_implisit
FROM   buku_koleksi k
JOIN   buku b ON b.isbn = k.buku_isbn
WHERE  k.id <= 5
ORDER  BY k.id;

-- [F8] Membandingkan tanggal: literal DATE, TO_DATE (format penuh dan RR), dan TO_CHAR pada kolom
SELECT 'Literal DATE'                 AS cara, COUNT(*) AS pinjaman
FROM   peminjaman WHERE tanggal_pinjam = DATE '2026-11-05'
UNION ALL
SELECT 'TO_DATE dengan format', COUNT(*)
FROM   peminjaman WHERE tanggal_pinjam = TO_DATE('05/11/2026', 'DD/MM/YYYY')
UNION ALL
SELECT 'TO_DATE tahun dua digit (RR, bahasa eksplisit)', COUNT(*)
FROM   peminjaman WHERE tanggal_pinjam = TO_DATE('05-NOV-26', 'DD-MON-RR', 'NLS_DATE_LANGUAGE=ENGLISH')
UNION ALL
SELECT 'TO_CHAR pada kolom (indeks tidak terpakai)', COUNT(*)
FROM   peminjaman WHERE TO_CHAR(tanggal_pinjam, 'YYYY-MM-DD') = '2026-11-05';


-- ######## G. Fungsi umum dan ekspresi kondisional ########

-- [G1] Menangani NULL pada tanggal pengembalian: NVL, NVL2, NULLIF, COALESCE
SELECT a.nama,
       p.tanggal_pinjam,
       p.batas_pengembalian,
       p.tanggal_pengembalian,
       NVL(TO_CHAR(p.tanggal_pengembalian, 'DD/MM/YYYY'), 'belum kembali')              AS kembali_teks,
       NVL2(p.tanggal_pengembalian, 'SELESAI', 'DIPINJAM')                               AS status_pinjam,
       NVL(p.tanggal_pengembalian, DATE '2026-11-05') - p.tanggal_pinjam                  AS lama_pinjam_hari,
       COALESCE(p.tanggal_pengembalian, p.batas_pengembalian, p.tanggal_pinjam)          AS tanggal_acuan,
       NULLIF(p.tanggal_pengembalian, p.batas_pengembalian)                              AS null_jika_tepat_di_batas,
       GREATEST(NVL(p.tanggal_pengembalian, DATE '2026-11-05') - p.batas_pengembalian, 0) AS hari_terlambat
FROM   peminjaman p
JOIN   anggota a ON a.nik = p.anggota_nik
WHERE  p.tanggal_pinjam >= DATE '2026-10-26'
ORDER  BY p.tanggal_pinjam, a.nama
FETCH FIRST 12 ROWS ONLY;

-- [G2] DECODE dan CASE sederhana: menerjemahkan kode kondisi menjadi tindakan
SELECT k.kondisi,
       k.cara_masuk,
       DECODE(k.kondisi, 'BAIK',         'Layak pinjam',
                         'RUSAK RINGAN', 'Layak pinjam, jadwalkan perbaikan',
                         'RUSAK BERAT',  'Tarik dari rak, usulkan penggantian',
                         'HILANG',       'Hapus dari katalog, tagih anggota',
                                         'Tidak diketahui')                     AS tindakan_decode,
       CASE k.kondisi
            WHEN 'BAIK'         THEN 'Layak pinjam'
            WHEN 'RUSAK RINGAN' THEN 'Layak pinjam, jadwalkan perbaikan'
            WHEN 'RUSAK BERAT'  THEN 'Tarik dari rak, usulkan penggantian'
            WHEN 'HILANG'       THEN 'Hapus dari katalog, tagih anggota'
            ELSE 'Tidak diketahui'
       END                                                                       AS tindakan_case,
       SUM(DECODE(k.cara_masuk, 'PEMBELIAN', 1, 0))                              AS dibeli,
       COUNT(*)                                                                  AS eksemplar
FROM   buku_koleksi k
GROUP  BY k.kondisi, k.cara_masuk
ORDER  BY k.kondisi, k.cara_masuk;

-- [G3] CASE bersyarat (searched CASE) di SELECT, di dalam SUM, dan di ORDER BY
SELECT a.nama,
       COUNT(*)                                                                        AS total,
       SUM(CASE WHEN p.tanggal_pengembalian IS NULL THEN 1 ELSE 0 END)                 AS belum_kembali,
       SUM(CASE WHEN p.tanggal_pengembalian <= p.batas_pengembalian THEN 1 ELSE 0 END) AS tepat_waktu,
       SUM(CASE WHEN p.tanggal_pengembalian >  p.batas_pengembalian THEN 1 ELSE 0 END) AS terlambat,
       CASE
            WHEN SUM(CASE WHEN p.tanggal_pengembalian > p.batas_pengembalian THEN 1 ELSE 0 END) = 0          THEN 'Teladan'
            WHEN SUM(CASE WHEN p.tanggal_pengembalian > p.batas_pengembalian THEN 1 ELSE 0 END) * 4 < COUNT(*) THEN 'Baik'
            WHEN SUM(CASE WHEN p.tanggal_pengembalian > p.batas_pengembalian THEN 1 ELSE 0 END) * 2 < COUNT(*) THEN 'Cukup'
            ELSE 'Perlu pembinaan'
       END                                                                              AS kategori
FROM   peminjaman p
JOIN   anggota a ON a.nik = p.anggota_nik
GROUP  BY a.nama
HAVING COUNT(*) >= 20
ORDER  BY CASE WHEN SUM(CASE WHEN p.tanggal_pengembalian > p.batas_pengembalian THEN 1 ELSE 0 END) = 0 THEN 0 ELSE 1 END,
          terlambat, a.nama;

-- [G4] DECODE dengan SIGN dan MOD untuk perbandingan, dibandingkan CASE berjenjang
SELECT b.judul,
       b.tahun_terbit,
       DECODE(SIGN(b.tahun_terbit - 2010), -1, 'Sebelum 2010', 0, 'Tepat 2010', 'Sesudah 2010') AS kategori_decode,
       CASE WHEN b.tahun_terbit <  2000 THEN 'Klasik'
            WHEN b.tahun_terbit <  2010 THEN 'Lama'
            WHEN b.tahun_terbit <  2020 THEN 'Modern'
            ELSE 'Terbaru'
       END                                                                                     AS kategori_case,
       DECODE(MOD(b.tahun_terbit, 2), 0, 'genap', 'ganjil')                                    AS paritas_tahun
FROM   buku b
WHERE  b.genre_id = 7
ORDER  BY b.tahun_terbit DESC, b.judul
FETCH FIRST 10 ROWS ONLY;

-- [G5] LNNVL: kondisi yang bernilai FALSE atau UNKNOWN (NULL) sekaligus
SELECT CASE WHEN p.tanggal_pengembalian IS NULL THEN 'Belum kembali' ELSE 'Terlambat' END AS keadaan,
       COUNT(*)                                                                               AS pinjaman,
       MIN(p.tanggal_pinjam)                                                                  AS paling_awal,
       MAX(p.tanggal_pinjam)                                                                  AS paling_akhir
FROM   peminjaman p
WHERE  LNNVL(p.tanggal_pengembalian <= p.batas_pengembalian)
GROUP  BY CASE WHEN p.tanggal_pengembalian IS NULL THEN 'Belum kembali' ELSE 'Terlambat' END
ORDER  BY keadaan;

-- [G6] Pengurutan kustom dengan DECODE/CASE di ORDER BY
SELECT k.kondisi,
       COUNT(*)                                           AS eksemplar,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)    AS persen,
       DECODE(k.kondisi, 'BAIK', 1, 'RUSAK RINGAN', 2, 'RUSAK BERAT', 3, 'HILANG', 4, 9) AS urutan_keparahan
FROM   buku_koleksi k
GROUP  BY k.kondisi
ORDER  BY DECODE(k.kondisi, 'BAIK', 1, 'RUSAK RINGAN', 2, 'RUSAK BERAT', 3, 'HILANG', 4, 9);


-- ######## H. Fungsi baris jamak (fungsi grup) ########

-- [H1] Ringkasan satu baris untuk seluruh tabel peminjaman: COUNT, MIN, MAX, SUM, AVG, STDDEV, VARIANCE, MEDIAN
SELECT COUNT(*)                                                 AS jumlah_transaksi,
       COUNT(tanggal_pengembalian)                              AS sudah_kembali,
       COUNT(*) - COUNT(tanggal_pengembalian)                   AS belum_kembali,
       COUNT(DISTINCT anggota_nik)                              AS anggota_unik,
       COUNT(DISTINCT buku_koleksi_id)                          AS eksemplar_unik,
       MIN(tanggal_pinjam)                                      AS pinjam_pertama,
       MAX(tanggal_pinjam)                                      AS pinjam_terakhir,
       SUM(batas_pengembalian - tanggal_pinjam)                 AS total_hari_dipinjamkan,
       ROUND(AVG(batas_pengembalian - tanggal_pinjam), 2)       AS rata_durasi_pinjam,
       ROUND(AVG(tanggal_pengembalian - tanggal_pinjam), 2)     AS rata_lama_aktual,
       MEDIAN(tanggal_pengembalian - tanggal_pinjam)            AS median_lama_aktual,
       ROUND(STDDEV(tanggal_pengembalian - tanggal_pinjam), 2)  AS simpangan_baku,
       ROUND(VARIANCE(tanggal_pengembalian - tanggal_pinjam), 2) AS varians
FROM   peminjaman;

-- [H2] Pengaruh NULL pada AVG: dengan dan tanpa NVL, pada anggota yang masih memegang buku
SELECT a.nama,
       COUNT(*)                                                                        AS transaksi,
       COUNT(p.tanggal_pengembalian)                                                   AS kembali,
       ROUND(AVG(p.tanggal_pengembalian - p.tanggal_pinjam), 1)                        AS rata_tanpa_null,
       ROUND(AVG(NVL(p.tanggal_pengembalian, DATE '2026-11-05') - p.tanggal_pinjam), 1) AS rata_dengan_nvl,
       MAX(p.tanggal_pengembalian - p.batas_pengembalian)                              AS keterlambatan_terlama,
       MIN(p.tanggal_pengembalian - p.batas_pengembalian)                              AS pengembalian_paling_awal
FROM   peminjaman p
JOIN   anggota a ON a.nik = p.anggota_nik
GROUP  BY a.nama
HAVING COUNT(*) <> COUNT(p.tanggal_pengembalian)
ORDER  BY transaksi DESC, a.nama;

-- [H3] GROUP BY dua kolom dengan HAVING; MIN/MAX juga berlaku untuk teks dan tanggal
SELECT g.nama                                               AS genre,
       k.kondisi,
       COUNT(*)                                             AS eksemplar,
       MIN(b.judul)                                         AS judul_pertama_abjad,
       MAX(b.judul)                                         AS judul_terakhir_abjad,
       MIN(k.tanggal_masuk)                                 AS pengadaan_pertama,
       MAX(k.tanggal_masuk)                                 AS pengadaan_terakhir,
       MIN(b.tahun_terbit) || ' - ' || MAX(b.tahun_terbit)  AS rentang_tahun_terbit
FROM   buku_koleksi k
JOIN   buku b  ON b.isbn = k.buku_isbn
JOIN   genre g ON g.id = b.genre_id
GROUP  BY g.nama, k.kondisi
HAVING COUNT(*) >= 5
ORDER  BY g.nama, eksemplar DESC;

-- [H4] LISTAGG: daftar penulis per judul dalam satu baris
SELECT b.judul,
       COUNT(bp.penulis_id)                                     AS jumlah_penulis,
       LISTAGG(pn.nama, '; ') WITHIN GROUP (ORDER BY pn.nama)   AS daftar_penulis
FROM   buku b
JOIN   buku_penulis bp ON bp.buku_isbn = b.isbn
JOIN   penulis pn      ON pn.nik = bp.penulis_id
GROUP  BY b.isbn, b.judul
HAVING COUNT(bp.penulis_id) >= 3
ORDER  BY jumlah_penulis DESC, b.judul;

-- [H5] LISTAGG dengan ON OVERFLOW TRUNCATE: daftar judul per penulis produktif
SELECT pn.nama                                                        AS penulis,
       COUNT(*)                                                       AS jumlah_judul,
       MIN(b.tahun_terbit) || '-' || MAX(b.tahun_terbit)              AS rentang_terbit,
       LISTAGG(b.judul, ' | ' ON OVERFLOW TRUNCATE '...' WITH COUNT)
           WITHIN GROUP (ORDER BY b.tahun_terbit, b.judul)            AS judul
FROM   penulis pn
JOIN   buku_penulis bp ON bp.penulis_id = pn.nik
JOIN   buku b          ON b.isbn = bp.buku_isbn
GROUP  BY pn.nama
HAVING COUNT(*) >= 5
ORDER  BY jumlah_judul DESC, pn.nama;

-- [H6] Subtotal dan total dengan ROLLUP; GROUPING membedakan baris subtotal
SELECT DECODE(GROUPING(g.nama), 1, '** TOTAL **', g.nama)                     AS genre,
       CASE WHEN GROUPING(k.cara_masuk) = 1 AND GROUPING(g.nama) = 0 THEN '-- subtotal genre --'
            WHEN GROUPING(k.cara_masuk) = 1                           THEN NULL
            ELSE k.cara_masuk
       END                                                                       AS cara_masuk,
       COUNT(*)                                                                  AS eksemplar,
       SUM(CASE WHEN k.kondisi = 'BAIK' THEN 1 ELSE 0 END)                        AS kondisi_baik
FROM   buku_koleksi k
JOIN   buku b  ON b.isbn = k.buku_isbn
JOIN   genre g ON g.id = b.genre_id
GROUP  BY ROLLUP(g.nama, k.cara_masuk)
ORDER  BY GROUPING(g.nama), g.nama, GROUPING(k.cara_masuk), k.cara_masuk;

-- [H7] CUBE: semua kombinasi subtotal tahun x durasi pinjam
SELECT EXTRACT(YEAR FROM p.tanggal_pinjam)                   AS tahun,
       p.batas_pengembalian - p.tanggal_pinjam               AS durasi_hari,
       COUNT(*)                                              AS transaksi,
       GROUPING(EXTRACT(YEAR FROM p.tanggal_pinjam))         AS g_tahun,
       GROUPING(p.batas_pengembalian - p.tanggal_pinjam)     AS g_durasi
FROM   peminjaman p
GROUP  BY CUBE(EXTRACT(YEAR FROM p.tanggal_pinjam), p.batas_pengembalian - p.tanggal_pinjam)
ORDER  BY g_tahun, tahun, g_durasi, durasi_hari;

-- [H8] GROUPING SETS: dua rekap berbeda (per genre dan per tahun) dalam satu query
SELECT g.nama                                  AS genre,
       TO_CHAR(p.tanggal_pinjam, 'YYYY')       AS tahun,
       COUNT(*)                                AS transaksi,
       COUNT(DISTINCT p.anggota_nik)           AS anggota
FROM   peminjaman p
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
JOIN   genre g        ON g.id = b.genre_id
GROUP  BY GROUPING SETS ((g.nama), (TO_CHAR(p.tanggal_pinjam, 'YYYY')), ())
ORDER  BY genre NULLS LAST, tahun NULLS LAST;

-- [H9] Fungsi grup bersarang (MAX(COUNT(*))) dan padanannya dengan subquery
SELECT MAX(COUNT(*))           AS pinjaman_terbanyak_satu_anggota,
       MIN(COUNT(*))           AS pinjaman_tersedikit_satu_anggota,
       ROUND(AVG(COUNT(*)), 2) AS rata_pinjaman_per_anggota,
       COUNT(COUNT(*))         AS jumlah_anggota_aktif
FROM   peminjaman
GROUP  BY anggota_nik;

SELECT MAX(jumlah)            AS pinjaman_terbanyak_satu_anggota,
       MIN(jumlah)            AS pinjaman_tersedikit_satu_anggota,
       ROUND(AVG(jumlah), 2)  AS rata_pinjaman_per_anggota,
       COUNT(*)               AS jumlah_anggota_aktif
FROM   (SELECT anggota_nik, COUNT(*) AS jumlah
        FROM   peminjaman
        GROUP  BY anggota_nik);

-- [H10] HAVING dengan subquery: genre yang rata-rata keterlambatannya di atas rata-rata keseluruhan
SELECT g.nama                                                                   AS genre,
       COUNT(*)                                                                 AS dikembalikan,
       ROUND(AVG(GREATEST(p.tanggal_pengembalian - p.batas_pengembalian, 0)), 2) AS rata_hari_terlambat,
       ROUND(100 * SUM(CASE WHEN p.tanggal_pengembalian > p.batas_pengembalian THEN 1 ELSE 0 END) / COUNT(*), 1) AS persen_terlambat
FROM   peminjaman p
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
JOIN   genre g        ON g.id = b.genre_id
WHERE  p.tanggal_pengembalian IS NOT NULL
GROUP  BY g.nama
HAVING AVG(GREATEST(p.tanggal_pengembalian - p.batas_pengembalian, 0)) >
       (SELECT AVG(GREATEST(tanggal_pengembalian - batas_pengembalian, 0))
        FROM   peminjaman
        WHERE  tanggal_pengembalian IS NOT NULL)
ORDER  BY rata_hari_terlambat DESC;

-- [H11] Statistik sebaran per genre: STATS_MODE, MEDIAN, PERCENTILE_CONT, PERCENTILE_DISC, CORR
SELECT g.nama                                                                                  AS genre,
       COUNT(*)                                                                                AS dikembalikan,
       STATS_MODE(p.tanggal_pengembalian - p.tanggal_pinjam)                                   AS modus_lama_pinjam,
       MEDIAN(p.tanggal_pengembalian - p.tanggal_pinjam)                                       AS median_lama_pinjam,
       PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY p.tanggal_pengembalian - p.tanggal_pinjam)  AS persentil_90,
       PERCENTILE_DISC(0.9) WITHIN GROUP (ORDER BY p.tanggal_pengembalian - p.tanggal_pinjam)  AS persentil_90_diskrit,
       ROUND(CORR(b.tahun_terbit, p.tanggal_pengembalian - p.tanggal_pinjam), 3)               AS korelasi_tahun_vs_lama
FROM   peminjaman p
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
JOIN   genre g        ON g.id = b.genre_id
WHERE  p.tanggal_pengembalian IS NOT NULL
GROUP  BY g.nama
ORDER  BY g.nama;

-- [H12] Transaksi per hari dalam seminggu: TO_CHAR berbahasa Indonesia, persentase dari total, grafik batang
SELECT tanggal_pinjam - TRUNC(tanggal_pinjam, 'IW') + 1                   AS urutan_hari_iso,
       TO_CHAR(tanggal_pinjam, 'fmDay', 'NLS_DATE_LANGUAGE=INDONESIAN')   AS hari,
       COUNT(*)                                                           AS transaksi,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                    AS persen,
       RPAD('#', CAST(COUNT(*) / 20 AS INTEGER), '#')                      AS grafik
FROM   peminjaman
GROUP  BY tanggal_pinjam - TRUNC(tanggal_pinjam, 'IW') + 1,
          TO_CHAR(tanggal_pinjam, 'fmDay', 'NLS_DATE_LANGUAGE=INDONESIAN')
ORDER  BY urutan_hari_iso;

-- [H13] Produktivitas penerbit: COUNT DISTINCT, rasio antar agregat, HAVING
SELECT pb.nama                                           AS penerbit,
       COUNT(DISTINCT b.isbn)                            AS judul,
       COUNT(k.id)                                       AS eksemplar,
       COUNT(DISTINCT b.genre_id)                        AS ragam_genre,
       MIN(b.tahun_terbit)                               AS terbit_terlama,
       MAX(b.tahun_terbit)                               AS terbit_terbaru,
       ROUND(COUNT(k.id) / COUNT(DISTINCT b.isbn), 2)    AS eksemplar_per_judul
FROM   penerbit pb
JOIN   buku b         ON b.penerbit_id = pb.id
JOIN   buku_koleksi k ON k.buku_isbn = b.isbn
GROUP  BY pb.nama
HAVING COUNT(DISTINCT b.isbn) >= 10
ORDER  BY judul DESC, penerbit;

-- [H14] Kelompok usia anggota (dari NIK) dan perilaku peminjamannya
WITH usia AS (
  SELECT a.nik, a.nama,
         TRUNC(MONTHS_BETWEEN(DATE '2026-11-05',
               TO_DATE(LPAD(TO_CHAR(MOD(TO_NUMBER(SUBSTR(a.nik, 7, 2)), 40)), 2, '0') || SUBSTR(a.nik, 9, 4), 'DDMMRR')) / 12) AS umur
  FROM   anggota a)
SELECT CASE WHEN u.umur < 21 THEN '< 21'
            WHEN u.umur BETWEEN 21 AND 24 THEN '21-24'
            WHEN u.umur BETWEEN 25 AND 34 THEN '25-34'
            ELSE '35+'
       END                                                                               AS kelompok_usia,
       COUNT(DISTINCT u.nik)                                                              AS anggota,
       COUNT(p.tanggal_pinjam)                                                            AS pinjaman,
       ROUND(COUNT(p.tanggal_pinjam) / COUNT(DISTINCT u.nik), 1)                          AS pinjaman_per_anggota,
       ROUND(100 * SUM(CASE WHEN p.tanggal_pengembalian > p.batas_pengembalian THEN 1 ELSE 0 END)
                 / NULLIF(COUNT(p.tanggal_pengembalian), 0), 1)                            AS persen_terlambat
FROM   usia u
LEFT   JOIN peminjaman p ON p.anggota_nik = u.nik
GROUP  BY CASE WHEN u.umur < 21 THEN '< 21'
               WHEN u.umur BETWEEN 21 AND 24 THEN '21-24'
               WHEN u.umur BETWEEN 25 AND 34 THEN '25-34'
               ELSE '35+'
          END
ORDER  BY kelompok_usia;

-- [H15] HAVING dengan COUNT(DISTINCT) dan beberapa syarat agregat sekaligus
SELECT a.nama,
       COUNT(*)                                                     AS pinjaman,
       COUNT(DISTINCT b.genre_id)                                   AS genre_berbeda,
       ROUND(AVG(p.tanggal_pengembalian - p.tanggal_pinjam), 1)     AS rata_lama_pinjam
FROM   peminjaman p
JOIN   anggota a      ON a.nik = p.anggota_nik
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
GROUP  BY a.nik, a.nama
HAVING COUNT(DISTINCT b.genre_id) >= 7
   AND AVG(p.tanggal_pengembalian - p.tanggal_pinjam) < 12
   AND MAX(p.tanggal_pengembalian - p.batas_pengembalian) <= 30
ORDER  BY genre_berbeda DESC, pinjaman DESC, a.nama;


-- ######## I. Penggabungan tabel (JOIN) ########

-- [I1] INNER JOIN enam tabel: transaksi lengkap bulan berjalan
SELECT p.tanggal_pinjam,
       a.nama      AS anggota,
       b.judul,
       g.nama      AS genre,
       pb.nama     AS penerbit,
       k.id        AS eksemplar,
       k.kondisi,
       p.batas_pengembalian,
       p.tanggal_pengembalian
FROM   peminjaman p
JOIN   anggota a      ON a.nik = p.anggota_nik
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
JOIN   genre g        ON g.id = b.genre_id
JOIN   penerbit pb    ON pb.id = b.penerbit_id
WHERE  p.tanggal_pinjam >= TRUNC(DATE '2026-11-05', 'MM')
ORDER  BY p.tanggal_pinjam DESC, a.nama;

-- [I2] LEFT OUTER JOIN: semua genre, termasuk yang tidak dipinjam pada periode tertentu
SELECT g.nama                     AS genre,
       COUNT(p.tanggal_pinjam)    AS pinjaman_minggu_ini,
       MIN(p.tanggal_pinjam)      AS pertama,
       MAX(p.tanggal_pinjam)      AS terakhir
FROM   genre g
LEFT   JOIN buku b         ON b.genre_id = g.id
LEFT   JOIN buku_koleksi k ON k.buku_isbn = b.isbn
LEFT   JOIN peminjaman p   ON p.buku_koleksi_id = k.id
                          AND p.tanggal_pinjam BETWEEN TRUNC(DATE '2026-11-05', 'IW') AND DATE '2026-11-05'
GROUP  BY g.id, g.nama
ORDER  BY pinjaman_minggu_ini DESC, genre;

-- [I3] Notasi outer join lama Oracle (+) dan jebakan kondisi di WHERE
SELECT g.nama AS genre, COUNT(p.tanggal_pinjam) AS pinjaman_bulan_ini
FROM   genre g, buku b, buku_koleksi k, peminjaman p
WHERE  b.genre_id (+) = g.id
  AND  k.buku_isbn (+) = b.isbn
  AND  p.buku_koleksi_id (+) = k.id
  AND  p.tanggal_pinjam (+) >= TRUNC(DATE '2026-11-05', 'MM')
GROUP  BY g.nama
ORDER  BY pinjaman_bulan_ini DESC, genre;

SELECT g.nama AS genre, COUNT(p.tanggal_pinjam) AS pinjaman_bulan_ini
FROM   genre g, buku b, buku_koleksi k, peminjaman p
WHERE  b.genre_id (+) = g.id
  AND  k.buku_isbn (+) = b.isbn
  AND  p.buku_koleksi_id (+) = k.id
  AND  p.tanggal_pinjam >= TRUNC(DATE '2026-11-05', 'MM')
GROUP  BY g.nama
ORDER  BY pinjaman_bulan_ini DESC, genre;

-- [I4] FULL OUTER JOIN: judul yang dipinjam hanya pada 2024 atau hanya pada 2026
SELECT COALESCE(t24.judul, t26.judul)                AS judul,
       t24.pinjaman                                  AS pinjaman_2024,
       t26.pinjaman                                  AS pinjaman_2026,
       CASE WHEN t24.judul IS NULL THEN 'Baru diminati 2026'
            ELSE 'Tidak lagi dipinjam 2026' END      AS pola
FROM  (SELECT k.buku_isbn, b.judul, COUNT(*) AS pinjaman
       FROM   peminjaman p
       JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
       JOIN   buku b         ON b.isbn = k.buku_isbn
       WHERE  EXTRACT(YEAR FROM p.tanggal_pinjam) = 2024
       GROUP  BY k.buku_isbn, b.judul) t24
FULL   OUTER JOIN
      (SELECT k.buku_isbn, b.judul, COUNT(*) AS pinjaman
       FROM   peminjaman p
       JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
       JOIN   buku b         ON b.isbn = k.buku_isbn
       WHERE  EXTRACT(YEAR FROM p.tanggal_pinjam) = 2026
       GROUP  BY k.buku_isbn, b.judul) t26 ON t26.buku_isbn = t24.buku_isbn
WHERE  t24.judul IS NULL OR t26.judul IS NULL
ORDER  BY pola, NVL(t24.pinjaman, 0) + NVL(t26.pinjaman, 0) DESC, judul
FETCH FIRST 20 ROWS ONLY;

-- [I5] Self-join: pasangan buku yang dipinjam bersamaan oleh anggota yang sama
SELECT b1.judul                   AS buku_pertama,
       b2.judul                   AS buku_kedua,
       COUNT(*)                   AS kali_bersamaan,
       MIN(p1.tanggal_pinjam)     AS contoh_tanggal
FROM   peminjaman p1
JOIN   peminjaman p2   ON p2.anggota_nik = p1.anggota_nik
                      AND p2.tanggal_pinjam = p1.tanggal_pinjam
                      AND p2.buku_koleksi_id > p1.buku_koleksi_id
JOIN   buku_koleksi k1 ON k1.id = p1.buku_koleksi_id
JOIN   buku b1         ON b1.isbn = k1.buku_isbn
JOIN   buku_koleksi k2 ON k2.id = p2.buku_koleksi_id
JOIN   buku b2         ON b2.isbn = k2.buku_isbn
GROUP  BY b1.judul, b2.judul
ORDER  BY kali_bersamaan DESC, buku_pertama, buku_kedua
FETCH FIRST 10 ROWS ONLY;

-- [I6] Non-equijoin dengan BETWEEN: kategori dan tarif denda dari tabel rentang
WITH kategori AS (
  SELECT 'Ringan' AS nama, 1  AS hari_min, 7    AS hari_maks, 1000 AS tarif FROM dual UNION ALL
  SELECT 'Sedang',         8,              30,               1500          FROM dual UNION ALL
  SELECT 'Berat',          31,             9999,             2000          FROM dual)
SELECT kat.nama                                                       AS kategori,
       kat.hari_min || '-' || kat.hari_maks || ' hari'                AS rentang,
       kat.tarif                                                      AS tarif_per_hari,
       COUNT(*)                                                       AS pinjaman,
       SUM(p.tanggal_pengembalian - p.batas_pengembalian)             AS total_hari,
       SUM((p.tanggal_pengembalian - p.batas_pengembalian) * kat.tarif) AS total_denda
FROM   peminjaman p
JOIN   kategori kat ON (p.tanggal_pengembalian - p.batas_pengembalian) BETWEEN kat.hari_min AND kat.hari_maks
GROUP  BY kat.nama, kat.hari_min, kat.hari_maks, kat.tarif
ORDER  BY kat.hari_min;

-- [I7] CROSS JOIN untuk matriks lengkap genre x tahun, termasuk sel bernilai nol
SELECT g.nama                 AS genre,
       t.tahun,
       NVL(x.pinjaman, 0)     AS pinjaman
FROM   genre g
CROSS  JOIN (SELECT DISTINCT EXTRACT(YEAR FROM tanggal_pinjam) AS tahun FROM peminjaman) t
LEFT   JOIN (SELECT b.genre_id, EXTRACT(YEAR FROM p.tanggal_pinjam) AS tahun, COUNT(*) AS pinjaman
             FROM   peminjaman p
             JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
             JOIN   buku b         ON b.isbn = k.buku_isbn
             GROUP  BY b.genre_id, EXTRACT(YEAR FROM p.tanggal_pinjam)) x
       ON x.genre_id = g.id AND x.tahun = t.tahun
WHERE  g.id <= 4
ORDER  BY g.id, t.tahun;

-- [I8] JOIN ... USING ketika nama kolom kunci sama (lewat inline view)
SELECT genre_id,
       nama                 AS genre,
       COUNT(*)             AS judul,
       MIN(tahun_terbit)    AS terbit_terlama,
       MAX(tahun_terbit)    AS terbit_terbaru
FROM  (SELECT id AS genre_id, nama FROM genre) g
JOIN   buku USING (genre_id)
GROUP  BY genre_id, nama
ORDER  BY genre_id;


-- ######## J. Subquery ########

-- [J1] Subquery baris tunggal di WHERE dan subquery skalar berkorelasi di SELECT
SELECT b.judul,
       b.tahun_terbit,
       (SELECT COUNT(*) FROM buku_koleksi k WHERE k.buku_isbn = b.isbn)                  AS eksemplar,
       (SELECT COUNT(*)
        FROM   peminjaman p
        JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
        WHERE  k.buku_isbn = b.isbn)                                                     AS pinjaman
FROM   buku b
WHERE  b.tahun_terbit = (SELECT MAX(tahun_terbit) FROM buku)
ORDER  BY b.judul;

-- [J2] Subquery baris tunggal di HAVING: genre dengan jumlah peminjaman tertinggi
SELECT g.nama AS genre, COUNT(*) AS pinjaman
FROM   peminjaman p
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
JOIN   genre g        ON g.id = b.genre_id
GROUP  BY g.nama
HAVING COUNT(*) = (SELECT MAX(COUNT(*))
                   FROM   peminjaman p2
                   JOIN   buku_koleksi k2 ON k2.id = p2.buku_koleksi_id
                   JOIN   buku b2         ON b2.isbn = k2.buku_isbn
                   GROUP  BY b2.genre_id);

-- [J3] ORA-01427 (subquery baris tunggal mengembalikan banyak baris) dan perbaikannya dengan subquery multi-kolom
-- Bentuk berikut GAGAL dengan ORA-01427 karena subquery menghasilkan satu baris per genre:
--   SELECT judul FROM buku WHERE tahun_terbit = (SELECT MAX(tahun_terbit) FROM buku GROUP BY genre_id)
-- Perbaikan: subquery multi-kolom (pairwise), judul terbaru di tiap genre
SELECT g.nama AS genre, b.tahun_terbit, b.judul
FROM   buku b
JOIN   genre g ON g.id = b.genre_id
WHERE  (b.genre_id, b.tahun_terbit) IN (SELECT genre_id, MAX(tahun_terbit)
                                        FROM   buku
                                        GROUP  BY genre_id)
ORDER  BY g.nama, b.judul;

-- [J4] Perbandingan berpasangan vs tidak berpasangan: pinjaman terakhir setiap anggota
SELECT 'Berpasangan: (anggota, tanggal) IN (...)'                AS cara, COUNT(*) AS baris
FROM   peminjaman
WHERE  (anggota_nik, tanggal_pinjam) IN (SELECT anggota_nik, MAX(tanggal_pinjam)
                                         FROM   peminjaman
                                         GROUP  BY anggota_nik)
UNION ALL
SELECT 'Tidak berpasangan: anggota IN (...) AND tanggal IN (...)', COUNT(*)
FROM   peminjaman
WHERE  anggota_nik    IN (SELECT anggota_nik FROM peminjaman)
  AND  tanggal_pinjam IN (SELECT MAX(tanggal_pinjam) FROM peminjaman GROUP BY anggota_nik);

SELECT a.nama,
       p.tanggal_pinjam                                        AS pinjaman_terakhir,
       b.judul,
       NVL2(p.tanggal_pengembalian, 'sudah kembali', 'masih dipinjam') AS status
FROM   peminjaman p
JOIN   anggota a      ON a.nik = p.anggota_nik
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
WHERE  (p.anggota_nik, p.tanggal_pinjam) IN (SELECT anggota_nik, MAX(tanggal_pinjam)
                                             FROM   peminjaman
                                             GROUP  BY anggota_nik)
ORDER  BY p.tanggal_pinjam DESC, a.nama
FETCH FIRST 10 ROWS ONLY;

-- [J5] Subquery baris jamak dengan IN dan NOT IN
SELECT a.nama,
       (SELECT COUNT(*) FROM peminjaman p WHERE p.anggota_nik = a.nik) AS total_pinjaman
FROM   anggota a
WHERE  a.nik IN (SELECT p.anggota_nik
                 FROM   peminjaman p
                 JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
                 JOIN   buku b         ON b.isbn = k.buku_isbn
                 WHERE  b.genre_id = 8)
  AND  a.nik NOT IN (SELECT p.anggota_nik
                     FROM   peminjaman p
                     JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
                     JOIN   buku b         ON b.isbn = k.buku_isbn
                     WHERE  b.genre_id = 4)
ORDER  BY total_pinjaman DESC, a.nama;

-- [J6] Jebakan NULL pada NOT IN: subquery yang memuat NULL membuat hasil kosong
SELECT 'NOT IN, subquery mengandung NULL'   AS cara, COUNT(DISTINCT tanggal_pinjam) AS hari_pinjam_tanpa_pengembalian
FROM   peminjaman
WHERE  tanggal_pinjam NOT IN (SELECT tanggal_pengembalian FROM peminjaman)
UNION ALL
SELECT 'NOT IN, NULL disaring di subquery', COUNT(DISTINCT tanggal_pinjam)
FROM   peminjaman
WHERE  tanggal_pinjam NOT IN (SELECT tanggal_pengembalian FROM peminjaman WHERE tanggal_pengembalian IS NOT NULL)
UNION ALL
SELECT 'NOT EXISTS (kebal NULL)', COUNT(DISTINCT p.tanggal_pinjam)
FROM   peminjaman p
WHERE  NOT EXISTS (SELECT 1 FROM peminjaman x WHERE x.tanggal_pengembalian = p.tanggal_pinjam);

-- [J7] Operator ANY dan ALL pada subquery baris jamak
SELECT 'Terbit > ALL (lebih baru dari semua buku Algoritma)'      AS kriteria, COUNT(*) AS judul
FROM   buku
WHERE  tahun_terbit > ALL (SELECT tahun_terbit FROM buku WHERE genre_id = 2)
UNION ALL
SELECT 'Terbit > ANY (lebih baru dari minimal satu buku Algoritma)', COUNT(*)
FROM   buku
WHERE  tahun_terbit > ANY (SELECT tahun_terbit FROM buku WHERE genre_id = 2)
UNION ALL
SELECT 'Setara > ALL: tahun_terbit > (SELECT MAX(...))', COUNT(*)
FROM   buku
WHERE  tahun_terbit > (SELECT MAX(tahun_terbit) FROM buku WHERE genre_id = 2);

-- [J8] IN, EXISTS, dan JOIN untuk pertanyaan yang sama: kapan hasilnya berbeda
SELECT 'IN' AS cara, COUNT(*) AS anggota
FROM   anggota a
WHERE  a.nik IN (SELECT p.anggota_nik
                 FROM   peminjaman p
                 JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
                 JOIN   buku b         ON b.isbn = k.buku_isbn
                 WHERE  b.genre_id = 8)
UNION ALL
SELECT 'EXISTS', COUNT(*)
FROM   anggota a
WHERE  EXISTS (SELECT 1
               FROM   peminjaman p
               JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
               JOIN   buku b         ON b.isbn = k.buku_isbn
               WHERE  p.anggota_nik = a.nik
                 AND  b.genre_id = 8)
UNION ALL
SELECT 'JOIN + DISTINCT', COUNT(DISTINCT a.nik)
FROM   anggota a
JOIN   peminjaman p   ON p.anggota_nik = a.nik
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
WHERE  b.genre_id = 8
UNION ALL
SELECT 'JOIN tanpa DISTINCT (baris ganda)', COUNT(*)
FROM   anggota a
JOIN   peminjaman p   ON p.anggota_nik = a.nik
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
WHERE  b.genre_id = 8;

-- [J9] Subquery berkorelasi: judul yang eksemplarnya di atas rata-rata genre-nya sendiri
WITH eks AS (
  SELECT b.isbn, b.judul, b.genre_id, COUNT(k.id) AS eksemplar
  FROM   buku b
  JOIN   buku_koleksi k ON k.buku_isbn = b.isbn
  GROUP  BY b.isbn, b.judul, b.genre_id)
SELECT g.nama                                                                        AS genre,
       e.judul,
       e.eksemplar,
       ROUND((SELECT AVG(e2.eksemplar) FROM eks e2 WHERE e2.genre_id = e.genre_id), 2) AS rata_genre
FROM   eks e
JOIN   genre g ON g.id = e.genre_id
WHERE  e.eksemplar > (SELECT AVG(e2.eksemplar) FROM eks e2 WHERE e2.genre_id = e.genre_id) + 1
ORDER  BY e.eksemplar DESC, genre, e.judul
FETCH FIRST 12 ROWS ONLY;

-- [J10] Peringkat dengan subquery berkorelasi dibandingkan RANK()
WITH per_anggota AS (
  SELECT a.nik, a.nama, COUNT(*) AS pinjaman
  FROM   peminjaman p
  JOIN   anggota a ON a.nik = p.anggota_nik
  GROUP  BY a.nik, a.nama)
SELECT pa.nama,
       pa.pinjaman,
       (SELECT COUNT(*) + 1 FROM per_anggota x WHERE x.pinjaman > pa.pinjaman) AS peringkat_subquery,
       RANK() OVER (ORDER BY pa.pinjaman DESC)                                 AS peringkat_rank
FROM   per_anggota pa
ORDER  BY pa.pinjaman DESC, pa.nama
FETCH FIRST 10 ROWS ONLY;

-- [J11] Total berjalan dengan subquery berkorelasi dibandingkan SUM() OVER
WITH bulanan AS (
  SELECT TRUNC(tanggal_pinjam, 'MM') AS bulan, COUNT(*) AS pinjaman
  FROM   peminjaman
  GROUP  BY TRUNC(tanggal_pinjam, 'MM'))
SELECT b.bulan,
       b.pinjaman,
       (SELECT SUM(x.pinjaman) FROM bulanan x WHERE x.bulan <= b.bulan)    AS kumulatif_subquery,
       SUM(b.pinjaman) OVER (ORDER BY b.bulan)                             AS kumulatif_analitik,
       (SELECT COUNT(*) FROM bulanan x WHERE x.pinjaman > b.pinjaman) + 1  AS peringkat_kesibukan
FROM   bulanan b
WHERE  b.bulan >= DATE '2026-01-01'
ORDER  BY b.bulan;

-- [J12] Pembagian relasional dengan NOT EXISTS bersarang: anggota yang pernah meminjam dari semua genre
SELECT a.nama,
       (SELECT COUNT(*) FROM peminjaman p WHERE p.anggota_nik = a.nik) AS total_pinjaman
FROM   anggota a
WHERE  NOT EXISTS (SELECT 1
                   FROM   genre g
                   WHERE  NOT EXISTS (SELECT 1
                                      FROM   peminjaman p
                                      JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
                                      JOIN   buku b         ON b.isbn = k.buku_isbn
                                      WHERE  p.anggota_nik = a.nik
                                        AND  b.genre_id = g.id))
ORDER  BY total_pinjaman DESC, a.nama;

-- [J13] Subquery skalar yang tidak mengembalikan baris bernilai NULL, bukan error
SELECT (SELECT id FROM genre WHERE nama = 'Fiksi')                                   AS id_fiksi_null,
       NVL((SELECT id FROM genre WHERE nama = 'Fiksi'), 0)                           AS id_fiksi_nvl,
       NVL2((SELECT id FROM genre WHERE nama = 'Basis Data'), 'ada', 'tidak ada')    AS genre_basis_data,
       NVL2((SELECT id FROM genre WHERE nama = 'Fiksi'), 'ada', 'tidak ada')         AS genre_fiksi
FROM   dual;

SELECT g.nama                                                                  AS genre,
       (SELECT MAX(p.tanggal_pinjam)
        FROM   peminjaman p
        JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
        JOIN   buku b         ON b.isbn = k.buku_isbn
        WHERE  b.genre_id = g.id
          AND  p.tanggal_pinjam >= TRUNC(DATE '2026-11-05', 'IW'))                        AS pinjam_terakhir_minggu_ini,
       NVL(TO_CHAR((SELECT MAX(p.tanggal_pinjam)
                    FROM   peminjaman p
                    JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
                    JOIN   buku b         ON b.isbn = k.buku_isbn
                    WHERE  b.genre_id = g.id
                      AND  p.tanggal_pinjam >= TRUNC(DATE '2026-11-05', 'IW')), 'DD/MM/YYYY'),
           'belum ada minggu ini')                                             AS keterangan
FROM   genre g
ORDER  BY g.id;

-- [J14] Inline view di FROM untuk agregasi bertingkat: rata-rata pinjaman per anggota di tiap genre
SELECT genre,
       COUNT(*)                        AS anggota_peminjam,
       ROUND(AVG(pinjaman), 2)         AS rata_pinjaman_per_anggota,
       MAX(pinjaman)                   AS maks_satu_anggota,
       SUM(pinjaman)                   AS total
FROM  (SELECT g.nama AS genre, p.anggota_nik, COUNT(*) AS pinjaman
       FROM   peminjaman p
       JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
       JOIN   buku b         ON b.isbn = k.buku_isbn
       JOIN   genre g        ON g.id = b.genre_id
       GROUP  BY g.nama, p.anggota_nik) t
GROUP  BY genre
ORDER  BY rata_pinjaman_per_anggota DESC;

-- [J15] Subquery skalar tak berkorelasi di SELECT: persentase dan selisih terhadap rata-rata
SELECT g.nama                                                              AS genre,
       COUNT(*)                                                            AS pinjaman,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM peminjaman), 1)        AS persen_total,
       COUNT(*) - (SELECT COUNT(*) / COUNT(DISTINCT b2.genre_id)
                   FROM   peminjaman p2
                   JOIN   buku_koleksi k2 ON k2.id = p2.buku_koleksi_id
                   JOIN   buku b2         ON b2.isbn = k2.buku_isbn)        AS selisih_dari_rata_genre
FROM   peminjaman p
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
JOIN   genre g        ON g.id = b.genre_id
GROUP  BY g.nama
ORDER  BY pinjaman DESC;

-- [J16] Subquery bersarang tiga tingkat: semua judul yang pernah dipinjam anggota teraktif
SELECT g.nama AS genre, b.judul
FROM   buku b
JOIN   genre g ON g.id = b.genre_id
WHERE  b.isbn IN (SELECT k.buku_isbn
                  FROM   buku_koleksi k
                  WHERE  k.id IN (SELECT p.buku_koleksi_id
                                  FROM   peminjaman p
                                  WHERE  p.anggota_nik = (SELECT anggota_nik
                                                          FROM   peminjaman
                                                          GROUP  BY anggota_nik
                                                          ORDER  BY COUNT(*) DESC, anggota_nik
                                                          FETCH FIRST 1 ROW ONLY)))
ORDER  BY g.nama, b.judul;

-- [J17] WITH berantai: anggota yang meminjam di atas rata-rata dengan tingkat keterlambatan di bawah rata-rata
WITH per_anggota AS (
  SELECT a.nik, a.nama,
         COUNT(*)                                                                        AS pinjaman,
         SUM(CASE WHEN p.tanggal_pengembalian > p.batas_pengembalian THEN 1 ELSE 0 END)  AS terlambat
  FROM   peminjaman p
  JOIN   anggota a ON a.nik = p.anggota_nik
  GROUP  BY a.nik, a.nama),
pembanding AS (
  SELECT AVG(pinjaman) AS rata_pinjaman, SUM(terlambat) AS total_terlambat, SUM(pinjaman) AS total_pinjaman
  FROM   per_anggota)
SELECT pa.nama,
       pa.pinjaman,
       pa.terlambat,
       ROUND(100 * pa.terlambat / pa.pinjaman, 1)                   AS persen_terlambat,
       ROUND(pb.rata_pinjaman, 1)                                   AS rata_pinjaman_semua,
       ROUND(100 * pb.total_terlambat / pb.total_pinjaman, 1)       AS persen_terlambat_semua
FROM   per_anggota pa
CROSS  JOIN pembanding pb
WHERE  pa.pinjaman > pb.rata_pinjaman
  AND  100 * pa.terlambat / pa.pinjaman < 100 * pb.total_terlambat / pb.total_pinjaman
ORDER  BY persen_terlambat, pa.pinjaman DESC;

-- [J18] WITH rekursif: deret bulan lengkap sebagai kerangka laporan
WITH bulan (awal_bulan) AS (
  SELECT DATE '2023-10-01' FROM dual
  UNION ALL
  SELECT ADD_MONTHS(awal_bulan, 1) FROM bulan WHERE awal_bulan < DATE '2026-11-01')
SELECT TO_CHAR(bl.awal_bulan, 'YYYY-MM')                    AS bulan,
       NVL(m.pinjaman, 0)                                    AS pinjaman,
       NVL(m.anggota, 0)                                     AS anggota_aktif,
       SUM(NVL(m.pinjaman, 0)) OVER (ORDER BY bl.awal_bulan) AS kumulatif
FROM   bulan bl
LEFT   JOIN (SELECT TRUNC(tanggal_pinjam, 'MM') AS awal_bulan,
                    COUNT(*)                    AS pinjaman,
                    COUNT(DISTINCT anggota_nik) AS anggota
             FROM   peminjaman
             GROUP  BY TRUNC(tanggal_pinjam, 'MM')) m ON m.awal_bulan = bl.awal_bulan
ORDER  BY bl.awal_bulan;

-- [J19] CROSS APPLY (inline view berkorelasi): tiga pinjaman terakhir tiap anggota teraktif
SELECT ta.nama, t.tanggal_pinjam, t.judul, t.status
FROM  (SELECT a.nik, a.nama
       FROM   anggota a
       JOIN   peminjaman p ON p.anggota_nik = a.nik
       GROUP  BY a.nik, a.nama
       ORDER  BY COUNT(*) DESC, a.nama
       FETCH FIRST 4 ROWS ONLY) ta
CROSS  APPLY (SELECT p.tanggal_pinjam, b.judul,
                     NVL2(p.tanggal_pengembalian, 'sudah kembali', 'masih dipinjam') AS status
              FROM   peminjaman p
              JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
              JOIN   buku b         ON b.isbn = k.buku_isbn
              WHERE  p.anggota_nik = ta.nik
              ORDER  BY p.tanggal_pinjam DESC
              FETCH FIRST 3 ROWS ONLY) t
ORDER  BY ta.nama, t.tanggal_pinjam DESC;

-- [J20] Subquery dalam DML: CREATE TABLE AS SELECT, UPDATE berkorelasi multi-kolom, DELETE dengan subquery
-- 0) Bersihkan sisa percobaan sebelumnya (abaikan ORA-00942: tabel belum ada)
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE anggota_rekap PURGE';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE <> -942 THEN RAISE; END IF;
END;
/

-- 1) CREATE TABLE ... AS SELECT: subquery sebagai sumber tabel kerja
CREATE TABLE anggota_rekap AS
SELECT nik, nama, 0 AS jumlah_pinjam, CAST(NULL AS DATE) AS pinjam_terakhir
FROM   anggota;

-- 2) UPDATE dengan subquery berkorelasi yang mengisi dua kolom sekaligus
UPDATE anggota_rekap r
SET    (jumlah_pinjam, pinjam_terakhir) = (SELECT COUNT(*), MAX(p.tanggal_pinjam)
                                           FROM   peminjaman p
                                           WHERE  p.anggota_nik = r.nik);

-- 3) DELETE dengan subquery: buang anggota yang tidak meminjam dalam 6 bulan terakhir
DELETE FROM anggota_rekap
WHERE  nik NOT IN (SELECT anggota_nik
                   FROM   peminjaman
                   WHERE  tanggal_pinjam >= ADD_MONTHS(DATE '2026-11-05', -6));

-- 4) Hasil
SELECT nama, jumlah_pinjam, pinjam_terakhir
FROM   anggota_rekap
ORDER  BY jumlah_pinjam DESC, nama
FETCH FIRST 10 ROWS ONLY;

-- 5) Hapus tabel kerja
DROP TABLE anggota_rekap PURGE;


-- ######## K. Operator himpunan (UNION, UNION ALL, INTERSECT, MINUS) ########

-- [K1] UNION vs UNION ALL: anggota yang pernah terlambat atau sedang menunggak
SELECT 'UNION (unik)' AS operator, COUNT(*) AS anggota
FROM  (SELECT anggota_nik FROM peminjaman WHERE tanggal_pengembalian > batas_pengembalian
       UNION
       SELECT anggota_nik FROM peminjaman WHERE tanggal_pengembalian IS NULL AND batas_pengembalian < DATE '2026-11-05')
UNION ALL
SELECT 'UNION ALL (dengan duplikat)', COUNT(*)
FROM  (SELECT anggota_nik FROM peminjaman WHERE tanggal_pengembalian > batas_pengembalian
       UNION ALL
       SELECT anggota_nik FROM peminjaman WHERE tanggal_pengembalian IS NULL AND batas_pengembalian < DATE '2026-11-05');

-- [K2] INTERSECT: anggota yang aktif meminjam pada 2024 dan 2026
SELECT a.nama,
       (SELECT COUNT(*) FROM peminjaman p WHERE p.anggota_nik = a.nik) AS total_pinjaman
FROM   anggota a
WHERE  a.nik IN (SELECT anggota_nik FROM peminjaman WHERE EXTRACT(YEAR FROM tanggal_pinjam) = 2024
                 INTERSECT
                 SELECT anggota_nik FROM peminjaman WHERE EXTRACT(YEAR FROM tanggal_pinjam) = 2026)
ORDER  BY total_pinjaman DESC, a.nama
FETCH FIRST 15 ROWS ONLY;

-- [K3] MINUS: anggota yang berhenti meminjam dan anggota yang baru aktif
SELECT 'Aktif 2024, tidak meminjam 2026' AS pola, a.nama
FROM   anggota a
WHERE  a.nik IN (SELECT anggota_nik FROM peminjaman WHERE EXTRACT(YEAR FROM tanggal_pinjam) = 2024
                 MINUS
                 SELECT anggota_nik FROM peminjaman WHERE EXTRACT(YEAR FROM tanggal_pinjam) = 2026)
UNION ALL
SELECT 'Baru meminjam 2026, belum pernah 2024', a.nama
FROM   anggota a
WHERE  a.nik IN (SELECT anggota_nik FROM peminjaman WHERE EXTRACT(YEAR FROM tanggal_pinjam) = 2026
                 MINUS
                 SELECT anggota_nik FROM peminjaman WHERE EXTRACT(YEAR FROM tanggal_pinjam) = 2024)
ORDER  BY 1, 2;

-- [K4] UNION ALL untuk menyatukan dua jenis kejadian menjadi satu linimasa
SELECT 'PENGADAAN'       AS jenis, k.tanggal_masuk AS tanggal, b.judul AS keterangan, k.cara_masuk AS detail
FROM   buku_koleksi k
JOIN   buku b ON b.isbn = k.buku_isbn
WHERE  k.tanggal_masuk >= DATE '2026-05-01'
UNION ALL
SELECT 'PEMINJAMAN', p.tanggal_pinjam, b.judul, a.nama
FROM   peminjaman p
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
JOIN   anggota a      ON a.nik = p.anggota_nik
WHERE  p.tanggal_pinjam >= DATE '2026-05-01'
UNION ALL
SELECT 'PENGEMBALIAN', p.tanggal_pengembalian, b.judul, a.nama
FROM   peminjaman p
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
JOIN   anggota a      ON a.nik = p.anggota_nik
WHERE  p.tanggal_pengembalian >= DATE '2026-05-01'
ORDER  BY tanggal DESC, jenis, keterangan
FETCH FIRST 20 ROWS ONLY;

-- [K5] INTERSECT berantai: judul yang dipinjam pada tiga tahun berturut-turut
SELECT b.judul,
       COUNT(*)              AS total_pinjaman,
       MIN(p.tanggal_pinjam) AS pertama,
       MAX(p.tanggal_pinjam) AS terakhir
FROM   peminjaman p
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
WHERE  k.buku_isbn IN (SELECT k1.buku_isbn FROM peminjaman p1 JOIN buku_koleksi k1 ON k1.id = p1.buku_koleksi_id
                       WHERE  EXTRACT(YEAR FROM p1.tanggal_pinjam) = 2024
                       INTERSECT
                       SELECT k2.buku_isbn FROM peminjaman p2 JOIN buku_koleksi k2 ON k2.id = p2.buku_koleksi_id
                       WHERE  EXTRACT(YEAR FROM p2.tanggal_pinjam) = 2025
                       INTERSECT
                       SELECT k3.buku_isbn FROM peminjaman p3 JOIN buku_koleksi k3 ON k3.id = p3.buku_koleksi_id
                       WHERE  EXTRACT(YEAR FROM p3.tanggal_pinjam) = 2026)
GROUP  BY b.isbn, b.judul
ORDER  BY total_pinjaman DESC, b.judul
FETCH FIRST 15 ROWS ONLY;


-- ######## L. Lanjutan: fungsi analitik (window) ########

-- [L1] Tiga judul terpopuler per genre dengan DENSE_RANK dan ROW_NUMBER
SELECT genre, judul, pinjaman, peringkat, nomor_urut
FROM  (SELECT g.nama                                                                   AS genre,
              b.judul,
              COUNT(*)                                                                 AS pinjaman,
              DENSE_RANK() OVER (PARTITION BY g.nama ORDER BY COUNT(*) DESC)           AS peringkat,
              ROW_NUMBER() OVER (PARTITION BY g.nama ORDER BY COUNT(*) DESC, b.judul)  AS nomor_urut
       FROM   peminjaman p
       JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
       JOIN   buku b         ON b.isbn = k.buku_isbn
       JOIN   genre g        ON g.id = b.genre_id
       GROUP  BY g.nama, b.judul)
WHERE  peringkat <= 3
ORDER  BY genre, peringkat, judul;

-- [L2] Tren bulanan: total kumulatif, LAG, rata-rata bergerak, RATIO_TO_REPORT, NTILE
SELECT bulan,
       transaksi,
       SUM(transaksi) OVER (ORDER BY bulan)                                                   AS kumulatif,
       LAG(transaksi) OVER (ORDER BY bulan)                                                   AS bulan_sebelumnya,
       transaksi - LAG(transaksi) OVER (ORDER BY bulan)                                       AS selisih,
       ROUND(AVG(transaksi) OVER (ORDER BY bulan ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 1) AS rata_bergerak_3_bulan,
       ROUND(100 * RATIO_TO_REPORT(transaksi) OVER (), 2)                                     AS persen_dari_total,
       NTILE(4) OVER (ORDER BY transaksi)                                                     AS kuartil_kesibukan
FROM  (SELECT TO_CHAR(tanggal_pinjam, 'YYYY-MM') AS bulan, COUNT(*) AS transaksi
       FROM   peminjaman
       GROUP  BY TO_CHAR(tanggal_pinjam, 'YYYY-MM'))
ORDER  BY bulan;

-- [L3] RANK, DENSE_RANK, ROW_NUMBER, PERCENT_RANK, dan CUME_DIST dibandingkan
SELECT nama,
       pinjaman,
       RANK()         OVER (ORDER BY pinjaman DESC)            AS peringkat_rank,
       DENSE_RANK()   OVER (ORDER BY pinjaman DESC)            AS peringkat_dense,
       ROW_NUMBER()   OVER (ORDER BY pinjaman DESC, nama)      AS nomor_baris,
       ROUND(PERCENT_RANK() OVER (ORDER BY pinjaman DESC), 3)  AS posisi_relatif,
       ROUND(CUME_DIST()    OVER (ORDER BY pinjaman DESC), 3)  AS distribusi_kumulatif
FROM  (SELECT a.nama, COUNT(*) AS pinjaman
       FROM   peminjaman p
       JOIN   anggota a ON a.nik = p.anggota_nik
       GROUP  BY a.nik, a.nama)
ORDER  BY pinjaman DESC, nama
FETCH FIRST 12 ROWS ONLY;

-- [L4] LEAD dan LAG per eksemplar: berapa hari buku menganggur di rak antar peminjaman
SELECT p.buku_koleksi_id                                                   AS eksemplar,
       p.tanggal_pinjam,
       p.tanggal_pengembalian,
       LAG(p.tanggal_pengembalian) OVER (PARTITION BY p.buku_koleksi_id ORDER BY p.tanggal_pinjam)  AS kembali_sebelumnya,
       LEAD(p.tanggal_pinjam)      OVER (PARTITION BY p.buku_koleksi_id ORDER BY p.tanggal_pinjam)  AS pinjam_berikutnya,
       LEAD(p.tanggal_pinjam)      OVER (PARTITION BY p.buku_koleksi_id ORDER BY p.tanggal_pinjam)
         - p.tanggal_pengembalian                                            AS hari_di_rak
FROM   peminjaman p
JOIN  (SELECT buku_koleksi_id
       FROM   peminjaman
       GROUP  BY buku_koleksi_id
       ORDER  BY COUNT(*) DESC, buku_koleksi_id
       FETCH FIRST 2 ROWS ONLY) top ON top.buku_koleksi_id = p.buku_koleksi_id
ORDER  BY p.buku_koleksi_id, p.tanggal_pinjam;

-- [L5] FIRST_VALUE, LAST_VALUE, dan jeda antar pinjaman seorang anggota
SELECT a.nama,
       p.tanggal_pinjam,
       b.judul,
       FIRST_VALUE(p.tanggal_pinjam) OVER (PARTITION BY a.nik ORDER BY p.tanggal_pinjam)        AS pinjam_pertama,
       LAST_VALUE(p.tanggal_pinjam)  OVER (PARTITION BY a.nik ORDER BY p.tanggal_pinjam
                                           ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS pinjam_terakhir,
       p.tanggal_pinjam - LAG(p.tanggal_pinjam) OVER (PARTITION BY a.nik ORDER BY p.tanggal_pinjam) AS jeda_hari,
       COUNT(*) OVER (PARTITION BY a.nik ORDER BY p.tanggal_pinjam)                            AS pinjaman_ke
FROM   peminjaman p
JOIN   anggota a      ON a.nik = p.anggota_nik
JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
JOIN   buku b         ON b.isbn = k.buku_isbn
WHERE  a.nik = (SELECT MIN(nik) FROM anggota)
ORDER  BY p.tanggal_pinjam;

-- [L6] Total berjalan dan porsi dalam partisi: pinjaman bulanan dua genre
SELECT genre,
       bulan,
       pinjaman,
       SUM(pinjaman) OVER (PARTITION BY genre ORDER BY bulan)                   AS kumulatif_genre,
       ROUND(100 * pinjaman / SUM(pinjaman) OVER (PARTITION BY genre), 1)        AS persen_dari_total_genre,
       CASE WHEN pinjaman = MAX(pinjaman) OVER (PARTITION BY genre) THEN 'PUNCAK' END AS penanda
FROM  (SELECT g.nama AS genre, TO_CHAR(p.tanggal_pinjam, 'YYYY-MM') AS bulan, COUNT(*) AS pinjaman
       FROM   peminjaman p
       JOIN   buku_koleksi k ON k.id = p.buku_koleksi_id
       JOIN   buku b         ON b.isbn = k.buku_isbn
       JOIN   genre g        ON g.id = b.genre_id
       WHERE  g.id IN (3, 8)
         AND  p.tanggal_pinjam >= DATE '2026-01-01'
       GROUP  BY g.nama, TO_CHAR(p.tanggal_pinjam, 'YYYY-MM'))
ORDER  BY genre, bulan;

-- [L7] Jendela RANGE berbasis tanggal: jumlah pinjaman 30 hari terakhir pada setiap tanggal
SELECT tanggal,
       pinjaman_hari_itu,
       pinjaman_30_hari,
       ROUND(pinjaman_30_hari / 30, 2) AS rata_per_hari_30_hari
FROM  (SELECT tanggal_pinjam AS tanggal,
              COUNT(*)       AS pinjaman_hari_itu,
              SUM(COUNT(*)) OVER (ORDER BY tanggal_pinjam
                                  RANGE BETWEEN INTERVAL '29' DAY PRECEDING AND CURRENT ROW) AS pinjaman_30_hari
       FROM   peminjaman
       GROUP  BY tanggal_pinjam)
WHERE  tanggal >= DATE '2026-10-15'
ORDER  BY tanggal;

-- [L8] Pertumbuhan tahun-ke-tahun per bulan dengan LAG(..., 12)
SELECT bulan,
       pinjaman,
       LAG(pinjaman, 12) OVER (ORDER BY bulan)                                    AS bulan_sama_tahun_lalu,
       pinjaman - LAG(pinjaman, 12) OVER (ORDER BY bulan)                         AS selisih,
       ROUND(100 * (pinjaman - LAG(pinjaman, 12) OVER (ORDER BY bulan))
                 / LAG(pinjaman, 12) OVER (ORDER BY bulan), 1)                    AS pertumbuhan_persen
FROM  (SELECT TO_CHAR(tanggal_pinjam, 'YYYY-MM') AS bulan, COUNT(*) AS pinjaman
       FROM   peminjaman
       GROUP  BY TO_CHAR(tanggal_pinjam, 'YYYY-MM'))
ORDER  BY bulan;

-- [L9] Analisis Pareto dengan NTILE: porsi pinjaman tiap kuartil anggota
SELECT kuartil,
       COUNT(*)                                              AS anggota,
       MIN(pinjaman)                                         AS pinjaman_min,
       MAX(pinjaman)                                         AS pinjaman_maks,
       SUM(pinjaman)                                         AS total_pinjaman,
       ROUND(100 * SUM(pinjaman) / SUM(SUM(pinjaman)) OVER (), 1) AS persen_dari_total
FROM  (SELECT anggota_nik,
              COUNT(*)                                     AS pinjaman,
              NTILE(4) OVER (ORDER BY COUNT(*) DESC)       AS kuartil
       FROM   peminjaman
       GROUP  BY anggota_nik)
GROUP  BY kuartil
ORDER  BY kuartil;

