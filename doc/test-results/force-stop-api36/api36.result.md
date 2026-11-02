### Android 16 (API 36), 60 menit per kondisi

| Kondisi | Harapan | Run spike | Catatan |
|---|---|---|---|
| 0. Force stop → app dibangunkan sistem (aktivasi device admin), tanpa dibuka | API 35+: alarm kembali | - | sebelum: proses= stopped=true; sesudah 15 s: proses=22092 stopped=false; BOOT_COMPLETED tanpa reboot: 1× |

Kondisi 1–4 **tidak valid, belum ada hasil**. Emulator dimatikan Claude Code (memori host hampir habis) sekitar 00:08:20, sesaat setelah fase 0; log terakhir `api36.logcat` 00:08:20. Skrip waktu itu belum mengecek device, jadi tetap menunggu 4 jam dan menulis `0` dari adb yang tidak tersambung (`stopped=` kosong). Skrip sekarang berhenti kalau device hilang.

Kolom `alarm=` dihapus dari fase 0: hitungannya ikut riwayat alarm di Android 16, jadi tidak akurat.
