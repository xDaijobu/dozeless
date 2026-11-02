# Force stop: bisakah job jalan lagi tanpa membuka aplikasi?

Tanggal: 29–30 Oktober 2026. Emulator Pixel 9 (Android 16, API 36) dan Pixel 5 (Android 14, API 34), baterai *Unrestricted*, build debug example app.

## Jawaban singkat

Setelah force stop sungguhan, **aplikasi tidak bisa menghidupkan dirinya sendiri**. Android menaruh app di *stopped state*: semua alarm dihapus, broadcast tidak dikirim, dan sejak Android 15 semua PendingIntent ikut dibatalkan. App baru keluar dari keadaan itu lewat **aksi pengguna** (membuka app, widget, share sheet, tile, live wallpaper). Ini aturan sistem, berlaku untuk semua app.

Yang bisa dilakukan, dan sekarang ada di plugin:

| Cara | Apa yang terjadi | Status |
|---|---|---|
| **Recovery saat keluar dari stopped state** | Android 15+ mengirim `BOOT_COMPLETED` (tanpa reboot) saat aksi pengguna mengakhiri stopped state. Sebelumnya plugin menganggap itu "boot yang sama" dan diam saja, jadi job tidak di-arm ulang kalau app tidak dibuka. Sekarang plugin langsung reconcile. | Terbukti di Android 16 (fase 0 di bawah) |
| **Tile Quick Settings** (`DozelessTileService`, opt-in) | Begitu panel Quick Settings dibuka dan tile terlihat, SystemUI mengikat (bind) service tile. Itu menyalakan proses app, mengeluarkannya dari stopped state, dan plugin reconcile semua job. App tidak terbuka. | Terbukti sekali di Android 16 (probe B); belum diuji 1 jam, belum diuji di Android 14 |
| **Pengaman force stop** (`DozelessAdminReceiver`, opt-in) | Device admin tanpa policy. Selama aktif, Settings mematikan tombol **Force stop** (logika di `AppButtonsPreferenceController` AOSP: `packageHasActiveAdmins`). | Terbukti di Android 16 (probe C); belum diuji 1 jam |
| Device owner (`setUserControlDisabledPackages`) | Kalau app adalah device owner (HP kantor), plugin juga memblokir force stop dan clear data di semua halaman Settings. | **Belum diuji** |

Yang tidak bisa: menghidupkan app dari force stop tanpa aksi pengguna sama sekali. FCM, alarm, JobScheduler, WorkManager, dan broadcast biasa semuanya tidak sampai ke app yang stopped.

## Yang sudah diuji

### Probe A: Doze (Android 16, build release)

Layar mati, baterai dicabut, `dumpsys deviceidle force-idle`, 7 menit. Job `spike` tetap jalan tiap menit (7 run, `idle=true`), telat alarm 4–11 ms. Job `slow` (20 detik) jalan 2× penuh. Build release (R8) juga jalan normal.

### Probe B: force stop → buka panel Quick Settings (Android 16)

1. Tile ditambahkan (`cmd statusbar add-tile`), tunggu ±40 detik.
2. `am force-stop`: tidak ada proses, `stopped=true`, tidak ada alarm. Tetap begitu selama 30 detik pengamatan.
3. `cmd statusbar expand-settings` (panel dibuka, tile tidak ditekan): `Start proc … for service DozelessTileService`, `stopped=false`, plugin log `reconcile armed id=spike` dan `id=slow`, job `spike` jalan 5 detik kemudian. Alarm berikutnya ter-arm.

Catatan: setelah panel ditutup, proses app dimatikan sistem sebagai proses cache, tapi alarm tetap ada, jadi rantai tetap jalan.

### Probe C: pengaman force stop (Android 16)

`dpm set-active-admin` lalu buka App info: tombol **Force stop** (dan Archive) abu-abu. Diketuk: tidak ada dialog, app tetap `stopped=false`. Screenshot: `doc/screenshots/force-stop-disabled.png`.

### Fase 0 skrip: sistem membangunkan app yang stopped (Android 16)

App di-force stop (`stopped=true`), lalu device admin diaktifkan lewat `dpm`. Sistem mengirim `DEVICE_ADMIN_ENABLED`, app keluar dari stopped state, dan Android 16 mengirim `BOOT_COMPLETED` tanpa reboot. Pukul 00:07:59 plugin mencatat `boot broadcast, no new boot to restart: reconciling`, membaca event `processExit` (`USER_REQUESTED`, `[FORCE STOP]`), lalu `reconcile armed id=spike` dan `id=slow`, semuanya tanpa app dibuka (`stopped=false`, proses hidup). 12 detik kemudian skrip membuka app untuk mematikan admin, jadi run berikutnya (00:08:12) tidak dihitung sebagai bukti terpisah. Ini membuktikan perbaikan `SystemEventReceiver`: tanpa perbaikan itu, `BOOT_COMPLETED` ini diabaikan dan job baru di-arm ulang saat app dibuka.

Bukti: `force-stop-api36/api36.logcat`, `force-stop-api36/api36.result.md`.

### Temuan sampingan (Android 16): memori emulator sempit

Selama probe, proses app berkali-kali dibunuh low memory killer (event `processExit` `LOW_MEMORY`). Rantai alarm tetap jalan: tiap alarm menyalakan proses baru dan job tetap jalan (lihat `force-stop-api36/api36.logcat`, 00:03–00:07).

### Temuan sampingan (Android 14)

Kalau force stop terjadi **tepat setelah** tile ditambahkan (SystemUI masih bind ke tile), sistem me-restart service tile 1 detik kemudian, jadi app langsung hidup lagi (`Start proc … for service DozelessTileService`). Itu membuat fase 0 di Android 14 tidak valid (app tidak sempat stopped). Skrip sekarang menunggu 60 detik setelah menambah tile.

Bukti: `force-stop-api34/api34.logcat`, `force-stop-api34/api34.result.md`.

## Yang belum selesai

Eksperimen satu jam per kondisi (`force_stop.sh`) **terputus** di awal fase 1 pada kedua emulator: Claude Code menghentikan emulator dan skrip karena memori host hampir habis (dua emulator 2 GB + build Gradle di mesin 32 GB). Belum ada angka satu jam untuk:

1. Force stop, tanpa interaksi apa pun (harapan: 0 run)
2. Force stop → panel Quick Settings dibuka sekali (harapan: ~60 run)
3. Pengaman aktif → tombol Force stop ditekan (harapan: ~60 run), lalu 3b `am force-stop` tetap menghentikan
4. Di-swipe dari Recents lalu layar mati (mengisi sel Android 16 yang kosong di README)

Kolom `alarm=` di `*.result.md` yang sudah ada tidak akurat: di Android 16 `dumpsys alarm` juga mencetak riwayat alarm. Skrip sudah diperbaiki untuk run berikutnya.

## Menjalankan ulang

Satu emulator dalam satu waktu supaya memori cukup. App harus sudah terpasang (build debug), izin diberikan, baterai *Unrestricted*, dan tombol **Start** sudah ditekan.

```bash
cd example && flutter build apk --debug && adb install -r build/app/outputs/flutter-apk/app-debug.apk
bash doc/test-results/force_stop.sh emulator-5554 api36 doc/test-results/force-stop-api36 60
```

Total sekitar 4 jam 10 menit per emulator. Argumen terakhir adalah menit per kondisi (pakai `5` untuk uji cepat).
