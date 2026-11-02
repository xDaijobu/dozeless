### Android 14 (API 34), 60 menit per kondisi

| Kondisi | Harapan | Run spike | Catatan |
|---|---|---|---|
| 0. Force stop → app dibangunkan sistem (aktivasi device admin), tanpa dibuka | API 35+: alarm kembali | - | **Tidak valid**: app tidak sempat stopped (sebelum: proses=5814 stopped=false). Force stop dilakukan tepat setelah `add-tile`, dan sistem me-restart service tile 1 detik kemudian. Skrip sekarang menunggu 60 detik setelah `add-tile`. |

Kondisi 1–4 **tidak valid, belum ada hasil**. Emulator dimatikan Claude Code (memori host hampir habis) sekitar 00:10:51, sesaat setelah fase 0; log terakhir `api34.logcat` 00:10:50. Skrip waktu itu belum mengecek device, jadi tetap menunggu 4 jam dan menulis `0` dari adb yang tidak tersambung (`stopped=` kosong). Skrip sekarang berhenti kalau device hilang.
