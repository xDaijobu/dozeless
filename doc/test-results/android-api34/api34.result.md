### Android 14 (API 34)

| Kondisi | Jalan? | Run | Catatan |
|---|---|---|---|
| 1. App terbuka (foreground) | ✅ | 2/2 | alarm(0s) alarm(0s) |
| 2. App di background (Home) | ✅ | 1/1 | alarm(0s) |
| 3. Di-swipe dari Recents | ✅ | 2/2 | proses mati setelah swipe; alarm(0s) alarm(19s) |
| 4. Proses dibunuh (kill -9) | ✅ | 2/2 | pid 4467 -> mati; alarm(0s) alarm(0s) |
| 5. Layar mati | ✅ | 1/1 | alarm(0s,layar-mati) |
| 6. Doze (deep IDLE) | ✅ | 2/2 | idle=true di 2 run; alarm(0s,idle,layar-mati) alarm(0s,idle,layar-mati) |
| 7. HP reboot (app tidak dibuka) | ✅ | 2/2 | run trigger=boot: 1; boot(23s) alarm(0s) |
| 8. Force stop → app dibuka lagi | ✅ | 1/1 | selama force stop: berhenti (aturan Android untuk force stop); setelah dibuka: pulih, event processExit di 1 run; alarm(4s) |

Job 20 detik (slow): 3 run, terpendek 20 s · mode alarm: exact=16  · lokasi: FAILED=2 LAST_KNOWN=8 OK=3  · total run spike: 13
