# Analisis 3NF dan Audit Trail

## Mengapa Header-Line Lebih Andal dari Flat Journal Table?

### 1. Jejak Audit (Audit Trail) Lebih Terstruktur
Model header-line memisahkan metadata transaksi (tanggal, nomor bukti, deskripsi, status posting) di tabel `journal_headers` dengan detail debit-kredit di tabel `journal_lines`. Auditor dapat dengan mudah melacak:
- Siapa yang membuat jurnal (`created_by`)
- Kapan dibuat (`created_at`)
- Status posting (`DRAFT`, `POSTED`, `REVERSED`)
- Nomor bukti referensi

Jika memakai tabel tunggal (flat), metadata akan terduplikasi di setiap baris sehingga rawan inkonsistensi dan menyulitkan pelacakan.

### 2. Memenuhi Bentuk Normal Ketiga (3NF)
Syarat 3NF:
1. Sudah 1NF (tidak ada repeating group)
2. Sudah 2NF (tidak ada partial dependency)
3. Tidak ada transitive dependency (atribut non-key tidak bergantung pada atribut non-key lain)

Pada model header-line:
- Data header hanya disimpan sekali di `journal_headers`
- Data akun hanya disimpan sekali di `chart_of_accounts`
- `journal_lines` hanya menyimpan foreign key, bukan duplikasi nama/deskripsi

Jika memakai flat table, akan terjadi:
- **Redundansi** — tanggal dan nomor bukti diulang di setiap baris
- **Anomali update** — jika salah satu baris di-update, harus update semua baris serupa
- **Anomali insert** — tidak bisa insert header tanpa line
- **Anomali delete** — menghapus satu line bisa menghapus info header

### 3. Penegakan Double-Entry Lebih Kuat
Dengan `header_id` sebagai penghubung, total debit dan kredit dapat dicek per jurnal. Ini memudahkan trigger/procedure menolak jurnal yang tidak balance.

### 4. Keamanan Finansial & Reversing Entry
Status `POSTED` dapat dikunci di level header. Koreksi dilakukan dengan membuat header baru (reversing entry) yang membalik debit/kredit, bukan mengedit jurnal lama. Ini menjaga keaslian jejak audit.

### 5. Skalabilitas
Model header-line memisahkan concerns sehingga lebih mudah dikembangkan (misalnya menambah field approval, attachment, multi-currency) tanpa mengubah struktur line.