# Android 9 (API 28): pengujian dihentikan atas permintaan user (uji cukup sampai Android 11)

Di `api28.log`, kondisi 1 dan 2 tertulis ❌ 0 run. Penyebabnya alat uji gagal membaca database app di Android 9, bukan plugin.
`api28.logcat` menunjukkan job sebenarnya jalan normal setiap menit:
`schedule id=spike … mode=exact` → `fire id=spike trigger=alarm delayMs=8` → `engine ready in 216ms` → `done id=spike result=ok`,
termasuk job 20 detik (`done id=slow result=ok durMs=20021`). Kondisi lain (swipe, kill, layar mati, Doze, reboot, force stop) tidak dites di Android 9.
