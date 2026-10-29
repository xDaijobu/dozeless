### Android 15 (API 35)

| Kondisi | Jalan? | Run | Catatan |
|---|---|---|---|
| 1. App terbuka (foreground) | ✅ | 2/2 | alarm(0s) alarm(0s) |
| 2. App di background (Home) | ✅ | 1/1 | alarm(0s,layar-mati) |
| 3. Di-swipe dari Recents | ✅ | 2/2 | proses mati setelah swipe; alarm(0s,idle) alarm(0s,idle) |
| 4. Proses dibunuh | ❌ | 0/2 | pid ? -> mati (kill -9);  |
| 5. Layar mati | ✅ | 1/1 | alarm(4s) |
| 6. Doze (deep IDLE) | ❌ | 0/2 | idle=true di 0 run;  |
