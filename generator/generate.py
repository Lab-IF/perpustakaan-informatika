#!/usr/bin/env python3
"""Generator data simulasi Perpustakaan Informatika (Oracle 21c).

Pemakaian:
  python3 generate.py            # semua profil + README.md + contoh_analisis.sql
  python3 generate.py utama      # versi utama (<= 500 KB, siap unggah APEX) -> perpustakaan_*.sql
  python3 generate.py lengkap    # versi lengkap opsional (938 judul, ~0,9 MB) -> versi-lengkap/perpustakaan_*.sql

Setiap profil menghasilkan tiga berkas SQL:
  perpustakaan_ddl.sql       - DDL saja
  perpustakaan_data.sql      - INSERT saja
  perpustakaan_ddl_data.sql  - DDL + INSERT

Deterministik (seed tetap) sehingga dapat di-regenerate identik.
"""
import math
import random
import sys
from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path

from catalog_id import BOOKS_ID
from catalog_en import BOOKS_EN
import rekap

SEED = 20261106
OUT_DIR = Path(__file__).resolve().parent.parent

TODAY = date(2026, 11, 5)          # batas akhir simulasi
LOAN_START = date(2024, 1, 2)      # peminjaman disimulasikan ~3 tahun terakhir
ACQ_START = date(2008, 1, 1)       # pengadaan koleksi paling awal
ACQ_END = date(2026, 6, 30)

PROFILES = {
    # Versi utama: muat di bawah batas unggah 500 KB APEX SQL Workshop; subset katalog
    # yang tetap memenuhi syarat 500+ judul, 100+ anggota, 2.000+ transaksi, 2-6 eksemplar per judul.
    "utama": dict(
        label="VERSI UTAMA (<= 500 KB, APEX)", subdir="", books=501, members=101, loans=2000,
        koleksi_weights=[50, 30, 12, 5, 3], batch=100, sep=",", max_bytes=500_000,
    ),
    # Versi lengkap (opsional): seluruh katalog (938 judul), ~2.700 transaksi, ~0,9 MB.
    "lengkap": dict(
        label="VERSI LENGKAP (OPSIONAL)", subdir="versi-lengkap", books=None, members=120, loans=2800,
        koleksi_weights=[30, 30, 20, 12, 8], batch=None, sep=", ", max_bytes=None,
    ),
}

GENRES = [
    (1, "Pemrograman"),
    (2, "Algoritma dan Struktur Data"),
    (3, "Basis Data"),
    (4, "Jaringan Komputer"),
    (5, "Sistem Operasi dan Arsitektur Komputer"),
    (6, "Rekayasa Perangkat Lunak"),
    (7, "Kecerdasan Buatan dan Data Science"),
    (8, "Keamanan Informasi"),
    (9, "Pengembangan Web dan Mobile"),
    (10, "Sistem Informasi dan Manajemen TI"),
]

# ----------------------------------------------------------------------------
# Pool nama anggota (nuansa Sulawesi Selatan + umum Indonesia)
# ----------------------------------------------------------------------------
MALE_FIRST = [
    "Muhammad", "Muh.", "Ahmad", "Andi", "Rizky", "Fajar", "Syahrul", "Ilham", "Fahri",
    "Aldi", "Rahmat", "Zulkifli", "Irfan", "Arham", "Firman", "Akbar", "Rifaldi", "Reski",
    "Aswar", "Asrul", "Baso", "Dirga", "Alif", "Farhan", "Yusuf", "Ismail", "Ridwan",
    "Hamka", "Taufik", "Wahyu", "Imran", "Sultan", "Adnan", "Haikal", "Fadli", "Riswan",
    "Agung", "Alfian", "Fikri", "Ikhsan", "Asdar", "Rusli", "Hasrul", "Arya", "Dandi",
]
FEMALE_FIRST = [
    "Nurul", "Siti", "Andi", "Nur", "Putri", "Dewi", "Sri", "Ayu", "Rahma", "Fitri",
    "Aisyah", "Nadia", "Salsabila", "Indah", "Wulan", "Mutmainnah", "Rezki", "Husnul",
    "Miftahul", "Sakinah", "Annisa", "Fadhilah", "Khairunnisa", "Hikmah", "Aulia", "Zahra",
    "Magfirah", "Nurhidayah", "Irmayanti", "Rosmini", "Hasnawati", "Jumriani", "Besse",
    "Tenri", "Alya", "Nabila", "Rina", "Syahraeni", "Marwah", "Nurfadillah",
]
MALE_LAST = [
    "Hidayat", "Saputra", "Pratama", "Ramadhan", "Syam", "Akbar", "Hamid", "Rahman", "Latif",
    "Said", "Ansar", "Amir", "Bahar", "Yusuf", "Mansyur", "Nasir", "Arsyad", "Jamaluddin",
    "Syamsuddin", "Alimuddin", "Nurdin", "Tahir", "Mappiare", "Patawari", "Makkulau",
    "Pabbajah", "Pasolong", "Mustari", "Idris", "Mustafa", "Rasyid", "Sudirman", "Basri",
    "Haris", "Faisal", "Karim", "Rusdi", "Sabir", "Kadir", "Majid", "Halim", "Daeng Nai",
    "Daeng Situju", "Tenriadji", "Palinrungi", "Sanusi", "Ridwan", "Lukman", "Hasyim",
]
FEMALE_LAST = [
    "Lestari", "Rahayu", "Sari", "Utami", "Anggraeni", "Amalia", "Ramlah", "Syahrani",
    "Maharani", "Pertiwi", "Safitri", "Oktaviani", "Wahyuni", "Tenriawaru", "Daeng Ngai",
    "Pratiwi", "Handayani", "Mustika", "Azzahra", "Fauziah", "Rahmadani", "Kartini",
    "Amaliah", "Humairah", "Mardiana", "Nurjannah", "Rosdiana", "Hasanah", "Fitriani",
    "Jumiati", "Suryani", "Salmah", "Nurlaela", "Patimasang", "Rahmatia",
]

# Kode wilayah NIK: provinsi 73 (Sulawesi Selatan) + kab/kota
KABKOTA = ["71", "71", "71", "71", "06", "06", "03", "09", "05", "04", "07", "02", "08", "10",
           "11", "12", "13", "14", "15", "16", "72", "73"]


def nik_from(rng, kabkota, dob, female):
    kec = rng.randint(1, 15)
    dd = dob.day + (40 if female else 0)
    serial = rng.randint(1, 9999)
    return f"73{kabkota}{kec:02d}{dd:02d}{dob.month:02d}{dob.year % 100:02d}{serial:04d}"


def isbn13(rng, group):
    """ISBN-13 sintetis dengan check digit valid. group: '602'/'979' (ID), '0'/'1' (EN)."""
    body = "978" + group
    body += "".join(str(rng.randint(0, 9)) for _ in range(12 - len(body)))
    s = sum((1 if i % 2 == 0 else 3) * int(c) for i, c in enumerate(body))
    return body + str((10 - s % 10) % 10)


def q(s):
    return "'" + s.replace("'", "''") + "'"


def d(x):
    """Literal tanggal ANSI (didukung Oracle 9i+), lebih ringkas daripada TO_DATE."""
    return "NULL" if x is None else f"DATE '{x.isoformat()}'"


def skip_sunday(x):
    return x + timedelta(days=1) if x.weekday() == 6 else x


def rand_date(rng, lo, hi):
    return lo + timedelta(days=rng.randint(0, (hi - lo).days))


def select_books(target):
    """Subset katalog yang deterministik: proporsional per genre, judul Indonesia
    diberi bobot lebih besar (1.6x) agar tetap mayoritas. Urutan asli dipertahankan."""
    allb = BOOKS_ID + BOOKS_EN
    if target is None or target >= len(allb):
        return allb
    r = random.Random(SEED + 3)
    id_set = set(id(b) for b in BOOKS_ID)
    by_genre = defaultdict(list)
    for idx, b in enumerate(allb):
        by_genre[b[0]].append(idx)
    quota = {g: round(target * len(ix) / len(allb)) for g, ix in by_genre.items()}
    # koreksi pembulatan agar total tepat
    diff = target - sum(quota.values())
    for g in sorted(by_genre, key=lambda g: -len(by_genre[g]))[:abs(diff)]:
        quota[g] += 1 if diff > 0 else -1
    chosen = []
    for g, ix in by_genre.items():
        # weighted sampling tanpa pengembalian (Efraimidis-Spirakis)
        keyed = sorted(ix, key=lambda i: -(r.random() ** (1.0 / (1.6 if id(allb[i]) in id_set else 1.0))))
        chosen.extend(keyed[:quota[g]])
    return [allb[i] for i in sorted(chosen)]


def build(profile):
    rng = random.Random(SEED)
    books_src = select_books(profile["books"])
    id_books = set(id(b) for b in BOOKS_ID)
    n_id = sum(1 for b in books_src if id(b) in id_books)

    # ---- genre
    genres = GENRES

    # ---- penerbit (urut alfabet, id berurutan)
    penerbit_names = sorted({b[2] for b in books_src}, key=str.lower)
    penerbit_id = {n: i + 1 for i, n in enumerate(penerbit_names)}

    # ---- penulis (urut alfabet, NIK sintetis unik)
    penulis_names = sorted({a for b in books_src for a in b[4]}, key=str.lower)
    penulis_nik = {}
    used = set()
    for name in penulis_names:
        while True:
            dob = rand_date(rng, date(1945, 1, 1), date(1990, 12, 31))
            prov = rng.choice(["31", "32", "33", "34", "35", "73", "73"])
            nik = f"{prov}{rng.randint(1, 20):02d}{rng.randint(1, 20):02d}{dob.day:02d}{dob.month:02d}{dob.year % 100:02d}{rng.randint(1, 9999):04d}"
            if nik not in used:
                used.add(nik)
                penulis_nik[name] = nik
                break

    # ---- buku + buku_penulis
    buku = []        # (isbn, judul, tahun, penerbit_id, genre_id)
    buku_penulis = []  # (isbn, penulis_nik)
    isbns = set()
    for b in books_src:
        genre_id, tahun, penerbit, judul, authors = b
        is_id = id(b) in id_books
        while True:
            isbn = isbn13(rng, rng.choice(["602", "979"]) if is_id else rng.choice(["0", "1"]))
            if isbn not in isbns:
                isbns.add(isbn)
                break
        buku.append((isbn, judul, tahun, penerbit_id[penerbit], genre_id))
        for a in authors:
            buku_penulis.append((isbn, penulis_nik[a]))

    # ---- anggota
    anggota = []  # (nik, nama, hp)
    used_nik, used_hp, used_name = set(), set(), set()
    while len(anggota) < profile["members"]:
        female = rng.random() < 0.48
        first = rng.choice(FEMALE_FIRST if female else MALE_FIRST)
        last = rng.choice(FEMALE_LAST if female else MALE_LAST)
        if rng.random() < 0.35:
            mid = rng.choice(FEMALE_LAST if female else MALE_LAST)
            if mid != last:
                last = f"{mid} {last}"
        nama = f"{first} {last}"
        if nama in used_name:
            continue
        # mayoritas mahasiswa (lahir 1999-2007), sebagian dosen/staf (1970-1995)
        dob = rand_date(rng, date(1999, 1, 1), date(2007, 12, 31)) if rng.random() < 0.85 \
            else rand_date(rng, date(1970, 1, 1), date(1995, 12, 31))
        nik = nik_from(rng, rng.choice(KABKOTA), dob, female)
        if nik in used_nik:
            continue
        hp = "08" + rng.choice(["11", "12", "13", "21", "22", "23", "52", "53", "51", "55",
                                "56", "57", "58", "77", "78", "81", "82", "85", "87", "88",
                                "89", "95", "96", "97", "98"]) + "".join(str(rng.randint(0, 9)) for _ in range(8))
        if hp in used_hp:
            continue
        used_name.add(nama); used_nik.add(nik); used_hp.add(hp)
        anggota.append((nik, nama, hp))

    # ---- buku_koleksi: 2-6 eksemplar per judul, pengadaan dalam 1-2 batch
    koleksi = []  # dict per eksemplar
    cara_w = [("PEMBELIAN", 70), ("HIBAH", 20), ("SUMBANGAN", 8), ("TUKAR", 2)]
    next_id = 1
    for (isbn, judul, tahun, _pid, _gid) in buku:
        n = rng.choices([2, 3, 4, 5, 6], weights=profile["koleksi_weights"])[0]
        lo = max(ACQ_START, date(tahun, 1, 1))
        first_batch = rand_date(rng, lo, ACQ_END)
        n1 = n if (n <= 2 or rng.random() < 0.55) else rng.randint(1, n - 1)
        second_batch = rand_date(rng, first_batch, ACQ_END) if n1 < n else None
        cara1 = rng.choices([c for c, _ in cara_w], weights=[w for _, w in cara_w])[0]
        cara2 = rng.choices([c for c, _ in cara_w], weights=[w for _, w in cara_w])[0]
        for i in range(n):
            tgl = first_batch if i < n1 else second_batch
            koleksi.append({"id": next_id, "isbn": isbn, "cara": cara1 if i < n1 else cara2,
                            "masuk": tgl, "kondisi": None, "tahun": tahun})
            next_id += 1

    # ---- peminjaman
    # popularitas judul: lognormal x faktor kebaruan; anggota: lognormal
    pop = {}
    for (isbn, _j, tahun, _p, _g) in buku:
        recency = 1.0 + 0.06 * max(0, min(tahun, 2024) - 1995)
        pop[isbn] = rng.lognormvariate(0.0, 0.9) * recency
    member_w = [rng.lognormvariate(0.0, 0.8) for _ in anggota]

    def simulate(k, seed):
        """Tahap 1: bangun interval pinjaman per eksemplar (tanpa anggota)."""
        r = random.Random(seed)
        intervals = []  # (tanggal_pinjam, koleksi_id, batas, kembali|None)
        for c in koleksi:
            mean_gap = k / pop[c["isbn"]]
            t = max(c["masuk"] + timedelta(days=3), LOAN_START)
            while True:
                t = skip_sunday(t + timedelta(days=int(r.expovariate(1.0 / mean_gap)) + 1))
                if t > TODAY:
                    break
                dur = 7 if r.random() < 0.35 else 14
                batas = t + timedelta(days=dur)
                u = r.random()
                if u < 0.68:
                    ret = t + timedelta(days=r.randint(1, dur))
                elif u < 0.95:
                    ret = batas + timedelta(days=r.randint(1, 21))
                else:
                    ret = batas + timedelta(days=r.randint(22, 120))
                ret = skip_sunday(ret)
                lost = r.random() < 0.007 and t < TODAY - timedelta(days=60)
                still_out = lost or ret > TODAY
                intervals.append((t, c["id"], batas, None if still_out else ret))
                if still_out:
                    break
                t = ret
        return intervals

    def assign_members(intervals, seed):
        """Tahap 2: tetapkan anggota secara kronologis; maks 3 buku dipegang bersamaan."""
        r = random.Random(seed)
        active = defaultdict(list)  # anggota_nik -> [(start, end|None)]
        loans = []
        for t, kid, batas, ret in sorted(intervals):
            nik = None
            for _ in range(50):
                cand = r.choices(anggota, weights=member_w)[0][0]
                held = sum(1 for (s, e) in active[cand] if s <= t and (e is None or e >= t))
                if held < 3:
                    nik = cand
                    break
            if nik is None:  # fallback: anggota dengan pinjaman aktif paling sedikit
                nik = min((a[0] for a in anggota),
                          key=lambda n: sum(1 for (s, e) in active[n] if s <= t and (e is None or e >= t)))
            active[nik].append((t, ret))
            loans.append((kid, nik, t, batas, ret))
        return loans

    k = 400.0
    for _ in range(8):  # kalibrasi agar jumlah transaksi ~ profile["loans"]
        n = len(simulate(k, SEED + 1))
        k *= n / profile["loans"]
    loans = assign_members(simulate(k, SEED + 1), SEED + 2)
    assert len(loans) > 2000, len(loans)

    # ---- kondisi eksemplar (HILANG hanya jika pinjaman terakhir tak kembali & jauh lewat batas)
    last_loan = {}
    for ln in loans:
        last_loan[ln[0]] = ln
    kondisi_w = [("BAIK", 82), ("RUSAK RINGAN", 13), ("RUSAK BERAT", 5)]
    for c in koleksi:
        ln = last_loan.get(c["id"])
        if ln and ln[4] is None and ln[3] < TODAY - timedelta(days=60):
            c["kondisi"] = "HILANG"
        elif ln is None:
            c["kondisi"] = rng.choices(["BAIK", "RUSAK RINGAN"], weights=[93, 7])[0]
        else:
            c["kondisi"] = rng.choices([x for x, _ in kondisi_w], weights=[w for _, w in kondisi_w])[0]

    return {
        "profile": profile, "n_id": n_id, "n_en": len(books_src) - n_id,
        "genres": genres, "penerbit": [(penerbit_id[n], n) for n in penerbit_names],
        "penulis": [(penulis_nik[n], n) for n in penulis_names],
        "anggota": anggota, "buku": buku, "buku_penulis": buku_penulis,
        "koleksi": koleksi, "loans": sorted(loans, key=lambda x: (x[2], x[0])),
    }


# ----------------------------------------------------------------------------
# Penulisan SQL
# ----------------------------------------------------------------------------
HEADER = """-- ============================================================================
-- PERPUSTAKAAN INFORMATIKA - {what}
-- Target  : Oracle Database 21c (SQL Developer / SQL*Plus / SQLcl / APEX SQL Scripts)
-- Dibuat  : {today} (generator deterministik, seed {seed}, profil {profile})
-- Sumber model: Oracle SQL Developer Data Modeler 24.3.1 (dimodifikasi)
--
-- Perubahan dari model asli:
--   * Kolom buku.buku_koleksi_id dan FK buku_buku_koleksi_FK DIHAPUS.
--   * Kolom buku_koleksi.buku_isbn ditambahkan + FK buku_koleksi_buku_FK -> buku(isbn).
--   Alasan: satu judul (buku) memiliki 2-6 eksemplar fisik (buku_koleksi),
--   dan peminjaman merujuk ke eksemplar fisik.
-- ============================================================================
"""

DDL = """
-- Hapus tabel perpustakaan yang sudah ada (bila ada) agar skrip aman dijalankan
-- ulang. Hanya 8 tabel di bawah ini yang disentuh; PURGE mencegah tabel lama
-- menumpuk di recycle bin dan memakan kuota ruang skema.
BEGIN
  FOR t IN (SELECT table_name FROM user_tables
             WHERE table_name IN ('PEMINJAMAN', 'BUKU_PENULIS', 'BUKU_KOLEKSI', 'BUKU',
                                  'ANGGOTA', 'GENRE', 'PENERBIT', 'PENULIS')) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
  END LOOP;
END;
/

-- Bila muncul ORA-01536 (space quota exceeded): kuota ruang skema penuh.
-- Jalankan PURGE RECYCLEBIN; lalu periksa SELECT * FROM user_ts_quotas;
-- Data ini membutuhkan sekitar 2 MB ruang (tabel + indeks).

CREATE TABLE anggota 
    ( 
     nik  VARCHAR2 (16)  NOT NULL , 
     nama VARCHAR2 (200)  NOT NULL , 
     hp   VARCHAR2 (15) 
    ) 
;

ALTER TABLE anggota 
    ADD CONSTRAINT anggota_PK PRIMARY KEY ( nik ) ;

ALTER TABLE anggota 
    ADD CONSTRAINT anggota_hp_UN UNIQUE ( hp ) ;

CREATE TABLE buku 
    ( 
     isbn         VARCHAR2 (13)  NOT NULL , 
     judul        VARCHAR2 (200)  NOT NULL , 
     tahun_terbit INTEGER  NOT NULL , 
     penerbit_id  INTEGER  NOT NULL , 
     genre_id     INTEGER  NOT NULL 
    ) 
;

ALTER TABLE buku 
    ADD CONSTRAINT buku_PK PRIMARY KEY ( isbn ) ;

CREATE TABLE buku_koleksi 
    ( 
     id            INTEGER  NOT NULL , 
     buku_isbn     VARCHAR2 (13)  NOT NULL , 
     cara_masuk    VARCHAR2 (20)  NOT NULL , 
     tanggal_masuk DATE  NOT NULL , 
     kondisi       VARCHAR2 (20)  NOT NULL 
    ) 
;

ALTER TABLE buku_koleksi 
    ADD CONSTRAINT buku_koleksi_PK PRIMARY KEY ( id ) ;

CREATE TABLE buku_penulis 
    ( 
     buku_isbn  VARCHAR2 (13)  NOT NULL , 
     penulis_id VARCHAR2 (16)  NOT NULL 
    ) 
;

ALTER TABLE buku_penulis 
    ADD CONSTRAINT buku_penulis_PK PRIMARY KEY ( buku_isbn, penulis_id ) ;

CREATE TABLE genre 
    ( 
     id   INTEGER  NOT NULL , 
     nama VARCHAR2 (200)  NOT NULL 
    ) 
;

ALTER TABLE genre 
    ADD CONSTRAINT genre_PK PRIMARY KEY ( id ) ;

CREATE TABLE peminjaman 
    ( 
     buku_koleksi_id      INTEGER  NOT NULL , 
     anggota_nik          VARCHAR2 (16)  NOT NULL , 
     tanggal_pinjam       DATE  NOT NULL , 
     batas_pengembalian   DATE  NOT NULL , 
     tanggal_pengembalian DATE 
    ) 
;

ALTER TABLE peminjaman 
    ADD CONSTRAINT peminjaman_PK PRIMARY KEY ( buku_koleksi_id, anggota_nik, tanggal_pinjam ) ;

CREATE TABLE penerbit 
    ( 
     id   INTEGER  NOT NULL , 
     nama VARCHAR2 (60) 
    ) 
;

ALTER TABLE penerbit 
    ADD CONSTRAINT penerbit_PK PRIMARY KEY ( id ) ;

CREATE TABLE penulis 
    ( 
     nik  VARCHAR2 (16)  NOT NULL , 
     nama VARCHAR2 (60)  NOT NULL 
    ) 
;

ALTER TABLE penulis 
    ADD CONSTRAINT penulis_PK PRIMARY KEY ( nik ) ;

ALTER TABLE buku 
    ADD CONSTRAINT buku_genre_FK FOREIGN KEY 
    ( 
     genre_id
    ) 
    REFERENCES genre 
    ( 
     id
    ) 
;

ALTER TABLE buku 
    ADD CONSTRAINT buku_penerbit_FK FOREIGN KEY 
    ( 
     penerbit_id
    ) 
    REFERENCES penerbit 
    ( 
     id
    ) 
;

ALTER TABLE buku_koleksi 
    ADD CONSTRAINT buku_koleksi_buku_FK FOREIGN KEY 
    ( 
     buku_isbn
    ) 
    REFERENCES buku 
    ( 
     isbn
    ) 
;

ALTER TABLE buku_penulis 
    ADD CONSTRAINT buku_penulis_buku_FK FOREIGN KEY 
    ( 
     buku_isbn
    ) 
    REFERENCES buku 
    ( 
     isbn
    ) 
;

ALTER TABLE buku_penulis 
    ADD CONSTRAINT buku_penulis_penulis_FK FOREIGN KEY 
    ( 
     penulis_id
    ) 
    REFERENCES penulis 
    ( 
     nik
    ) 
;

ALTER TABLE peminjaman 
    ADD CONSTRAINT peminjaman_anggota_FK FOREIGN KEY 
    ( 
     anggota_nik
    ) 
    REFERENCES anggota 
    ( 
     nik
    ) 
;

ALTER TABLE peminjaman 
    ADD CONSTRAINT peminjaman_buku_koleksi_FK FOREIGN KEY 
    ( 
     buku_koleksi_id
    ) 
    REFERENCES buku_koleksi 
    ( 
     id
    ) 
;
"""


def render_data(data):
    """Tulis INSERT. batch=None -> satu baris per INSERT;
    batch=N -> INSERT ALL ... SELECT 1 FROM dual per N baris (statement jauh lebih sedikit,
    lebih cepat dieksekusi di APEX SQL Scripts, dan berkas ~7% lebih kecil)."""
    batch, sep = data["profile"]["batch"], data["profile"]["sep"]
    out = []
    w = out.append

    def emit(table, count, cols, rows):
        """rows: daftar tuple berisi literal SQL yang sudah di-render."""
        w(f"\n-- ---------------------------------------------------------------- {table} ({count})")
        w(f"-- kolom: {cols}")
        rows = ["(" + sep.join(r) + ")" for r in rows]
        if batch is None:
            for r in rows:
                w(f"INSERT INTO {table} VALUES {r};")
            return
        # Batasan Oracle multitable insert: total kolom target per statement <= 999.
        ncols = cols.count(",") + 1
        assert batch * ncols <= 999, f"batch {batch} x {ncols} kolom melebihi 999 kolom target"
        for i in range(0, len(rows), batch):
            w("INSERT ALL")
            for r in rows[i:i + batch]:
                w(f"  INTO {table} VALUES {r}")
            w("SELECT 1 FROM dual;")

    w("\n-- Urutan INSERT mengikuti dependensi FK: genre, penerbit, penulis, anggota,")
    w("-- buku, buku_penulis, buku_koleksi, peminjaman.")
    w("-- Format ringkas: INSERT tanpa daftar kolom (urutan kolom = urutan pada DDL,")
    w("-- dicantumkan di awal tiap blok) dan literal tanggal ANSI DATE 'YYYY-MM-DD'.")
    if batch:
        w(f"-- Baris dikelompokkan {batch} per statement dengan INSERT ALL ... SELECT 1 FROM dual.")
    w("-- Catatan: ISBN dan NIK bersifat sintetis (ISBN-13 dengan check digit valid);")
    w("-- judul, penulis, penerbit, dan genre adalah data riil.")

    emit("genre", len(data["genres"]), "id, nama",
         [(str(gid), q(nama)) for gid, nama in data["genres"]])
    emit("penerbit", len(data["penerbit"]), "id, nama",
         [(str(pid), q(nama)) for pid, nama in data["penerbit"]])
    emit("penulis", len(data["penulis"]), "nik, nama",
         [(q(nik), q(nama)) for nik, nama in data["penulis"]])
    emit("anggota", len(data["anggota"]), "nik, nama, hp",
         [(q(nik), q(nama), q(hp)) for nik, nama, hp in data["anggota"]])
    emit("buku", len(data["buku"]), "isbn, judul, tahun_terbit, penerbit_id, genre_id",
         [(q(isbn), q(judul), str(tahun), str(pid), str(gid)) for isbn, judul, tahun, pid, gid in data["buku"]])
    emit("buku_penulis", len(data["buku_penulis"]), "buku_isbn, penulis_id",
         [(q(isbn), q(nik)) for isbn, nik in data["buku_penulis"]])
    emit("buku_koleksi", len(data["koleksi"]), "id, buku_isbn, cara_masuk, tanggal_masuk, kondisi",
         [(str(c["id"]), q(c["isbn"]), q(c["cara"]), d(c["masuk"]), q(c["kondisi"])) for c in data["koleksi"]])
    emit("peminjaman", len(data["loans"]), "buku_koleksi_id, anggota_nik, tanggal_pinjam, batas_pengembalian, tanggal_pengembalian",
         [(str(kid), q(nik), d(t), d(batas), d(ret)) for kid, nik, t, batas, ret in data["loans"]])

    w("\nCOMMIT;\n")
    return "\n".join(out)


def summary(data):
    open_loans = sum(1 for l in data["loans"] if l[4] is None)
    late = sum(1 for l in data["loans"] if l[4] is not None and l[4] > l[3])
    kond = defaultdict(int)
    for c in data["koleksi"]:
        kond[c["kondisi"]] += 1
    lines = [
        "-- Ringkasan data:",
        f"--   genre         : {len(data['genres'])}",
        f"--   penerbit      : {len(data['penerbit'])}",
        f"--   penulis       : {len(data['penulis'])}",
        f"--   anggota       : {len(data['anggota'])}",
        f"--   buku (judul)  : {len(data['buku'])}  (Indonesia {data['n_id']}, Inggris {data['n_en']})",
        f"--   buku_penulis  : {len(data['buku_penulis'])}",
        f"--   buku_koleksi  : {len(data['koleksi'])}  ({', '.join(f'{k} {v}' for k, v in sorted(kond.items()))})",
        f"--   peminjaman    : {len(data['loans'])}  (belum kembali {open_loans}, terlambat {late})",
        f"--   periode pinjam: {data['loans'][0][2]} s.d. {data['loans'][-1][2]}",
    ]
    return "\n".join(lines) + "\n"


def generate(name):
    prof = PROFILES[name]
    data = build(prof)
    out = OUT_DIR / prof["subdir"] if prof["subdir"] else OUT_DIR
    out.mkdir(parents=True, exist_ok=True)
    today = TODAY.isoformat()
    summ = summary(data)
    body = render_data(data)

    def header(what):
        return HEADER.format(what=f"{what} - {prof['label']}", today=today, seed=SEED, profile=name)

    files = {
        "perpustakaan_ddl.sql": header("DDL") + DDL,
        "perpustakaan_data.sql": header("DATA (INSERT)") + summ + body,
        "perpustakaan_ddl_data.sql": header("DDL + DATA") + summ + DDL + "\n" + body,
    }
    print(f"== profil {name}: {prof['label']} -> {out}")
    print(summ)
    result = {"data": data, "profile": prof, "sizes": {}, "statements": {}}
    for fname, txt in files.items():
        raw = txt.encode("ascii")
        if prof["max_bytes"] and len(raw) > prof["max_bytes"]:
            raise SystemExit(f"{fname}: {len(raw):,} bytes melebihi batas {prof['max_bytes']:,}; "
                             f"kecilkan books/loans pada PROFILES['{name}']")
        (out / fname).write_bytes(raw)
        result["sizes"][fname] = len(raw)
        result["statements"][fname] = rekap.count_statements(txt)
        print(f"{fname:28s} {len(raw):>9,} bytes  {result['statements'][fname]:>6,} statement")
    if name == "utama":
        p = rekap.write_contoh_sql(out / "contoh_analisis.sql", TODAY)
        result["sizes"]["contoh_analisis.sql"] = p.stat().st_size
        print(f"{'contoh_analisis.sql':28s} {p.stat().st_size:>9,} bytes")
    print()
    return result


def main():
    names = sys.argv[1:] or list(PROFILES)
    results = {}
    for n in names:
        if n not in PROFILES:
            raise SystemExit(f"profil tidak dikenal: {n} (pilihan: {', '.join(PROFILES)})")
        results[n] = generate(n)
    if "utama" in results:
        path = rekap.write(OUT_DIR, results["utama"], TODAY, SEED)
        print(f"README: {path} ({path.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
