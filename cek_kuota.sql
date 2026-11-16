-- ============================================================================
-- CEK KUOTA RUANG SKEMA (jalankan di APEX: SQL Workshop > SQL Commands)
-- Gunakan bila skrip gagal dengan ORA-01536: space quota exceeded for tablespace
-- ============================================================================

-- 1) Kuota vs pemakaian (kuota_mb = -1 berarti tanpa batas)
SELECT tablespace_name,
       ROUND(bytes / 1048576, 2)     AS terpakai_mb,
       ROUND(max_bytes / 1048576, 2) AS kuota_mb,
       ROUND((max_bytes - bytes) / 1048576, 2) AS sisa_mb
FROM   user_ts_quotas;

-- 2) Ruang yang tertahan di recycle bin (tabel yang pernah di-DROP tanpa PURGE)
SELECT COUNT(*) AS objek_di_recyclebin,
       ROUND(NVL(SUM(bytes), 0) / 1048576, 2) AS mb_tertahan
FROM   user_segments
WHERE  segment_name LIKE 'BIN$%';

-- 3) Objek yang paling banyak memakai ruang
SELECT segment_name, segment_type, ROUND(bytes / 1048576, 2) AS mb
FROM   user_segments
ORDER  BY bytes DESC
FETCH FIRST 20 ROWS ONLY;

-- 4) Bebaskan ruang recycle bin (aman: hanya menghapus permanen objek yang
--    memang sudah di-DROP). Setelah ini ulangi query no. 1.
-- PURGE RECYCLEBIN;

-- 5) Bila sisa_mb masih < 3 MB: minta tambahan kuota di apex.oracle.com melalui
--    Administration > Manage Service > Make a Service Request > Request Storage.
