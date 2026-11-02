# Dokumentasi dozeless

| Path | Isi |
|---|---|
| `ringkasan.html` | **Mulai di sini.** Ringkasan satu halaman: apa yang dibuat, plugin bisa apa, hasil uji, keputusan, sisa pekerjaan. |
| `spec/flutter-background-tracking-spec.html` | Spesifikasi desain. Di dokumen ini plugin masih bernama sementara `bg_jobs`. |
| `plan/2026-10-29-dozeless-plugin.md` | Plan implementasi per task (TDD) yang menghasilkan repo ini, plus langkah verifikasi di HP asli. |
| `test-results/` | Bukti uji per versi Android: hasil (`*.result.md`), database yang ditulis job (`*.db`), logcat, dan skrip uji (`matrix.sh`, `run_all2.sh`). Diuji saat plugin masih bernama `bg_jobs`. |
| `test-results/FORCE-STOP.md` | Eksperimen force stop, satu jam per kondisi, di Android 14 dan 16 (skrip `force_stop.sh`), plus fitur yang dibuat dari hasilnya. |
| `screenshots/` | Gambar untuk README, diambil dari emulator Android 16. |
| `internal/` | Catatan tentang tracking di app Sa.To, asal fitur ini diambil. Tidak ikut dipublikasikan (`.pubignore`). |
