# Penanganan Concurrency (Race Condition) pada Transaksi Persediaan

## Masalah: Overselling saat Dua Kasir Bersamaan

Skenario:
- Stok item ITM001 = 1 unit
- Kasir A dan Kasir B menekan tombol "Jual" pada detik yang sama
- Tanpa proteksi, keduanya membaca stok = 1 sebelum ada yang update
- Keduanya lolos validasi, stok akhir menjadi -1 → **overselling / phantom stock**

## Solusi 1 — `SELECT ... FOR UPDATE` (Row-Level Lock)

`SELECT ... FOR UPDATE` mengunci baris item sampai transaksi selesai. Transaksi kedua akan menunggu hingga transaksi pertama commit/rollback.

**Cuplikan kode:**

```sql
BEGIN;

-- Kunci baris item, kasir lain harus menunggu
SELECT stock_qty
FROM inventory_items
WHERE item_id = 'ITM001'
FOR UPDATE;

-- Aplikasi cek stok di sini
-- Jika stok >= qty yang diminta, lanjutkan
UPDATE inventory_items
SET stock_qty = stock_qty - 1
WHERE item_id = 'ITM001'
  AND stock_qty >= 1;

INSERT INTO inventory_transactions (item_id, trx_type, qty)
VALUES ('ITM001', 'SALE', 1);

COMMIT;