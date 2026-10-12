-- ============================================================
-- AUDIT TRAIL & IMMUTABILITY
-- Mengunci jurnal berstatus POSTED agar tidak bisa diubah/dihapus
-- Koreksi hanya via jurnal pembalik (reversing entry / storno)
-- ============================================================

-- ------------------------------------------------------------
-- 1. Pastikan kolom audit trail tersedia
-- ------------------------------------------------------------
ALTER TABLE journal_headers
    ADD COLUMN IF NOT EXISTS created_by    VARCHAR(50),
    ADD COLUMN IF NOT EXISTS created_at    TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    ADD COLUMN IF NOT EXISTS hash_checksum TEXT;

-- ------------------------------------------------------------
-- 2. Trigger: cegah UPDATE pada jurnal POSTED
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION prevent_posted_update()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status_posting = 'POSTED' THEN
        RAISE EXCEPTION
            'Transaksi POSTED (header_id=%) tidak dapat diubah. '
            'Buat jurnal pembalik (reversing entry).',
            OLD.header_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_posted_update ON journal_headers;

CREATE TRIGGER trg_prevent_posted_update
BEFORE UPDATE ON journal_headers
FOR EACH ROW
EXECUTE FUNCTION prevent_posted_update();

-- ------------------------------------------------------------
-- 3. Trigger: cegah DELETE pada jurnal POSTED
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION prevent_posted_delete()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status_posting = 'POSTED' THEN
        RAISE EXCEPTION
            'Transaksi POSTED (header_id=%) tidak dapat dihapus. '
            'Buat jurnal pembalik (reversing entry).',
            OLD.header_id;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_posted_delete ON journal_headers;

CREATE TRIGGER trg_prevent_posted_delete
BEFORE DELETE ON journal_headers
FOR EACH ROW
EXECUTE FUNCTION prevent_posted_delete();

-- ------------------------------------------------------------
-- 4. Trigger: cegah UPDATE/DELETE pada journal_lines
--    jika header-nya sudah POSTED
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION prevent_posted_line_change()
RETURNS TRIGGER AS $$
DECLARE
    v_status VARCHAR(10);
BEGIN
    SELECT status_posting INTO v_status
    FROM journal_headers
    WHERE header_id = COALESCE(OLD.header_id, NEW.header_id);

    IF v_status = 'POSTED' THEN
        RAISE EXCEPTION
            'Baris jurnal dari header POSTED tidak dapat diubah/dihapus. '
            'Gunakan reversing entry.';
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_posted_line_update ON journal_lines;
CREATE TRIGGER trg_prevent_posted_line_update
BEFORE UPDATE ON journal_lines
FOR EACH ROW
EXECUTE FUNCTION prevent_posted_line_change();

DROP TRIGGER IF EXISTS trg_prevent_posted_line_delete ON journal_lines;
CREATE TRIGGER trg_prevent_posted_line_delete
BEFORE DELETE ON journal_lines
FOR EACH ROW
EXECUTE FUNCTION prevent_posted_line_change();

-- ------------------------------------------------------------
-- 5. Fungsi reversing entry (storno)
--    Membuat header baru dengan debit/kredit dibalik
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION create_reversing_entry(
    p_original_header_id INT,
    p_created_by VARCHAR
)
RETURNS INT AS $$
DECLARE
    v_new_header_id INT;
    v_new_ref       VARCHAR(50);
BEGIN
    -- Validasi header asal
    IF NOT EXISTS (
        SELECT 1 FROM journal_headers
        WHERE header_id = p_original_header_id
          AND status_posting = 'POSTED'
    ) THEN
        RAISE EXCEPTION
            'Header % tidak ditemukan atau belum POSTED.',
            p_original_header_id;
    END IF;

    v_new_ref := 'REV-' || p_original_header_id || '-' ||
                 to_char(now(), 'YYYYMMDDHH24MISS');

    -- Buat header baru
    INSERT INTO journal_headers (
        transaction_date, reference_no, description, status_posting, created_by
    )
    VALUES (
        CURRENT_DATE,
        v_new_ref,
        'Reversing entry untuk header #' || p_original_header_id,
        'POSTED',
        p_created_by
    )
    RETURNING header_id INTO v_new_header_id;

    -- Salin line dengan debit & kredit ditukar
    INSERT INTO journal_lines (
        header_id, account_id, debit, credit, description
    )
    SELECT
        v_new_header_id,
        account_id,
        credit,
        debit,
        'Reversing line untuk line #' || line_id
    FROM journal_lines
    WHERE header_id = p_original_header_id;

    -- Tandai header asal sebagai REVERSED
    UPDATE journal_headers
    SET status_posting = 'REVERSED'
    WHERE header_id = p_original_header_id;

    RETURN v_new_header_id;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- 6. (Opsional) Fungsi hitung hash_checksum untuk integritas
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION compute_journal_hash(p_header_id INT)
RETURNS TEXT AS $$
DECLARE
    v_payload TEXT;
BEGIN
    SELECT
        h.header_id || '|' ||
        h.transaction_date || '|' ||
        h.reference_no || '|' ||
        COALESCE(h.description, '') || '|' ||
        COALESCE(string_agg(
            l.account_id || ':' || l.debit || ':' || l.credit,
            ',' ORDER BY l.line_id
        ), '')
    INTO v_payload
    FROM journal_headers h
    LEFT JOIN journal_lines l ON l.header_id = h.header_id
    WHERE h.header_id = p_header_id
    GROUP BY h.header_id, h.transaction_date, h.reference_no, h.description;

    RETURN encode(digest(v_payload, 'sha256'), 'hex');
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- 7. Contoh uji coba (komentar saja)
-- ------------------------------------------------------------
-- SELECT create_reversing_entry(1, 'auditor_01');
-- UPDATE journal_headers SET description = 'diubah' WHERE header_id = 1;
--   → ERROR: Transaksi POSTED tidak dapat diubah