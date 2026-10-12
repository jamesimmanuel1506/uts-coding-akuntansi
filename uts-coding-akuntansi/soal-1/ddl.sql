CREATE TABLE chart_of_accounts (
    account_id SERIAL PRIMARY KEY,
    account_code VARCHAR(20) NOT NULL UNIQUE,
    account_name VARCHAR(100) NOT NULL,
    normal_balance VARCHAR(10) NOT NULL
        CHECK (normal_balance IN ('DEBIT', 'CREDIT')),
    report_classification VARCHAR(20) NOT NULL
        CHECK (report_classification IN ('ASSET', 'LIABILITY', 'EQUITY', 'REVENUE', 'EXPENSE'))
);

CREATE TABLE journal_headers (
    header_id SERIAL PRIMARY KEY,
    transaction_date DATE NOT NULL,
    reference_no VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    status_posting VARCHAR(10) NOT NULL DEFAULT 'DRAFT'
        CHECK (status_posting IN ('DRAFT', 'POSTED', 'REVERSED')),
    created_by VARCHAR(50) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hash_checksum TEXT
);

CREATE TABLE journal_lines (
    line_id SERIAL PRIMARY KEY,
    header_id INT NOT NULL,
    account_id INT NOT NULL,
    debit NUMERIC(15,2) NOT NULL DEFAULT 0,
    credit NUMERIC(15,2) NOT NULL DEFAULT 0,
    description TEXT,
    CONSTRAINT fk_journal_lines_header
        FOREIGN KEY (header_id) REFERENCES journal_headers(header_id)
        ON DELETE RESTRICT,
    CONSTRAINT fk_journal_lines_account
        FOREIGN KEY (account_id) REFERENCES chart_of_accounts(account_id)
        ON DELETE RESTRICT,
    CONSTRAINT chk_debit_nonnegative CHECK (debit >= 0),
    CONSTRAINT chk_credit_nonnegative CHECK (credit >= 0),
    CONSTRAINT chk_not_both_zero CHECK (debit > 0 OR credit > 0)
);lanjut