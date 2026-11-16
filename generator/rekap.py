#!/usr/bin/env python3
"""Membuat README.md: informasi skema, aturan simulasi, dan rekap data semua profil.

Dipanggil otomatis oleh generate.py ketika seluruh profil dibangkitkan
(python3 generate.py tanpa argumen), sehingga angka di README selalu sama
dengan isi berkas SQL.
"""
import re
from collections import Counter

BULAN = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"]
HARI = [("Mon", "Senin"), ("Tue", "Selasa"), ("Wed", "Rabu"), ("Thu", "Kamis"),
        ("Fri", "Jumat"), ("Sat", "Sabtu"), ("Sun", "Minggu")]


def n(x):
    """Format angka gaya Indonesia (ribuan dengan titik, desimal dengan koma)."""
    if isinstance(x, float):
        return f"{x:,.1f}".replace(",", "\0").replace(".", ",").replace("\0", ".")
    return f"{x:,}".replace(",", ".")


def kb(b):
    """Ukuran berkas: KB desimal (seperti Finder/APEX) + byte eksak."""
    return f"{n(round(b / 1000))} KB ({n(b)} byte)"


def tgl(d):
    return f"{d.day} {BULAN[d.month - 1]} {d.year}"


def bln(ym):
    y, m = ym.split("-")
    return f"{BULAN[int(m) - 1]} {y}"


def table(headers, rows, align=None):
    align = align or ["l"] * len(headers)
    mark = {"l": "---", "r": "---:", "c": ":---:"}
    out = ["| " + " | ".join(headers) + " |",
           "|" + "|".join(mark[a] for a in align) + "|"]
    out += ["| " + " | ".join(str(c) for c in r) + " |" for r in rows]
    return "\n".join(out)


def count_statements(text):
    """Jumlah statement seperti yang dihitung APEX SQL Scripts / SQL*Plus."""
    return sum(1 for line in text.splitlines()
               if re.match(r"(CREATE TABLE|ALTER TABLE|INSERT (ALL|INTO)|COMMIT;)", line)
               or line.strip() == "/")


def stats(data, today):
    buku, kol, loans, agg = data["buku"], data["koleksi"], data["loans"], data["anggota"]
    pname = dict(data["penerbit"])
    aname = dict(data["penulis"])
    isbn_genre = {b[0]: b[4] for b in buku}
    isbn_judul = {b[0]: b[1] for b in buku}
    isbn_tahun = {b[0]: b[2] for b in buku}
    kol_isbn = {c["id"]: c["isbn"] for c in kol}
    kol_masuk = {c["id"]: c["masuk"] for c in kol}
    an = {a[0]: a[1] for a in agg}
    ret = [l for l in loans if l[4] is not None]
    opn = [l for l in loans if l[4] is None]
    late = [l for l in ret if l[4] > l[3]]
    per_a = Counter(l[1] for l in loans)
    bulan = Counter(l[2].strftime("%Y-%m") for l in loans)
    s = {}
    s["tabel"] = {"genre": len(data["genres"]), "penerbit": len(data["penerbit"]),
                  "penulis": len(data["penulis"]), "anggota": len(agg), "buku": len(buku),
                  "buku_penulis": len(data["buku_penulis"]), "buku_koleksi": len(kol),
                  "peminjaman": len(loans)}
    s["bahasa"] = (data["n_id"], data["n_en"])
    jud_g = Counter(b[4] for b in buku)
    eks_g = Counter(isbn_genre[c["isbn"]] for c in kol)
    pin_g = Counter(isbn_genre[kol_isbn[l[0]]] for l in loans)
    s["genre"] = [(gid, nm, jud_g[gid], eks_g[gid], pin_g[gid]) for gid, nm in data["genres"]]
    s["tahun"] = (min(b[2] for b in buku), max(b[2] for b in buku))
    s["tahun_dist"] = Counter(("< 2000" if b[2] < 2000 else "2000-2009" if b[2] < 2010
                               else "2010-2019" if b[2] < 2020 else "2020+") for b in buku)
    s["penulis_per_judul"] = Counter(Counter(bp[0] for bp in data["buku_penulis"]).values())
    s["top_penulis"] = [(aname[k], v) for k, v in Counter(bp[1] for bp in data["buku_penulis"]).most_common(10)]
    s["top_penerbit"] = [(pname[k], v) for k, v in Counter(b[3] for b in buku).most_common(10)]
    s["eks_per_judul"] = Counter(Counter(c["isbn"] for c in kol).values())
    s["cara"] = Counter(c["cara"] for c in kol)
    s["kondisi"] = Counter(c["kondisi"] for c in kol)
    s["masuk"] = (min(c["masuk"] for c in kol), max(c["masuk"] for c in kol))
    opn_k = {l[0] for l in opn}
    s["kondisi_belum"] = Counter(c["kondisi"] for c in kol if c["id"] in opn_k)
    tl = [(l[4] - l[3]).days for l in late]
    s["pinjam"] = dict(total=len(loans), kembali=len(ret), belum=len(opn), terlambat=len(late),
                       pct=100 * len(late) / len(ret),
                       overdue_now=sum(1 for l in opn if l[3] < today),
                       durasi=Counter((l[3] - l[2]).days for l in loans),
                       lama_rata=sum((l[4] - l[2]).days for l in ret) / len(ret),
                       telat_rata=sum(tl) / len(tl), telat_max=max(tl),
                       telat30=sum(1 for x in tl if x > 30),
                       awal=loans[0][2], akhir=loans[-1][2])
    s["per_tahun"] = {y: (sum(1 for l in loans if l[2].year == y),
                          sum(1 for l in late if l[2].year == y),
                          sum(1 for l in opn if l[2].year == y))
                      for y in sorted({l[2].year for l in loans})}
    s["per_bulan"] = (sum(bulan.values()) / len(bulan), min(bulan.values()), min(bulan, key=bulan.get),
                      max(bulan.values()), max(bulan, key=bulan.get))
    s["hari"] = Counter(l[2].strftime("%a") for l in loans)
    s["judul_dipinjam"] = len({kol_isbn[l[0]] for l in loans})
    s["eks_dipinjam"] = len({l[0] for l in loans})
    s["top_judul"] = [(isbn_judul[k], v) for k, v in Counter(kol_isbn[l[0]] for l in loans).most_common(10)]

    by_a = {}
    for l in loans:
        by_a.setdefault(l[1], []).append((l[2], l[4]))
    maks = 0
    for ls in by_a.values():
        for (t, _) in ls:
            maks = max(maks, sum(1 for (s0, e) in ls if s0 <= t and (e is None or e >= t)))
    sebaran = Counter(("1-9" if v < 10 else "10-19" if v < 20 else "20-39" if v < 40
                       else "40-69" if v < 70 else "70+") for v in per_a.values())
    s["anggota"] = dict(aktif=len(per_a), rata=len(loans) / len(agg), min=min(per_a.values()),
                        max=max(per_a.values()), sebaran=sebaran,
                        top=[(an[k], v) for k, v in per_a.most_common(5)],
                        telat=[(an[k], v) for k, v in Counter(l[1] for l in late).most_common(3)],
                        pegang=len({l[1] for l in opn}), maks_bersamaan=maks)

    by_k = {}
    for l in loans:
        by_k.setdefault(l[0], []).append(l)
    overlap = 0
    for ls in by_k.values():
        ls = sorted(ls, key=lambda x: x[2])
        for a, b in zip(ls, ls[1:]):
            if a[4] is None or a[4] > b[2]:
                overlap += 1
    s["cek"] = {
        "Judul tanpa penulis": len(set(isbn_judul) - {bp[0] for bp in data["buku_penulis"]}),
        "Penulis / penerbit / genre yang tidak dipakai buku":
            (len(aname) - len({bp[1] for bp in data["buku_penulis"]}))
            + (len(pname) - len({b[3] for b in buku})) + (len(data["genres"]) - len(jud_g)),
        "Eksemplar masuk sebelum tahun terbit": sum(1 for c in kol if c["masuk"].year < isbn_tahun[c["isbn"]]),
        "Pinjaman sebelum eksemplar masuk": sum(1 for l in loans if l[2] <= kol_masuk[l[0]]),
        "Batas <= tanggal pinjam, atau kembali < pinjam":
            sum(1 for l in loans if l[3] <= l[2] or (l[4] is not None and l[4] < l[2])),
        "Transaksi (pinjam/kembali) pada hari Minggu":
            sum(1 for l in loans if l[2].weekday() == 6 or (l[4] is not None and l[4].weekday() == 6)),
        "Eksemplar dipinjam tumpang-tindih": overlap,
        "Eksemplar HILANG tanpa pinjaman aktif":
            sum(1 for c in kol if c["kondisi"] == "HILANG" and c["id"] not in opn_k),
    }
    return s


# ----------------------------------------------------------------------------
# Teks statis
# ----------------------------------------------------------------------------
ERD = """```mermaid
erDiagram
    GENRE        ||--o{ BUKU         : genre_id
    PENERBIT     ||--o{ BUKU         : penerbit_id
    BUKU         ||--|{ BUKU_PENULIS : buku_isbn
    PENULIS      ||--|{ BUKU_PENULIS : penulis_id
    BUKU         ||--|{ BUKU_KOLEKSI : buku_isbn
    BUKU_KOLEKSI ||--o{ PEMINJAMAN   : buku_koleksi_id
    ANGGOTA      ||--o{ PEMINJAMAN   : anggota_nik
```"""

KOLOM = [
    ("genre", "id", "INTEGER", "PK"),
    ("", "nama", "VARCHAR2(200)", "NOT NULL"),
    ("penerbit", "id", "INTEGER", "PK"),
    ("", "nama", "VARCHAR2(60)", ""),
    ("penulis", "nik", "VARCHAR2(16)", "PK (NIK sintetis)"),
    ("", "nama", "VARCHAR2(60)", "NOT NULL"),
    ("anggota", "nik", "VARCHAR2(16)", "PK (NIK sintetis, kode provinsi 73)"),
    ("", "nama", "VARCHAR2(200)", "NOT NULL"),
    ("", "hp", "VARCHAR2(15)", "UNIQUE"),
    ("buku", "isbn", "VARCHAR2(13)", "PK (ISBN-13 sintetis, check digit valid)"),
    ("", "judul", "VARCHAR2(200)", "NOT NULL"),
    ("", "tahun_terbit", "INTEGER", "NOT NULL"),
    ("", "penerbit_id", "INTEGER", "NOT NULL, FK -> penerbit(id)"),
    ("", "genre_id", "INTEGER", "NOT NULL, FK -> genre(id)"),
    ("buku_penulis", "buku_isbn", "VARCHAR2(13)", "PK bagian 1, FK -> buku(isbn)"),
    ("", "penulis_id", "VARCHAR2(16)", "PK bagian 2, FK -> penulis(nik)"),
    ("buku_koleksi", "id", "INTEGER", "PK (nomor eksemplar)"),
    ("", "buku_isbn", "VARCHAR2(13)", "NOT NULL, FK -> buku(isbn) **(ditambahkan)**"),
    ("", "cara_masuk", "VARCHAR2(20)", "NOT NULL: PEMBELIAN / HIBAH / SUMBANGAN / TUKAR"),
    ("", "tanggal_masuk", "DATE", "NOT NULL"),
    ("", "kondisi", "VARCHAR2(20)", "NOT NULL: BAIK / RUSAK RINGAN / RUSAK BERAT / HILANG"),
    ("peminjaman", "buku_koleksi_id", "INTEGER", "PK bagian 1, FK -> buku_koleksi(id)"),
    ("", "anggota_nik", "VARCHAR2(16)", "PK bagian 2, FK -> anggota(nik)"),
    ("", "tanggal_pinjam", "DATE", "PK bagian 3"),
    ("", "batas_pengembalian", "DATE", "NOT NULL (pinjam + 7 atau 14 hari)"),
    ("", "tanggal_pengembalian", "DATE", "NULL = masih dipinjam / belum kembali"),
]

ATURAN = """\
Data dibangkitkan oleh `generator/generate.py` dengan seed tetap (`SEED = 20261106`),
sehingga setiap eksekusi menghasilkan berkas yang byte-identik. Tanggal acuan
simulasi (hari "ini") adalah **{today}**.

**Katalog buku**
- Judul, penulis, penerbit, tahun terbit, dan genre adalah **data riil** buku informatika
  yang beredar. Katalog sumber (`catalog_id.py`, `catalog_en.py`) memuat {kat_id} judul berbahasa
  Indonesia dan {kat_en} berbahasa Inggris; dataset ini memakai {n_id} + {n_en} judul di antaranya,
  dipilih secara deterministik dan proporsional per genre agar seluruh berkas tetap di bawah 500 KB.
- ISBN **sintetis** namun valid secara format: prefiks 978-602 / 978-979 untuk
  terbitan Indonesia, 978-0 / 978-1 untuk terbitan berbahasa Inggris, check digit dihitung benar.
- NIK penulis dan anggota **sintetis** (16 digit berpola NIK), nomor HP anggota unik
  dengan prefiks operator Indonesia. Nama anggota fiktif bernuansa Sulawesi Selatan.

**Eksemplar (buku_koleksi)**
- Setiap judul memiliki **2-6 eksemplar**, diadakan dalam 1-2 gelombang pengadaan
  antara Jan 2008 dan Jun 2026, tidak pernah sebelum tahun terbit.
- Cara masuk: pembelian ±70%, hibah ±20%, sumbangan ±8%, tukar ±2%.
- Kondisi: BAIK ±82%, RUSAK RINGAN ±13%, RUSAK BERAT ±5%; **HILANG** hanya diberikan
  pada eksemplar yang pinjaman terakhirnya belum kembali dan sudah >60 hari melewati batas.

**Peminjaman**
- Periode Jan 2024 s.d. {today}; tidak ada transaksi pada hari Minggu.
- Durasi pinjam 14 hari (±65%) atau 7 hari (±35%).
- ±68% dikembalikan tepat waktu, ±27% terlambat 1-21 hari, ±5% terlambat 22-120 hari,
  ±0,7% tidak kembali (hilang). Pinjaman yang jatuh temponya melewati tanggal acuan
  dicatat dengan `tanggal_pengembalian = NULL`.
- Satu eksemplar tidak pernah dipinjam dua orang pada rentang yang tumpang-tindih.
- Satu anggota memegang **maksimal 3 buku** pada saat bersamaan.
- Popularitas judul mengikuti distribusi log-normal dikali faktor kebaruan
  (judul lebih baru lebih sering dipinjam); keaktifan anggota juga log-normal,
  sehingga ada segelintir anggota/judul yang sangat aktif dan ekor panjang yang jarang.
"""

QUERY_VERIFIKASI = """```sql
SELECT 'genre' tabel, COUNT(*) n FROM genre
UNION ALL SELECT 'penerbit',     COUNT(*) FROM penerbit
UNION ALL SELECT 'penulis',      COUNT(*) FROM penulis
UNION ALL SELECT 'anggota',      COUNT(*) FROM anggota
UNION ALL SELECT 'buku',         COUNT(*) FROM buku
UNION ALL SELECT 'buku_penulis', COUNT(*) FROM buku_penulis
UNION ALL SELECT 'buku_koleksi', COUNT(*) FROM buku_koleksi
UNION ALL SELECT 'peminjaman',   COUNT(*) FROM peminjaman;

-- semua constraint harus ENABLED / VALIDATED
SELECT constraint_type, status, validated, COUNT(*) FROM user_constraints
WHERE  table_name IN ('GENRE','PENERBIT','PENULIS','ANGGOTA','BUKU','BUKU_PENULIS','BUKU_KOLEKSI','PEMINJAMAN')
GROUP  BY constraint_type, status, validated;
```"""

TROUBLESHOOT = [
    ("`ORA-01536: space quota exceeded for tablespace ...`",
     "Kuota ruang skema penuh (sering terjadi di apex.oracle.com). Jalankan `cek_kuota.sql` di SQL Commands: "
     "`PURGE RECYCLEBIN;` lalu periksa `user_ts_quotas`. Data ini butuh sekitar 2 MB. Bila masih kurang, "
     "minta tambahan melalui Administration > Manage Service > Make a Service Request > Request Storage."),
    ("`ORA-00955: name is already used by an existing object`",
     "Tabel sudah ada dari percobaan sebelumnya. Skrip versi terbaru sudah menghapus 8 tabel perpustakaan "
     "secara otomatis di awal; pastikan memakai berkas terbaru."),
    ("`ORA-02260`, `ORA-02264`, `ORA-02275` saat ALTER TABLE",
     "Constraint sudah ada - efek lanjutan dari ORA-00955 di atas; hilang setelah tabel dibuat ulang."),
    ("`ORA-02291: integrity constraint violated - parent key not found`",
     "Sebagian INSERT induk gagal (biasanya karena kuota). Perbaiki penyebabnya lalu jalankan ulang seluruh skrip."),
    ("Berkas ditolak saat upload ke SQL Scripts",
     "Batas unggah APEX SQL Scripts 500 KB. Berkas utama di folder induk sudah di bawah batas; yang di `versi-lengkap/` memang tidak bisa diunggah."),
    ("Karakter aneh pada judul",
     "Seluruh berkas ASCII murni (tanpa diakritik/kutip tipografis); pastikan editor tidak mengubah encoding."),
]




# ----------------------------------------------------------------------------
# Contoh analisis: indeks fungsi dan berkas SQL
# ----------------------------------------------------------------------------
from contoh_query import SECTIONS, FUNGSI, POLA_KHUSUS  # noqa: E402


def _strip_strings(sql):
    """Buang isi string literal agar nama fungsi di dalam kutip tidak ikut terdeteksi."""
    return re.sub(r"'(?:[^']|'')*'", "''", sql)


def fungsi_dipakai(sql):
    body = _strip_strings(sql).upper()
    found = []
    for kategori, names in FUNGSI.items():
        if kategori == "Subquery":          # diisi dari penanda "topik", bukan pola teks
            continue
        for f in names:
            pat = POLA_KHUSUS.get(f, r"\b" + re.escape(f) + r"\s*\(")
            if re.search(pat, body):
                found.append(f)
    return found


def query_index():
    """by_func: {nama: [kode_query, ...]}; by_query: {kode_query: (fungsi, topik_subquery)}."""
    by_func, by_query = {}, {}
    for sec in SECTIONS:
        for i, q in enumerate(sec["queries"], 1):
            kode = f"{sec['kode']}{i}"
            fs = fungsi_dipakai(q["sql"])
            topik = [t for t in q.get("topik", []) if t in FUNGSI["Subquery"]]
            by_query[kode] = (fs, topik)
            for f in fs + topik:
                by_func.setdefault(f, []).append(kode)
    return by_func, by_query


def write_contoh_sql(path, today):
    L = ["-- ============================================================================",
         "-- PERPUSTAKAAN INFORMATIKA - CONTOH ANALISIS (fungsi Oracle SQL)",
         "-- Jalankan setelah perpustakaan_ddl_data.sql dimuat (berkas utama maupun versi-lengkap/).",
         f"-- Tanggal acuan data: {today.isoformat()} (ganti DATE '{today.isoformat()}' dengan SYSDATE",
         "-- bila ingin relatif terhadap hari berjalan). Penjelasan tiap query ada di README.md.",
         "-- ============================================================================", ""]
    for sec in SECTIONS:
        L += ["", f"-- ######## {sec['kode']}. {sec['judul']} ########", ""]
        for i, q in enumerate(sec["queries"], 1):
            L.append(f"-- [{sec['kode']}{i}] {q['judul']}")
            L.append(q["sql"].rstrip())
            L.append("")
    text = "\n".join(L) + "\n"
    text.encode("ascii")  # pastikan ASCII murni
    path.write_text(text, encoding="ascii")
    return path


# ----------------------------------------------------------------------------
# Penyusunan README.md (berdasarkan profil utama)
# ----------------------------------------------------------------------------
def write(out_dir, result, today, seed):
    """result: {"data", "profile", "sizes", "statements"} untuk profil utama."""
    S = stats(result["data"], today)
    prof, sizes, stmts = result["profile"], result["sizes"], result["statements"]
    sub = (prof["subdir"] + "/") if prof["subdir"] else ""
    fname = f"{sub}perpustakaan_ddl_data.sql"
    by_func, by_query = query_index()
    n_query = sum(len(s["queries"]) for s in SECTIONS)
    L = []
    w = L.append

    w("# Data Simulasi Perpustakaan Informatika (Oracle Database / APEX)\n")
    w(f"Berkas utama: **`{fname}`** ({n(round(sizes['perpustakaan_ddl_data.sql'] / 1000))} KB, {n(stmts['perpustakaan_ddl_data.sql'])} statement) "
      "berisi DDL dan data simulasi perpustakaan program studi Informatika untuk **Oracle Database** (APEX, SQL Developer, SQLcl, SQL*Plus): "
      f"{n(S['tabel']['buku'])} judul buku informatika riil berbahasa Indonesia dan Inggris, {n(S['tabel']['buku_koleksi'])} eksemplar, "
      f"{n(S['tabel']['anggota'])} anggota, dan {n(S['tabel']['peminjaman'])} transaksi peminjaman "
      f"({tgl(S['pinjam']['awal'])} s.d. {tgl(S['pinjam']['akhir'])}). Ukuran di bawah 500 KB agar dapat diunggah ke APEX SQL Workshop.\n")
    w(f"Bagian 6 memuat **{n_query} contoh query**: analisis operasional perpustakaan (keterlambatan dan denda, judul terpopuler, "
      "ketersediaan eksemplar, tren, pengingat jatuh tempo), dasar SELECT dan penyaringan, fungsi baris tunggal (karakter, angka, tanggal, "
      "konversi tipe data, umum/kondisional), fungsi baris jamak (grup), join, subquery, operator himpunan, dan fungsi analitik Oracle.\n")
    w("> README ini dibangkitkan otomatis oleh `generator/rekap.py`; seluruh angka dihitung dari data yang sama dengan isi berkas SQL.\n")

    # ---- 1. isi paket
    w("## 1. Isi paket\n")
    rows = [
        (f"`{fname}`", kb(sizes["perpustakaan_ddl_data.sql"]), n(stmts["perpustakaan_ddl_data.sql"]), "**DDL + data** dalam satu berkas (yang diunggah ke APEX)"),
        (f"`{sub}perpustakaan_ddl.sql`", kb(sizes["perpustakaan_ddl.sql"]), n(stmts["perpustakaan_ddl.sql"]), "DDL saja"),
        (f"`{sub}perpustakaan_data.sql`", kb(sizes["perpustakaan_data.sql"]), n(stmts["perpustakaan_data.sql"]), "INSERT saja (jalankan setelah DDL)"),
        (f"`{sub}contoh_analisis.sql`", kb(sizes["contoh_analisis.sql"]), n(n_query), "Semua contoh query bagian 6, siap dijalankan di SQL Scripts"),
        ("`cek_kuota.sql`", "", "", "Diagnosa kuota ruang skema bila muncul ORA-01536"),
        ("`versi-lengkap/perpustakaan_*.sql`", "", "", "Opsional: versi lengkap (938 judul, 2.721 transaksi, ~0,9 MB) untuk SQL Developer/SQLcl; skema sama, terlalu besar untuk APEX"),
        ("`generator/`", "", "", "Generator deterministik (`generate.py`), katalog judul riil, contoh query, pembuat README"),
    ]
    w(table(["Berkas", "Ukuran", "Statement", "Keterangan"], rows, ["l", "r", "r", "l"]))
    w("")

    # ---- 2. cara memuat
    w("## 2. Cara memuat ke Oracle APEX\n")
    w(f"1. SQL Workshop > SQL Scripts > **Upload**, pilih `{fname}` (batas unggah SQL Scripts 500 KB).")
    w(f"2. **Run** > Run Now. Hasil yang diharapkan: **{n(stmts['perpustakaan_ddl_data.sql'])} statements processed, 0 errors**.")
    w("3. Verifikasi jumlah baris dengan query pada bagian 5.")
    w(f"4. (Opsional) Unggah dan jalankan `{sub}contoh_analisis.sql`; pilih *View: Detail* untuk melihat hasil tiap query.\n")
    w("Skrip **aman dijalankan berulang**: blok PL/SQL di awal menghapus 8 tabel perpustakaan (bila ada) dengan "
      "`DROP TABLE ... CASCADE CONSTRAINTS PURGE`; tabel lain di skema tidak disentuh. Data dimuat dengan `INSERT ALL ... SELECT 1 FROM dual` "
      f"({prof['batch']} baris per statement), urut sesuai dependensi FK (genre, penerbit, penulis, anggota, buku, buku_penulis, buku_koleksi, peminjaman), "
      "dan diakhiri `COMMIT`. Tanggal ditulis sebagai literal ANSI `DATE 'YYYY-MM-DD'` sehingga tidak bergantung pada `NLS_DATE_FORMAT`.\n")
    w("Untuk SQL Developer buka berkas lalu jalankan sebagai *script* (F5); untuk SQLcl/SQL*Plus gunakan `@perpustakaan_ddl_data.sql`.\n")

    # ---- 3. skema
    w("## 3. Skema basis data\n")
    w(ERD + "\n")
    w(table(["Tabel", "Kolom", "Tipe", "Keterangan"], [(f"**{t}**" if t else "", k, ty, ket) for t, k, ty, ket in KOLOM]))
    w("\n**Perubahan dari model Data Modeler asli**: kolom `buku.buku_koleksi_id` beserta FK `buku_buku_koleksi_FK` dihapus, dan kolom "
      "`buku_koleksi.buku_isbn` + FK `buku_koleksi_buku_FK` ditambahkan. Pada model asli satu judul hanya bisa punya satu eksemplar, "
      "padahal perpustakaan menyimpan 2-6 eksemplar per judul dan `peminjaman` merujuk ke eksemplar fisik.\n")
    w("Daftar genre:\n")
    w(table(["id", "Genre", "Judul", "Eksemplar", "Peminjaman"],
            [(gid, nm, n(j), n(e), n(p)) for gid, nm, j, e, p in S["genre"]], ["r", "l", "r", "r", "r"]))
    w("")

    # ---- 4. aturan simulasi
    w("## 4. Aturan dan asumsi simulasi\n")
    from catalog_id import BOOKS_ID
    from catalog_en import BOOKS_EN
    w(ATURAN.format(today=tgl(today), n_id=S["bahasa"][0], n_en=S["bahasa"][1], kat_id=len(BOOKS_ID), kat_en=len(BOOKS_EN)))

    # ---- 5. rekap
    w("## 5. Rekap data\n")
    w("### 5.1 Jumlah baris per tabel\n")
    w(table(["Tabel", "Baris", "Keterangan"], [
        ("genre", n(S["tabel"]["genre"]), "10 bidang informatika"),
        ("penerbit", n(S["tabel"]["penerbit"]), "penerbit riil; semuanya dirujuk minimal satu judul"),
        ("penulis", n(S["tabel"]["penulis"]), "penulis riil; NIK sintetis"),
        ("anggota", n(S["tabel"]["anggota"]), "nama fiktif; NIK dan HP sintetis, HP unik"),
        ("buku", n(S["tabel"]["buku"]), f"{n(S['bahasa'][0])} judul berbahasa Indonesia + {n(S['bahasa'][1])} berbahasa Inggris; ISBN-13 sintetis"),
        ("buku_penulis", n(S["tabel"]["buku_penulis"]), "relasi banyak-ke-banyak buku-penulis"),
        ("buku_koleksi", n(S["tabel"]["buku_koleksi"]), "eksemplar fisik, 2-6 per judul"),
        ("peminjaman", n(S["tabel"]["peminjaman"]), f"{tgl(S['pinjam']['awal'])} s.d. {tgl(S['pinjam']['akhir'])}"),
    ], ["l", "r", "l"]))
    w("\nVerifikasi setelah memuat (hasil harus sama persis):\n")
    w(QUERY_VERIFIKASI + "\n")

    w("### 5.2 Katalog buku\n")
    rows = [("Rentang tahun terbit", f"{S['tahun'][0]}-{S['tahun'][1]}")]
    rows += [(f"Terbit {k}", n(S["tahun_dist"].get(k, 0))) for k in ("< 2000", "2000-2009", "2010-2019", "2020+")]
    rows += [(f"Judul dengan {k} penulis", n(S["penulis_per_judul"].get(k, 0))) for k in sorted(S["penulis_per_judul"])]
    w(table(["", "Jumlah"], rows, ["l", "r"]))
    w("\nPenulis dan penerbit dengan judul terbanyak:\n")
    w(table(["#", "Penulis", "Judul", "Penerbit", "Judul"],
            [(i + 1, S["top_penulis"][i][0], S["top_penulis"][i][1], S["top_penerbit"][i][0], S["top_penerbit"][i][1]) for i in range(10)],
            ["r", "l", "r", "l", "r"]))
    w("")

    w("### 5.3 Eksemplar (buku_koleksi)\n")
    rows = [(f"Judul dengan {k} eksemplar", n(S["eks_per_judul"].get(k, 0))) for k in range(2, 7)]
    rows += [(f"Cara masuk {k}", n(S["cara"].get(k, 0))) for k in ("PEMBELIAN", "HIBAH", "SUMBANGAN", "TUKAR")]
    rows += [(f"Kondisi {k}", n(S["kondisi"].get(k, 0))) for k in ("BAIK", "RUSAK RINGAN", "RUSAK BERAT", "HILANG")]
    rows += [("Tanggal masuk paling awal", tgl(S["masuk"][0])), ("Tanggal masuk paling akhir", tgl(S["masuk"][1])),
             ("Eksemplar yang pernah dipinjam", f"{n(S['eks_dipinjam'])} ({100 * S['eks_dipinjam'] / S['tabel']['buku_koleksi']:.0f}%)")]
    w(table(["", "Jumlah"], rows, ["l", "r"]))
    w("\nSeluruh eksemplar berkondisi HILANG memiliki tepat satu pinjaman yang belum kembali.\n")

    w("### 5.4 Peminjaman\n")
    P = S["pinjam"]
    w(table(["", "Nilai"], [
        ("Total transaksi", n(P["total"])),
        ("Periode", f"{tgl(P['awal'])} - {tgl(P['akhir'])}"),
        ("Sudah dikembalikan", n(P["kembali"])),
        ("Belum kembali (tanggal_pengembalian NULL)", n(P["belum"])),
        ("- di antaranya sudah lewat batas per tanggal acuan", n(P["overdue_now"])),
        ("Dikembalikan terlambat (% dari yang kembali)", f"{n(P['terlambat'])} ({n(P['pct'])}%)"),
        ("Rata-rata keterlambatan (hari)", n(P["telat_rata"])),
        ("Keterlambatan maksimum (hari)", n(P["telat_max"])),
        ("Terlambat > 30 hari", n(P["telat30"])),
        ("Durasi pinjam 14 hari / 7 hari", f"{n(P['durasi'][14])} / {n(P['durasi'][7])}"),
        ("Rata-rata lama pinjam aktual (hari)", n(P["lama_rata"])),
        ("Rata-rata transaksi per bulan", n(S["per_bulan"][0])),
        ("Bulan tersibuk", f"{bln(S['per_bulan'][4])} ({n(S['per_bulan'][3])})"),
        ("Judul yang pernah dipinjam", f"{n(S['judul_dipinjam'])} dari {n(S['tabel']['buku'])}"),
    ], ["l", "r"]))
    w("\nPer tahun:\n")
    w(table(["Tahun", "Transaksi", "Terlambat", "Belum kembali"],
            [(y, n(v[0]), n(v[1]), n(v[2])) for y, v in S["per_tahun"].items()], ["l", "r", "r", "r"]))
    w("\nSebaran hari peminjaman:\n")
    w(table(["Hari", "Transaksi"], [(nm, n(S["hari"].get(k, 0))) for k, nm in HARI], ["l", "r"]))
    w("\nJudul terpopuler:\n")
    w(table(["#", "Judul", "Pinjam"], [(i + 1, j, v) for i, (j, v) in enumerate(S["top_judul"])], ["r", "l", "r"]))
    w("")

    w("### 5.5 Anggota\n")
    A = S["anggota"]
    rows = [("Anggota terdaftar / pernah meminjam", f"{n(S['tabel']['anggota'])} / {n(A['aktif'])}"),
            ("Rata-rata pinjaman per anggota", n(A["rata"])),
            ("Pinjaman per anggota (min - maks)", f"{A['min']} - {A['max']}")]
    rows += [(f"Anggota dengan {k} pinjaman", n(A["sebaran"].get(k, 0))) for k in ("1-9", "10-19", "20-39", "40-69", "70+")]
    rows += [("Sedang memegang buku", n(A["pegang"])), ("Maks. buku dipegang bersamaan", A["maks_bersamaan"])]
    w(table(["", "Nilai"], rows, ["l", "r"]))
    w("\nAnggota teraktif: " + "; ".join(f"{nm} ({v})" for nm, v in A["top"]) + ". "
      "Paling sering terlambat: " + "; ".join(f"{nm} ({v}x)" for nm, v in A["telat"]) + ".\n")

    w("### 5.6 Pemeriksaan konsistensi\n")
    w("Dihitung ulang dari data saat README dibuat; semua pelanggaran harus 0.\n")
    rows = [(k, n(v)) for k, v in S["cek"].items()]
    rows.append(("Eksemplar per judul (min - maks)", f"{min(S['eks_per_judul'])} - {max(S['eks_per_judul'])}"))
    w(table(["Pemeriksaan", "Hasil"], rows, ["l", "r"]))
    w("\nValidasi eksekusi: DDL berkas ini telah dijalankan pada Oracle APEX 26.2 (8 tabel, 39 constraint); DDL+data divalidasi utuh pada PostgreSQL "
      "dengan dialek disamakan (0 pelanggaran integritas); skema yang sama dengan data versi lengkap dieksekusi utuh (`WHENEVER SQLERROR EXIT`) "
      "pada Oracle Database 23ai Free dengan seluruh constraint ENABLED/VALIDATED.\n")

    # ---- 6. contoh analisis
    w("## 6. Contoh analisis\n")
    w(f"{n_query} query dikelompokkan ke dalam {len(SECTIONS)} sub-bagian; indeks fungsi/klausa ke nomor query ada di 6.{len(SECTIONS) + 1}. "
      f"Semua query memakai tanggal acuan data (`DATE '{today.isoformat()}'`) agar hasilnya dapat direproduksi; ganti dengan `SYSDATE` untuk laporan "
      f"yang mengikuti hari berjalan. Seluruh query tersedia dalam `{sub}contoh_analisis.sql` dengan label `-- [kode]` yang sama. "
      "Baris hasil dibatasi dengan `FETCH FIRST n ROWS ONLY` (Oracle 12c+) bila daftarnya panjang.\n")
    w(table(["Sub-bagian", "Topik", "Query", "Kode"],
            [(f"6.{i}", sec["judul"], len(sec["queries"]), f"{sec['kode']}1-{sec['kode']}{len(sec['queries'])}")
             for i, sec in enumerate(SECTIONS, 1)], ["l", "l", "r", "l"]))
    w("")
    w("Pemeriksaan kualitas: setiap query dijalankan terhadap data ini pada PostgreSQL + ekstensi orafce (emulasi fungsi Oracle) dengan hasil tidak kosong; "
      "sintaks khusus Oracle (`SYSDATE`, parameter NLS, `LISTAGG ... WITHIN GROUP`, `DECODE`, `MEDIAN`, fungsi grup bersarang) ditulis mengikuti "
      "dokumentasi Oracle Database SQL Language Reference.\n")

    for si, sec in enumerate(SECTIONS, 1):
        w(f"### 6.{si} {sec['judul']}\n")
        w(sec["intro"] + "\n")
        for i, q in enumerate(sec["queries"], 1):
            kode = f"{sec['kode']}{i}"
            w(f"#### {kode}. {q['judul']}\n")
            w(q["ket"] + "\n")
            fs, topik = by_query[kode]
            if fs:
                w("Fungsi: " + ", ".join(f"`{f}`" for f in fs) + "\n")
            if topik:
                w("Topik subquery: " + ", ".join(topik) + "\n")
            w("```sql\n" + q["sql"].rstrip() + "\n```\n")

    w(f"### 6.{len(SECTIONS) + 1} Indeks fungsi\n")
    w("Nomor query tempat tiap fungsi, klausa, atau jenis subquery dipakai. Kategori *Subquery* mencakup juga query di luar sub-bagian 6.10 "
      "yang memakai subquery sebagai bagian dari analisisnya.\n")
    rows = []
    for kategori, names in FUNGSI.items():
        for f in names:
            if f in by_func:
                label = f if kategori == "Subquery" else f"`{f}`"
                rows.append((kategori, label, ", ".join(by_func[f])))
    w(table(["Kategori", "Fungsi", "Query"], rows))
    w("")

    # ---- 7. troubleshooting
    w("## 7. Pemecahan masalah\n")
    w(table(["Gejala", "Penyebab dan solusi"], TROUBLESHOOT))
    w("")

    # ---- 8. generator
    w("## 8. Membangkitkan ulang atau mengubah data\n")
    w("```bash\ncd generator\npython3 generate.py          # semua profil + README.md + contoh_analisis.sql\n"
      "python3 generate.py utama    # hanya versi utama (folder induk)\npython3 generate.py lengkap  # hanya versi lengkap (versi-lengkap/)\n```\n")
    w("Hanya memerlukan Python 3.8+ tanpa pustaka tambahan. Parameter profil `utama` pada `PROFILES` di `generate.py` "
      "(profil `lengkap` memakai seluruh katalog, 120 anggota, target 2.800 transaksi, satu INSERT per baris):\n")
    w(table(["Parameter", "Arti", "Nilai"], [
        ("`books`", "jumlah judul yang dipakai dari katalog (dipilih proporsional per genre)", prof["books"]),
        ("`members`", "jumlah anggota", prof["members"]),
        ("`loans`", "target jumlah transaksi (hasil dikalibrasi mendekati nilai ini)", prof["loans"]),
        ("`koleksi_weights`", "bobot peluang 2/3/4/5/6 eksemplar per judul", prof["koleksi_weights"]),
        ("`batch`", "baris per `INSERT ALL`", prof["batch"]),
        ("`max_bytes`", "batas ukuran berkas; generator gagal bila terlampaui", n(prof["max_bytes"])),
    ]))
    w(f"\nKonstanta lain: `SEED = {seed}`, `TODAY` (tanggal acuan), `LOAN_START`, `ACQ_START`, `ACQ_END`. "
      "Untuk menambah judul, tambahkan tuple `(genre_id, tahun, penerbit, judul, (penulis, ...))` pada `catalog_id.py` atau `catalog_en.py`; "
      "penerbit dan penulis baru otomatis dibuatkan barisnya. Contoh query ada di `contoh_query.py`; `uji_query_pg.py` menjalankannya pada "
      "PostgreSQL + orafce (Docker) sebagai uji regresi.\n")

    # ---- 9. catatan
    w("## 9. Catatan\n")
    w("- Judul, penulis, dan penerbit adalah karya nyata; tahun terbit mengacu pada salah satu edisi yang beredar dan dapat berbeda dengan edisi lain.")
    w("- ISBN, NIK, nomor HP, nama anggota, tanggal, dan seluruh transaksi bersifat sintetis. Kesamaan dengan orang atau peristiwa nyata adalah kebetulan.")
    w("- Berkas SQL ASCII murni, akhir baris LF, tanpa karakter `&` (aman dari substitusi SQL*Plus) dan tanpa baris kosong di dalam statement.")
    w("- Fungsi yang bergantung pada pengaturan sesi: `NEXT_DAY` (nama hari mengikuti `NLS_DATE_LANGUAGE`), `TO_CHAR(tanggal)` tanpa format "
      "(`NLS_DATE_FORMAT`), `TO_CHAR(angka, 'L...')` tanpa parameter NLS (`NLS_CURRENCY`). Contoh di README menyertakan parameter NLS eksplisit bila perlu.")
    (out_dir / "README.md").write_text("\n".join(L) + "\n", encoding="utf-8")
    return out_dir / "README.md"
