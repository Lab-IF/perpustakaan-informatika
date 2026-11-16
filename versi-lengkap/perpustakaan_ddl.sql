-- ============================================================================
-- PERPUSTAKAAN INFORMATIKA - DDL - VERSI LENGKAP (OPSIONAL)
-- Target  : Oracle Database 21c (SQL Developer / SQL*Plus / SQLcl / APEX SQL Scripts)
-- Dibuat  : 2026-11-05 (generator deterministik, seed 20261106, profil lengkap)
-- Sumber model: Oracle SQL Developer Data Modeler 24.3.1 (dimodifikasi)
--
-- Perubahan dari model asli:
--   * Kolom buku.buku_koleksi_id dan FK buku_buku_koleksi_FK DIHAPUS.
--   * Kolom buku_koleksi.buku_isbn ditambahkan + FK buku_koleksi_buku_FK -> buku(isbn).
--   Alasan: satu judul (buku) memiliki 2-6 eksemplar fisik (buku_koleksi),
--   dan peminjaman merujuk ke eksemplar fisik.
-- ============================================================================

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
