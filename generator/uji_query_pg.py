#!/usr/bin/env python3
"""Harness uji: menjalankan semua query contoh_query.py pada PostgreSQL + orafce.

Tujuan: menangkap kesalahan nama kolom, join, GROUP BY, dan logika sebelum
dijalankan di Oracle. Sintaks khusus Oracle diterjemahkan seperlunya (lihat
translate()). Query bertanda pg="skip" dilewati; pg="<sql>" memakai SQL pengganti.

Pemakaian:
  python3 uji_query_pg.py --setup    # buat container Docker "perpus-validate" (postgres:16 + orafce)
                                     # dan muat ../perpustakaan_ddl_data.sql ke dalamnya
  python3 uji_query_pg.py            # jalankan semua query, tampilkan ringkasan
  python3 uji_query_pg.py -v         # juga tampilkan 3 baris pertama tiap query
  docker stop perpus-validate        # hapus container setelah selesai (dibuat dengan --rm)
"""
import re
import subprocess
import sys
import time
from pathlib import Path

from contoh_query import SECTIONS
from rekap import sidik_query

CONTAINER = "perpus-validate"
PSQL = ["docker", "exec", "-i", CONTAINER, "psql", "-U", "postgres", "-d", "perpus", "-v", "ON_ERROR_STOP=1", "-q"]
PREAMBLE = "SET search_path = oracle, \"$user\", public, pg_catalog;\n"

DATE_TRUNC_FMT = {"MM": "month", "MONTH": "month", "YYYY": "year", "YEAR": "year", "Q": "quarter", "IW": "week", "DD": "day"}


def _balanced(s, start):
    """Indeks tepat setelah kurung tutup yang menyeimbangkan kurung buka di s[start]."""
    depth, i, in_str = 0, start, False
    while True:
        c = s[i]
        if c == "'":
            in_str = not in_str
        elif not in_str:
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    return i + 1
        i += 1


def listagg_to_pg(s):
    """LISTAGG(expr, sep) WITHIN GROUP (ORDER BY ...) -> listagg(expr, sep ORDER BY ...) (orafce)."""
    out, pos = [], 0
    while True:
        m = re.compile(r"\bLISTAGG\(").search(s, pos)
        if not m:
            out.append(s[pos:])
            return "".join(out)
        a_end = _balanced(s, m.end() - 1)
        args = s[m.end():a_end - 1]
        w = re.compile(r"\s*WITHIN GROUP\s*\(").match(s, a_end)
        if not w:
            out.append(s[pos:a_end])
            pos = a_end
            continue
        o_end = _balanced(s, w.end() - 1)
        order = s[w.end():o_end - 1].strip()
        out.append(s[pos:m.start()] + f"listagg({args} {order})")
        pos = o_end


def decode_to_case(s):
    """DECODE(expr, s1, r1, ..., default) -> CASE WHEN expr = s1 THEN r1 ... ELSE default END."""
    while True:
        m = re.search(r"\bDECODE\(", s)
        if not m:
            return s
        i, depth, args, start, in_str = m.end(), 1, [], m.end(), False
        while depth:
            c = s[i]
            if c == "'":
                in_str = not in_str
            elif not in_str:
                if c == "(":
                    depth += 1
                elif c == ")":
                    depth -= 1
                elif c == "," and depth == 1:
                    args.append(s[start:i].strip())
                    start = i + 1
            i += 1
        args.append(s[start:i - 1].strip())
        expr, rest = args[0], args[1:]
        pairs = [f"WHEN {expr} = {rest[k]} THEN {rest[k + 1]}" for k in range(0, len(rest) - 1, 2)]
        default = f" ELSE {rest[-1]}" if len(rest) % 2 else ""
        s = s[:m.start()] + "(CASE " + " ".join(pairs) + default + " END)" + s[i:]


def translate(sql):
    s = sql
    # literal tanggal acuan menggantikan SYSDATE agar deterministik
    s = re.sub(r"\bSYSDATE\b", "DATE '2026-11-05'", s)
    # dengan search_path "oracle" di depan, nama tipe DATE merujuk ke oracle.date (timestamp);
    # paksa tipe date bawaan agar aritmetika tanggal tetap menghasilkan integer hari
    s = re.sub(r"\bDATE '", "pg_catalog.date '", s)
    s = s.replace("::date", "::pg_catalog.date")
    s = decode_to_case(s)
    # TO_DATE: paksa versi pg_catalog (mengembalikan date, bukan oracle.date)
    s = re.sub(r"\bTO_DATE\(", "pg_catalog.to_date(", s)
    # parameter NLS (argumen ke-3 TO_CHAR/TO_DATE/TO_NUMBER) tidak didukung PG
    s = re.sub(r",\s*'NLS_[A-Z_]+=(?:[^']|'')*'\s*\)", ")", s)
    # TRUNC(tanggal, 'FMT') -> date_trunc(...)::date supaya aritmetika tetap bertipe date
    def _trunc(m):
        return f"(date_trunc('{DATE_TRUNC_FMT[m.group(2)]}', {m.group(1)})::pg_catalog.date)"
    s = re.sub(r"\bTRUNC\(((?:[a-z_]+\.)?tanggal_[a-z_]+|pg_catalog\.date '[0-9-]+'),\s*'(MM|MONTH|YYYY|YEAR|Q|IW|DD)'\)", _trunc, s)
    # LISTAGG(x, sep [ON OVERFLOW ...]) WITHIN GROUP (ORDER BY o) -> listagg(x, sep ORDER BY o)
    s = re.sub(r"\s+ON OVERFLOW TRUNCATE '[^']*' WITH COUNT", "", s)
    s = listagg_to_pg(s)
    # agregat statistik
    s = re.sub(r"\bMEDIAN\(([^()]*(?:\([^()]*\)[^()]*)*)\)", r"percentile_cont(0.5) WITHIN GROUP (ORDER BY \1)", s)
    s = re.sub(r"\bSTATS_MODE\(([^()]*(?:\([^()]*\)[^()]*)*)\)", r"mode() WITHIN GROUP (ORDER BY \1)", s)
    s = re.sub(r"\bRATIO_TO_REPORT\(([^)]+)\) OVER \(\)", r"((\1)::numeric / SUM(\1) OVER ())", s)
    # interval
    s = re.sub(r"INTERVAL '(\d+)' (DAY|MONTH|YEAR|HOUR|MINUTE)", r"INTERVAL '\1 \2'", s)
    s = re.sub(r"NUMTODSINTERVAL\(([^,]+),\s*'DAY'\)", r"((\1) * INTERVAL '1 day')", s)
    # top-N gaya lama: WHERE ROWNUM <= n (selalu klausa terakhir pada contoh) -> LIMIT n
    s = re.sub(r"\bWHERE\s+ROWNUM\s*<=\s*(\d+)", r"LIMIT \1", s)
    # operator himpunan Oracle
    s = re.sub(r"\bMINUS\b", "EXCEPT", s)
    # tipe data
    s = re.sub(r"\bVARCHAR2\(", "VARCHAR(", s)
    s = re.sub(r"\bNUMBER\b", "NUMERIC", s)
    # heksadesimal
    s = re.sub(r"TO_CHAR\(([^,]+(?:\([^)]*\))?[^,]*),\s*'X+'\)", r"upper(to_hex((\1)::int))", s)
    # format tahun dua digit RR
    s = re.sub(r"RR'", "YY'", s)
    return s


def run(sql):
    p = subprocess.run(PSQL + ["-At", "-F", " | "], input=PREAMBLE + sql, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def oracle_to_pg_script(text):
    """Ubah perpustakaan_ddl_data.sql (dialek Oracle) menjadi skrip PostgreSQL untuk harness."""
    s = text.replace("VARCHAR2", "VARCHAR")
    s = re.sub(r"^BEGIN\n.*?^END;\n/\n", "", s, flags=re.M | re.S)       # blok PL/SQL drop tabel
    s = re.sub(r"^INSERT ALL\n", "", s, flags=re.M)
    s = re.sub(r"^SELECT 1 FROM dual;\n", "", s, flags=re.M)
    s = re.sub(r"^  INTO (\w+) VALUES (\(.*\))$", r"INSERT INTO \1 VALUES \2;", s, flags=re.M)
    return s


def setup():
    sql_path = Path(__file__).resolve().parent.parent / "perpustakaan_ddl_data.sql"
    print(f"memuat {sql_path.name} ke container {CONTAINER} ...")
    subprocess.run(["docker", "rm", "-f", CONTAINER], capture_output=True)
    subprocess.run(["docker", "run", "-d", "--rm", "--name", CONTAINER, "-e", "POSTGRES_PASSWORD=pg",
                    "-e", "POSTGRES_DB=perpus", "postgres:16"], check=True, capture_output=True)
    for _ in range(60):
        if subprocess.run(["docker", "exec", CONTAINER, "pg_isready", "-U", "postgres", "-q"]).returncode == 0:
            break
        time.sleep(1)
    subprocess.run(["docker", "exec", CONTAINER, "bash", "-c",
                    "apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq postgresql-16-orafce >/dev/null 2>&1"], check=True)
    subprocess.run(["docker", "exec", CONTAINER, "psql", "-U", "postgres", "-d", "perpus", "-q",
                    "-c", "CREATE EXTENSION orafce; CREATE EXTENSION fuzzystrmatch;"], check=True)
    script = oracle_to_pg_script(sql_path.read_text(encoding="ascii"))
    p = subprocess.run(["docker", "exec", "-i", CONTAINER, "psql", "-U", "postgres", "-d", "perpus",
                        "-v", "ON_ERROR_STOP=1", "-q"], input=script, capture_output=True, text=True)
    if p.returncode != 0:
        raise SystemExit("gagal memuat data:\n" + p.stderr)
    rc, out, _ = run("SELECT (SELECT COUNT(*) FROM buku) || ' buku, ' || (SELECT COUNT(*) FROM peminjaman) || ' peminjaman';")
    print("siap:", out.strip())


def main():
    if "--setup" in sys.argv:
        setup()
        return 0
    verbose = "-v" in sys.argv
    total = ok = skipped = failed = 0
    for sec in SECTIONS:
        for i, q in enumerate(sec["queries"], 1):
            kode = f"{sec['kode']}{i}"
            total += 1
            pg = q.get("pg")
            if pg is None and re.search(r"\(\+\)|\bCONNECT BY\b|\bPIVOT\s*\(|\bq'\[", q["sql"]):
                pg = "skip"
            if pg == "skip":
                skipped += 1
                print(f"[{kode}] SKIP   {q['judul']}")
                continue
            stmts = [x.strip() for x in (pg or translate(q["sql"])).split(";\n\n") if x.strip()]
            for j, st in enumerate(stmts):
                rc, out, err = run(st.rstrip(";") + ";")
                lines = [l for l in out.splitlines() if l.strip()]
                tag = f"{kode}" + (f".{j + 1}" if len(stmts) > 1 else "")
                if rc != 0:
                    failed += 1
                    print(f"[{tag}] FAIL   {q['judul']}\n        {err.strip().splitlines()[0] if err.strip() else '?'}")
                    if verbose:
                        print("        " + (st.strip().splitlines()[0] if st.strip() else ""))
                else:
                    ok += 1
                    is_select = re.match(r"\s*(--[^\n]*\n\s*)*(SELECT|WITH)\b", st, flags=re.I) is not None
                    flag = "" if (lines or not is_select) else "   <-- 0 baris!"
                    print(f"[{tag}] OK {len(lines):>4} baris  {q['judul']}{flag}")
                    if verbose:
                        for l in lines[:3]:
                            print("        " + l[:160])
    print(f"\nTotal {total} query: OK {ok}, FAIL {failed}, SKIP {skipped}")
    print(f"Sidik query: {sidik_query()}  (catat di UJI_TERAKHIR pada rekap.py bersama tanggal dan statement={ok})")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
