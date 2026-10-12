-- ============================================================
-- CONSTRAINT TAMBAHAN: cegah stok negatif di level tabel
-- ============================================================
ALTER TABLE inventory_items
ADD CONSTRAINT chk_stock_qty_nonnegative CHECK (stock_qty >= 0);

-- ============================================================
-- TRIGGER FUNCTION
-- ============================================================
CREATE OR REPLACE FUNCTION trg_update_stock_and_journal()
RETURNS TRIGGER AS $$
DECLARE
    v_current_stock INT;
    v_new_stock INT;
BEGIN
    -- Validasi qty tidak boleh nol
    IF NEW.qty IS NULL OR NEW.qty = 0 THEN
        RAISE EXCEPTION 'Qty tidak boleh nol';
    END IF;

    -- Lock baris item agar aman dari race condition
    SELECT stock_qty
    INTO v_current_stock
    FROM inventory_items
    WHERE item_id = NEW.item_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Item % tidak ditemukan', NEW.item_id;
    END IF;

    -- Hitung stok baru berdasarkan tipe transaksi
    IF NEW.trx_type = 'PURCHASE' THEN
        v_new_stock := v_current_stock + NEW.qty;

    ELSIF NEW.trx_type = 'SALE' THEN
        IF NEW.qty <= 0 THEN
            RAISE EXCEPTION 'Qty SALE harus positif';
        END IF;
        v_new_stock := v_current_stock - NEW.qty;

    ELSIF NEW.trx_type = 'ADJUSTMENT' THEN
        -- qty boleh positif atau negatif
        v_new_stock := v_current_stock + NEW.qty;

    ELSE
        RAISE EXCEPTION 'Tipe transaksi % tidak dikenal', NEW.trx_type;
    END IF;

    -- Anti-negative inventory prevention
    IF v_new_stock < 0 THEN
        RAISE EXCEPTION
            'Anti-negative inventory: stok item % tidak cukup. Stok saat ini = %, qty transaksi = %',
            NEW.item_id, v_current_stock, NEW.qty;
    END IF;

    -- Update stok
    UPDATE inventory_items
    SET stock_qty = v_new_stock
    WHERE item_id = NEW.item_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- TRIGGER: jalankan function di atas sebelum INSERT
-- ============================================================
CREATE TRIGGER trg_update_stock_and_journal
BEFORE INSERT ON inventory_transactions
FOR EACH ROW
EXECUTE FUNCTION trg_update_stock_and_journal();

-- ============================================================
-- CONTOH UJI COBA (opsional, jalankan manual untuk testing)
-- ============================================================
-- INSERT INTO inventory_items (item_id, item_name, stock_qty, unit_cost)
-- VALUES ('ITM001', 'Barang A', 10, 1000);
--
-- INSERT INTO inventory_transactions (item_id, trx_type, qty)
-- VALUES ('ITM001', 'SALE', 3);   -- stok jadi 7
--
-- INSERT INTO inventory_transactions (item_id, trx_type, qty)
-- VALUES ('ITM001', 'SALE', 8);   -- ERROR, stok tidak cukup