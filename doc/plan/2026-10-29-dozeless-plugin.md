# dozeless (Plugin AlarmManager + Example App Uji Kelayakan) — Implementation Plan

> **Status 29 Okt 2026: plan ini sudah dijalankan, dan hasilnya adalah repo `dozeless` ini.** Plan disimpan sebagai riwayat cara plugin dibangun (urutan TDD per task) dan sebagai panduan verifikasi di HP asli (Task 8 dan cek manual Task 9–13). Nama sementara `bg_jobs` / `com.example.bg_jobs` sudah diganti menjadi `dozeless` / `io.github.xdaijobu.dozeless` di seluruh plan. Spec di `doc/spec/` sengaja dibiarkan apa adanya, jadi di sana namanya masih `bg_jobs`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Membangun plugin Flutter `dozeless` (Kotlin + API Dart) yang menjalankan callback Dart secara andal di background hanya dengan AlarmManager, lengkap dengan `example/` app untuk enam uji kelayakan di HP HyperOS.

**Architecture:** Plugin hanya menjadi *job runner*. Setiap job punya rantai alarm `setExactAndAllowWhileIdle` sekali jalan. Alarm berikutnya dipasang ulang sebelum job dijalankan. Saat alarm berbunyi, `JobReceiver` memanggil `goAsync()`, menyalakan FlutterEngine headless yang disimpan di cache, lalu memanggil callback Dart lewat dispatcher. Callback ditunggu sampai selesai, dengan batas waktu dan wake lock sendiri. Logika Get/Send **tidak** termasuk di plan ini. Bagian itu masuk package `tracking_jobs` dengan plan terpisah setelah uji kelayakan lulus (GO).

**Tech Stack:** Flutter 3.47.6 / Dart 3.13.5. Template plugin bawaan: Kotlin 2.4, AGP 9.1, Gradle 9.3, compileSdk 36, minSdk 24. Example app: geolocator ^14.1.2, sqflite ^2.4.5, permission_handler ^13.0.2 (butuh compileSdk 37), path ^1.9.1. Test: flutter_test, integration_test, kotlin-test (JUnit 5), org.json 20240303.

**Spec:** `doc/spec/flutter-background-tracking-spec.html`. Referensi pendukung (khusus Sa.To, tidak ikut dipublikasikan): `doc/internal/sato-background-tracking.html` dan `doc/internal/sato-tracking-v2-design.html`.

**Kode:** hasil akhir plan ini (kondisi setelah Task 13) adalah isi repo ini. Hasil uji per versi Android ada di `doc/test-results/`. Pada 29 Okt 2026 seluruhnya sudah di-compile dan dites: 59 unit test Kotlin, 25 test Dart plugin, 7 test Dart example, `flutter build apk --debug` sukses, dan 5 integration test lolos di **emulator** Pixel 9 (Android 16, API 36). Uji di HP HyperOS asli **belum** dilakukan. Ikuti plan per task, karena urutan TDD ada di plan. Referensi dipakai kalau ragu atau untuk membandingkan.

## Hasil uji di emulator (29 Okt 2026)

Kode referensi dijalankan di emulator Pixel 9 (Android 16 / API 36, RAM 4 GB, baterai example di-whitelist):

| Cek | Hasil | Bukti dari logcat |
|---|---|---|
| Integration test (Task 5 + watchdog Task 11) | ✅ 5/5 | `All tests passed!` |
| Spike job lokasi + sqflite setiap 1 menit | ✅ | alarm telat 0–18 **ms**, `loc=OK` |
| Uji 2: proses dibunuh (`run-as … kill -9`) | ✅ | `engine ready in 371ms`, job selesai, ada event `processExit` |
| Uji 3: Doze (`deviceidle force-idle`) | ✅ | 3 run tepat setiap menit, `idle=true` |
| Uji 4: reboot tanpa membuka app | ✅ | `event boot {bootCount=9, shutdownSource=lastJob, viaBroadcast=true}`, `trigger=boot`, lalu rantai alarm berlanjut |
| Uji 5: `adb install -r` tanpa membuka app | ✅ | `package replaced`, `trigger=packageReplaced` |
| Uji 6: job `slow` 20 detik saat Doze, layar mati | ✅ | `durMs=20014`, `result=ok` |
| Force stop lalu app dibuka | ✅ | `processExit {reason=USER_REQUESTED, [FORCE STOP]}`, `reconcile armed` (lihat temuan #3 untuk Android 14) |
| Baterai dikeluarkan dari whitelist | ✅ | `stop … missing=[BATTERY_UNRESTRICTED]`, `trigger=prerequisiteLost`, notifikasi "Spike berhenti" muncul |
| Whitelist dipulihkan lalu app di-resume | ✅ | `reconcile resumed`, `trigger=resumed`, notifikasi hilang |

### Matriks kondisi per versi Android (emulator, 29 Okt 2026)

Skrip `doc/test-results/matrix.sh` menjalankan 8 kondisi pada satu emulator. Hasil dibaca dari database yang ditulis job, bukan dari logcat.

| Kondisi | 11 | 12 | 13 | 14 | 15 | 16 |
|---|---|---|---|---|---|---|
| 1. App terbuka | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 2. App di background | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 3. Swipe dari Recents (proses ikut mati) | ✅ | ✅ | ✅ | ✅ | ✅ | – |
| 4. Proses dibunuh | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 5. Layar mati | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 6. Doze | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 7. Reboot, app tidak dibuka | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 8. Force stop → app dibuka | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

Kondisi 8: selama force stop job memang berhenti (aturan Android untuk semua app), lalu pulih saat app dibuka. Kolom 16 berasal dari uji manual sebelumnya. Android 7–10 tidak dites, karena uji dibatasi sampai Android 11. Android 9 sempat dites sebagian, dan job-nya jalan setiap menit. Android 15 diuji dengan build yang kodenya sudah dirapikan. Bukti lengkap ada di `doc/test-results/`.

**Temuan yang sudah diperbaiki di plan ini:**
1. *Race saat resume.* Android bisa mengirim dua event resume beruntun, sehingga reconcile kedua memasang alarm tambahan untuk job yang baru dilanjutkan (bisa membuat job jalan dobel). Perbaikannya ada di cabang `RESUME` di `Reconciler`: alarm langsung dipasang (Task 10 dan 13). Sudah dicek ulang di emulator.
2. *Integration test rapuh.* Kalau proses test dibunuh, `tearDown` tidak jalan dan job sisa ikut terbawa ke run berikutnya. Selain itu `flutter test` meng-uninstall app di akhir run, sehingga whitelist baterai ikut hilang. Perbaikannya ada tiga: `setUp` membatalkan job sisa, `nextRun(id, trigger)` hanya menunggu pesan yang memang diharapkan, dan `setUp` gagal dengan pesan jelas kalau baterai belum "Tidak dibatasi". Perintah test juga memakai `--no-uninstall` (Task 5).
3. **Force stop di Android 14 membuat job mati permanen** (ditemukan lewat uji matriks multi-versi). Force stop menghapus semua alarm, tapi di Android 14 *PendingIntent* app tidak ikut terhapus. `isArmed()` (cek lewat `FLAG_NO_CREATE`) jadi mengira alarm masih ada, sehingga reconcile tidak memasang ulang apa pun, dan job serta watchdog mati sampai HP reboot walaupun app sudah dibuka. Perbaikannya: reconcile **selalu** memasang ulang alarm semua job aktif (`ReconcilePolicy.decide` tidak lagi memakai `armed`) dan watchdog (`ensureArmed(force = true)`). Langkah ini aman diulang, karena alarm lama diganti dan jadwalnya memakai `nextRunAt` yang sudah ada (Task 7, 10, 11, 13). Sudah dicek ulang: Android 14 lolos.

**Temuan yang perlu diputuskan (penting untuk `tracking_jobs`):**
4. **Lokasi di background bisa basi.** Saat app di background, `Geolocator.getCurrentPosition` mengembalikan posisi cache dengan status OK. Umurnya terus naik (116 s → 176 s → 236 s setelah lokasi emulator dipindah), dan posisi baru baru muncul setelah app dibuka. Ini *background location limits* Android 8+: app di background hanya mendapat fix baru beberapa kali per jam. Pengecualian resminya hanya foreground service atau app yang sedang terlihat. Sa.To sendiri memakai `FusedLocationProviderClient.RequestLocationUpdates` dan memiliki izin `FOREGROUND_SERVICE`. Karena itu spike sekarang mencatat `fixAgeMs` (umur fix) dan statistik `segar` (umur < 2× interval). Uji 1 di HyperOS **wajib** melaporkan angka `segar`. Kalau angkanya rendah, perlu keputusan sebelum `tracking_jobs`: menerima lokasi basi (ditandai `STALE`), atau memakai foreground service singkat selama Get (bertentangan dengan keputusan "tanpa foreground service" di spec §1).
5. *Run job dalam satu proses berjalan bergiliran.* Broadcast `goAsync()` dikirim satu per satu per proses. Saat `spike` dan `slow` jatuh tempo bersamaan, `slow` baru mulai setelah `spike` selesai (telat sekitar 1,7–12 detik). Untuk Get/Send ini tidak masalah, tapi timeout Get sebaiknya tetap pendek supaya Send tidak tertahan.

---

## Cara pakai di project lain

1. Repo ini sudah berisi hasil akhirnya. Plan hanya perlu diikuti dari nol kalau ingin membangun ulang di folder kosong.2. Repo plugin dibuat di Task 1 (`flutter create ... dozeless`). Semua path di plan ini **relatif terhadap root repo `dozeless/`**.
3. Lingkungan Windows (dicek di mesin ini):
   - `java` di PATH adalah JDK lama dan **gagal** menjalankan Gradle. Sebelum menjalankan perintah Gradle, set `JAVA_HOME` ke JDK 17 atau lebih baru. JDK yang dipakai Flutter di mesin ini: `C:\Users\UseR\.jdks\openjdk-23.0.1`.
     - Git Bash: `export JAVA_HOME=/c/Users/UseR/.jdks/openjdk-23.0.1; export PATH="$JAVA_HOME/bin:$PATH"`
     - PowerShell: `$env:JAVA_HOME='C:\Users\UseR\.jdks\openjdk-23.0.1'; $env:Path="$env:JAVA_HOME\bin;$env:Path"`
   - `adb` ada di `D:\platform-tools\adb`.
4. Unit test Kotlin dijalankan dari `example/android`: `./gradlew :dozeless:testDebugUnitTest` (bisa ditambah `--tests "io.github.xdaijobu.dozeless.NamaTest"`). Perintah ini bisa langsung jalan tanpa build APK dulu. Cukup `flutter pub get` di `example/` (sudah dilakukan oleh `flutter create`).
5. Mulai Task 10, setiap job butuh baterai "Tidak dibatasi". Kalau tidak, job langsung `stopped`. Sebelum menjalankan integration test, pastikan `adb shell dumpsys deviceidle whitelist` memuat `io.github.xdaijobu.dozeless_example`. Kalau belum, jalankan `adb shell dumpsys deviceidle whitelist +io.github.xdaijobu.dozeless_example` lagi, karena install ulang bisa menghapusnya.
6. **Emulator:** pakai RAM minimal 4 GB. Dengan RAM 2 GB, `lowmemorykiller` membunuh app debug, karena mode debug menjalankan dua engine Flutter dengan JIT. Jalankan tanpa mengubah AVD: `"%LOCALAPPDATA%\Android\sdk\emulator\emulator.exe" -avd Pixel_9 -memory 4096 -no-snapshot`. Lokasi emulator diatur dengan `adb emu geo fix <lon> <lat>`.
7. **Git Bash + adb:** path perangkat seperti `/sdcard/...` diubah otomatis oleh Git Bash. Awali perintahnya dengan `MSYS_NO_PATHCONV=1`, tetapi path file Windows (APK) tetap ditulis `C:/...`. Database app bisa dibaca dengan `adb exec-out run-as <pkg> cat databases/spike.db > spike.db` lalu `D:\platform-tools\sqlite3.exe spike.db`.

## Keputusan terbuka (spec §12) dan cara plan ini menanganinya

| Q | Status di plan ini |
|---|---|
| Q1 nama plugin/package | **Sudah diputuskan (29 Okt 2026):** `dozeless`, Kotlin package `io.github.xdaijobu.dozeless`. Nama ini belum dipakai di pub.dev maupun di repo Dart/Flutter di GitHub. |
| Q2 Google Play atau internal | Tidak memengaruhi plugin. `openSettings(batteryOptimization)` membuka **halaman daftar** optimasi baterai, bukan dialog `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, karena dialog itu butuh izin yang dibatasi Play. `QUERY_ALL_PACKAGES` tidak dipakai. |
| Q3 interval default & ukuran batch | Tidak memengaruhi plugin. Plugin menerima interval apa pun ≥ 1 menit. Ini urusan `tracking_jobs`. |
| Q4 teks notifikasi berhenti | Teks bisa dikonfigurasi lewat `Dozeless.initialize(stopNotification: StopNotification(...))`. Default di plugin masih generik. Notifikasi muncul **sekali per kejadian berhenti**. Pengulangan harian belum dibuat sampai Q4 dijawab. |

## Global Constraints

- Platform: **Android saja**, Flutter. (spec §1)
- Penjadwal: **AlarmManager saja. Tanpa WorkManager, tanpa foreground service, tanpa notifikasi permanen.** (spec §1)
- Rantai job: alarm exact sekali jalan per job id dengan `setExactAndAllowWhileIdle(RTC_WAKEUP)`. Alarm berikutnya dipasang **lebih dulu**. Kalau `canScheduleExactAlarms()` false, pakai `setAndAllowWhileIdle` dan mode menjadi `inexact`. (spec §3)
- Watchdog: `setInexactRepeating` per jam. Job dianggap terlambat kalau `nextRun` lewat **lebih dari 2× interval**. (spec §3)
- Logika job ditulis di Dart, berjalan di FlutterEngine headless. Callback **ditunggu sampai selesai** dengan timeout, sambil memegang partial wake lock milik plugin. Background isolate memanggil `DartPluginRegistrant.ensureInitialized()`. (spec §3)
- Baterai "Tidak dibatasi" (`isIgnoringBatteryOptimizations`) dan tidak "Dibatasi" (`!isBackgroundRestricted`) wajib untuk semua job di **semua versi Android**, tanpa pengecualian versi (keputusan user 29 Okt 2026). Di Android 14+, baterai "Tidak dibatasi" juga yang membuat exact alarm jalan, jadi izin `SCHEDULE_EXACT_ALARM` cukup dideklarasikan di manifest dan **tidak pernah diminta** ke user (sama dengan Sa.To). (spec §4)
- Manifest plugin: `RECEIVE_BOOT_COMPLETED`, `SCHEDULE_EXACT_ALARM`, `WAKE_LOCK`, ditambah `ACCESS_WIFI_STATE` untuk `wifiLevel`. Manifest app: izin lokasi, `INTERNET`, `ACCESS_NETWORK_STATE`, `POST_NOTIFICATIONS`. `android:installLocation` tidak boleh `preferExternal`. (spec §4)
- Tidak membaca IMEI, serial number, atau SIM serial. Tidak memakai `QUERY_ALL_PACKAGES`. (spec §7)
- Receiver hanya menjadwalkan dan mencatat. **Tidak boleh membuka UI.** (spec §10)
- Event sistem didaftarkan di manifest, atau lewat ContentProvider untuk receiver runtime. Tidak didaftarkan di Activity. (spec §10)
- Timeout job maksimal **50 detik** dan interval minimal **1 menit**. Ini turunan, bukan dari spec: broadcast alarm dimatikan sistem setelah 60 detik, dan sisa waktunya dipakai untuk start engine.
- Tag log native: `Dozeless`. Log Dart di background isolate muncul dengan tag `flutter`.

## Penafsiran spec yang perlu diketahui reviewer

1. **Urutan langkah 2 dan 3 (spec §3).** Prasyarat dicek dulu sebelum alarm berikutnya dipasang. Kalau ada prasyarat yang kurang, alarm dibatalkan, mode jadi `stopped`, notifikasi ditampilkan, lalu job dijalankan sekali dengan `prerequisiteLost`. Hasil akhirnya sama dengan spec, tetapi job yang berhenti tidak pernah punya alarm aktif.
2. **Run langsung pakai broadcast eksplisit.** Run untuk `boot`, `packageReplaced`, `manual`, `resumed`, dan `prerequisiteLost` (dari app) dikirim dengan broadcast eksplisit ke `JobReceiver`, bukan lewat alarm. Saat itu HP pasti sedang menyala. `watchdog` dan `timeChanged` tetap lewat alarm 1 detik lagi supaya HP dibangunkan.
3. **Antrean `systemEvents` per job.** Setiap job punya kursor `ackedEventSeq` sendiri. Event dihapus setelah semua job mengakuinya. Ini menggantikan "hapus setelah job sukses" di spec, yang akan membuat event hilang dari job lain.
4. **Re-arm saat jam digeser ≥ 60 detik.** Alarm RTC mengikuti jam dinding. Kalau jam dimundurkan 1 jam, alarm berikutnya akan telat 1 jam, jadi semua job dipasang ulang ke 1 detik lagi dengan `trigger=timeChanged`.
5. **Identitas boot.** Dicek dengan `Settings.Global.BOOT_COUNT`, dengan cadangan `bootTime` ± 60 detik. Boot dicatat dari `BOOT_COMPLETED`, atau saat app dibuka kalau broadcast boot tidak pernah datang (misalnya Autostart mati).

6. **Baterai wajib di semua versi, dan izin exact alarm tidak diminta.** Cara memintanya sama dengan Sa.To: buka daftar optimasi baterai (`ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`), dengan cadangan App info → Baterai → Tidak dibatasi, lalu cek ulang setiap app di-resume. Sa.To meng-hardcode "terpenuhi" di bawah Android 6, tapi plugin tidak perlu, karena `minSdk` 24 dan user memutuskan baterai wajib di semua versi.

## Review Focus

1. **App dibuka berkali-kali.** `schedule()` dipanggil setiap app start dan tidak boleh mendorong jadwal berikutnya mundur. Yang diharapkan: alarm yang masih aktif dibiarkan. → Task 2 `sameSpecWhileArmedKeepsTheCurrentAlarm`, `newCallbackHandleAloneKeepsTheCurrentAlarm`.
2. **Callback Dart tidak pernah selesai** (misalnya `await` future yang menggantung). Yang diharapkan: run itu tercatat `JOB_TIMEOUT`, run berikutnya `skippedBusy`, lalu setelah 3× timeout kunci dianggap basi dan job jalan lagi. Job tidak boleh macet selamanya. → Task 2 `hungRunIsOverriddenOnceStale`, `lateReleaseOfAStaleRunDoesNotFreeItsSuccessor`; Task 5 integration `JOB_TIMEOUT`.
3. **Jam HP dimundurkan 1 jam.** Yang diharapkan: event `timeChanged` dengan `jumpMs = -3600000`, dan job tetap jalan sekitar 1 detik kemudian, tidak menunggu 1 jam. → Task 12 `clockSetBackOneHourIsANegativeJump` plus cek manual.
4. **Boot ditangani tepat sekali.** Kasusnya: HP mengirim `BOOT_COMPLETED` dan `QUICKBOOT_POWERON` dua-duanya, tidak mengirim sama sekali (Autostart mati), atau jam diubah setelah boot. Yang diharapkan: satu event `boot` dan satu run `boot` per boot. → Task 7 `bootCompletedAndQuickbootOnTheSameBootAreHandledOnce`, `changingTheClockIsNotANewBootWhenBootCountIsKnown`, `firstStartEverIsNotABoot`.
5. **Event sistem tidak hilang dan tidak dobel.** Kalau job gagal, event yang sama dikirim lagi di run berikutnya. Job yang baru dibuat tidak menerima event lama. → Task 12 `aFailedRunAcknowledgesNothingSoEventsComeAgain`, `aNewJobStartingAtLastSeqSeesNoOlderEvents`.

## Struktur file (kondisi akhir)

```
dozeless/
  docs/spec/*.html                         spesifikasi (salinan)
  docs/feasibility-results.md              hasil uji kelayakan (Task 8)
  docs/phase2-verification.md              hasil cek manual fase 2 (Task 14)
  lib/dozeless.dart                         export publik
  lib/src/wire.dart                        helper parsing map dari channel
  lib/src/models.dart                      enum, JobStatus, PrerequisiteStatus, DeviceState, BootInfo, SystemEvent, StopNotification
  lib/src/job_context.dart                 JobContext + typedef JobCallback
  lib/src/dozeless_api.dart                 class Dozeless (API Dart)
  lib/src/dispatcher.dart                  entry point engine background
  test/models_test.dart · dozeless_api_test.dart · dispatcher_test.dart
  android/build.gradle.kts                 + testImplementation org.json
  android/src/main/AndroidManifest.xml     permission, receiver, provider
  android/src/main/kotlin/io/github/xdaijobu/dozeless/
    Model.kt            Triggers, Mode, Prereq, JobSpec, JobState, Job        (murni)
    JobCodec.kt         JSON job + status map                                  (murni)
    SchedulePolicy.kt   kapan alarm dipasang: schedule / watchdog              (murni)
    RunLocks.kt         satu run per job                                       (murni)
    TimeJump.kt         deteksi jam diubah                                     (murni)
    EventLog.kt         SystemEvent, EventLogPolicy, EventCodec (murni) + EventStore
    BootInfo.kt         BootInfo, BootDedupe, ShutdownGuess (murni) + read()
    Prereqs.kt          PrereqSnapshot (murni) + PrereqReader
    DeviceState.kt      StandbyBuckets (murni) + DeviceState.read
    SettingsOpener.kt   AutostartIntents, SettingsTargets (murni) + SettingsOpener
    JobStore.kt         SharedPreferences
    AlarmScheduler.kt   alarm exact/inexact per job
    JobReceiver.kt      receiver alarm + dispatch()
    JobRunner.kt        alur spec §3
    DartRunner.kt       engine headless + dispatcher
    ContextBuilder.kt   map JobContext
    Jobs.kt             operasi job dari API
    Reconciler.kt       ReconcilePolicy (murni), Reconciler, BootHandler
    SystemEventReceiver.kt  boot, update app, jam, zona waktu
    WatchdogReceiver.kt     watchdog per jam
    Housekeeping.kt     upkeep tiap run
    Notifier.kt         StopText + notifikasi berhenti
    ProcessStartHook.kt ContentProvider + receiver ACTION_SHUTDOWN
    ExitInfoReader.kt   ExitReasons (murni) + pembaca exit info
    DozelessPlugin.kt     MethodChannel "dozeless"
  android/src/test/kotlin/io/github/xdaijobu/dozeless/
    JobCodecTest · SchedulePolicyTest · RunLocksTest · SnapshotTest · RecoveryTest · SettingsTargetsTest · EventsTest
  example/
    lib/main.dart · spike_jobs.dart · spike_db.dart · spike_row.dart · spike_stats.dart
    test/spike_stats_test.dart
    integration_test/dozeless_test.dart
```

Bagian yang murni (tanpa Android API) diuji dengan unit test JVM. Bagian yang menyentuh Android API diverifikasi lewat integration test di HP dan pengecekan adb, di task yang sama.

---

# FASE 1: Uji kelayakan (Task 1–8)

Akhir fase ini adalah gerbang **GO / NO-GO** (Task 8). Fase 2 jangan dikerjakan sebelum hasilnya GO.

### Task 1: Scaffold repo plugin + model Dart

**Files:**
- Create: repo `dozeless/` (lewat `flutter create`)
- Create: `docs/spec/` (salinan spec)
- Delete: `lib/dozeless_method_channel.dart`, `lib/dozeless_platform_interface.dart`, `test/dozeless_method_channel_test.dart`, `test/dozeless_test.dart`, `android/src/test/kotlin/io/github/xdaijobu/dozeless/DozelessPluginTest.kt`, `example/integration_test/plugin_integration_test.dart`, `example/test/widget_test.dart`
- Modify: `pubspec.yaml` (hapus `plugin_platform_interface`)
- Modify: `example/lib/main.dart` (app kosong sementara, diganti di Task 6)
- Create: `lib/src/wire.dart`, `lib/src/models.dart`, `lib/src/job_context.dart`
- Modify: `lib/dozeless.dart`
- Test: `test/models_test.dart`

**Interfaces:**
- Produces (Dart, dipakai semua task berikutnya): `enum JobTrigger {alarm, boot, watchdog, packageReplaced, timeChanged, prerequisiteLost, resumed, manual}`, `enum Prereq {location, backgroundLocation, batteryUnrestricted, notBackgroundRestricted}`, `enum JobMode {exact, inexact, stopped}`, `enum Setting {batteryOptimization, appDetails, exactAlarm, autostart}`, `JobStatus.fromMap`, `PrerequisiteStatus.fromMap` + `has(Prereq)` + `missingFor(Set<Prereq>)` + `static always`, `DeviceState.fromMap`, `BootInfo.fromMap`, `SystemEvent.fromMap`, `typedef JobCallback = Future<void> Function(JobContext ctx)`, `JobContext.fromMap` + `deadline`. Helper internal di `wire.dart`: `enumByName`, `timeOrNull`, `intOrNull`, `asMap`.
- Format wire (Kotlin → Dart): waktu dalam epoch millis (int), enum dikirim sebagai nama Dart (`'packageReplaced'`).

- [ ] **Step 1: Buat repo dari template**

```bash
flutter create --template=plugin --platforms=android --org io.github.xdaijobu -a kotlin dozeless
cd dozeless
git init
mkdir -p docs/spec
cp <path-repo-dozeless>/doc/spec/*.html docs/spec/
```

- [ ] **Step 2: Buang kode contoh dari template**

```bash
rm lib/dozeless_method_channel.dart lib/dozeless_platform_interface.dart \
   test/dozeless_method_channel_test.dart test/dozeless_test.dart \
   android/src/test/kotlin/io/github/xdaijobu/dozeless/DozelessPluginTest.kt \
   example/integration_test/plugin_integration_test.dart example/test/widget_test.dart
```

Hapus baris `plugin_platform_interface: ^2.0.2` dari `dependencies:` di `pubspec.yaml`.

Ganti seluruh isi `example/lib/main.dart` dengan app kosong. File ini diganti lagi di Task 6:

```dart
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('dozeless example')))));
```

Jangan ubah `android/src/main/kotlin/io/github/xdaijobu/dozeless/DozelessPlugin.kt` dulu. File itu ditulis ulang di Task 3.

- [ ] **Step 3: Tulis test yang gagal**

`test/models_test.dart`:

```dart
import 'package:dozeless/dozeless.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> sampleContext() => {
      'jobId': 'get',
      'trigger': 'boot',
      'scheduledAt': 1700000000000,
      'firedAt': 1700000004500,
      'delayMs': 4500,
      'timeoutMs': 45000,
      'mode': 'inexact',
      'lastRunAt': 1699999940000,
      'lastError': 'JOB_TIMEOUT',
      'stoppedAt': null,
      'boot': {'bootCount': 12, 'bootTime': 1699990000000, 'firstJobSinceBoot': true},
      'systemEvents': [
        {
          'seq': 7,
          'type': 'timeChanged',
          'at': 1699999990000,
          'data': {'jumpMs': -3600000, 'autoTime': false},
        },
      ],
      'prerequisites': {
        'location': true,
        'backgroundLocation': false,
        'batteryUnrestricted': true,
        'backgroundRestricted': false,
        'exactAlarm': true,
        'notification': false,
        'autostartSettingAvailable': true,
      },
      'device': {
        'deviceId': 'abc123',
        'deviceIdle': true,
        'interactive': false,
        'powerSaveMode': false,
        'standbyBucket': 'active',
        'autoTime': false,
        'timezone': 'Asia/Jakarta',
        'cellLevel': 3,
        'wifiLevel': null,
      },
    };

void main() {
  group('JobContext.fromMap', () {
    test('parses every field the plugin sends', () {
      final ctx = JobContext.fromMap(sampleContext());
      expect(ctx.jobId, 'get');
      expect(ctx.trigger, JobTrigger.boot);
      expect(ctx.delayMs, 4500);
      expect(ctx.firedAt.millisecondsSinceEpoch, 1700000004500);
      expect(ctx.deadline.millisecondsSinceEpoch, 1700000004500 + 45000);
      expect(ctx.mode, JobMode.inexact);
      expect(ctx.lastError, 'JOB_TIMEOUT');
      expect(ctx.stoppedAt, isNull);
      expect(ctx.boot.bootCount, 12);
      expect(ctx.boot.firstJobSinceBoot, isTrue);
      expect(ctx.systemEvents.single.type, 'timeChanged');
      expect(ctx.systemEvents.single.data['jumpMs'], -3600000);
      expect(ctx.prerequisites.backgroundLocation, isFalse);
      expect(ctx.prerequisites.autostartSettingAvailable, isTrue);
      expect(ctx.device.deviceIdle, isTrue);
      expect(ctx.device.timezone, 'Asia/Jakarta');
      expect(ctx.device.cellLevel, 3);
      expect(ctx.device.wifiLevel, isNull);
    });

    test('an unknown trigger falls back to alarm instead of throwing', () {
      expect(JobContext.fromMap({...sampleContext(), 'trigger': 'somethingNew'}).trigger, JobTrigger.alarm);
    });

    test('missing sections give safe defaults', () {
      final ctx = JobContext.fromMap({'jobId': 'x', 'trigger': 'manual', 'scheduledAt': 1, 'firedAt': 2});
      expect(ctx.systemEvents, isEmpty);
      expect(ctx.prerequisites.batteryUnrestricted, isFalse);
      expect(ctx.boot.bootCount, isNull);
      expect(ctx.timeout, const Duration(seconds: 45));
    });
  });

  group('PrerequisiteStatus.missingFor', () {
    const allOk = PrerequisiteStatus(
      location: true,
      backgroundLocation: true,
      batteryUnrestricted: true,
      backgroundRestricted: false,
      exactAlarm: true,
      notification: true,
    );

    test('nothing is missing when everything is granted', () {
      expect(allOk.missingFor({Prereq.location, Prereq.backgroundLocation}), isEmpty);
    });

    test('battery and background restriction count even when not requested', () {
      const s = PrerequisiteStatus(
        location: true,
        backgroundLocation: true,
        batteryUnrestricted: false,
        backgroundRestricted: true,
        exactAlarm: true,
        notification: true,
      );
      expect(s.missingFor({}), [Prereq.batteryUnrestricted, Prereq.notBackgroundRestricted]);
    });

    test('exact alarm and notification never block', () {
      const s = PrerequisiteStatus(
        location: true,
        backgroundLocation: true,
        batteryUnrestricted: true,
        backgroundRestricted: false,
        exactAlarm: false,
        notification: false,
      );
      expect(s.missingFor(Prereq.values.toSet()), isEmpty);
    });
  });

  test('JobStatus.fromMap parses status and drops unknown prerequisite names', () {
    final s = JobStatus.fromMap({
      'id': 'get',
      'mode': 'stopped',
      'nextRunAt': null,
      'lastRunAt': 1700000000000,
      'lastError': null,
      'lastTrigger': 'watchdog',
      'runCount': 5,
      'skippedBusyCount': 1,
      'missing': ['backgroundLocation', 'bogus'],
      'stoppedAt': 1700000001000,
    });
    expect(s.mode, JobMode.stopped);
    expect(s.lastTrigger, JobTrigger.watchdog);
    expect(s.missing, [Prereq.backgroundLocation]);
    expect(s.nextRunAt, isNull);
    expect(s.runCount, 5);
    expect(s.stoppedAt!.millisecondsSinceEpoch, 1700000001000);
  });
}
```

- [ ] **Step 4: Jalankan test dan pastikan gagal**

Run: `flutter test test/models_test.dart`
Expected: FAIL, compile error karena `JobContext`, `JobTrigger`, dan lainnya belum ada.

- [ ] **Step 5: Implementasi model**

`lib/src/wire.dart`:

```dart
// Helpers for reading maps that arrive over the platform channel.

T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.asNameMap()[name] ?? fallback;

DateTime? timeOrNull(Object? epochMs) =>
    epochMs == null ? null : DateTime.fromMillisecondsSinceEpoch((epochMs as num).toInt());

int? intOrNull(Object? value) => (value as num?)?.toInt();

Map<Object?, Object?> asMap(Object? value) =>
    (value as Map?)?.cast<Object?, Object?>() ?? const <Object?, Object?>{};
```

`lib/src/models.dart` (class `StopNotification` baru ditambahkan di Task 10):

```dart
import 'wire.dart';

/// Why a job run started. Wire names equal the enum names.
enum JobTrigger { alarm, boot, watchdog, packageReplaced, timeChanged, prerequisiteLost, resumed, manual }

/// Conditions a job needs. [batteryUnrestricted] and [notBackgroundRestricted]
/// are enforced for every job on every Android version, requested or not (spec §4).
enum Prereq { location, backgroundLocation, batteryUnrestricted, notBackgroundRestricted }

/// How a job's next alarm is armed.
enum JobMode { exact, inexact, stopped }

/// Pages [Dozeless.openSettings] can open.
enum Setting { batteryOptimization, appDetails, exactAlarm, autostart }

List<Prereq> _prereqs(Object? raw) => [
      for (final name in (raw as List?) ?? const [])
        ?Prereq.values.asNameMap()[name],
    ];

class JobStatus {
  const JobStatus({
    required this.id,
    required this.mode,
    this.nextRunAt,
    this.lastRunAt,
    this.lastFinishedAt,
    this.lastDurationMs,
    this.lastError,
    this.lastTrigger,
    this.runCount = 0,
    this.skippedBusyCount = 0,
    this.missing = const [],
    this.stoppedAt,
  });

  factory JobStatus.fromMap(Map<Object?, Object?> m) => JobStatus(
        id: m['id']! as String,
        mode: enumByName(JobMode.values, m['mode'], JobMode.exact),
        nextRunAt: timeOrNull(m['nextRunAt']),
        lastRunAt: timeOrNull(m['lastRunAt']),
        lastFinishedAt: timeOrNull(m['lastFinishedAt']),
        lastDurationMs: intOrNull(m['lastDurationMs']),
        lastError: m['lastError'] as String?,
        lastTrigger: m['lastTrigger'] == null ? null : enumByName(JobTrigger.values, m['lastTrigger'], JobTrigger.alarm),
        runCount: intOrNull(m['runCount']) ?? 0,
        skippedBusyCount: intOrNull(m['skippedBusyCount']) ?? 0,
        missing: _prereqs(m['missing']),
        stoppedAt: timeOrNull(m['stoppedAt']),
      );

  final String id;
  final JobMode mode;
  final DateTime? nextRunAt;
  final DateTime? lastRunAt;
  final DateTime? lastFinishedAt;
  final int? lastDurationMs;
  final String? lastError;
  final JobTrigger? lastTrigger;
  final int runCount;
  final int skippedBusyCount;

  /// Why the job is [JobMode.stopped].
  final List<Prereq> missing;
  final DateTime? stoppedAt;
}

class PrerequisiteStatus {
  const PrerequisiteStatus({
    required this.location,
    required this.backgroundLocation,
    required this.batteryUnrestricted,
    required this.backgroundRestricted,
    required this.exactAlarm,
    required this.notification,
    this.autostartSettingAvailable = false,
  });

  factory PrerequisiteStatus.fromMap(Map<Object?, Object?> m) => PrerequisiteStatus(
        location: m['location'] == true,
        backgroundLocation: m['backgroundLocation'] == true,
        batteryUnrestricted: m['batteryUnrestricted'] == true,
        backgroundRestricted: m['backgroundRestricted'] == true,
        exactAlarm: m['exactAlarm'] == true,
        notification: m['notification'] == true,
        autostartSettingAvailable: m['autostartSettingAvailable'] == true,
      );

  /// Enforced for every job.
  static const always = {Prereq.batteryUnrestricted, Prereq.notBackgroundRestricted};

  final bool location;
  final bool backgroundLocation;
  final bool batteryUnrestricted;

  final bool backgroundRestricted;

  /// Not blocking: without it jobs run in [JobMode.inexact].
  final bool exactAlarm;

  /// Not blocking: without it the user is not told when jobs stop.
  final bool notification;

  /// This brand has an Autostart page; the wizard should ask the user to enable it.
  final bool autostartSettingAvailable;

  bool has(Prereq p) => switch (p) {
        Prereq.location => location,
        Prereq.backgroundLocation => backgroundLocation,
        Prereq.batteryUnrestricted => batteryUnrestricted,
        Prereq.notBackgroundRestricted => !backgroundRestricted,
      };

  /// What stops a job that requires [requires], in [Prereq] order.
  List<Prereq> missingFor(Set<Prereq> requires) {
    final need = {...requires, ...always};
    return [for (final p in Prereq.values) if (need.contains(p) && !has(p)) p];
  }
}

class DeviceState {
  const DeviceState({
    this.deviceId,
    this.deviceIdle = false,
    this.interactive = false,
    this.powerSaveMode = false,
    this.standbyBucket = 'unknown',
    this.autoTime = true,
    this.timezone = '',
    this.cellLevel,
    this.wifiLevel,
  });

  factory DeviceState.fromMap(Map<Object?, Object?> m) => DeviceState(
        deviceId: m['deviceId'] as String?,
        deviceIdle: m['deviceIdle'] == true,
        interactive: m['interactive'] == true,
        powerSaveMode: m['powerSaveMode'] == true,
        standbyBucket: (m['standbyBucket'] as String?) ?? 'unknown',
        autoTime: m['autoTime'] != false,
        timezone: (m['timezone'] as String?) ?? '',
        cellLevel: intOrNull(m['cellLevel']),
        wifiLevel: intOrNull(m['wifiLevel']),
      );

  /// ANDROID_ID.
  final String? deviceId;
  final bool deviceIdle;
  final bool interactive;
  final bool powerSaveMode;

  /// exempted · active · workingSet · frequent · rare · restricted · never · unknown
  final String standbyBucket;
  final bool autoTime;
  final String timezone;

  /// Signal level 0–4, null when unknown.
  final int? cellLevel;
  final int? wifiLevel;
}

class BootInfo {
  const BootInfo({this.bootCount, required this.bootTime, required this.firstJobSinceBoot});

  factory BootInfo.fromMap(Map<Object?, Object?> m) => BootInfo(
        bootCount: intOrNull(m['bootCount']),
        bootTime: timeOrNull(m['bootTime']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        firstJobSinceBoot: m['firstJobSinceBoot'] == true,
      );

  final int? bootCount;
  final DateTime bootTime;
  final bool firstJobSinceBoot;
}

/// Something the plugin saw outside a job run.
///
/// | type              | data                                                                 |
/// |-------------------|----------------------------------------------------------------------|
/// | `boot`            | bootCount, bootTime, shutdownAt, shutdownSource (marker·lastJob·unknown), viaBroadcast |
/// | `timeChanged`     | jumpMs (null if unknown), autoTime                                   |
/// | `timezoneChanged` | from, to                                                             |
/// | `processExit`     | reason (e.g. USER_REQUESTED), reasonCode, importance, description    |
class SystemEvent {
  const SystemEvent({required this.seq, required this.type, required this.at, this.data = const {}});

  factory SystemEvent.fromMap(Map<Object?, Object?> m) => SystemEvent(
        seq: intOrNull(m['seq'])!,
        type: m['type']! as String,
        at: timeOrNull(m['at'])!,
        data: {for (final e in asMap(m['data']).entries) e.key! as String: e.value},
      );

  final int seq;
  final String type;
  final DateTime at;
  final Map<String, Object?> data;
}
```

`lib/src/job_context.dart`:

```dart
import 'models.dart';
import 'wire.dart';

/// A job body. Must be a top-level or static function annotated with
/// `@pragma('vm:entry-point')`; it runs in a background FlutterEngine.
typedef JobCallback = Future<void> Function(JobContext ctx);

/// Everything the plugin knows about one run (spec §3 JobContext table).
class JobContext {
  const JobContext({
    required this.jobId,
    required this.trigger,
    required this.scheduledAt,
    required this.firedAt,
    required this.delayMs,
    required this.timeout,
    required this.mode,
    required this.boot,
    required this.systemEvents,
    required this.prerequisites,
    required this.device,
    this.lastRunAt,
    this.lastError,
    this.stoppedAt,
  });

  factory JobContext.fromMap(Map<Object?, Object?> m) => JobContext(
        jobId: m['jobId']! as String,
        trigger: enumByName(JobTrigger.values, m['trigger'], JobTrigger.alarm),
        scheduledAt: timeOrNull(m['scheduledAt'])!,
        firedAt: timeOrNull(m['firedAt'])!,
        delayMs: intOrNull(m['delayMs']) ?? 0,
        timeout: Duration(milliseconds: intOrNull(m['timeoutMs']) ?? 45000),
        mode: enumByName(JobMode.values, m['mode'], JobMode.exact),
        boot: BootInfo.fromMap(asMap(m['boot'])),
        systemEvents: [
          for (final e in (m['systemEvents'] as List?) ?? const []) SystemEvent.fromMap(asMap(e)),
        ],
        prerequisites: PrerequisiteStatus.fromMap(asMap(m['prerequisites'])),
        device: DeviceState.fromMap(asMap(m['device'])),
        lastRunAt: timeOrNull(m['lastRunAt']),
        lastError: m['lastError'] as String?,
        stoppedAt: timeOrNull(m['stoppedAt']),
      );

  final String jobId;
  final JobTrigger trigger;
  final DateTime scheduledAt;
  final DateTime firedAt;

  /// How late the alarm fired.
  final int delayMs;
  final Duration timeout;
  final JobMode mode;
  final BootInfo boot;

  /// Events since this job's last successful run. Delivered again if this run fails.
  final List<SystemEvent> systemEvents;
  final PrerequisiteStatus prerequisites;
  final DeviceState device;

  /// Start of the previous run, for gap detection.
  final DateTime? lastRunAt;
  final String? lastError;

  /// When the job was stopped; set on [JobTrigger.resumed] runs.
  final DateTime? stoppedAt;

  /// The plugin stops waiting at this moment; keep every step inside it.
  DateTime get deadline => firedAt.add(timeout);
}
```

Ganti seluruh isi `lib/dozeless.dart`:

```dart
export 'src/job_context.dart';
export 'src/models.dart';
```

- [ ] **Step 6: Jalankan test dan analyzer**

Run: `flutter test test/models_test.dart` → Expected: `All tests passed!` (7 test)
Run: `flutter analyze` → Expected: `No issues found!`

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: scaffold dozeless plugin with Dart job models"
```

---

### Task 2: Inti Kotlin murni (model, codec, kebijakan jadwal, kunci run)

**Files:**
- Modify: `android/build.gradle.kts` (tambah dependency test org.json)
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/Model.kt`
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/JobCodec.kt`
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/SchedulePolicy.kt`
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/RunLocks.kt`
- Test: `android/src/test/kotlin/io/github/xdaijobu/dozeless/JobCodecTest.kt`, `SchedulePolicyTest.kt`, `RunLocksTest.kt`

**Interfaces:**
- Produces:
  - `object Triggers { ALARM, BOOT, WATCHDOG, PACKAGE_REPLACED, TIME_CHANGED, PREREQUISITE_LOST, RESUMED, MANUAL }` (String, sama dengan nama Dart)
  - `enum class Mode(val wire: String) { EXACT, INEXACT, STOPPED }` + `Mode.fromWire(String?)`
  - `enum class Prereq(val wire: String)` + `Prereq.fromWire(String): Prereq?` + `Prereq.ALWAYS`
  - `data class JobSpec(id, callbackHandle: Long, everyMs: Long, timeoutMs: Long, requires: Set<Prereq>)` + `effectiveRequires`
  - `data class JobState(mode, nextRunAt, lastRunAt, lastFinishedAt, lastDurationMs, lastError, lastTrigger, runCount, skippedBusyCount, ackedEventSeq, missing, stoppedAt)`
  - `data class Job(spec, state)`
  - `JobCodec.encode(Job): String`, `JobCodec.decode(String): Job`, `JobCodec.statusMap(Job): Map<String, Any?>`
  - `SchedulePolicy.Decision` (`Keep`, `ArmAt(at, trigger = Triggers.ALARM)`), `SchedulePolicy.onSchedule(existing, spec, now, armed)`, `SchedulePolicy.rearmAt(nextRunAt, now)`, `SchedulePolicy.REARM_DELAY_MS = 1000`
  - `RunLocks.tryAcquire(id, now, staleAfterMs): Long?`, `RunLocks.release(id, token)`

- [ ] **Step 1: Tambah org.json untuk unit test JVM**

Di `android/build.gradle.kts`, blok `dependencies` menjadi:

```kotlin
dependencies {
    testImplementation("org.jetbrains.kotlin:kotlin-test")
    testImplementation("org.json:json:20240303")
}
```

(`org.json` di `android.jar` hanya stub. Tanpa dependency ini, `JSONObject` melempar "not mocked" di unit test.)

- [ ] **Step 2: Tulis test yang gagal**

`android/src/test/kotlin/io/github/xdaijobu/dozeless/JobCodecTest.kt`:

```kotlin
package io.github.xdaijobu.dozeless

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

internal class JobCodecTest {
    // Larger than 2^53: proves 64-bit callback handles survive JSON.
    private val spec = JobSpec(
        id = "get",
        callbackHandle = 9_007_199_254_740_993L,
        everyMs = 300_000,
        timeoutMs = 45_000,
        requires = setOf(Prereq.LOCATION, Prereq.BACKGROUND_LOCATION),
    )

    @Test
    fun roundTripsAFullJob() {
        val job = Job(
            spec,
            JobState(
                mode = Mode.STOPPED, nextRunAt = 1L, lastRunAt = 2L, lastFinishedAt = 3L, lastDurationMs = 4L,
                lastError = "JOB_TIMEOUT", lastTrigger = Triggers.WATCHDOG, runCount = 5, skippedBusyCount = 6,
                ackedEventSeq = 7, missing = listOf(Prereq.BACKGROUND_LOCATION), stoppedAt = 8L,
            ),
        )
        assertEquals(job, JobCodec.decode(JobCodec.encode(job)))
    }

    @Test
    fun roundTripsAFreshJobWithNulls() {
        val job = Job(spec, JobState())
        assertEquals(job, JobCodec.decode(JobCodec.encode(job)))
    }

    @Test
    fun ignoresUnknownPrerequisiteNames() {
        val json = JobCodec.encode(Job(spec, JobState())).replace("\"location\"", "\"teleport\"")
        assertEquals(setOf(Prereq.BACKGROUND_LOCATION), JobCodec.decode(json).spec.requires)
    }

    @Test
    fun statusMapUsesWireNames() {
        val map = JobCodec.statusMap(Job(spec, JobState(mode = Mode.INEXACT, missing = listOf(Prereq.BATTERY_UNRESTRICTED))))
        assertEquals("inexact", map["mode"])
        assertEquals(listOf("batteryUnrestricted"), map["missing"])
        assertNull(map["lastError"])
    }
}
```

`android/src/test/kotlin/io/github/xdaijobu/dozeless/SchedulePolicyTest.kt`. Test untuk watchdog ditambahkan di Task 11:

```kotlin
package io.github.xdaijobu.dozeless

import io.github.xdaijobu.dozeless.SchedulePolicy.Decision.ArmAt
import io.github.xdaijobu.dozeless.SchedulePolicy.Decision.Keep
import io.github.xdaijobu.dozeless.SchedulePolicy.REARM_DELAY_MS
import kotlin.test.Test
import kotlin.test.assertEquals

internal class SchedulePolicyTest {
    private val now = 1_700_000_000_000L
    private val spec = JobSpec("get", callbackHandle = 1L, everyMs = 60_000, timeoutMs = 45_000, requires = emptySet())

    private fun job(state: JobState = JobState(nextRunAt = now + 30_000)) = Job(spec, state)

    @Test
    fun newJobArmsOneIntervalFromNow() =
        assertEquals(ArmAt(now + 60_000), SchedulePolicy.onSchedule(null, spec, now, armed = false))

    @Test
    fun sameSpecWhileArmedKeepsTheCurrentAlarm() =
        assertEquals(Keep, SchedulePolicy.onSchedule(job(), spec, now, armed = true))

    @Test
    fun newCallbackHandleAloneKeepsTheCurrentAlarm() =
        assertEquals(Keep, SchedulePolicy.onSchedule(job(), spec.copy(callbackHandle = 2L), now, armed = true))

    @Test
    fun changedIntervalRearmsFromNow() =
        assertEquals(ArmAt(now + 120_000), SchedulePolicy.onSchedule(job(), spec.copy(everyMs = 120_000), now, armed = true))

    @Test
    fun vanishedAlarmIsRearmedAtItsPlannedTime() =
        assertEquals(ArmAt(now + 30_000), SchedulePolicy.onSchedule(job(), spec, now, armed = false))

    @Test
    fun vanishedOverdueAlarmIsRearmedAlmostImmediately() =
        assertEquals(ArmAt(now + REARM_DELAY_MS), SchedulePolicy.onSchedule(job(JobState(nextRunAt = now - 600_000)), spec, now, armed = false))

    @Test
    fun stoppedJobIsLeftAlone() =
        assertEquals(Keep, SchedulePolicy.onSchedule(job(JobState(mode = Mode.STOPPED)), spec, now, armed = false))
}
```

`android/src/test/kotlin/io/github/xdaijobu/dozeless/RunLocksTest.kt`:

```kotlin
package io.github.xdaijobu.dozeless

import kotlin.test.Test
import kotlin.test.assertNotNull
import kotlin.test.assertNull

internal class RunLocksTest {
    private val stale = 135_000L

    @Test
    fun secondRunIsRejectedWhileTheFirstIsBusy() {
        val locks = RunLocks()
        assertNotNull(locks.tryAcquire("get", 0, stale))
        assertNull(locks.tryAcquire("get", 60_000, stale))
    }

    @Test
    fun differentJobsDoNotBlockEachOther() {
        val locks = RunLocks()
        assertNotNull(locks.tryAcquire("get", 0, stale))
        assertNotNull(locks.tryAcquire("send", 0, stale))
    }

    @Test
    fun releasedLockCanBeTakenAgain() {
        val locks = RunLocks()
        val token = locks.tryAcquire("get", 0, stale)!!
        locks.release("get", token)
        assertNotNull(locks.tryAcquire("get", 1, stale))
    }

    @Test
    fun hungRunIsOverriddenOnceStale() {
        val locks = RunLocks()
        locks.tryAcquire("get", 0, stale)
        assertNull(locks.tryAcquire("get", stale - 1, stale))
        assertNotNull(locks.tryAcquire("get", stale, stale))
    }

    @Test
    fun lateReleaseOfAStaleRunDoesNotFreeItsSuccessor() {
        val locks = RunLocks()
        val first = locks.tryAcquire("get", 0, stale)!!
        locks.tryAcquire("get", stale, stale)!!
        locks.release("get", first)
        assertNull(locks.tryAcquire("get", stale + 1, stale))
    }
}
```

- [ ] **Step 3: Jalankan test dan pastikan gagal**

Run (dari `example/android`, dengan `JAVA_HOME` sudah diset): `./gradlew :dozeless:testDebugUnitTest`
Expected: FAIL di `compileDebugUnitTestKotlin` dengan `Unresolved reference: JobSpec` dan sejenisnya.

- [ ] **Step 4: Implementasi**

`android/src/main/kotlin/io/github/xdaijobu/dozeless/Model.kt`:

```kotlin
package io.github.xdaijobu.dozeless

/** Log tag of every native message: `adb logcat -s Dozeless`. */
internal const val TAG = "Dozeless"

/** Why a run started. Values equal the Dart `JobTrigger` names. */
internal object Triggers {
    const val ALARM = "alarm"
    const val BOOT = "boot"
    const val WATCHDOG = "watchdog"
    const val PACKAGE_REPLACED = "packageReplaced"
    const val TIME_CHANGED = "timeChanged"
    const val PREREQUISITE_LOST = "prerequisiteLost"
    const val RESUMED = "resumed"
    const val MANUAL = "manual"
}

internal enum class Mode(val wire: String) {
    EXACT("exact"),
    INEXACT("inexact"),
    STOPPED("stopped");

    companion object {
        fun fromWire(value: String?): Mode = entries.firstOrNull { it.wire == value } ?: EXACT
    }
}

internal enum class Prereq(val wire: String) {
    LOCATION("location"),
    BACKGROUND_LOCATION("backgroundLocation"),
    BATTERY_UNRESTRICTED("batteryUnrestricted"),
    NOT_BACKGROUND_RESTRICTED("notBackgroundRestricted");

    companion object {
        fun fromWire(value: String): Prereq? = entries.firstOrNull { it.wire == value }

        /** Without these no alarm runs in the background, so every job needs them (spec §4). */
        val ALWAYS: Set<Prereq> = setOf(BATTERY_UNRESTRICTED, NOT_BACKGROUND_RESTRICTED)
    }
}

internal data class JobSpec(
    val id: String,
    val callbackHandle: Long,
    val everyMs: Long,
    val timeoutMs: Long,
    val requires: Set<Prereq>,
) {
    val effectiveRequires: Set<Prereq> get() = requires + Prereq.ALWAYS
}

internal data class JobState(
    val mode: Mode = Mode.EXACT,
    val nextRunAt: Long? = null,
    val lastRunAt: Long? = null,
    val lastFinishedAt: Long? = null,
    val lastDurationMs: Long? = null,
    val lastError: String? = null,
    val lastTrigger: String? = null,
    val runCount: Long = 0,
    val skippedBusyCount: Long = 0,
    val ackedEventSeq: Long = 0,
    val missing: List<Prereq> = emptyList(),
    val stoppedAt: Long? = null,
)

internal data class Job(val spec: JobSpec, val state: JobState)
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/JobCodec.kt`:

```kotlin
package io.github.xdaijobu.dozeless

import org.json.JSONArray
import org.json.JSONObject

/** Stores jobs as JSON strings and turns them into status maps for Dart. */
internal object JobCodec {
    fun encode(job: Job): String {
        val s = job.state
        return JSONObject()
            .put("id", job.spec.id)
            .put("callbackHandle", job.spec.callbackHandle)
            .put("everyMs", job.spec.everyMs)
            .put("timeoutMs", job.spec.timeoutMs)
            .put("requires", JSONArray(job.spec.requires.map { it.wire }.sorted()))
            .put("mode", s.mode.wire)
            .putOpt("nextRunAt", s.nextRunAt)
            .putOpt("lastRunAt", s.lastRunAt)
            .putOpt("lastFinishedAt", s.lastFinishedAt)
            .putOpt("lastDurationMs", s.lastDurationMs)
            .putOpt("lastError", s.lastError)
            .putOpt("lastTrigger", s.lastTrigger)
            .put("runCount", s.runCount)
            .put("skippedBusyCount", s.skippedBusyCount)
            .put("ackedEventSeq", s.ackedEventSeq)
            .put("missing", JSONArray(s.missing.map { it.wire }))
            .putOpt("stoppedAt", s.stoppedAt)
            .toString()
    }

    fun decode(json: String): Job {
        val o = JSONObject(json)
        val spec = JobSpec(
            id = o.getString("id"),
            callbackHandle = o.getLong("callbackHandle"),
            everyMs = o.getLong("everyMs"),
            timeoutMs = o.getLong("timeoutMs"),
            requires = o.optJSONArray("requires").strings().mapNotNull { Prereq.fromWire(it) }.toSet(),
        )
        val state = JobState(
            mode = Mode.fromWire(o.optString("mode")),
            nextRunAt = o.longOrNull("nextRunAt"),
            lastRunAt = o.longOrNull("lastRunAt"),
            lastFinishedAt = o.longOrNull("lastFinishedAt"),
            lastDurationMs = o.longOrNull("lastDurationMs"),
            lastError = o.stringOrNull("lastError"),
            lastTrigger = o.stringOrNull("lastTrigger"),
            runCount = o.optLong("runCount"),
            skippedBusyCount = o.optLong("skippedBusyCount"),
            ackedEventSeq = o.optLong("ackedEventSeq"),
            missing = o.optJSONArray("missing").strings().mapNotNull { Prereq.fromWire(it) },
            stoppedAt = o.longOrNull("stoppedAt"),
        )
        return Job(spec, state)
    }

    fun statusMap(job: Job): Map<String, Any?> = mapOf(
        "id" to job.spec.id,
        "mode" to job.state.mode.wire,
        "nextRunAt" to job.state.nextRunAt,
        "lastRunAt" to job.state.lastRunAt,
        "lastFinishedAt" to job.state.lastFinishedAt,
        "lastDurationMs" to job.state.lastDurationMs,
        "lastError" to job.state.lastError,
        "lastTrigger" to job.state.lastTrigger,
        "runCount" to job.state.runCount,
        "skippedBusyCount" to job.state.skippedBusyCount,
        "missing" to job.state.missing.map { it.wire },
        "stoppedAt" to job.state.stoppedAt,
    )

    private fun JSONObject.longOrNull(key: String): Long? = if (has(key) && !isNull(key)) getLong(key) else null

    private fun JSONObject.stringOrNull(key: String): String? = if (has(key) && !isNull(key)) getString(key) else null

    private fun JSONArray?.strings(): List<String> = if (this == null) emptyList() else List(length()) { getString(it) }
}
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/SchedulePolicy.kt`. `onWatchdog` ditambahkan di Task 11:

```kotlin
package io.github.xdaijobu.dozeless

/** Pure decisions about when a job's alarm should fire. */
internal object SchedulePolicy {
    /** How soon a vanished or overdue alarm is re-armed. */
    const val REARM_DELAY_MS = 1_000L

    sealed interface Decision {
        data object Keep : Decision
        data class ArmAt(val at: Long, val trigger: String = Triggers.ALARM) : Decision
    }

    /** schedule() runs on every app start, so it must never push an armed job's next run later. */
    fun onSchedule(existing: Job?, spec: JobSpec, now: Long, armed: Boolean): Decision = when {
        existing == null -> Decision.ArmAt(now + spec.everyMs)
        existing.state.mode == Mode.STOPPED -> Decision.Keep
        existing.spec.copy(callbackHandle = spec.callbackHandle) != spec -> Decision.ArmAt(now + spec.everyMs)
        !armed -> Decision.ArmAt(rearmAt(existing.state.nextRunAt, now))
        else -> Decision.Keep
    }

    /** Never arm in the past: a missed time becomes "almost now". */
    fun rearmAt(nextRunAt: Long?, now: Long): Long =
        if (nextRunAt != null && nextRunAt > now) nextRunAt else now + REARM_DELAY_MS
}
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/RunLocks.kt`:

```kotlin
package io.github.xdaijobu.dozeless

/** One run per job at a time (spec §3 step 4). Main thread only. */
internal class RunLocks {
    private val heldSince = HashMap<String, Long>()

    /** Returns a token, or null while [id] is still running and younger than [staleAfterMs]. */
    fun tryAcquire(id: String, now: Long, staleAfterMs: Long): Long? {
        val since = heldSince[id]
        if (since != null && now - since < staleAfterMs) return null
        heldSince[id] = now
        return now
    }

    /** Releases only if [token] still owns the lock, so a stale run cannot free its successor. */
    fun release(id: String, token: Long) {
        if (heldSince[id] == token) heldSince.remove(id)
    }
}
```

- [ ] **Step 5: Jalankan test dan pastikan lolos**

Run (dari `example/android`): `./gradlew :dozeless:testDebugUnitTest`
Expected: `BUILD SUCCESSFUL` dan 16 test `PASSED` (JobCodecTest 4, SchedulePolicyTest 7, RunLocksTest 5).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(android): add job model, JSON codec, schedule policy and run locks"
```

---

### Task 3: JobStore, AlarmScheduler, MethodChannel, dan API `schedule/cancel/status/debugFireIn`

**Files:**
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/JobStore.kt`
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/AlarmScheduler.kt`
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/JobReceiver.kt` (versi sementara: hanya log, diganti di Task 5)
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/Jobs.kt`
- Modify (tulis ulang): `android/src/main/kotlin/io/github/xdaijobu/dozeless/DozelessPlugin.kt`
- Modify (tulis ulang): `android/src/main/AndroidManifest.xml`
- Create: `lib/src/dozeless_api.dart`
- Modify: `lib/dozeless.dart`
- Test: `test/dozeless_api_test.dart`

**Interfaces:**
- Consumes: Task 2 (`JobSpec`, `JobState`, `Job`, `JobCodec`, `SchedulePolicy`, `Mode`, `Prereq`, `Triggers`).
- Produces:
  - Kotlin `JobStore(context)`: `all(): List<Job>`, `get(id): Job?`, `put(job)`, `update(id, (JobState) -> JobState): Job?`, `remove(id)`, `var dispatcherHandle: Long`
  - Kotlin `AlarmScheduler(context)`: `arm(id, at, trigger = Triggers.ALARM): Mode`, `cancel(id)`, `isArmed(id): Boolean`, `canExact(): Boolean`
  - Kotlin `JobReceiver.ACTION_RUN`, `EXTRA_JOB_ID`, `EXTRA_TRIGGER`, `EXTRA_SCHEDULED_AT`
  - Kotlin `Jobs.schedule(app, spec)`, `Jobs.cancel(app, id)`, `Jobs.requireJob(app, id): Job`, `Jobs.debugFireIn(app, id, delayMs)`
  - Kotlin ekstensi `MethodCall.long(key)`, `MethodCall.str(key)`
  - Dart `Dozeless.channel` (`MethodChannel('dozeless')`), `Dozeless.callbackHandleOf`, `Dozeless.minInterval`, `Dozeless.maxTimeout`, `Dozeless.schedule({id, callback, every, requires, timeout})`, `Dozeless.cancel(id)`, `Dozeless.status(id): Future<JobStatus?>`, `Dozeless.debugFireIn(id, delay)`
  - Method channel `dozeless`: `schedule {id, callbackHandle, everyMs, timeoutMs, requires: [String]}`, `cancel {id}`, `status {id} → Map|null`, `debugFireIn {id, delayMs}`

- [ ] **Step 1: Tulis test Dart yang gagal**

`test/dozeless_api_test.dart`:

```dart
import 'package:dozeless/dozeless.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> topLevelJob(JobContext ctx) async {}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  Object? reply;

  setUp(() {
    calls.clear();
    reply = null;
    Dozeless.callbackHandleOf = (_) => 4242;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(Dozeless.channel, (call) async {
      calls.add(call);
      return reply;
    });
  });

  group('schedule', () {
    test('sends the job spec with sorted prerequisite names', () async {
      await Dozeless.schedule(
        id: 'get',
        callback: topLevelJob,
        every: const Duration(minutes: 5),
        requires: {Prereq.location, Prereq.backgroundLocation},
      );
      expect(calls.single.method, 'schedule');
      expect(calls.single.arguments, {
        'id': 'get',
        'callbackHandle': 4242,
        'everyMs': 300000,
        'timeoutMs': 45000,
        'requires': ['backgroundLocation', 'location'],
      });
    });

    test('rejects a callback without a handle, such as a closure', () async {
      Dozeless.callbackHandleOf = (_) => null;
      await expectLater(
        Dozeless.schedule(id: 'get', callback: (ctx) async {}, every: const Duration(minutes: 5)),
        throwsArgumentError,
      );
      expect(calls, isEmpty);
    });

    test('rejects intervals under one minute', () async {
      await expectLater(
        Dozeless.schedule(id: 'get', callback: topLevelJob, every: const Duration(seconds: 59)),
        throwsArgumentError,
      );
    });

    test('rejects timeouts over 50 seconds', () async {
      await expectLater(
        Dozeless.schedule(
          id: 'get',
          callback: topLevelJob,
          every: const Duration(minutes: 5),
          timeout: const Duration(seconds: 51),
        ),
        throwsArgumentError,
      );
    });

    test('rejects ids that cannot go into an alarm URI', () async {
      await expectLater(
        Dozeless.schedule(id: 'get job', callback: topLevelJob, every: const Duration(minutes: 5)),
        throwsArgumentError,
      );
    });
  });

  group('status', () {
    test('parses the native map', () async {
      reply = {'id': 'get', 'mode': 'inexact', 'runCount': 3};
      final s = await Dozeless.status('get');
      expect(s!.mode, JobMode.inexact);
      expect(s.runCount, 3);
      expect(calls.single.arguments, {'id': 'get'});
    });

    test('is null for an unknown job', () async {
      expect(await Dozeless.status('nope'), isNull);
    });
  });

  test('debugFireIn sends the delay in milliseconds', () async {
    await Dozeless.debugFireIn('get', const Duration(seconds: 10));
    expect(calls.single.method, 'debugFireIn');
    expect(calls.single.arguments, {'id': 'get', 'delayMs': 10000});
  });
}
```

- [ ] **Step 2: Jalankan dan pastikan gagal**

Run: `flutter test test/dozeless_api_test.dart`
Expected: FAIL, compile error `Undefined name 'Dozeless'`.

- [ ] **Step 3: Implementasi API Dart**

`lib/src/dozeless_api.dart`. Method lain ditambahkan di task-task berikutnya:

```dart
import 'dart:ui' show PluginUtilities;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'job_context.dart';
import 'models.dart';

/// AlarmManager-only job runner (spec §3).
class Dozeless {
  Dozeless._();

  @visibleForTesting
  static const MethodChannel channel = MethodChannel('dozeless');

  /// Turns a callback into its raw handle; tests replace it.
  @visibleForTesting
  static int? Function(Function callback) callbackHandleOf =
      (callback) => PluginUtilities.getCallbackHandle(callback)?.toRawHandle();

  static const Duration minInterval = Duration(minutes: 1);

  /// Alarm broadcasts are killed after 60 s, and engine start-up eats into that.
  static const Duration maxTimeout = Duration(seconds: 50);

  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_.-]{1,64}$');

  /// Creates or updates job [id]. Safe to call on every app start: an armed
  /// job keeps its next run unless [every], [timeout] or [requires] changed.
  static Future<void> schedule({
    required String id,
    required JobCallback callback,
    required Duration every,
    Set<Prereq> requires = const {},
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (!_idPattern.hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'use 1-64 of A-Z a-z 0-9 _ . -');
    }
    if (every < minInterval) throw ArgumentError.value(every, 'every', 'must be at least 1 minute');
    if (timeout <= Duration.zero || timeout > maxTimeout) {
      throw ArgumentError.value(timeout, 'timeout', 'must be within (0, 50 s]');
    }
    final handle = callbackHandleOf(callback);
    if (handle == null) {
      throw ArgumentError.value(callback, 'callback',
          "must be a top-level or static function annotated with @pragma('vm:entry-point')");
    }
    await channel.invokeMethod<void>('schedule', {
      'id': id,
      'callbackHandle': handle,
      'everyMs': every.inMilliseconds,
      'timeoutMs': timeout.inMilliseconds,
      'requires': requires.map((p) => p.name).toList()..sort(),
    });
  }

  static Future<void> cancel(String id) => channel.invokeMethod<void>('cancel', {'id': id});

  static Future<JobStatus?> status(String id) async {
    final map = await channel.invokeMapMethod<Object?, Object?>('status', {'id': id});
    return map == null ? null : JobStatus.fromMap(map);
  }

  /// Debug: move [id]'s next alarm to [delay] from now.
  static Future<void> debugFireIn(String id, Duration delay) =>
      channel.invokeMethod<void>('debugFireIn', {'id': id, 'delayMs': delay.inMilliseconds});
}
```

`lib/dozeless.dart`:

```dart
export 'src/dozeless_api.dart';
export 'src/job_context.dart';
export 'src/models.dart';
```

- [ ] **Step 4: Jalankan test Dart dan pastikan lolos**

Run: `flutter test` → Expected: `All tests passed!` (7 test dari Task 1 + 8 test baru = 15)

- [ ] **Step 5: Implementasi native**

`android/src/main/kotlin/io/github/xdaijobu/dozeless/JobStore.kt`. Property lain ditambahkan di Task 7, 10, 12, dan 13:

```kotlin
package io.github.xdaijobu.dozeless

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import org.json.JSONException

/** Jobs and plugin bookkeeping in SharedPreferences. Writes use commit() so they survive a process kill. */
internal class JobStore(context: Context) {
    private val prefs = context.getSharedPreferences("dozeless", Context.MODE_PRIVATE)

    fun all(): List<Job> = prefs.all
        .filterKeys { it.startsWith(JOB_PREFIX) }
        .values
        .mapNotNull { (it as? String)?.let(::decodeOrNull) }

    fun get(id: String): Job? = prefs.getString(JOB_PREFIX + id, null)?.let(::decodeOrNull)

    fun put(job: Job) = edit { putString(JOB_PREFIX + job.spec.id, JobCodec.encode(job)) }

    fun update(id: String, change: (JobState) -> JobState): Job? {
        val job = get(id) ?: return null
        return job.copy(state = change(job.state)).also(::put)
    }

    fun remove(id: String) = edit { remove(JOB_PREFIX + id) }

    var dispatcherHandle: Long
        get() = prefs.getLong(KEY_DISPATCHER, 0L)
        set(value) = edit { putLong(KEY_DISPATCHER, value) }

    private fun edit(change: SharedPreferences.Editor.() -> Unit) {
        prefs.edit().apply(change).commit()
    }

    private fun decodeOrNull(json: String): Job? = try {
        JobCodec.decode(json)
    } catch (e: JSONException) {
        Log.w(TAG, "dropping unreadable job: $json", e)
        null
    }

    private companion object {
        const val JOB_PREFIX = "job:"
        const val KEY_DISPATCHER = "dispatcherHandle"
    }
}
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/AlarmScheduler.kt`:

```kotlin
package io.github.xdaijobu.dozeless

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log

/** One-shot exact alarm per job id, with an inexact fallback (spec §3 AlarmScheduler). */
internal class AlarmScheduler(private val context: Context) {
    private val alarmManager = context.getSystemService(AlarmManager::class.java)

    /** Arms [id] at [at] (wall clock) and returns the mode actually used. */
    fun arm(id: String, at: Long, trigger: String = Triggers.ALARM): Mode {
        val pi = pendingIntent(id, at, trigger, PendingIntent.FLAG_UPDATE_CURRENT)!!
        if (canExact()) {
            try {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
                return Mode.EXACT
            } catch (e: SecurityException) {
                Log.w(TAG, "exact alarm denied for $id, falling back to inexact", e)
            }
        }
        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pi)
        return Mode.INEXACT
    }

    /** [arm] and remember the planned time and the mode on the stored job. */
    fun armAndRecord(store: JobStore, id: String, at: Long, trigger: String = Triggers.ALARM): Mode =
        arm(id, at, trigger).also { mode -> store.update(id) { it.copy(nextRunAt = at, mode = mode) } }

    fun cancel(id: String) {
        pendingIntent(id, 0, Triggers.ALARM, PendingIntent.FLAG_NO_CREATE)?.let {
            alarmManager.cancel(it)
            it.cancel()
        }
    }

    /** Only a hint: the PendingIntent survives process death and, on Android 14, even a force stop that deleted the alarm. */
    fun isArmed(id: String): Boolean = pendingIntent(id, 0, Triggers.ALARM, PendingIntent.FLAG_NO_CREATE) != null

    fun canExact(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) alarmManager.canScheduleExactAlarms() else true

    // Extras do not take part in PendingIntent identity, so FLAG_NO_CREATE finds the alarm whatever its trigger.
    private fun pendingIntent(id: String, at: Long, trigger: String, flag: Int): PendingIntent? {
        val intent = Intent(context, JobReceiver::class.java)
            .setAction(JobReceiver.ACTION_RUN)
            .setData(Uri.parse("dozeless://job/" + Uri.encode(id)))
            .putExtra(JobReceiver.EXTRA_JOB_ID, id)
            .putExtra(JobReceiver.EXTRA_SCHEDULED_AT, at)
            .putExtra(JobReceiver.EXTRA_TRIGGER, trigger)
        return PendingIntent.getBroadcast(context, 0, intent, flag or PendingIntent.FLAG_IMMUTABLE)
    }
}
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/JobReceiver.kt` (versi Task 3: hanya mencatat bahwa alarm berbunyi):

```kotlin
package io.github.xdaijobu.dozeless

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/** Receives job alarms. Task 5 hands them to JobRunner. */
class JobReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_RUN) return
        val id = intent.getStringExtra(EXTRA_JOB_ID) ?: return
        val trigger = intent.getStringExtra(EXTRA_TRIGGER) ?: Triggers.ALARM
        val firedAt = System.currentTimeMillis()
        Log.i(TAG, "fire id=$id trigger=$trigger delayMs=${firedAt - intent.getLongExtra(EXTRA_SCHEDULED_AT, firedAt)}")
    }

    companion object {
        const val ACTION_RUN = "io.github.xdaijobu.dozeless.RUN"
        const val EXTRA_JOB_ID = "jobId"
        const val EXTRA_TRIGGER = "trigger"
        const val EXTRA_SCHEDULED_AT = "scheduledAt"
    }
}
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/Jobs.kt` (versi Task 3. Task 11 dan 12 menambah beberapa baris):

```kotlin
package io.github.xdaijobu.dozeless

import android.content.Context
import android.util.Log

/** Job operations called from the Dart API. */
internal object Jobs {
    fun schedule(app: Context, spec: JobSpec) {
        val store = JobStore(app)
        val scheduler = AlarmScheduler(app)
        val existing = store.get(spec.id)
        val state = existing?.state ?: JobState()
        when (val d = SchedulePolicy.onSchedule(existing, spec, System.currentTimeMillis(), scheduler.isArmed(spec.id))) {
            SchedulePolicy.Decision.Keep -> store.put(Job(spec, state))
            is SchedulePolicy.Decision.ArmAt -> {
                val mode = scheduler.arm(spec.id, d.at, d.trigger)
                store.put(Job(spec, state.copy(nextRunAt = d.at, mode = mode)))
                Log.i(TAG, "schedule id=${spec.id} everyMs=${spec.everyMs} next=${d.at} mode=${mode.wire}")
            }
        }
    }

    fun cancel(app: Context, id: String) {
        AlarmScheduler(app).cancel(id)
        JobStore(app).remove(id)
        Log.i(TAG, "cancel id=$id")
    }

    fun requireJob(app: Context, id: String): Job =
        JobStore(app).get(id) ?: throw IllegalArgumentException("unknown job $id")

    fun debugFireIn(app: Context, id: String, delayMs: Long) {
        requireJob(app, id)
        AlarmScheduler(app).armAndRecord(JobStore(app), id, System.currentTimeMillis() + delayMs)
    }
}
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/DozelessPlugin.kt`. Tulis ulang seluruhnya. Cabang `when` ditambahkan di task-task berikutnya:

```kotlin
package io.github.xdaijobu.dozeless

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class DozelessPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var app: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        app = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "dozeless")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "schedule" -> {
                    Jobs.schedule(app, specOf(call))
                    result.success(null)
                }
                "cancel" -> {
                    Jobs.cancel(app, call.str("id"))
                    result.success(null)
                }
                "status" -> result.success(JobStore(app).get(call.str("id"))?.let(JobCodec::statusMap))
                "debugFireIn" -> {
                    Jobs.debugFireIn(app, call.str("id"), call.long("delayMs"))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: IllegalArgumentException) {
            result.error("BAD_ARGUMENT", e.message, null)
        }
    }

    private fun specOf(call: MethodCall) = JobSpec(
        id = call.str("id"),
        callbackHandle = call.long("callbackHandle"),
        everyMs = call.long("everyMs"),
        timeoutMs = call.long("timeoutMs"),
        requires = call.argument<List<String>>("requires").orEmpty().mapNotNull { Prereq.fromWire(it) }.toSet(),
    )
}

/** Dart ints arrive as Integer or Long depending on their size. */
internal fun MethodCall.long(key: String): Long =
    (argument<Number>(key) ?: throw IllegalArgumentException("missing $key")).toLong()

internal fun MethodCall.str(key: String): String =
    argument<String>(key) ?: throw IllegalArgumentException("missing $key")
```

`android/src/main/AndroidManifest.xml`. Tulis ulang. Baris `package=` dari template tetap dipakai:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
  package="io.github.xdaijobu.dozeless">

    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />

    <application>
        <receiver
            android:name="io.github.xdaijobu.dozeless.JobReceiver"
            android:exported="false" />
    </application>
</manifest>
```

- [ ] **Step 6: Pastikan native ter-compile dan manifest ter-merge**

Run (dari `example/android`): `./gradlew :dozeless:testDebugUnitTest` → Expected: `BUILD SUCCESSFUL` (16 test Kotlin tetap lolos dan kode main ter-compile).
Run (dari `example/`): `flutter build apk --debug` → Expected: `√ Built build\app\outputs\flutter-apk\app-debug.apk`

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: schedule, cancel and status jobs with exact alarm chain"
```

---

### Task 4: Snapshot konteks (prasyarat, perangkat, boot)

**Files:**
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/Prereqs.kt`
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/SettingsOpener.kt` (baru berisi `AutostartIntents`; sisanya ditambahkan di Task 9)
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/DeviceState.kt`
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/BootInfo.kt` (baru berisi `BootInfo`; Task 7 dan 13 menambah isinya)
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/ContextBuilder.kt` (versi Task 4)
- Modify: `DozelessPlugin.kt` (cabang `checkPrerequisites`)
- Modify: `android/src/main/AndroidManifest.xml` (`ACCESS_WIFI_STATE`)
- Modify: `lib/src/dozeless_api.dart` (`checkPrerequisites`)
- Test: `android/src/test/kotlin/io/github/xdaijobu/dozeless/SnapshotTest.kt`, `test/dozeless_api_test.dart`

**Interfaces:**
- Consumes: `Prereq`, `Job`, `AlarmScheduler.canExact()`.
- Produces:
  - `data class PrereqSnapshot(location, backgroundLocation, batteryUnrestricted, backgroundRestricted, exactAlarm, notification, autostartSettingAvailable)` dengan `has(p)`, `missing(required: Set<Prereq>): List<Prereq>`, `toMap()`
  - `PrereqReader.read(context): PrereqSnapshot`
  - `AutostartIntents.candidates(manufacturer): List<Pair<String, String>>` (package to activity)
  - `DeviceState.read(context): Map<String, Any?>`, `StandbyBuckets.name(Int): String`
  - `data class BootInfo(bootCount: Int?, bootTime: Long)` + `isFirstRunSinceBoot(lastRunAt)` + `BootInfo.read(context)`
  - `class BuiltContext(map, deliveredSeq: Long)`, `ContextBuilder.build(app, job, trigger, scheduledAt, firedAt): BuiltContext`
  - Dart `Dozeless.checkPrerequisites(): Future<PrerequisiteStatus>`

- [ ] **Step 1: Tulis test yang gagal**

`android/src/test/kotlin/io/github/xdaijobu/dozeless/SnapshotTest.kt`:

```kotlin
package io.github.xdaijobu.dozeless

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class SnapshotTest {
    private val allOk = PrereqSnapshot(
        location = true, backgroundLocation = true, batteryUnrestricted = true, backgroundRestricted = false,
        exactAlarm = true, notification = true, autostartSettingAvailable = false,
    )

    @Test
    fun nothingMissingWhenEverythingIsGranted() =
        assertEquals(emptyList(), allOk.missing(setOf(Prereq.LOCATION) + Prereq.ALWAYS))

    @Test
    fun missingListsOnlyRequiredOnesInEnumOrder() {
        val s = allOk.copy(location = false, backgroundLocation = false, backgroundRestricted = true)
        assertEquals(listOf(Prereq.BACKGROUND_LOCATION, Prereq.NOT_BACKGROUND_RESTRICTED), s.missing(setOf(Prereq.NOT_BACKGROUND_RESTRICTED, Prereq.BACKGROUND_LOCATION)))
    }

    @Test
    fun everyJobImplicitlyNeedsBatteryAndNoBackgroundRestriction() {
        val spec = JobSpec("send", 1L, 60_000, 45_000, requires = emptySet())
        val s = allOk.copy(batteryUnrestricted = false)
        assertEquals(listOf(Prereq.BATTERY_UNRESTRICTED), s.missing(spec.effectiveRequires))
    }

    @Test
    fun exactAlarmAndNotificationNeverBlock() =
        assertEquals(emptyList(), allOk.copy(exactAlarm = false, notification = false).missing(Prereq.entries.toSet()))

    @Test
    fun autostartPagesExistOnlyForKnownBrands() {
        assertEquals(1, AutostartIntents.candidates("Xiaomi").size)
        assertEquals(3, AutostartIntents.candidates("realme").size)
        assertTrue(AutostartIntents.candidates("samsung").isEmpty())
    }

    @Test
    fun standbyBucketNames() {
        assertEquals("active", StandbyBuckets.name(10))
        assertEquals("rare", StandbyBuckets.name(40))
        assertEquals("restricted", StandbyBuckets.name(45))
        assertEquals("unknown", StandbyBuckets.name(99))
    }

    @Test
    fun firstRunSinceBootComparesLastRunWithBootTime() {
        val boot = BootInfo(bootCount = 12, bootTime = 1_000)
        assertTrue(boot.isFirstRunSinceBoot(null))
        assertTrue(boot.isFirstRunSinceBoot(999))
        assertFalse(boot.isFirstRunSinceBoot(1_001))
    }
}
```

Tambahkan ke `test/dozeless_api_test.dart`, di dalam `main()` setelah test `debugFireIn`:

```dart
  test('checkPrerequisites parses the snapshot', () async {
    reply = {'location': true, 'batteryUnrestricted': false, 'autostartSettingAvailable': true};
    final p = await Dozeless.checkPrerequisites();
    expect(p.location, isTrue);
    expect(p.autostartSettingAvailable, isTrue);
    expect(p.missingFor({Prereq.location}), [Prereq.batteryUnrestricted]);
  });
```

- [ ] **Step 2: Jalankan dan pastikan gagal**

Run (dari `example/android`): `./gradlew :dozeless:testDebugUnitTest --tests "io.github.xdaijobu.dozeless.SnapshotTest"` → Expected: FAIL `Unresolved reference: PrereqSnapshot`
Run: `flutter test test/dozeless_api_test.dart` → Expected: FAIL `The method 'checkPrerequisites' isn't defined`

- [ ] **Step 3: Implementasi**

`android/src/main/kotlin/io/github/xdaijobu/dozeless/Prereqs.kt`:

```kotlin
package io.github.xdaijobu.dozeless

import android.Manifest
import android.app.ActivityManager
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager

/** What the device allows right now (spec §4 table). */
internal data class PrereqSnapshot(
    val location: Boolean,
    val backgroundLocation: Boolean,
    val batteryUnrestricted: Boolean,
    val backgroundRestricted: Boolean,
    val exactAlarm: Boolean,
    val notification: Boolean,
    val autostartSettingAvailable: Boolean,
) {
    fun has(p: Prereq): Boolean = when (p) {
        Prereq.LOCATION -> location
        Prereq.BACKGROUND_LOCATION -> backgroundLocation
        Prereq.BATTERY_UNRESTRICTED -> batteryUnrestricted
        Prereq.NOT_BACKGROUND_RESTRICTED -> !backgroundRestricted
    }

    /** Blocking prerequisites that are missing, in [Prereq] order. Exact alarm and notification never block. */
    fun missing(required: Set<Prereq>): List<Prereq> = Prereq.entries.filter { it in required && !has(it) }

    fun toMap(): Map<String, Any?> = mapOf(
        "location" to location,
        "backgroundLocation" to backgroundLocation,
        "batteryUnrestricted" to batteryUnrestricted,
        "backgroundRestricted" to backgroundRestricted,
        "exactAlarm" to exactAlarm,
        "notification" to notification,
        "autostartSettingAvailable" to autostartSettingAvailable,
    )
}

internal object PrereqReader {
    fun read(context: Context): PrereqSnapshot {
        val fine = granted(context, Manifest.permission.ACCESS_FINE_LOCATION)
        val background = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            granted(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        } else {
            fine
        }
        val power = context.getSystemService(PowerManager::class.java)
        val activity = context.getSystemService(ActivityManager::class.java)
        val notifications = context.getSystemService(NotificationManager::class.java)
        val notificationAllowed = notifications.areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || granted(context, Manifest.permission.POST_NOTIFICATIONS))
        return PrereqSnapshot(
            location = fine,
            backgroundLocation = background,
            batteryUnrestricted = power.isIgnoringBatteryOptimizations(context.packageName),
            backgroundRestricted = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && activity.isBackgroundRestricted,
            exactAlarm = AlarmScheduler(context).canExact(),
            notification = notificationAllowed,
            autostartSettingAvailable = AutostartIntents.candidates(Build.MANUFACTURER).isNotEmpty(),
        )
    }

    private fun granted(context: Context, permission: String) =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
}
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/SettingsOpener.kt` (versi Task 4):

```kotlin
package io.github.xdaijobu.dozeless

/** OEM "Autostart" pages. Without Autostart these brands do not deliver BOOT_COMPLETED (spec §4). */
internal object AutostartIntents {
    fun candidates(manufacturer: String): List<Pair<String, String>> = when (manufacturer.lowercase()) {
        "xiaomi", "redmi", "poco" -> listOf(
            "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
        )
        "oppo", "realme" -> listOf(
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
            "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
        )
        "vivo" -> listOf(
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
        )
        else -> emptyList()
    }
}
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/DeviceState.kt`:

```kotlin
package io.github.xdaijobu.dozeless

import android.annotation.SuppressLint
import android.app.usage.UsageStatsManager
import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.telephony.TelephonyManager
import java.util.TimeZone

/** Device facts for `JobContext.device` and the record's Jam/Perangkat/Sistem fields (spec §7). */
internal object DeviceState {
    @SuppressLint("HardwareIds")
    fun read(context: Context): Map<String, Any?> {
        val power = context.getSystemService(PowerManager::class.java)
        return mapOf(
            "deviceId" to Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID),
            "deviceIdle" to power.isDeviceIdleMode,
            "interactive" to power.isInteractive,
            "powerSaveMode" to power.isPowerSaveMode,
            "standbyBucket" to standbyBucket(context),
            "autoTime" to (Settings.Global.getInt(context.contentResolver, Settings.Global.AUTO_TIME, 1) == 1),
            "timezone" to TimeZone.getDefault().id,
            "cellLevel" to cellLevel(context),
            "wifiLevel" to wifiLevel(context),
        )
    }

    private fun standbyBucket(context: Context): String =
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) "unknown"
        else StandbyBuckets.name(context.getSystemService(UsageStatsManager::class.java).appStandbyBucket)

    private fun cellLevel(context: Context): Int? = try {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) null
        else context.getSystemService(TelephonyManager::class.java)?.signalStrength?.level
    } catch (e: SecurityException) {
        null
    }

    @Suppress("DEPRECATION")
    private fun wifiLevel(context: Context): Int? = try {
        val rssi = context.getSystemService(WifiManager::class.java)?.connectionInfo?.rssi
        if (rssi == null || rssi <= -127) null else WifiManager.calculateSignalLevel(rssi, 5)
    } catch (e: SecurityException) {
        null
    }
}

internal object StandbyBuckets {
    fun name(bucket: Int): String = when (bucket) {
        5 -> "exempted"
        10 -> "active"
        20 -> "workingSet"
        30 -> "frequent"
        40 -> "rare"
        45 -> "restricted"
        50 -> "never"
        else -> "unknown"
    }
}
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/BootInfo.kt` (versi Task 4):

```kotlin
package io.github.xdaijobu.dozeless

import android.content.Context
import android.os.SystemClock
import android.provider.Settings

internal data class BootInfo(val bootCount: Int?, val bootTime: Long) {
    fun isFirstRunSinceBoot(lastRunAt: Long?): Boolean = lastRunAt == null || lastRunAt < bootTime

    companion object {
        fun read(context: Context) = BootInfo(
            bootCount = try {
                Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT)
            } catch (e: Settings.SettingNotFoundException) {
                null
            },
            bootTime = System.currentTimeMillis() - SystemClock.elapsedRealtime(),
        )
    }
}
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/ContextBuilder.kt` (versi Task 4. `systemEvents` diisi di Task 12):

```kotlin
package io.github.xdaijobu.dozeless

import android.content.Context

internal class BuiltContext(val map: Map<String, Any?>, val deliveredSeq: Long)

/** Builds the map that becomes `JobContext` in Dart (spec §3 JobContext table). */
internal object ContextBuilder {
    fun build(app: Context, job: Job, trigger: String, scheduledAt: Long, firedAt: Long): BuiltContext {
        val boot = BootInfo.read(app)
        val s = job.state
        val map = mapOf(
            "jobId" to job.spec.id,
            "trigger" to trigger,
            "scheduledAt" to scheduledAt,
            "firedAt" to firedAt,
            "delayMs" to firedAt - scheduledAt,
            "timeoutMs" to job.spec.timeoutMs,
            "mode" to s.mode.wire,
            "lastRunAt" to s.lastRunAt,
            "lastError" to s.lastError,
            "stoppedAt" to s.stoppedAt,
            "boot" to mapOf(
                "bootCount" to boot.bootCount,
                "bootTime" to boot.bootTime,
                "firstJobSinceBoot" to boot.isFirstRunSinceBoot(s.lastRunAt),
            ),
            "systemEvents" to emptyList<Map<String, Any?>>(),
            "prerequisites" to PrereqReader.read(app).toMap(),
            "device" to DeviceState.read(app),
        )
        return BuiltContext(map, deliveredSeq = s.ackedEventSeq)
    }
}
```

Di `DozelessPlugin.onMethodCall`, tambahkan cabang ini sebelum `"debugFireIn"`:

```kotlin
                "checkPrerequisites" -> result.success(PrereqReader.read(app).toMap())
```

Di `AndroidManifest.xml`, tambahkan setelah `WAKE_LOCK`:

```xml
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
```

Di `lib/src/dozeless_api.dart`, tambahkan method ini ke class `Dozeless` setelah `status`:

```dart
  static Future<PrerequisiteStatus> checkPrerequisites() async =>
      PrerequisiteStatus.fromMap((await channel.invokeMapMethod<Object?, Object?>('checkPrerequisites'))!);
```

- [ ] **Step 4: Jalankan test dan pastikan lolos**

Run (dari `example/android`): `./gradlew :dozeless:testDebugUnitTest` → Expected: `BUILD SUCCESSFUL`, 23 test (16 + 7)
Run: `flutter test` → Expected: `All tests passed!` (16)

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: read prerequisites, device state and boot info for job context"
```

---

### Task 5: Jalur eksekusi (receiver → engine headless → callback Dart yang ditunggu)

**Files:**
- Create: `lib/src/dispatcher.dart`
- Modify: `lib/src/dozeless_api.dart` (`initialize`, `runNow`)
- Modify: `lib/dozeless.dart` (export dispatcher)
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/DartRunner.kt`
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/JobRunner.kt` (versi Task 5)
- Modify (tulis ulang): `android/src/main/kotlin/io/github/xdaijobu/dozeless/JobReceiver.kt`
- Modify: `DozelessPlugin.kt` (cabang `initialize`, `runNow`)
- Test: `test/dispatcher_test.dart`, `test/dozeless_api_test.dart`, `example/integration_test/dozeless_test.dart`

**Interfaces:**
- Consumes: `JobStore`, `AlarmScheduler`, `RunLocks`, `ContextBuilder.build`, `Triggers`.
- Produces:
  - Dart `dozelessDispatcher()` (entry point, `@pragma('vm:entry-point')`), `handleBackgroundCall(MethodCall, {resolve})` (`@visibleForTesting`)
  - Dart `Dozeless.initialize()`, `Dozeless.runNow(id)`
  - Channel `dozeless/background`: native → Dart `runJob {jobId, callbackHandle, context}`, Dart → native `dispatcherReady`
  - Channel `dozeless`: `initialize {dispatcherHandle}`, `runNow {id}`
  - Kotlin `sealed interface JobOutcome { Success, Timeout, Failed(error), EngineFailed(error) }`
  - Kotlin `DartRunner.invoke(app, callbackHandle, jobId, ctx, shouldStart: () -> Boolean, onResult: (JobOutcome) -> Unit)`
  - Kotlin `JobRunner.run(app, id, trigger, scheduledAt, firedAt, onDone: () -> Unit)`
  - Kotlin `JobReceiver.dispatch(context, id, trigger)`
  - Isi `lastError`: `null` · `"JOB_TIMEOUT"` · `"JOB_FAILED: <pesan>"` · `"CALLBACK_NOT_FOUND: ..."` · `"ENGINE_START_FAILED: DISPATCHER_NOT_INITIALIZED|DISPATCHER_NOT_FOUND|ENGINE_START_TIMEOUT ..."`

- [ ] **Step 1: Tulis test Dart yang gagal**

`test/dispatcher_test.dart`:

```dart
import 'package:dozeless/dozeless.dart';
import 'package:dozeless/src/dispatcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final seen = <JobContext>[];

Future<void> recordingJob(JobContext ctx) async => seen.add(ctx);

Future<void> throwingJob(JobContext ctx) async => throw StateError('boom');

MethodCall runJob() => const MethodCall('runJob', {
      'jobId': 'get',
      'callbackHandle': 1,
      'context': {'jobId': 'get', 'trigger': 'alarm', 'scheduledAt': 1, 'firedAt': 2},
    });

void main() {
  setUp(seen.clear);

  test('resolves the handle and passes the parsed context to the callback', () async {
    await handleBackgroundCall(runJob(), resolve: (_) => recordingJob);
    expect(seen.single.jobId, 'get');
    expect(seen.single.trigger, JobTrigger.alarm);
  });

  test('completes only after a slow callback has finished', () async {
    var finished = false;
    Future<void> slowJob(JobContext ctx) async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      finished = true;
    }

    await handleBackgroundCall(runJob(), resolve: (_) => slowJob);
    expect(finished, isTrue);
  });

  test('a throwing job becomes a JOB_FAILED platform error', () async {
    await expectLater(
      handleBackgroundCall(runJob(), resolve: (_) => throwingJob),
      throwsA(isA<PlatformException>()
          .having((e) => e.code, 'code', 'JOB_FAILED')
          .having((e) => e.message, 'message', contains('boom'))),
    );
  });

  test('an unknown handle becomes CALLBACK_NOT_FOUND', () async {
    await expectLater(
      handleBackgroundCall(runJob(), resolve: (_) => null),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'CALLBACK_NOT_FOUND')),
    );
  });

  test('a function with the wrong signature becomes CALLBACK_NOT_FOUND', () async {
    await expectLater(
      handleBackgroundCall(runJob(), resolve: (_) => () {}),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'CALLBACK_NOT_FOUND')),
    );
  });
}
```

Tambahkan ke `test/dozeless_api_test.dart`, di dalam `main()` setelah test `debugFireIn`:

```dart
  test('runNow sends the job id', () async {
    await Dozeless.runNow('get');
    expect(calls.single.method, 'runNow');
    expect(calls.single.arguments, {'id': 'get'});
  });

  test('initialize sends the dispatcher handle', () async {
    await Dozeless.initialize();
    expect(calls.single.method, 'initialize');
    expect(calls.single.arguments, {'dispatcherHandle': 4242});
  });
```

- [ ] **Step 2: Jalankan dan pastikan gagal**

Run: `flutter test` → Expected: FAIL. `package:dozeless/src/dispatcher.dart` belum ada, dan `runNow` / `initialize` belum didefinisikan.

- [ ] **Step 3: Implementasi sisi Dart**

`lib/src/dispatcher.dart`:

```dart
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'job_context.dart';

const MethodChannel _background = MethodChannel('dozeless/background');

/// Entry point of the background engine. Registered by [Dozeless.initialize].
@pragma('vm:entry-point')
void dozelessDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  _background.setMethodCallHandler(handleBackgroundCall);
  _background.invokeMethod<void>('dispatcherReady');
}

/// Runs one job and completes only when the callback has finished.
@visibleForTesting
Future<Object?> handleBackgroundCall(
  MethodCall call, {
  Function? Function(CallbackHandle handle) resolve = PluginUtilities.getCallbackFromHandle,
}) async {
  if (call.method != 'runJob') {
    throw MissingPluginException('dozeless/background has no method ${call.method}');
  }
  final args = (call.arguments as Map).cast<Object?, Object?>();
  final raw = (args['callbackHandle']! as num).toInt();
  final callback = resolve(CallbackHandle.fromRawHandle(raw));
  if (callback is! JobCallback) {
    throw PlatformException(code: 'CALLBACK_NOT_FOUND', message: 'no JobCallback for handle $raw');
  }
  final ctx = JobContext.fromMap((args['context']! as Map).cast<Object?, Object?>());
  try {
    await callback(ctx);
  } catch (e, st) {
    throw PlatformException(code: 'JOB_FAILED', message: '$e', details: '$st');
  }
  return null;
}
```

Di `lib/src/dozeless_api.dart`, tambahkan `import 'dispatcher.dart';`, lalu tambahkan dua method ini ke class `Dozeless` (`initialize` sebelum `schedule`, `runNow` setelah `status`):

```dart
  /// Call once in `main()` after `WidgetsFlutterBinding.ensureInitialized()`.
  static Future<void> initialize() async {
    final handle = callbackHandleOf(dozelessDispatcher);
    if (handle == null) throw StateError('dozeless: dispatcher handle unavailable');
    await channel.invokeMethod<void>('initialize', {'dispatcherHandle': handle});
  }
```

```dart
  /// Runs [id] now with trigger=manual. Does not move the alarm chain.
  static Future<void> runNow(String id) => channel.invokeMethod<void>('runNow', {'id': id});
```

`lib/dozeless.dart`:

```dart
export 'src/dozeless_api.dart';
export 'src/dispatcher.dart' show dozelessDispatcher;
export 'src/job_context.dart';
export 'src/models.dart';
```

- [ ] **Step 4: Jalankan test Dart**

Run: `flutter test` → Expected: `All tests passed!` (16 + 5 + 2 = 23)
Run: `flutter analyze` → Expected: `No issues found!`

- [ ] **Step 5: Implementasi sisi native**

`android/src/main/kotlin/io/github/xdaijobu/dozeless/DartRunner.kt`:

```kotlin
package io.github.xdaijobu.dozeless

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.FlutterCallbackInformation

internal sealed interface JobOutcome {
    data object Success : JobOutcome
    data object Timeout : JobOutcome
    data class Failed(val error: String) : JobOutcome
    data class EngineFailed(val error: String) : JobOutcome
}

/** Owns the cached headless engine that runs Dart job callbacks. Main thread only. */
internal object DartRunner {
    private const val STARTUP_TIMEOUT_MS = 15_000L
    private val main = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var ready = false
    private var starting = false
    private var startedAt = 0L
    private val waiting = ArrayList<(String?) -> Unit>()
    private val startupTimeout = Runnable { if (!ready) failAll("ENGINE_START_TIMEOUT") }

    /**
     * Calls the Dart callback behind [callbackHandle]. [onResult] fires once: when Dart returns, or when the
     * engine cannot start. If [shouldStart] is false by the time the engine is ready, the callback is skipped.
     */
    fun invoke(
        app: Context,
        callbackHandle: Long,
        jobId: String,
        ctx: Map<String, Any?>,
        shouldStart: () -> Boolean,
        onResult: (JobOutcome) -> Unit,
    ) {
        withEngine(app) { error ->
            when {
                error != null -> onResult(JobOutcome.EngineFailed(error))
                !shouldStart() -> onResult(JobOutcome.Timeout)
                else -> channel!!.invokeMethod(
                    "runJob",
                    mapOf("jobId" to jobId, "callbackHandle" to callbackHandle, "context" to ctx),
                    object : MethodChannel.Result {
                        override fun success(result: Any?) = onResult(JobOutcome.Success)
                        override fun error(code: String, message: String?, details: Any?) =
                            onResult(JobOutcome.Failed("$code: $message"))
                        override fun notImplemented() =
                            onResult(JobOutcome.Failed("NOT_IMPLEMENTED: dispatcher did not handle runJob"))
                    },
                )
            }
        }
    }

    private fun withEngine(app: Context, then: (String?) -> Unit) {
        if (ready) return then(null)
        waiting += then
        if (starting) return
        starting = true
        startedAt = SystemClock.elapsedRealtime()
        main.postDelayed(startupTimeout, STARTUP_TIMEOUT_MS)
        val handle = JobStore(app).dispatcherHandle
        if (handle == 0L) return failAll("DISPATCHER_NOT_INITIALIZED: open the app once so Dozeless.initialize() runs")
        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(app)
            loader.ensureInitializationCompleteAsync(app, null, main) {
                startEngine(app, handle, loader.findAppBundlePath())
            }
        } catch (e: Exception) {
            failAll("ENGINE_START_FAILED: $e")
        }
    }

    private fun startEngine(app: Context, handle: Long, bundlePath: String) {
        val info = FlutterCallbackInformation.lookupCallbackInformation(handle)
            ?: return failAll("DISPATCHER_NOT_FOUND: handle $handle; open the app once")
        try {
            val eng = FlutterEngine(app)
            val ch = MethodChannel(eng.dartExecutor.binaryMessenger, "dozeless/background")
            ch.setMethodCallHandler { call, result ->
                if (call.method == "dispatcherReady") {
                    result.success(null)
                    onReady()
                } else {
                    result.notImplemented()
                }
            }
            engine = eng
            channel = ch
            eng.dartExecutor.executeDartCallback(DartExecutor.DartCallback(app.assets, bundlePath, info))
        } catch (e: Exception) {
            failAll("ENGINE_START_FAILED: $e")
        }
    }

    private fun onReady() {
        main.removeCallbacks(startupTimeout)
        ready = true
        starting = false
        Log.i(TAG, "engine ready in ${SystemClock.elapsedRealtime() - startedAt}ms")
        flush(null)
    }

    private fun failAll(error: String) {
        main.removeCallbacks(startupTimeout)
        Log.e(TAG, "engine failed: $error")
        engine?.destroy()
        engine = null
        channel = null
        ready = false
        starting = false
        flush(error)
    }

    private fun flush(error: String?) {
        val callbacks = waiting.toList()
        waiting.clear()
        callbacks.forEach { it(error) }
    }
}
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/JobRunner.kt` (versi Task 5. Task 10 menulis ulang file ini dan menambahkan gerbang prasyarat):

```kotlin
package io.github.xdaijobu.dozeless

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log

/** The native flow of spec §3 "Alur native saat alarm berbunyi". Main thread only. */
internal object JobRunner {
    private val main = Handler(Looper.getMainLooper())
    private val locks = RunLocks()

    /** [onDone] must be called exactly once; it finishes the broadcast. */
    fun run(app: Context, id: String, trigger: String, scheduledAt: Long, firedAt: Long, onDone: () -> Unit) {
        val store = JobStore(app)
        val job = store.get(id)
        if (job == null) {
            Log.w(TAG, "fire id=$id ignored: job is not scheduled")
            onDone()
            return
        }
        Log.i(TAG, "fire id=$id trigger=$trigger delayMs=${firedAt - scheduledAt}")

        if (trigger != Triggers.MANUAL) {
            // Chain the next alarm before anything below can fail (spec §3 step 2).
            AlarmScheduler(app).armAndRecord(store, id, firedAt + job.spec.everyMs)
        }

        val token = locks.tryAcquire(id, SystemClock.elapsedRealtime(), staleAfterMs = job.spec.timeoutMs * 3)
        if (token == null) {
            Log.w(TAG, "skip id=$id: previous run still busy")
            store.update(id) { it.copy(skippedBusyCount = it.skippedBusyCount + 1) }
            onDone()
            return
        }

        val built = ContextBuilder.build(app, store.get(id) ?: job, trigger, scheduledAt, firedAt)
        val wakeLock = app.getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "dozeless:$id")
            .apply {
                setReferenceCounted(false)
                acquire(job.spec.timeoutMs + 5_000)
            }

        var finished = false
        lateinit var timeout: Runnable
        fun finish(outcome: JobOutcome) {
            if (finished) return
            finished = true
            main.removeCallbacks(timeout)
            val end = System.currentTimeMillis()
            val error = errorOf(outcome)
            store.update(id) {
                it.copy(
                    lastRunAt = firedAt,
                    lastFinishedAt = end,
                    lastDurationMs = end - firedAt,
                    lastError = error,
                    lastTrigger = trigger,
                    runCount = it.runCount + 1,
                )
            }
            Log.i(TAG, "done id=$id result=${error ?: "ok"} durMs=${end - firedAt}")
            if (wakeLock.isHeld) wakeLock.release()
            onDone()
        }
        timeout = Runnable { finish(JobOutcome.Timeout) }
        main.postDelayed(timeout, job.spec.timeoutMs)

        DartRunner.invoke(app, job.spec.callbackHandle, id, built.map, shouldStart = { !finished }) { outcome ->
            locks.release(id, token)
            finish(outcome)
        }
    }

    private fun errorOf(outcome: JobOutcome): String? = when (outcome) {
        JobOutcome.Success -> null
        JobOutcome.Timeout -> "JOB_TIMEOUT"
        is JobOutcome.Failed -> outcome.error
        is JobOutcome.EngineFailed -> "ENGINE_START_FAILED: ${outcome.error}"
    }
}
```

Catatan untuk reviewer: kunci dilepas saat Dart benar-benar kembali, **bukan** saat timeout. Akibatnya callback yang menggantung membuat run berikutnya `skippedBusy` sampai kunci basi (3× timeout). Lihat Review Focus #2.

`android/src/main/kotlin/io/github/xdaijobu/dozeless/JobReceiver.kt` (tulis ulang):

```kotlin
package io.github.xdaijobu.dozeless

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Receives job alarms and immediate dispatches, then hands over to [JobRunner]. */
class JobReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_RUN) return
        val id = intent.getStringExtra(EXTRA_JOB_ID) ?: return
        val trigger = intent.getStringExtra(EXTRA_TRIGGER) ?: Triggers.ALARM
        val firedAt = System.currentTimeMillis()
        val scheduledAt = intent.getLongExtra(EXTRA_SCHEDULED_AT, firedAt)
        val pending = goAsync()
        JobRunner.run(context.applicationContext, id, trigger, scheduledAt, firedAt) { pending.finish() }
    }

    companion object {
        const val ACTION_RUN = "io.github.xdaijobu.dozeless.RUN"
        const val EXTRA_JOB_ID = "jobId"
        const val EXTRA_TRIGGER = "trigger"
        const val EXTRA_SCHEDULED_AT = "scheduledAt"

        /** Runs [id] now through the same path as an alarm. Only for moments the device is awake. */
        fun dispatch(context: Context, id: String, trigger: String) {
            context.sendBroadcast(
                Intent(context, JobReceiver::class.java)
                    .setAction(ACTION_RUN)
                    .putExtra(EXTRA_JOB_ID, id)
                    .putExtra(EXTRA_TRIGGER, trigger)
                    .putExtra(EXTRA_SCHEDULED_AT, System.currentTimeMillis()),
            )
        }
    }
}
```

Di `DozelessPlugin.onMethodCall`, tambahkan dua cabang ini di awal `when`:

```kotlin
                "initialize" -> {
                    JobStore(app).dispatcherHandle = call.long("dispatcherHandle")
                    result.success(null)
                }
                "runNow" -> {
                    val id = call.str("id")
                    Jobs.requireJob(app, id)
                    JobReceiver.dispatch(app, id, Triggers.MANUAL)
                    result.success(null)
                }
```

- [ ] **Step 6: Compile native**

Run (dari `example/android`): `./gradlew :dozeless:testDebugUnitTest` → Expected: `BUILD SUCCESSFUL` (23 test Kotlin)

- [ ] **Step 7: Tulis integration test di HP**

`example/integration_test/dozeless_test.dart`. Test watchdog ditambahkan di Task 11:

```dart
import 'dart:isolate';
import 'dart:ui';

import 'package:dozeless/dozeless.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _portName = 'dozeless_it';
const _ids = ['it_ok', 'it_fail', 'it_slow'];

@pragma('vm:entry-point')
Future<void> okJob(JobContext ctx) async {
  IsolateNameServer.lookupPortByName(_portName)?.send({'id': ctx.jobId, 'trigger': ctx.trigger.name});
}

@pragma('vm:entry-point')
Future<void> failingJob(JobContext ctx) async => throw StateError('boom');

@pragma('vm:entry-point')
Future<void> slowJob(JobContext ctx) async => Future<void>.delayed(const Duration(seconds: 8));

Future<JobStatus> waitForStatus(String id, bool Function(JobStatus s) done) async {
  for (var i = 0; i < 60; i++) {
    final s = await Dozeless.status(id);
    if (s != null && done(s)) return s;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw TestFailure('status of $id never matched');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late ReceivePort port;
  late Stream<Object?> messages;

  /// Waits for a run of [id] with [trigger]; runs left over from an earlier, killed test run are skipped.
  Future<Map<Object?, Object?>> nextRun(String id, String trigger, Duration timeout) => messages
      .map((m) => m! as Map<Object?, Object?>)
      .firstWhere((m) => m['id'] == id && m['trigger'] == trigger)
      .timeout(timeout);

  setUp(() async {
    IsolateNameServer.removePortNameMapping(_portName);
    port = ReceivePort();
    IsolateNameServer.registerPortWithName(port.sendPort, _portName);
    messages = port.asBroadcastStream();
    // A killed run never reaches tearDown, so start from a clean slate.
    for (final id in _ids) {
      await Dozeless.cancel(id);
    }
    await Dozeless.initialize();
    if (!(await Dozeless.checkPrerequisites()).batteryUnrestricted) {
      fail('Battery is not unrestricted, so every job would stop. Run: '
          'adb shell dumpsys deviceidle whitelist +io.github.xdaijobu.dozeless_example '
          'and use flutter test --no-uninstall');
    }
  });

  tearDown(() async {
    for (final id in _ids) {
      await Dozeless.cancel(id);
    }
    port.close();
  });

  testWidgets('runNow runs the callback in the background engine', (tester) async {
    await Dozeless.schedule(id: 'it_ok', callback: okJob, every: const Duration(minutes: 15));
    await Dozeless.runNow('it_ok');
    await nextRun('it_ok', 'manual', const Duration(seconds: 30));
    final s = await waitForStatus('it_ok', (s) => s.runCount == 1);
    expect(s.lastError, isNull);
  });

  testWidgets('an alarm fires the callback and chains the next alarm', (tester) async {
    await Dozeless.schedule(id: 'it_ok', callback: okJob, every: const Duration(minutes: 15));
    await Dozeless.debugFireIn('it_ok', const Duration(seconds: 5));
    await nextRun('it_ok', 'alarm', const Duration(seconds: 90));
    final s = await waitForStatus('it_ok', (s) => s.runCount == 1);
    expect(s.nextRunAt!.isAfter(DateTime.now().add(const Duration(minutes: 14))), isTrue);
  });

  testWidgets('a throwing job records JOB_FAILED and keeps the chain', (tester) async {
    await Dozeless.schedule(id: 'it_fail', callback: failingJob, every: const Duration(minutes: 15));
    await Dozeless.debugFireIn('it_fail', const Duration(seconds: 5));
    final s = await waitForStatus('it_fail', (s) => s.runCount == 1);
    expect(s.lastError, startsWith('JOB_FAILED'));
    expect(s.nextRunAt!.isAfter(DateTime.now().add(const Duration(minutes: 14))), isTrue);
  });

  testWidgets('a job past its timeout records JOB_TIMEOUT', (tester) async {
    await Dozeless.schedule(
      id: 'it_slow',
      callback: slowJob,
      every: const Duration(minutes: 15),
      timeout: const Duration(seconds: 3),
    );
    await Dozeless.runNow('it_slow');
    final s = await waitForStatus('it_slow', (s) => s.runCount == 1);
    expect(s.lastError, 'JOB_TIMEOUT');
    expect(s.lastDurationMs, lessThan(6000));
  });
}
```

Dua job di test ini berkomunikasi lewat `IsolateNameServer`. Engine background dan engine test ada di Dart VM yang sama, jadi `SendPort` bisa ditemukan. `nextRun(id, trigger)` sengaja menyaring berdasarkan id dan trigger. Contohnya, kalau HP baru reboot, job sisa dari run test yang dibunuh akan jalan dengan `trigger=boot`, dan pesan itu tidak boleh dianggap hasil test.

- [ ] **Step 8: Jalankan integration test di HP**

Siapkan HP. Aktifkan USB debugging, dan di HyperOS juga "Install via USB". Pastikan `adb devices` menampilkan HP itu. Lalu dari `example/`:

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell dumpsys deviceidle whitelist +io.github.xdaijobu.dozeless_example
flutter test integration_test/dozeless_test.dart -d <DEVICE_ID> --no-uninstall
```

Expected: `All tests passed!` (4). Di terminal lain jalankan `adb logcat -s Dozeless:I flutter:I`. Harus terlihat `engine ready in …ms`, `fire id=it_ok trigger=alarm`, `done id=it_ok result=ok`, `done id=it_fail result=JOB_FAILED: Bad state: boom`, dan `done id=it_slow result=JOB_TIMEOUT`.

Tanpa `--no-uninstall`, `flutter test` meng-uninstall app setiap selesai, sehingga run berikutnya mulai dari install bersih tanpa whitelist. Kalau whitelist hilang, `setUp` gagal dengan pesan yang menyebut perintah perbaikannya. Kalau test gagal dengan `WebSocketChannelException` saat loading, cek `adb logcat | grep lowmemorykiller`. Kalau app ikut dibunuh, RAM emulator kurang (lihat "Cara pakai" #6).

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: run Dart job callbacks in a cached headless engine and await them"
```

---

### Task 6: Example app untuk uji kelayakan (lokasi + sqflite)

**Files:**
- Modify: `example/pubspec.yaml` (lewat `flutter pub add`)
- Modify: `example/android/app/build.gradle.kts` (`compileSdk = 37`)
- Modify: `example/android/app/src/main/AndroidManifest.xml` (permission)
- Create: `example/lib/spike_row.dart`, `example/lib/spike_db.dart`, `example/lib/spike_jobs.dart`, `example/lib/spike_stats.dart`
- Modify (tulis ulang): `example/lib/main.dart`
- Test: `example/test/spike_stats_test.dart`

**Interfaces:**
- Consumes: `Dozeless.initialize/schedule/cancel/status/runNow/debugFireIn/checkPrerequisites`, `JobContext`.
- Produces: job `spike` (setiap 1 menit, butuh lokasi dan lokasi background) dan `slow` (setiap 5 menit, `await` 20 detik), tabel `rows` di `spike.db`, kolom `fixAgeMs` (umur fix lokasi), `SpikeStats.compute(rows, jobId, interval, from, to)` dengan `passes` dan `withFreshLocation`, dan log `DOZELESS_ROW …` di logcat (tag `flutter`).

- [ ] **Step 1: Tambah dependency dan permission**

Dari `example/`:

```bash
flutter pub add geolocator sqflite path permission_handler
```

Versi saat plan ini diuji: geolocator ^14.1.2, sqflite ^2.4.5, path ^1.9.1, permission_handler ^13.0.2.

Di `example/android/app/build.gradle.kts`, ganti `compileSdk = flutter.compileSdkVersion` menjadi:

```kotlin
    compileSdk = 37
```

(`permission_handler_android` versi ini menolak build kalau compileSdk < 37. Kalau muncul `Failed to find target android-37`, pasang Android SDK Platform 37 lewat SDK Manager.)

Di `example/android/app/src/main/AndroidManifest.xml`, tambahkan tepat setelah tag pembuka `<manifest …>`:

```xml
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
    <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

Jangan tambahkan `android:installLocation`. Default-nya sudah internal.

- [ ] **Step 2: Tulis test statistik yang gagal**

`example/test/spike_stats_test.dart`:

```dart
import 'package:dozeless_example/spike_row.dart';
import 'package:dozeless_example/spike_stats.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime(2026, 10, 29, 10);

SpikeRow row(int minute,
    {int delayMs = 1000, String jobId = 'spike', String trigger = 'alarm', double? lat = -6.2, int? fixAgeMs = 3000}) {
  final firedAt = t0.add(Duration(minutes: minute)).millisecondsSinceEpoch;
  return SpikeRow(
    jobId: jobId,
    trigger: trigger,
    scheduledAt: firedAt - delayMs,
    firedAt: firedAt,
    delayMs: delayMs,
    startedAt: firedAt,
    finishedAt: firedAt + 2000,
    lat: lat,
    lon: lat == null ? null : 106.8,
    fixAgeMs: lat == null ? null : fixAgeMs,
    locationStatus: lat == null ? 'FAILED' : 'OK',
    deviceIdle: true,
    interactive: false,
    standbyBucket: 'active',
    mode: 'exact',
    batteryUnrestricted: true,
  );
}

SpikeStats stats(List<SpikeRow> rows) => SpikeStats.compute(
      rows,
      jobId: 'spike',
      interval: const Duration(minutes: 1),
      from: t0,
      to: t0.add(const Duration(minutes: 90)),
    );

void main() {
  test('a run every minute for 90 minutes passes', () {
    final s = stats([for (var m = 0; m < 90; m++) row(m)]);
    expect(s.expected, 90);
    expect(s.ran, 90);
    expect(s.medianDelayMs, 1000);
    expect(s.passes, isTrue);
  });

  test('fewer than 95% of the runs fails', () {
    final s = stats([for (var m = 0; m < 85; m++) row(m)]);
    expect(s.ranRatio, closeTo(0.944, 0.001));
    expect(s.passes, isFalse);
  });

  test('a median delay of 10 seconds or more fails', () {
    expect(stats([for (var m = 0; m < 90; m++) row(m, delayMs: 10000)]).passes, isFalse);
  });

  test('a row without location fails', () {
    expect(stats([for (var m = 0; m < 90; m++) row(m, lat: m == 40 ? null : -6.2)]).passes, isFalse);
  });

  test('median of an even count averages the middle two', () {
    expect(stats([row(0, delayMs: 1000), row(1, delayMs: 3000)]).medianDelayMs, 2000);
  });

  test('ignores other jobs, non-alarm triggers and rows outside the window', () {
    final s = stats([
      row(0),
      row(1, jobId: 'slow'),
      row(2, trigger: 'manual'),
      row(-1),
      row(90),
    ]);
    expect(s.ran, 1);
  });

  test('a cached fix older than two intervals counts as located but not fresh', () {
    final s = stats([row(0), row(1, fixAgeMs: 120000), row(2, fixAgeMs: 119999), row(3, lat: null)]);
    expect(s.withLocation, 3);
    expect(s.withFreshLocation, 2);
  });
}
```

- [ ] **Step 3: Jalankan dan pastikan gagal**

Run (dari `example/`): `flutter test test/spike_stats_test.dart` → Expected: FAIL, `spike_row.dart` belum ada.

- [ ] **Step 4: Implementasi**

`example/lib/spike_row.dart`:

```dart
/// One job run recorded by the feasibility app. Times are epoch milliseconds.
class SpikeRow {
  const SpikeRow({
    this.id,
    required this.jobId,
    required this.trigger,
    required this.scheduledAt,
    required this.firedAt,
    required this.delayMs,
    required this.startedAt,
    required this.finishedAt,
    this.lat,
    this.lon,
    this.accuracyM,
    this.fixAgeMs,
    required this.locationStatus,
    required this.deviceIdle,
    required this.interactive,
    required this.standbyBucket,
    required this.mode,
    required this.batteryUnrestricted,
    this.events = '',
    this.error,
  });

  factory SpikeRow.fromMap(Map<String, Object?> m) => SpikeRow(
        id: m['id'] as int?,
        jobId: m['jobId']! as String,
        trigger: m['trigger']! as String,
        scheduledAt: m['scheduledAt']! as int,
        firedAt: m['firedAt']! as int,
        delayMs: m['delayMs']! as int,
        startedAt: m['startedAt']! as int,
        finishedAt: m['finishedAt']! as int,
        lat: m['lat'] as double?,
        lon: m['lon'] as double?,
        accuracyM: m['accuracyM'] as double?,
        fixAgeMs: m['fixAgeMs'] as int?,
        locationStatus: m['locationStatus']! as String,
        deviceIdle: m['deviceIdle'] == 1,
        interactive: m['interactive'] == 1,
        standbyBucket: m['standbyBucket']! as String,
        mode: m['mode']! as String,
        batteryUnrestricted: m['batteryUnrestricted'] == 1,
        events: (m['events'] as String?) ?? '',
        error: m['error'] as String?,
      );

  final int? id;
  final String jobId;
  final String trigger;
  final int scheduledAt;
  final int firedAt;
  final int delayMs;
  final int startedAt;
  final int finishedAt;
  final double? lat;
  final double? lon;
  final double? accuracyM;

  /// How old the fix was when the job read it; large values mean a cached position.
  final int? fixAgeMs;

  /// OK · LAST_KNOWN · FAILED · SLOW
  final String locationStatus;
  final bool deviceIdle;
  final bool interactive;
  final String standbyBucket;
  final String mode;
  final bool batteryUnrestricted;

  /// Comma-separated `ctx.systemEvents` types.
  final String events;
  final String? error;

  Map<String, Object?> toMap() => {
        'jobId': jobId,
        'trigger': trigger,
        'scheduledAt': scheduledAt,
        'firedAt': firedAt,
        'delayMs': delayMs,
        'startedAt': startedAt,
        'finishedAt': finishedAt,
        'lat': lat,
        'lon': lon,
        'accuracyM': accuracyM,
        'fixAgeMs': fixAgeMs,
        'locationStatus': locationStatus,
        'deviceIdle': deviceIdle ? 1 : 0,
        'interactive': interactive ? 1 : 0,
        'standbyBucket': standbyBucket,
        'mode': mode,
        'batteryUnrestricted': batteryUnrestricted ? 1 : 0,
        'events': events,
        'error': error,
      };
}
```

`example/lib/spike_stats.dart`:

```dart
import 'spike_row.dart';

/// Pass/fail numbers for the "screen off 90 minutes" test (spec §9).
class SpikeStats {
  const SpikeStats({
    required this.expected,
    required this.ran,
    required this.medianDelayMs,
    required this.withLocation,
    required this.withFreshLocation,
  });

  /// Alarm runs of [jobId] fired in [from, to).
  factory SpikeStats.compute(
    List<SpikeRow> rows, {
    required String jobId,
    required Duration interval,
    required DateTime from,
    required DateTime to,
  }) {
    final runs = rows
        .where((r) =>
            r.jobId == jobId &&
            r.trigger == 'alarm' &&
            r.firedAt >= from.millisecondsSinceEpoch &&
            r.firedAt < to.millisecondsSinceEpoch)
        .toList();
    final delays = runs.map((r) => r.delayMs).toList()..sort();
    final mid = delays.length ~/ 2;
    final median = delays.isEmpty
        ? 0
        : delays.length.isOdd
            ? delays[mid]
            : (delays[mid - 1] + delays[mid]) ~/ 2;
    return SpikeStats(
      expected: to.difference(from).inMilliseconds ~/ interval.inMilliseconds,
      ran: runs.length,
      medianDelayMs: median,
      withLocation: runs.where((r) => r.lat != null).length,
      withFreshLocation:
          runs.where((r) => r.fixAgeMs != null && r.fixAgeMs! < 2 * interval.inMilliseconds).length,
    );
  }

  final int expected;
  final int ran;
  final int medianDelayMs;
  final int withLocation;

  /// Rows whose fix is younger than two intervals. Background apps may get cached positions.
  final int withFreshLocation;

  double get ranRatio => expected == 0 ? 0 : ran / expected;

  /// ≥ 95% of runs, median delay < 10 s, every row has a location.
  bool get passes => ranRatio >= 0.95 && medianDelayMs < 10000 && withLocation == ran;
}
```

`example/lib/spike_db.dart`:

```dart
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'spike_row.dart';

/// Rows written by background jobs and read by the UI.
class SpikeDb {
  static Database? _db;

  static Future<Database> _open() async => _db ??= await openDatabase(
        p.join(await getDatabasesPath(), 'spike.db'),
        version: 1,
        onCreate: (db, _) => db.execute('''
          CREATE TABLE rows(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            jobId TEXT NOT NULL, trigger TEXT NOT NULL,
            scheduledAt INTEGER NOT NULL, firedAt INTEGER NOT NULL, delayMs INTEGER NOT NULL,
            startedAt INTEGER NOT NULL, finishedAt INTEGER NOT NULL,
            lat REAL, lon REAL, accuracyM REAL, fixAgeMs INTEGER, locationStatus TEXT NOT NULL,
            deviceIdle INTEGER NOT NULL, interactive INTEGER NOT NULL, standbyBucket TEXT NOT NULL,
            mode TEXT NOT NULL, batteryUnrestricted INTEGER NOT NULL, events TEXT NOT NULL, error TEXT
          )'''),
      );

  static Future<void> insert(SpikeRow row) async => (await _open()).insert('rows', row.toMap());

  /// Newest first.
  static Future<List<SpikeRow>> since(DateTime from) async => [
        for (final m in await (await _open()).query(
          'rows',
          where: 'firedAt >= ?',
          whereArgs: [from.millisecondsSinceEpoch],
          orderBy: 'firedAt DESC',
        ))
          SpikeRow.fromMap(m),
      ];

  static Future<void> clear() async => (await _open()).delete('rows');
}
```

`example/lib/spike_jobs.dart`:

```dart
import 'package:dozeless/dozeless.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'spike_db.dart';
import 'spike_row.dart';

const spikeJobId = 'spike';
const slowJobId = 'slow';
const spikeInterval = Duration(minutes: 1);
const slowInterval = Duration(minutes: 5);

/// Feasibility job (spec §9): every minute, take a location and write a row.
@pragma('vm:entry-point')
Future<void> spikeJob(JobContext ctx) async {
  final startedAt = DateTime.now().millisecondsSinceEpoch;
  double? lat, lon, accuracy;
  int? fixAgeMs;
  var status = 'OK';
  String? error;
  try {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)),
    );
    (lat, lon, accuracy) = (p.latitude, p.longitude, p.accuracy);
    fixAgeMs = DateTime.now().difference(p.timestamp).inMilliseconds;
  } catch (e) {
    error = 'current: $e';
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) {
        status = 'FAILED';
      } else {
        (lat, lon, accuracy) = (last.latitude, last.longitude, last.accuracy);
        fixAgeMs = DateTime.now().difference(last.timestamp).inMilliseconds;
        status = 'LAST_KNOWN';
      }
    } catch (e2) {
      status = 'FAILED';
      error = '$error; last: $e2';
    }
  }
  await _save(ctx, startedAt,
      lat: lat, lon: lon, accuracy: accuracy, fixAgeMs: fixAgeMs, status: status, error: error);
}

/// Wake-lock test (spec §9): a job that deliberately awaits 20 seconds.
@pragma('vm:entry-point')
Future<void> slowJob(JobContext ctx) async {
  final startedAt = DateTime.now().millisecondsSinceEpoch;
  await Future<void>.delayed(const Duration(seconds: 20));
  await _save(ctx, startedAt, status: 'SLOW');
}

Future<void> _save(
  JobContext ctx,
  int startedAt, {
  double? lat,
  double? lon,
  double? accuracy,
  int? fixAgeMs,
  required String status,
  String? error,
}) async {
  final row = SpikeRow(
    jobId: ctx.jobId,
    trigger: ctx.trigger.name,
    scheduledAt: ctx.scheduledAt.millisecondsSinceEpoch,
    firedAt: ctx.firedAt.millisecondsSinceEpoch,
    delayMs: ctx.delayMs,
    startedAt: startedAt,
    finishedAt: DateTime.now().millisecondsSinceEpoch,
    lat: lat,
    lon: lon,
    accuracyM: accuracy,
    fixAgeMs: fixAgeMs,
    locationStatus: status,
    deviceIdle: ctx.device.deviceIdle,
    interactive: ctx.device.interactive,
    standbyBucket: ctx.device.standbyBucket,
    mode: ctx.mode.name,
    batteryUnrestricted: ctx.prerequisites.batteryUnrestricted,
    events: ctx.systemEvents.map((e) => e.type).join(','),
    error: error,
  );
  await SpikeDb.insert(row);
  debugPrint('DOZELESS_ROW job=${row.jobId} trigger=${row.trigger} delayMs=${row.delayMs} '
      'durMs=${row.finishedAt - row.startedAt} idle=${row.deviceIdle} loc=${row.locationStatus} '
      'fixAgeS=${row.fixAgeMs == null ? '-' : row.fixAgeMs! ~/ 1000} events=${row.events}');
}

Future<void> startSpike() async {
  await Dozeless.schedule(
    id: spikeJobId,
    callback: spikeJob,
    every: spikeInterval,
    requires: {Prereq.location, Prereq.backgroundLocation},
  );
  await Dozeless.schedule(id: slowJobId, callback: slowJob, every: slowInterval);
}

Future<void> stopSpike() async {
  await Dozeless.cancel(spikeJobId);
  await Dozeless.cancel(slowJobId);
}
```

`example/lib/main.dart` (versi fase 1. Task 9, 10, dan 11 mengubah beberapa baris):

```dart
import 'dart:async';

import 'package:dozeless/dozeless.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'spike_db.dart';
import 'spike_jobs.dart';
import 'spike_row.dart';
import 'spike_stats.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Dozeless.initialize();
  runApp(const MaterialApp(home: SpikePage()));
}

class SpikePage extends StatefulWidget {
  const SpikePage({super.key});

  @override
  State<SpikePage> createState() => _SpikePageState();
}

class _SpikePageState extends State<SpikePage> with WidgetsBindingObserver {
  PrerequisiteStatus? _prereqs;
  JobStatus? _spike;
  JobStatus? _slow;
  List<SpikeRow> _rows = const [];
  Duration _window = const Duration(minutes: 90);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final prereqs = await Dozeless.checkPrerequisites();
    final spike = await Dozeless.status(spikeJobId);
    final slow = await Dozeless.status(slowJobId);
    final rows = await SpikeDb.since(DateTime.now().subtract(const Duration(hours: 24)));
    if (!mounted) return;
    setState(() {
      _prereqs = prereqs;
      _spike = spike;
      _slow = slow;
      _rows = rows;
    });
  }

  Future<void> _act(Future<void> Function() action) async {
    await action();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final oldest = _rows.isEmpty ? now : DateTime.fromMillisecondsSinceEpoch(_rows.last.firedAt);
    final windowStart = now.subtract(_window);
    final from = oldest.isAfter(windowStart) ? oldest : windowStart;
    final stats = SpikeStats.compute(_rows, jobId: spikeJobId, interval: spikeInterval, from: from, to: now);
    final p = _prereqs;

    return Scaffold(
      appBar: AppBar(title: const Text('dozeless spike'), actions: [
        IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
      ]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Prasyarat', style: Theme.of(context).textTheme.titleMedium),
          if (p != null) ...[
            _check('Lokasi', p.location),
            _check('Lokasi sepanjang waktu', p.backgroundLocation),
            _check('Baterai tidak dibatasi', p.batteryUnrestricted),
            _check('Tidak "Dibatasi"', !p.backgroundRestricted),
            _check('Exact alarm', p.exactAlarm),
            _check('Notifikasi', p.notification),
          ],
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(onPressed: () => _act(Permission.location.request), child: const Text('Izin lokasi')),
            OutlinedButton(
                onPressed: () => _act(Permission.locationAlways.request), child: const Text('Lokasi sepanjang waktu')),
            OutlinedButton(onPressed: () => _act(Permission.notification.request), child: const Text('Notifikasi')),
            OutlinedButton(onPressed: () => _act(openAppSettings), child: const Text('App info (baterai)')),
          ]),
          const Divider(height: 32),
          Text('Job', style: Theme.of(context).textTheme.titleMedium),
          Text(_describe(spikeJobId, _spike)),
          Text(_describe(slowJobId, _slow)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(onPressed: () => _act(startSpike), child: const Text('Start')),
            OutlinedButton(onPressed: () => _act(stopSpike), child: const Text('Stop')),
            OutlinedButton(onPressed: () => _act(() => Dozeless.runNow(spikeJobId)), child: const Text('Jalankan sekarang')),
            OutlinedButton(
                onPressed: () => _act(() => Dozeless.debugFireIn(spikeJobId, const Duration(seconds: 10))),
                child: const Text('Alarm 10 detik lagi')),
            OutlinedButton(onPressed: () => _act(SpikeDb.clear), child: const Text('Hapus baris')),
          ]),
          const Divider(height: 32),
          Text('Statistik spike', style: Theme.of(context).textTheme.titleMedium),
          Wrap(spacing: 8, children: [
            for (final minutes in [30, 90])
              ChoiceChip(
                label: Text('$minutes menit'),
                selected: _window.inMinutes == minutes,
                onSelected: (_) => setState(() => _window = Duration(minutes: minutes)),
              ),
          ]),
          Text('Diharapkan ${stats.expected} · jalan ${stats.ran} (${(stats.ranRatio * 100).toStringAsFixed(1)}%)'),
          Text('Median telat ${(stats.medianDelayMs / 1000).toStringAsFixed(1)} s · berlokasi ${stats.withLocation} '
              '· segar ${stats.withFreshLocation}'),
          Text(stats.passes ? 'LULUS' : 'BELUM LULUS',
              style: TextStyle(color: stats.passes ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
          const Divider(height: 32),
          Text('Baris terakhir', style: Theme.of(context).textTheme.titleMedium),
          for (final r in _rows.take(50))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${_clock(r.firedAt)}  ${r.jobId}/${r.trigger}'),
              subtitle: Text('telat ${(r.delayMs / 1000).toStringAsFixed(1)} s · '
                  'durasi ${((r.finishedAt - r.startedAt) / 1000).toStringAsFixed(1)} s · ${r.locationStatus}'
                  '${r.fixAgeMs == null ? '' : ' (umur ${r.fixAgeMs! ~/ 1000} s)'} · '
                  'idle ${r.deviceIdle} · ${r.standbyBucket}${r.events.isEmpty ? '' : ' · ${r.events}'}'),
            ),
        ],
      ),
    );
  }

  Widget _check(String label, bool ok) => Row(children: [
        Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? Colors.green : Colors.red, size: 18),
        const SizedBox(width: 8),
        Text(label),
      ]);

  String _describe(String id, JobStatus? s) {
    if (s == null) return '$id: belum dijadwalkan';
    final next = s.nextRunAt == null ? '-' : _clock(s.nextRunAt!.millisecondsSinceEpoch);
    final missing = s.missing.isEmpty ? '' : ' · kurang ${s.missing.map((m) => m.name).join(',')}';
    return '$id: ${s.mode.name} · next $next · run ${s.runCount} · busy ${s.skippedBusyCount}'
        '${s.lastError == null ? '' : ' · error ${s.lastError}'}$missing';
  }

  static String _clock(int epochMs) => DateTime.fromMillisecondsSinceEpoch(epochMs).toIso8601String().substring(11, 19);
}
```

- [ ] **Step 5: Jalankan test, analyzer, dan build**

Run (dari `example/`): `flutter test` → Expected: `All tests passed!` (7)
Run: `flutter analyze` → Expected: `No issues found!`
Run: `flutter build apk --debug` → Expected: `√ Built build\app\outputs\flutter-apk\app-debug.apk`

- [ ] **Step 6: Coba di HP (sekitar 6 menit)**

1. `adb install -r build/app/outputs/flutter-apk/app-debug.apk` lalu buka app.
2. Tekan **Izin lokasi** → Izinkan. **Lokasi sepanjang waktu** → pilih "Izinkan sepanjang waktu". **Notifikasi** → Izinkan. **App info (baterai)** → Baterai / Penghemat baterai → **Tidak dibatasi**. Kembali ke app. Keenam prasyarat harus hijau. Exact alarm otomatis hijau setelah baterai tidak dibatasi.
3. Tekan **Start**. Di terminal: `adb logcat -s Dozeless:I flutter:I`
4. Expected dalam 2 menit: `fire id=spike trigger=alarm`, `DOZELESS_ROW job=spike trigger=alarm … loc=OK fixAgeS=0`, `done id=spike result=ok`. Setelah 5 menit: `DOZELESS_ROW job=slow … durMs=2xxxx … loc=SLOW`.
5. `adb shell dumpsys alarm | grep -A3 "dozeless://job/spike"` (PowerShell: `adb shell dumpsys alarm | Select-String "dozeless://job/spike" -Context 0,3`) menampilkan satu alarm `RTC_WAKEUP` untuk spike.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(example): feasibility app with location job, slow job and stats"
```

---

### Task 7: Pemulihan setelah boot, update app, dan force stop

**Files:**
- Modify: `android/src/main/kotlin/io/github/xdaijobu/dozeless/BootInfo.kt` (tambah `BootKind`, `BootDedupe`)
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/Reconciler.kt` (versi Task 7)
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/SystemEventReceiver.kt` (versi Task 7)
- Modify: `JobStore.kt` (`handledBoot`)
- Modify: `DozelessPlugin.kt` (`initialize` memanggil reconcile, cabang `reconcile`)
- Modify: `android/src/main/AndroidManifest.xml` (boot permission + receiver)
- Modify: `lib/src/dozeless_api.dart` (reconcile setiap app di-resume)
- Test: `android/src/test/kotlin/io/github/xdaijobu/dozeless/RecoveryTest.kt`, `test/dozeless_api_test.dart`

**Interfaces:**
- Consumes: `BootInfo.read`, `JobReceiver.dispatch`, `AlarmScheduler`, `SchedulePolicy.rearmAt`.
- Produces:
  - `enum class BootKind { FIRST_SEEN, SAME_BOOT, NEW_BOOT }`, `BootDedupe.classify(handled: BootInfo?, current: BootInfo): BootKind`
  - `ReconcilePolicy.Action { NONE, REARM }` + `ReconcilePolicy.decide(mode)`: semua job aktif selalu `REARM` (Task 10 memperluas: `STOP`, `RESUME`, parameter `missing`)
  - `Reconciler.reconcile(app)`, `Reconciler.restartAll(app, trigger): Set<String>`
  - `BootHandler.handleIfNew(app, viaBroadcast): Set<String>`
  - `JobStore.handledBoot: BootInfo?`
  - Channel `dozeless`: `reconcile` (tanpa argumen). Dart memanggilnya setiap app di-resume.

- [ ] **Step 1: Tulis test yang gagal**

`android/src/test/kotlin/io/github/xdaijobu/dozeless/RecoveryTest.kt`:

```kotlin
package io.github.xdaijobu.dozeless

import io.github.xdaijobu.dozeless.ReconcilePolicy.Action
import kotlin.test.Test
import kotlin.test.assertEquals

internal class RecoveryTest {
    @Test
    fun firstStartEverIsNotABoot() =
        assertEquals(BootKind.FIRST_SEEN, BootDedupe.classify(null, BootInfo(3, 1_000_000)))

    @Test
    fun bootCompletedAndQuickbootOnTheSameBootAreHandledOnce() =
        assertEquals(BootKind.SAME_BOOT, BootDedupe.classify(BootInfo(3, 1_000_000), BootInfo(3, 1_000_020)))

    @Test
    fun changingTheClockIsNotANewBootWhenBootCountIsKnown() =
        assertEquals(BootKind.SAME_BOOT, BootDedupe.classify(BootInfo(3, 1_000_000), BootInfo(3, 1_000_000 - 3_600_000)))

    @Test
    fun higherBootCountIsANewBoot() =
        assertEquals(BootKind.NEW_BOOT, BootDedupe.classify(BootInfo(3, 1_000_000), BootInfo(4, 1_000_500)))

    @Test
    fun withoutBootCountBootTimeWithinAMinuteIsTheSameBoot() {
        assertEquals(BootKind.SAME_BOOT, BootDedupe.classify(BootInfo(null, 1_000_000), BootInfo(null, 1_059_999)))
        assertEquals(BootKind.NEW_BOOT, BootDedupe.classify(BootInfo(null, 1_000_000), BootInfo(null, 1_060_000)))
    }

    // A force stop deletes the alarms but on Android 14 not the PendingIntents, so "armed" cannot be trusted.
    @Test
    fun reconcileRearmsEveryActiveJob() {
        assertEquals(Action.REARM, ReconcilePolicy.decide(Mode.EXACT))
        assertEquals(Action.REARM, ReconcilePolicy.decide(Mode.INEXACT))
        assertEquals(Action.NONE, ReconcilePolicy.decide(Mode.STOPPED))
    }
}
```

Di `test/dozeless_api_test.dart`, tambahkan `import 'package:flutter/widgets.dart';`, lalu ganti test `initialize sends the dispatcher handle` dengan:

```dart
  test('initialize sends the dispatcher handle, then reconciles on every resume', () async {
    await Dozeless.initialize();
    expect(calls.single.method, 'initialize');
    expect(calls.single.arguments, {'dispatcherHandle': 4242});

    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(calls.map((c) => c.method), ['initialize', 'reconcile']);
  });
```

- [ ] **Step 2: Jalankan dan pastikan gagal**

Run (dari `example/android`): `./gradlew :dozeless:testDebugUnitTest --tests "io.github.xdaijobu.dozeless.RecoveryTest"` → Expected: FAIL `Unresolved reference: BootDedupe`
Run: `flutter test test/dozeless_api_test.dart` → Expected: FAIL. Panggilan `reconcile` tidak pernah tercatat.

- [ ] **Step 3: Implementasi**

Tambahkan di akhir `BootInfo.kt`, beserta import `kotlin.math.abs` di bagian atas file:

```kotlin
internal enum class BootKind { FIRST_SEEN, SAME_BOOT, NEW_BOOT }

internal object BootDedupe {
    /** bootTime comes from two clocks and jitters, and moves when the user changes the clock. */
    private const val TOLERANCE_MS = 60_000L

    fun classify(handled: BootInfo?, current: BootInfo): BootKind = when {
        handled == null -> BootKind.FIRST_SEEN
        handled.bootCount != null && current.bootCount != null ->
            if (handled.bootCount == current.bootCount) BootKind.SAME_BOOT else BootKind.NEW_BOOT
        abs(handled.bootTime - current.bootTime) < TOLERANCE_MS -> BootKind.SAME_BOOT
        else -> BootKind.NEW_BOOT
    }
}
```

Di `JobStore.kt`, tambahkan property ini setelah `dispatcherHandle`:

```kotlin
    var handledBoot: BootInfo?
        get() = longOrNull(KEY_BOOT_TIME)?.let { BootInfo(prefs.getInt(KEY_BOOT_COUNT, -1).takeIf { c -> c >= 0 }, it) }
        set(value) = edit {
            putInt(KEY_BOOT_COUNT, value?.bootCount ?: -1)
            putLong(KEY_BOOT_TIME, value?.bootTime ?: 0L)
        }
```

dan konstanta ini ke `companion object`:

```kotlin
        const val KEY_BOOT_COUNT = "handledBootCount"
        const val KEY_BOOT_TIME = "handledBootTime"
```

Tambahkan juga helper ini tepat setelah fungsi `edit`. Property nullable berikutnya (Task 12, 13) ikut memakainya:

```kotlin
    private fun longOrNull(key: String): Long? = if (prefs.contains(key)) prefs.getLong(key, 0L) else null
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/Reconciler.kt` (versi Task 7):

```kotlin
package io.github.xdaijobu.dozeless

import android.content.Context
import android.util.Log

internal object ReconcilePolicy {
    enum class Action { NONE, REARM }

    /**
     * Active jobs are always re-armed: a force stop deletes every alarm, but on Android 14 the PendingIntents survive,
     * so "is it armed" cannot be trusted. Re-arming the same PendingIntent replaces the alarm and is harmless.
     */
    fun decide(mode: Mode): Action = if (mode != Mode.STOPPED) Action.REARM else Action.NONE
}

/** Runs when the app starts or comes back to the foreground (Dozeless.initialize and every resume). */
internal object Reconciler {
    fun reconcile(app: Context) {
        val dispatched = BootHandler.handleIfNew(app, viaBroadcast = false)
        val store = JobStore(app)
        val scheduler = AlarmScheduler(app)
        val now = System.currentTimeMillis()
        for (job in store.all()) {
            val id = job.spec.id
            if (id in dispatched) continue
            if (ReconcilePolicy.decide(job.state.mode) == ReconcilePolicy.Action.REARM) {
                val at = SchedulePolicy.rearmAt(job.state.nextRunAt, now)
                scheduler.armAndRecord(store, id, at)
                Log.i(TAG, "reconcile armed id=$id at=$at")
            }
        }
    }

    /** Boot or app update: run every active job now; each run re-arms its own chain. */
    fun restartAll(app: Context, trigger: String): Set<String> {
        val ids = JobStore(app).all().filter { it.state.mode != Mode.STOPPED }.map { it.spec.id }.toSet()
        ids.forEach { JobReceiver.dispatch(app, it, trigger) }
        return ids
    }
}

/** Handles each boot exactly once, from BOOT_COMPLETED or, if that never came, from the next app start. */
internal object BootHandler {
    fun handleIfNew(app: Context, viaBroadcast: Boolean): Set<String> {
        val store = JobStore(app)
        val boot = BootInfo.read(app)
        val kind = BootDedupe.classify(store.handledBoot, boot)
        if (kind == BootKind.SAME_BOOT) return emptySet()
        store.handledBoot = boot
        if (kind == BootKind.FIRST_SEEN) return emptySet()
        Log.i(TAG, "boot bootCount=${boot.bootCount} viaBroadcast=$viaBroadcast")
        return Reconciler.restartAll(app, Triggers.BOOT)
    }
}
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/SystemEventReceiver.kt` (versi Task 7):

```kotlin
package io.github.xdaijobu.dozeless

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/** Manifest receiver for boot and app update (spec §3 SystemEventReceiver). Never opens UI. */
class SystemEventReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, ACTION_QUICKBOOT_POWERON -> BootHandler.handleIfNew(app, viaBroadcast = true)
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                Log.i(TAG, "package replaced")
                Reconciler.restartAll(app, Triggers.PACKAGE_REPLACED)
            }
        }
    }

    private companion object {
        const val ACTION_QUICKBOOT_POWERON = "android.intent.action.QUICKBOOT_POWERON"
    }
}
```

Di `DozelessPlugin.onMethodCall`, ganti cabang `"initialize"` dan tambahkan `"reconcile"`:

```kotlin
                "initialize" -> {
                    JobStore(app).dispatcherHandle = call.long("dispatcherHandle")
                    Reconciler.reconcile(app)
                    result.success(null)
                }
                "reconcile" -> {
                    Reconciler.reconcile(app)
                    result.success(null)
                }
```

Di `AndroidManifest.xml`, tambahkan permission ini sebagai `uses-permission` pertama:

```xml
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
```

dan receiver ini di dalam `<application>` setelah `JobReceiver`. `exported="false"` tetap menerima broadcast dari sistem:

```xml
        <receiver
            android:name="io.github.xdaijobu.dozeless.SystemEventReceiver"
            android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
            </intent-filter>
        </receiver>
```

Di `lib/src/dozeless_api.dart`, tambahkan `import 'dart:async';`, field `static AppLifecycleListener? _lifecycle;` (di bawah `_idPattern`), lalu ganti `initialize` dengan:

```dart
  /// Call once in `main()` after `WidgetsFlutterBinding.ensureInitialized()`.
  /// Stores the dispatcher, repairs alarms lost to a force stop or an unseen
  /// reboot, and re-checks prerequisites every time the app is resumed.
  static Future<void> initialize() async {
    final handle = callbackHandleOf(dozelessDispatcher);
    if (handle == null) throw StateError('dozeless: dispatcher handle unavailable');
    await channel.invokeMethod<void>('initialize', {'dispatcherHandle': handle});
    _lifecycle ??= AppLifecycleListener(onResume: () => unawaited(channel.invokeMethod<void>('reconcile')));
  }
```

- [ ] **Step 4: Jalankan test dan pastikan lolos**

Run (dari `example/android`): `./gradlew :dozeless:testDebugUnitTest` → Expected: `BUILD SUCCESSFUL` (29 test)
Run: `flutter test` → Expected: `All tests passed!` (23)

- [ ] **Step 5: Cek di HP**

Build dan pasang ulang example (`flutter build apk --debug` + `adb install -r …`). Buka app sekali, pastikan job spike jalan, lalu jalankan `adb logcat -s Dozeless:I` di terminal lain.

1. **Force stop.** `adb shell am force-stop io.github.xdaijobu.dozeless_example`, lalu `adb shell dumpsys alarm | grep -c "dozeless://"` → `0`. Tunggu 2 menit: tidak ada `fire`. Buka app → `reconcile armed id=spike …` lalu `fire id=spike trigger=alarm` pada jadwal semula, atau sekitar 1 detik kemudian kalau jadwalnya sudah lewat. Di Android 14, PendingIntent selamat dari force stop sementara alarmnya hilang, jadi reconcile **selalu** memasang ulang alarm, bukan hanya kalau `isArmed()` false.
2. **Update tanpa membuka app.** Ubah `version:` di `example/pubspec.yaml` (misalnya `1.0.0+1` menjadi `1.0.1+2`), lalu `flutter build apk --debug` dan `adb install -r build/app/outputs/flutter-apk/app-debug.apk`. **Jangan buka app.** Expected: `package replaced`, `fire id=spike trigger=packageReplaced`, `fire id=slow trigger=packageReplaced`.
3. **Reboot.** Di HyperOS, aktifkan dulu Autostart untuk example: Keamanan → Aplikasi → Izin → Autostart. Lalu `adb reboot`. Setelah HP menyala, **jangan buka app**. `adb logcat -s Dozeless:I` → `boot bootCount=… viaBroadcast=true` lalu `fire id=spike trigger=boot`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: recover alarms after boot, app update and force stop"
```

---

### Task 8: Jalankan 6 uji kelayakan (gerbang GO / NO-GO)

**Files:**
- Create: `docs/feasibility-results.md`

**Interfaces:**
- Consumes: example app dari Task 6–7 yang terpasang di HP HyperOS, dengan semua prasyarat hijau dan Autostart aktif.
- Produces: keputusan GO / NO-GO yang tercatat. Fase 2 hanya dikerjakan kalau GO.

- [ ] **Step 1: Siapkan HP**

1. Pasang build terbaru, buka app, pastikan keenam prasyarat hijau.
2. `adb shell dumpsys deviceidle whitelist` memuat `io.github.xdaijobu.dozeless_example`.
3. Tekan **Hapus baris**, lalu **Start**.

- [ ] **Step 2: Uji 1, layar mati 90 menit**

1. **Cabut kabel USB.** Saat HP mengisi daya, Doze tidak aktif dan hasilnya tidak mewakili pemakaian nyata.
2. Kunci layar dan biarkan HP selama 90 menit.
3. Colok lagi, buka app, pilih chip **90 menit**. Catat angka "Diharapkan / jalan / median telat / berlokasi / segar" dan screenshot bagian statistik. Angka **segar** adalah jumlah baris dengan umur fix < 2 menit. Di emulator, angka ini anjlok begitu app ke background (lihat "Hasil uji di emulator" #4).
4. Lulus kalau tulisan **LULUS** muncul: ≥ 95% job jalan, median telat < 10 detik, semua baris punya lokasi.

- [ ] **Step 3: Uji 2, proses dibunuh**

1. Tekan Home supaya app ada di background. Jalankan `adb logcat -c` lalu `adb logcat -s Dozeless:I flutter:I`.
2. `adb shell am kill io.github.xdaijobu.dozeless_example`, lalu `adb shell pidof io.github.xdaijobu.dozeless_example` → harus kosong. App yang baru saja ke background sering belum dianggap aman dibunuh, sehingga `am kill` tidak berefek. Kalau begitu, pakai `adb shell run-as io.github.xdaijobu.dozeless_example kill -9 <pid>` (berlaku untuk build debug, setara dengan dibunuh lowmemorykiller).
3. Tunggu alarm berikutnya. Expected: `fire id=spike …`, `engine ready in Nms` dengan N < 5000, `done id=spike result=ok`.

- [ ] **Step 4: Uji 3, Doze**

1. Matikan layar.
2. `adb shell dumpsys battery unplug`, lalu `adb shell dumpsys deviceidle force-idle` → `Now forced in to deep idle mode`.
3. Tunggu 5 menit, lalu `adb shell dumpsys deviceidle unforce` dan `adb shell dumpsys battery reset`.
4. Buka app. Baris spike selama 5 menit itu menunjukkan `idle true` dan jalan setiap menit.

- [ ] **Step 5: Uji 4, reboot**

`adb reboot`, lalu **jangan buka app**. Setelah 3 menit: `adb logcat -d -s Dozeless:I | grep -E "boot|trigger=boot|trigger=alarm"`. Expected: `boot … viaBroadcast=true`, `fire id=spike trigger=boot`, lalu `trigger=alarm` setiap menit. Setelah itu buka app dan pastikan ada baris `spike/boot`.

- [ ] **Step 6: Uji 5, update app tanpa dibuka**

Naikkan `version:` example lagi, build, lalu `adb install -r …apk`, **jangan buka app**. Pakai `adb install -r`, bukan `flutter install`, karena `flutter install` bisa meng-uninstall app dan menghapus data. Expected di logcat: `fire id=spike trigger=packageReplaced`, `done id=spike result=ok`, lalu alarm per menit terus berjalan. Ini membuktikan callback handle masih valid.

- [ ] **Step 7: Uji 6, wake lock**

Layar mati minimal 11 menit, tanpa USB. Buka app. Ada minimal 2 baris `slow/alarm` dengan `durasi` ≥ 20 detik, dan status `slow` tidak menunjukkan error.

- [ ] **Step 8: Tulis hasil**

`docs/feasibility-results.md`:

```markdown
# Hasil uji kelayakan dozeless

Tanggal: <yyyy-mm-dd>
HP: <merek model>, HyperOS <versi>, Android <versi>
Commit: <git rev-parse --short HEAD>
Baterai example: Tidak dibatasi · Autostart: aktif · Exact alarm: <true/false>

| # | Uji | Lulus kalau | Hasil | Angka / bukti |
|---|-----|-------------|-------|---------------|
| 1 | Layar mati 90 menit | ≥ 95% job, median telat < 10 s, semua baris berlokasi | ✅/❌ | jalan X/Y (Z%), median N s, berlokasi M, **segar S** |
| 2 | Proses dibunuh | engine cold start < 5 s, job selesai | ✅/❌ | `engine ready in N ms` |
| 3 | Doze | alarm tetap berbunyi, `deviceIdle=true` tercatat | ✅/❌ | N baris idle selama 5 menit |
| 4 | Reboot | alarm terpasang lagi tanpa membuka app, job `boot` jalan | ✅/❌ | potongan logcat |
| 5 | Update tanpa dibuka | job tetap jalan | ✅/❌ | potongan logcat |
| 6 | Wake lock | job 20 s selesai tanpa terpotong | ✅/❌ | durasi baris slow |

## Keputusan

GO / NO-GO: <pilih>
Alasan: <satu paragraf>

## Kesegaran lokasi di background

Segar S dari M baris berlokasi (S/M = …%). Umur fix terbesar: … s.
Keputusan untuk tracking_jobs: <terima lokasi basi dan tandai STALE / pakai foreground service singkat saat Get / lainnya>
```

- [ ] **Step 9: Ambil keputusan**

- **GO** kalau keenam uji lulus. Lanjut ke Fase 2. Hasil "segar" di Uji 1 tidak memblokir GO untuk plugin, karena plugin hanya menjalankan job. Tapi angka itu **harus** dibawa ke diskusi desain `tracking_jobs` sebelum plan berikutnya dibuat.
- **NO-GO** kalau Uji 1 atau Uji 2 gagal. Sesuai spec §9, logika job harus pindah ke Kotlin dengan API `Dozeless.schedule` yang sama. **Hentikan plan ini** dan minta plan baru untuk callback Kotlin. Jangan improvisasi.
- Kalau yang gagal uji lain (3–6), debug dulu dengan superpowers:systematic-debugging, perbaiki, lalu ulangi uji yang gagal sebelum ke Fase 2.

- [ ] **Step 10: Commit**

```bash
git add docs/feasibility-results.md
git commit -m "docs: record feasibility results on HyperOS"
```

---

# FASE 2: Plugin lengkap (Task 9–14). Kerjakan hanya kalau Task 8 = GO.

### Task 9: `openSettings` (baterai, app info, exact alarm, Autostart)

**Files:**
- Modify (tulis ulang): `android/src/main/kotlin/io/github/xdaijobu/dozeless/SettingsOpener.kt`
- Modify: `DozelessPlugin.kt` (cabang `openSettings`)
- Modify: `lib/src/dozeless_api.dart` (`openSettings`)
- Modify: `example/lib/main.dart` (tombol pengaturan)
- Test: `android/src/test/kotlin/io/github/xdaijobu/dozeless/SettingsTargetsTest.kt`, `test/dozeless_api_test.dart`

**Interfaces:**
- Consumes: `AutostartIntents.candidates` (Task 4).
- Produces: `sealed interface SettingsTarget { Action(action, withPackage), Component(pkg, cls) }`, `SettingsTargets.of(setting, sdk, manufacturer): List<SettingsTarget>`, `SettingsOpener.open(context, setting): Boolean`, Dart `Dozeless.openSettings(Setting): Future<bool>`, channel `openSettings {setting}` → bool.

- [ ] **Step 1: Tulis test yang gagal**

`android/src/test/kotlin/io/github/xdaijobu/dozeless/SettingsTargetsTest.kt`:

```kotlin
package io.github.xdaijobu.dozeless

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

internal class SettingsTargetsTest {
    private val appDetails = SettingsTarget.Action("android.settings.APPLICATION_DETAILS_SETTINGS", withPackage = true)

    @Test
    fun batteryOpensTheOptimizationListThenFallsBackToAppDetails() = assertEquals(
        listOf(SettingsTarget.Action("android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS", withPackage = false), appDetails),
        SettingsTargets.of("batteryOptimization", 34, "Xiaomi"),
    )

    @Test
    fun exactAlarmPageOnlyExistsFromAndroid12() {
        assertEquals(listOf(appDetails), SettingsTargets.of("exactAlarm", 30, "Xiaomi"))
        assertEquals("android.settings.REQUEST_SCHEDULE_EXACT_ALARM", (SettingsTargets.of("exactAlarm", 31, "Xiaomi").first() as SettingsTarget.Action).action)
    }

    @Test
    fun autostartMatchesBrandIgnoringCase() = assertEquals(
        listOf(SettingsTarget.Component("com.miui.securitycenter", "com.miui.permcenter.autostart.AutoStartManagementActivity")),
        SettingsTargets.of("autostart", 34, "XIAOMI"),
    )

    @Test
    fun autostartIsEmptyForBrandsWithoutSuchPage() =
        assertTrue(SettingsTargets.of("autostart", 34, "samsung").isEmpty())

    @Test
    fun unknownSettingIsRejected() {
        assertFailsWith<IllegalArgumentException> { SettingsTargets.of("wifi", 34, "Xiaomi") }
    }
}
```

Tambahkan ke `test/dozeless_api_test.dart`:

```dart
  test('openSettings sends the setting name and returns the result', () async {
    reply = true;
    expect(await Dozeless.openSettings(Setting.autostart), isTrue);
    expect(calls.single.arguments, {'setting': 'autostart'});
  });
```

- [ ] **Step 2: Jalankan dan pastikan gagal**

Run (dari `example/android`): `./gradlew :dozeless:testDebugUnitTest --tests "io.github.xdaijobu.dozeless.SettingsTargetsTest"` → Expected: FAIL `Unresolved reference: SettingsTarget`
Run: `flutter test test/dozeless_api_test.dart` → Expected: FAIL, `openSettings` belum ada.

- [ ] **Step 3: Implementasi**

`android/src/main/kotlin/io/github/xdaijobu/dozeless/SettingsOpener.kt` (tulis ulang, `AutostartIntents` tetap sama):

```kotlin
package io.github.xdaijobu.dozeless

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log

/** OEM "Autostart" pages. Without Autostart these brands do not deliver BOOT_COMPLETED (spec §4). */
internal object AutostartIntents {
    fun candidates(manufacturer: String): List<Pair<String, String>> = when (manufacturer.lowercase()) {
        "xiaomi", "redmi", "poco" -> listOf(
            "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
        )
        "oppo", "realme" -> listOf(
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
            "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
        )
        "vivo" -> listOf(
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
        )
        else -> emptyList()
    }
}

/** A settings page to try, in order, until one opens. */
internal sealed interface SettingsTarget {
    data class Action(val action: String, val withPackage: Boolean) : SettingsTarget
    data class Component(val pkg: String, val cls: String) : SettingsTarget
}

internal object SettingsTargets {
    private val appDetails = SettingsTarget.Action("android.settings.APPLICATION_DETAILS_SETTINGS", withPackage = true)

    fun of(setting: String, sdk: Int, manufacturer: String): List<SettingsTarget> = when (setting) {
        "batteryOptimization" -> listOf(SettingsTarget.Action("android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS", withPackage = false), appDetails)
        "appDetails" -> listOf(appDetails)
        "exactAlarm" -> if (sdk >= Build.VERSION_CODES.S) {
            listOf(SettingsTarget.Action("android.settings.REQUEST_SCHEDULE_EXACT_ALARM", withPackage = true), appDetails)
        } else {
            listOf(appDetails)
        }
        "autostart" -> AutostartIntents.candidates(manufacturer).map { SettingsTarget.Component(it.first, it.second) }
        else -> throw IllegalArgumentException("unknown setting $setting")
    }
}

internal object SettingsOpener {
    /** Opens the first page that exists. Returns false if none could be opened. */
    fun open(context: Context, setting: String): Boolean {
        for (target in SettingsTargets.of(setting, Build.VERSION.SDK_INT, Build.MANUFACTURER)) {
            val intent = when (target) {
                is SettingsTarget.Action -> Intent(target.action).apply {
                    if (target.withPackage) data = Uri.parse("package:${context.packageName}")
                }
                is SettingsTarget.Component -> Intent().setComponent(ComponentName(target.pkg, target.cls))
            }.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(intent)
                return true
            } catch (e: ActivityNotFoundException) {
                Log.i(TAG, "settings target not found: $target")
            } catch (e: SecurityException) {
                Log.i(TAG, "settings target not allowed: $target")
            }
        }
        return false
    }
}
```

`resolveActivity` sengaja tidak dipakai. Di Android 11+ fungsi itu mengembalikan null untuk activity milik app lain (seperti Keamanan MIUI) kalau tidak ada `<queries>`, jadi plugin langsung mencoba `startActivity` dan menangkap error-nya.

Di `DozelessPlugin.onMethodCall`, tambahkan cabang ini setelah `"checkPrerequisites"`:

```kotlin
                "openSettings" -> result.success(SettingsOpener.open(app, call.str("setting")))
```

Di `lib/src/dozeless_api.dart`, tambahkan setelah `checkPrerequisites`:

```dart
  /// Returns false when this device has no such page.
  static Future<bool> openSettings(Setting setting) async =>
      (await channel.invokeMethod<bool>('openSettings', {'setting': setting.name})) ?? false;
```

Di `example/lib/main.dart`, ganti baris tombol `App info (baterai)`:

```dart
            OutlinedButton(onPressed: () => _act(openAppSettings), child: const Text('App info (baterai)')),
```

dengan:

```dart
            OutlinedButton(
                onPressed: () => _act(() => Dozeless.openSettings(Setting.batteryOptimization)),
                child: const Text('Optimasi baterai')),
            OutlinedButton(
                onPressed: () => _act(() => Dozeless.openSettings(Setting.appDetails)), child: const Text('App info')),
            if (p?.autostartSettingAvailable ?? false)
              OutlinedButton(
                  onPressed: () => _act(() => Dozeless.openSettings(Setting.autostart)), child: const Text('Autostart')),
```

- [ ] **Step 4: Jalankan test**

Run (dari `example/android`): `./gradlew :dozeless:testDebugUnitTest` → Expected: 34 test lolos
Run: `flutter test` → Expected: `All tests passed!` (24)
Run (dari `example/`): `flutter analyze` → Expected: `No issues found!`

- [ ] **Step 5: Cek di HP**

Pasang build baru dan buka app. Tekan **Optimasi baterai** (daftar optimasi baterai terbuka), **App info** (halaman info example terbuka), dan **Autostart** (di HyperOS, halaman Autostart terbuka). Kalau Autostart tidak terbuka dan logcat berisi `settings target not found`, cari nama activity yang benar dengan `adb shell dumpsys package com.miui.securitycenter | grep -i autostart`, perbarui `AutostartIntents`, lalu ulangi Step 4–5.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: open battery, app info, exact alarm and OEM autostart settings"
```

---

### Task 10: Berhenti saat prasyarat hilang, lanjut saat lengkap lagi

**Files:**
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/Notifier.kt`
- Modify (tulis ulang): `android/src/main/kotlin/io/github/xdaijobu/dozeless/JobRunner.kt`
- Modify (tulis ulang): `android/src/main/kotlin/io/github/xdaijobu/dozeless/Reconciler.kt`
- Modify: `JobStore.kt` (`stopText`)
- Modify: `DozelessPlugin.kt` (`initialize` menyimpan teks notifikasi)
- Modify: `lib/src/models.dart` (`StopNotification`), `lib/src/dozeless_api.dart` (`initialize({stopNotification})`)
- Modify: `example/lib/main.dart` (`initialize` dengan teks)
- Test: `RecoveryTest.kt`, `test/dozeless_api_test.dart`

**Interfaces:**
- Consumes: `PrereqReader.read`, `PrereqSnapshot.missing`, `JobSpec.effectiveRequires`.
- Produces:
  - `data class StopText(title, body, channelName)`, `Notifier.showStopped(context)`, `Notifier.clear(context)`, `JobStore.stopText`
  - `ReconcilePolicy.Action { NONE, REARM, STOP, RESUME }`, `ReconcilePolicy.decide(mode, missing: List<Prereq>)`
  - Dart `StopNotification({title, body, channelName})` + `toMap()` → `notificationTitle`, `notificationBody`, `notificationChannel`
  - Dart `Dozeless.initialize({StopNotification stopNotification = const StopNotification()})`
  - Perilaku: prasyarat hilang saat alarm → job `stopped` (alarm dibatalkan, `missing` dan `stoppedAt` diisi), notifikasi biasa muncul, callback dijalankan sekali dengan `trigger=prerequisiteLost`. App dibuka atau di-resume dengan prasyarat lengkap → mode `exact`, callback dijalankan dengan `trigger=resumed` dan `ctx.stoppedAt` terisi, notifikasi dihapus. Prasyarat hilang saat app dibuka (misalnya background restricted, yang membuat alarm tidak jalan sama sekali) → dispatch `prerequisiteLost`.

- [ ] **Step 1: Tulis test yang gagal**

Di `RecoveryTest.kt`, ganti test `reconcileRearmsEveryActiveJob` dengan:

```kotlin
    // A force stop deletes the alarms but on Android 14 not the PendingIntents, so "armed" cannot be trusted.
    @Test
    fun reconcileAlwaysRearmsEveryActiveJob() {
        assertEquals(Action.REARM, ReconcilePolicy.decide(Mode.EXACT, emptyList()))
        assertEquals(Action.REARM, ReconcilePolicy.decide(Mode.INEXACT, emptyList()))
    }

    @Test
    fun reconcileStopsAJobWhosePrerequisiteWentMissing() =
        assertEquals(Action.STOP, ReconcilePolicy.decide(Mode.INEXACT, listOf(Prereq.NOT_BACKGROUND_RESTRICTED)))

    @Test
    fun reconcileResumesAStoppedJobOnlyWhenNothingIsMissing() {
        assertEquals(Action.RESUME, ReconcilePolicy.decide(Mode.STOPPED, emptyList()))
        assertEquals(Action.NONE, ReconcilePolicy.decide(Mode.STOPPED, listOf(Prereq.LOCATION)))
    }
```

Di `test/dozeless_api_test.dart`, ganti test `initialize sends the dispatcher handle, then reconciles on every resume` dengan:

```dart
  test('initialize sends the dispatcher and notification text, then reconciles on every resume', () async {
    await Dozeless.initialize(stopNotification: const StopNotification(title: 'T', body: 'B', channelName: 'C'));
    expect(calls.single.method, 'initialize');
    expect(calls.single.arguments, {
      'dispatcherHandle': 4242,
      'notificationTitle': 'T',
      'notificationBody': 'B',
      'notificationChannel': 'C',
    });

    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpEventQueue();
    expect(calls.map((c) => c.method), ['initialize', 'reconcile']);
  });
```

- [ ] **Step 2: Jalankan dan pastikan gagal**

Run (dari `example/android`): `./gradlew :dozeless:testDebugUnitTest --tests "io.github.xdaijobu.dozeless.RecoveryTest"` → Expected: FAIL. `decide` belum menerima `missing`, dan `Action.STOP` belum ada.
Run: `flutter test test/dozeless_api_test.dart` → Expected: FAIL `Undefined name 'StopNotification'`

- [ ] **Step 3: Implementasi Dart**

Tambahkan di akhir `lib/src/models.dart`:

```dart
/// Text of the ordinary notification shown when jobs stop for a missing prerequisite.
class StopNotification {
  const StopNotification({
    this.title = 'Proses latar belakang berhenti',
    this.body = 'Buka aplikasi untuk memperbaiki pengaturan.',
    this.channelName = 'Status latar belakang',
  });

  final String title;
  final String body;
  final String channelName;

  Map<String, String> toMap() => {
        'notificationTitle': title,
        'notificationBody': body,
        'notificationChannel': channelName,
      };
}
```

Di `lib/src/dozeless_api.dart`, ganti `initialize` dengan:

```dart
  /// Call once in `main()` after `WidgetsFlutterBinding.ensureInitialized()`.
  /// Stores the dispatcher, repairs alarms lost to a force stop or an unseen
  /// reboot, and re-checks prerequisites every time the app is resumed.
  static Future<void> initialize({StopNotification stopNotification = const StopNotification()}) async {
    final handle = callbackHandleOf(dozelessDispatcher);
    if (handle == null) throw StateError('dozeless: dispatcher handle unavailable');
    await channel.invokeMethod<void>('initialize', {'dispatcherHandle': handle, ...stopNotification.toMap()});
    _lifecycle ??= AppLifecycleListener(onResume: () => unawaited(channel.invokeMethod<void>('reconcile')));
  }
```

Di `example/lib/main.dart`, ganti `await Dozeless.initialize();` dengan:

```dart
  await Dozeless.initialize(
    stopNotification: const StopNotification(
      title: 'Spike berhenti',
      body: 'Buka dozeless example untuk memperbaiki izin atau baterai.',
      channelName: 'Status spike',
    ),
  );
```

- [ ] **Step 4: Implementasi native**

`android/src/main/kotlin/io/github/xdaijobu/dozeless/Notifier.kt`:

```kotlin
package io.github.xdaijobu.dozeless

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import android.util.Log

internal data class StopText(val title: String, val body: String, val channelName: String)

/** The ordinary (dismissable) "jobs stopped" notification of spec §3 step 3. */
internal object Notifier {
    private const val CHANNEL_ID = "dozeless_status"
    private const val NOTIFICATION_ID = 46_101

    fun showStopped(context: Context) {
        val text = JobStore(context).stopText
        val manager = context.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, text.channelName, NotificationManager.IMPORTANCE_DEFAULT),
            )
        }
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val contentIntent = launch?.let {
            PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        val notification = builder
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(text.title)
            .setContentText(text.body)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()
        try {
            manager.notify(NOTIFICATION_ID, notification)
        } catch (e: SecurityException) {
            Log.w(TAG, "notification not allowed", e)
        }
    }

    fun clear(context: Context) {
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }
}
```

Di `JobStore.kt`, tambahkan property ini setelah `handledBoot`:

```kotlin
    var stopText: StopText
        get() = StopText(
            title = prefs.getString(KEY_NOTIFY_TITLE, null) ?: "Proses latar belakang berhenti",
            body = prefs.getString(KEY_NOTIFY_BODY, null) ?: "Buka aplikasi untuk memperbaiki pengaturan.",
            channelName = prefs.getString(KEY_NOTIFY_CHANNEL, null) ?: "Status latar belakang",
        )
        set(value) = edit {
            putString(KEY_NOTIFY_TITLE, value.title)
            putString(KEY_NOTIFY_BODY, value.body)
            putString(KEY_NOTIFY_CHANNEL, value.channelName)
        }
```

dan konstanta ini ke `companion object`:

```kotlin
        const val KEY_NOTIFY_TITLE = "notifyTitle"
        const val KEY_NOTIFY_BODY = "notifyBody"
        const val KEY_NOTIFY_CHANNEL = "notifyChannel"
```

Di `DozelessPlugin.onMethodCall`, ganti cabang `"initialize"` dengan:

```kotlin
                "initialize" -> {
                    val store = JobStore(app)
                    store.dispatcherHandle = call.long("dispatcherHandle")
                    store.stopText = StopText(call.str("notificationTitle"), call.str("notificationBody"), call.str("notificationChannel"))
                    Reconciler.reconcile(app)
                    result.success(null)
                }
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/JobRunner.kt` (tulis ulang. Task 11 dan 12 menambah beberapa baris):

```kotlin
package io.github.xdaijobu.dozeless

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log

/** The native flow of spec §3 "Alur native saat alarm berbunyi". Main thread only. */
internal object JobRunner {
    private val main = Handler(Looper.getMainLooper())
    private val locks = RunLocks()

    /** [onDone] must be called exactly once; it finishes the broadcast. */
    fun run(app: Context, id: String, trigger: String, scheduledAt: Long, firedAt: Long, onDone: () -> Unit) {
        val store = JobStore(app)
        val job = store.get(id)
        if (job == null) {
            Log.w(TAG, "fire id=$id ignored: job is not scheduled")
            onDone()
            return
        }
        Log.i(TAG, "fire id=$id trigger=$trigger delayMs=${firedAt - scheduledAt}")

        // Prerequisites (spec §3 step 3). A stopped job only comes back through Reconciler (trigger=resumed).
        val missing = PrereqReader.read(app).missing(job.spec.effectiveRequires)
        var runTrigger = trigger
        if (missing.isNotEmpty()) {
            if (job.state.mode == Mode.STOPPED) {
                Log.i(TAG, "skip id=$id: stopped, still missing $missing")
                onDone()
                return
            }
            AlarmScheduler(app).cancel(id)
            store.update(id) { it.copy(mode = Mode.STOPPED, missing = missing, stoppedAt = firedAt, nextRunAt = null) }
            Notifier.showStopped(app)
            runTrigger = Triggers.PREREQUISITE_LOST
            Log.w(TAG, "stop id=$id missing=$missing")
        } else if (job.state.mode == Mode.STOPPED) {
            Log.i(TAG, "skip id=$id: stopped until the app reconciles")
            onDone()
            return
        } else if (trigger != Triggers.MANUAL) {
            // Chain the next alarm before anything below can fail (spec §3 step 2).
            AlarmScheduler(app).armAndRecord(store, id, firedAt + job.spec.everyMs)
        }

        val token = locks.tryAcquire(id, SystemClock.elapsedRealtime(), staleAfterMs = job.spec.timeoutMs * 3)
        if (token == null) {
            Log.w(TAG, "skip id=$id: previous run still busy")
            store.update(id) { it.copy(skippedBusyCount = it.skippedBusyCount + 1) }
            onDone()
            return
        }

        val built = ContextBuilder.build(app, store.get(id) ?: job, runTrigger, scheduledAt, firedAt)
        val wakeLock = app.getSystemService(PowerManager::class.java)
            .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "dozeless:$id")
            .apply {
                setReferenceCounted(false)
                acquire(job.spec.timeoutMs + 5_000)
            }

        var finished = false
        lateinit var timeout: Runnable
        fun finish(outcome: JobOutcome) {
            if (finished) return
            finished = true
            main.removeCallbacks(timeout)
            val end = System.currentTimeMillis()
            val error = errorOf(outcome)
            store.update(id) {
                it.copy(
                    lastRunAt = firedAt,
                    lastFinishedAt = end,
                    lastDurationMs = end - firedAt,
                    lastError = error,
                    lastTrigger = runTrigger,
                    runCount = it.runCount + 1,
                    stoppedAt = if (runTrigger == Triggers.RESUMED && error == null) null else it.stoppedAt,
                )
            }
            Log.i(TAG, "done id=$id result=${error ?: "ok"} durMs=${end - firedAt}")
            if (wakeLock.isHeld) wakeLock.release()
            onDone()
        }
        timeout = Runnable { finish(JobOutcome.Timeout) }
        main.postDelayed(timeout, job.spec.timeoutMs)

        DartRunner.invoke(app, job.spec.callbackHandle, id, built.map, shouldStart = { !finished }) { outcome ->
            locks.release(id, token)
            finish(outcome)
        }
    }

    private fun errorOf(outcome: JobOutcome): String? = when (outcome) {
        JobOutcome.Success -> null
        JobOutcome.Timeout -> "JOB_TIMEOUT"
        is JobOutcome.Failed -> outcome.error
        is JobOutcome.EngineFailed -> "ENGINE_START_FAILED: ${outcome.error}"
    }
}
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/Reconciler.kt` (tulis ulang. `BootHandler` sama dengan Task 7):

```kotlin
package io.github.xdaijobu.dozeless

import android.content.Context
import android.util.Log

internal object ReconcilePolicy {
    enum class Action { NONE, REARM, STOP, RESUME }

    /**
     * Active jobs are always re-armed: a force stop deletes every alarm, but on Android 14 the PendingIntents survive,
     * so "is it armed" cannot be trusted. Re-arming the same PendingIntent replaces the alarm and is harmless.
     */
    fun decide(mode: Mode, missing: List<Prereq>): Action = when {
        mode == Mode.STOPPED && missing.isEmpty() -> Action.RESUME
        mode == Mode.STOPPED -> Action.NONE
        missing.isNotEmpty() -> Action.STOP
        else -> Action.REARM
    }
}

/** Runs when the app starts or comes back to the foreground (Dozeless.initialize and every resume). */
internal object Reconciler {
    fun reconcile(app: Context) {
        val dispatched = BootHandler.handleIfNew(app, viaBroadcast = false)
        val store = JobStore(app)
        val scheduler = AlarmScheduler(app)
        val prereqs = PrereqReader.read(app)
        val now = System.currentTimeMillis()
        for (job in store.all()) {
            val id = job.spec.id
            if (id in dispatched) continue
            when (ReconcilePolicy.decide(job.state.mode, prereqs.missing(job.spec.effectiveRequires))) {
                ReconcilePolicy.Action.REARM -> {
                    val at = SchedulePolicy.rearmAt(job.state.nextRunAt, now)
                    scheduler.armAndRecord(store, id, at)
                    Log.i(TAG, "reconcile armed id=$id at=$at")
                }
                ReconcilePolicy.Action.STOP -> JobReceiver.dispatch(app, id, Triggers.PREREQUISITE_LOST)
                ReconcilePolicy.Action.RESUME -> {
                    // Arm right away: resume often fires twice, and a second reconcile must see an armed job.
                    store.update(id) { it.copy(missing = emptyList()) }
                    scheduler.armAndRecord(store, id, now + job.spec.everyMs)
                    JobReceiver.dispatch(app, id, Triggers.RESUMED)
                    Log.i(TAG, "reconcile resumed id=$id")
                }
                ReconcilePolicy.Action.NONE -> Unit
            }
        }
        if (store.all().none { it.state.mode == Mode.STOPPED }) Notifier.clear(app)
    }

    /** Boot or app update: run every active job now; each run re-arms its own chain. */
    fun restartAll(app: Context, trigger: String): Set<String> {
        val ids = JobStore(app).all().filter { it.state.mode != Mode.STOPPED }.map { it.spec.id }.toSet()
        ids.forEach { JobReceiver.dispatch(app, it, trigger) }
        return ids
    }
}

/** Handles each boot exactly once, from BOOT_COMPLETED or, if that never came, from the next app start. */
internal object BootHandler {
    fun handleIfNew(app: Context, viaBroadcast: Boolean): Set<String> {
        val store = JobStore(app)
        val boot = BootInfo.read(app)
        val kind = BootDedupe.classify(store.handledBoot, boot)
        if (kind == BootKind.SAME_BOOT) return emptySet()
        store.handledBoot = boot
        if (kind == BootKind.FIRST_SEEN) return emptySet()
        Log.i(TAG, "boot bootCount=${boot.bootCount} viaBroadcast=$viaBroadcast")
        return Reconciler.restartAll(app, Triggers.BOOT)
    }
}
```

- [ ] **Step 5: Jalankan test**

Run (dari `example/android`): `./gradlew :dozeless:testDebugUnitTest` → Expected: 36 test lolos
Run: `flutter test` → Expected: `All tests passed!` (24)

- [ ] **Step 6: Cek di HP dengan adb**

Pasang build baru, buka app, pastikan spike jalan. Jalankan `adb logcat -s Dozeless:I flutter:I` di terminal lain.

1. **Baterai.** `adb shell dumpsys deviceidle whitelist -io.github.xdaijobu.dozeless_example`. Alarm berikutnya akan menghasilkan `stop id=spike missing=[BATTERY_UNRESTRICTED]`, `stop id=slow …`, dan baris `spike/prerequisiteLost`. Notifikasi "Spike berhenti" muncul, dan status di app menunjukkan `stopped · kurang batteryUnrestricted`.
2. **Pulihkan.** `adb shell dumpsys deviceidle whitelist +io.github.xdaijobu.dozeless_example`, lalu buka app. Expected: `reconcile resumed id=spike`, baris `spike/resumed`, notifikasi hilang, status kembali `exact`.
3. **Lokasi background dicabut.** `adb shell pm revoke io.github.xdaijobu.dozeless_example android.permission.ACCESS_BACKGROUND_LOCATION`. Expected: hanya `spike` yang berhenti (`missing=[BACKGROUND_LOCATION]`), `slow` tetap jalan. Izinkan lagi lewat tombol **Lokasi sepanjang waktu** → `reconcile resumed id=spike`.
4. **Dibatasi.** `adb shell cmd appops set io.github.xdaijobu.dozeless_example RUN_ANY_IN_BACKGROUND ignore`, lalu buka app. Expected: `stop id=spike missing=[NOT_BACKGROUND_RESTRICTED]`. Kembalikan dengan `adb shell cmd appops set io.github.xdaijobu.dozeless_example RUN_ANY_IN_BACKGROUND allow`, lalu keluar dan masuk lagi ke app → resumed.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: stop jobs with a notification when prerequisites are lost and resume them"
```

---

### Task 11: Watchdog per jam

**Files:**
- Modify: `SchedulePolicy.kt` (`onWatchdog`)
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/WatchdogReceiver.kt`
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/Housekeeping.kt`
- Modify: `JobRunner.kt`, `Jobs.kt` (tulis ulang), `DozelessPlugin.kt`, `Reconciler.kt` (`BootHandler`), `SystemEventReceiver.kt`, `AndroidManifest.xml`
- Modify: `lib/src/dozeless_api.dart` (helper debug), `example/lib/main.dart` (tombol simulasi)
- Test: `SchedulePolicyTest.kt`, `test/dozeless_api_test.dart`, `example/integration_test/dozeless_test.dart`

**Interfaces:**
- Consumes: `SchedulePolicy.Decision`, `AlarmScheduler`, `JobStore`.
- Produces: `SchedulePolicy.onWatchdog(nextRunAt, everyMs, now, armed): Decision`, `WatchdogReceiver.check(app)`, `ensureArmed(app)`, `cancel(app)`, `Housekeeping.onJobStart(app)`, `Jobs.debugSimulateLostAlarm(app, id)`, Dart `Dozeless.debugSimulateLostAlarm(id)`, `Dozeless.debugRunWatchdog()`, channel `debugSimulateLostAlarm {id}` dan `debugRunWatchdog`.

- [ ] **Step 1: Tulis test yang gagal**

Tambahkan ke `SchedulePolicyTest.kt`:

```kotlin
    @Test
    fun watchdogKeepsAHealthyChain() =
        assertEquals(Keep, SchedulePolicy.onWatchdog(now + 30_000, 60_000, now, armed = true))

    @Test
    fun watchdogToleratesUpToTwoIntervalsLate() =
        assertEquals(Keep, SchedulePolicy.onWatchdog(now - 120_000, 60_000, now, armed = true))

    @Test
    fun watchdogRunsAJobMoreThanTwoIntervalsLate() =
        assertEquals(ArmAt(now + REARM_DELAY_MS, Triggers.WATCHDOG), SchedulePolicy.onWatchdog(now - 120_001, 60_000, now, armed = true))

    @Test
    fun watchdogRearmsAVanishedAlarmThatIsNotLateYet() =
        assertEquals(ArmAt(now + 30_000), SchedulePolicy.onWatchdog(now + 30_000, 60_000, now, armed = false))
```

Tambahkan ke `test/dozeless_api_test.dart`:

```dart
  test('watchdog debug helpers call the plugin', () async {
    await Dozeless.debugSimulateLostAlarm('get');
    await Dozeless.debugRunWatchdog();
    expect(calls.map((c) => c.method), ['debugSimulateLostAlarm', 'debugRunWatchdog']);
    expect(calls.first.arguments, {'id': 'get'});
  });
```

Tambahkan sebagai test terakhir di `example/integration_test/dozeless_test.dart`:

```dart
  testWidgets('the watchdog re-runs a job whose alarm was lost', (tester) async {
    await Dozeless.schedule(id: 'it_ok', callback: okJob, every: const Duration(minutes: 15));
    await Dozeless.debugSimulateLostAlarm('it_ok');
    await Dozeless.debugRunWatchdog();
    await nextRun('it_ok', 'watchdog', const Duration(seconds: 90));
  });
```

- [ ] **Step 2: Jalankan dan pastikan gagal**

Run (dari `example/android`): `./gradlew :dozeless:testDebugUnitTest --tests "io.github.xdaijobu.dozeless.SchedulePolicyTest"` → Expected: FAIL `Unresolved reference: onWatchdog`
Run: `flutter test` → Expected: FAIL, `debugSimulateLostAlarm` belum ada.

- [ ] **Step 3: Implementasi**

Tambahkan ke `SchedulePolicy` di antara `onSchedule` dan `rearmAt`:

```kotlin
    /** Hourly watchdog (spec §3): overdue means the alarm is more than 2x the interval late. */
    fun onWatchdog(nextRunAt: Long?, everyMs: Long, now: Long, armed: Boolean): Decision = when {
        nextRunAt == null || now - nextRunAt > 2 * everyMs -> Decision.ArmAt(now + REARM_DELAY_MS, Triggers.WATCHDOG)
        !armed -> Decision.ArmAt(rearmAt(nextRunAt, now))
        else -> Decision.Keep
    }
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/WatchdogReceiver.kt`:

```kotlin
package io.github.xdaijobu.dozeless

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.util.Log

/** Hourly inexact alarm that repairs broken chains, replacing WorkManager (spec §3 WatchdogReceiver). */
class WatchdogReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_WATCHDOG) check(context.applicationContext)
    }

    companion object {
        private const val ACTION_WATCHDOG = "io.github.xdaijobu.dozeless.WATCHDOG"

        /** Overdue jobs fire in one second with trigger=watchdog; vanished alarms are re-armed. */
        internal fun check(app: Context) {
            val store = JobStore(app)
            val scheduler = AlarmScheduler(app)
            val now = System.currentTimeMillis()
            for (job in store.all()) {
                if (job.state.mode == Mode.STOPPED) continue
                val id = job.spec.id
                val d = SchedulePolicy.onWatchdog(job.state.nextRunAt, job.spec.everyMs, now, scheduler.isArmed(id))
                if (d is SchedulePolicy.Decision.ArmAt) {
                    scheduler.armAndRecord(store, id, d.at, d.trigger)
                    Log.w(TAG, "watchdog id=$id nextRunAt=${job.state.nextRunAt} -> ${d.trigger} at ${d.at}")
                }
            }
        }

        /** [force] re-arms even if the PendingIntent still exists; it can outlive a force stop that deleted the alarm. */
        internal fun ensureArmed(app: Context, force: Boolean = false) {
            if (!force && pendingIntent(app, PendingIntent.FLAG_NO_CREATE) != null) return
            app.getSystemService(AlarmManager::class.java).setInexactRepeating(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + AlarmManager.INTERVAL_HOUR,
                AlarmManager.INTERVAL_HOUR,
                pendingIntent(app, PendingIntent.FLAG_UPDATE_CURRENT)!!,
            )
            Log.i(TAG, "watchdog armed")
        }

        internal fun cancel(app: Context) {
            pendingIntent(app, PendingIntent.FLAG_NO_CREATE)?.let {
                app.getSystemService(AlarmManager::class.java).cancel(it)
                it.cancel()
            }
        }

        private fun pendingIntent(app: Context, flag: Int): PendingIntent? = PendingIntent.getBroadcast(
            app,
            0,
            Intent(app, WatchdogReceiver::class.java).setAction(ACTION_WATCHDOG),
            flag or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/Housekeeping.kt` (versi Task 11):

```kotlin
package io.github.xdaijobu.dozeless

import android.content.Context

/** Cheap upkeep at the start of every job run. */
internal object Housekeeping {
    fun onJobStart(app: Context) {
        WatchdogReceiver.ensureArmed(app)
    }
}
```

Di `JobRunner.kt`, tambahkan satu baris tepat sebelum `val built = ContextBuilder.build(...)`:

```kotlin
        Housekeeping.onJobStart(app)
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/Jobs.kt` (tulis ulang):

```kotlin
package io.github.xdaijobu.dozeless

import android.content.Context
import android.util.Log

/** Job operations called from the Dart API. */
internal object Jobs {
    fun schedule(app: Context, spec: JobSpec) {
        val store = JobStore(app)
        val scheduler = AlarmScheduler(app)
        val existing = store.get(spec.id)
        val state = existing?.state ?: JobState()
        when (val d = SchedulePolicy.onSchedule(existing, spec, System.currentTimeMillis(), scheduler.isArmed(spec.id))) {
            SchedulePolicy.Decision.Keep -> store.put(Job(spec, state))
            is SchedulePolicy.Decision.ArmAt -> {
                val mode = scheduler.arm(spec.id, d.at, d.trigger)
                store.put(Job(spec, state.copy(nextRunAt = d.at, mode = mode)))
                Log.i(TAG, "schedule id=${spec.id} everyMs=${spec.everyMs} next=${d.at} mode=${mode.wire}")
            }
        }
        WatchdogReceiver.ensureArmed(app)
    }

    fun cancel(app: Context, id: String) {
        AlarmScheduler(app).cancel(id)
        val store = JobStore(app)
        store.remove(id)
        if (store.all().isEmpty()) WatchdogReceiver.cancel(app)
        Log.i(TAG, "cancel id=$id")
    }

    fun requireJob(app: Context, id: String): Job =
        JobStore(app).get(id) ?: throw IllegalArgumentException("unknown job $id")

    fun debugFireIn(app: Context, id: String, delayMs: Long) {
        requireJob(app, id)
        AlarmScheduler(app).armAndRecord(JobStore(app), id, System.currentTimeMillis() + delayMs)
    }

    /** Debug: make the watchdog see a broken chain. */
    fun debugSimulateLostAlarm(app: Context, id: String) {
        val job = requireJob(app, id)
        AlarmScheduler(app).cancel(id)
        JobStore(app).update(id) { it.copy(nextRunAt = System.currentTimeMillis() - 3 * job.spec.everyMs) }
    }
}
```

Di `Reconciler.reconcile`, tambahkan baris ini sebagai baris pertama. App yang dibuka setelah force stop harus memasang ulang watchdog walaupun PendingIntent-nya masih ada:

```kotlin
        WatchdogReceiver.ensureArmed(app, force = true)
```

Di `DozelessPlugin.onMethodCall`, tambahkan dua cabang ini setelah `"debugFireIn"`:

```kotlin
                "debugSimulateLostAlarm" -> {
                    Jobs.debugSimulateLostAlarm(app, call.str("id"))
                    result.success(null)
                }
                "debugRunWatchdog" -> {
                    WatchdogReceiver.check(app)
                    result.success(null)
                }
```

Di `Reconciler.kt`, di dalam `BootHandler.handleIfNew`, tambahkan `WatchdogReceiver.ensureArmed(app)` tepat setelah `store.handledBoot = boot`. Alarm watchdog hilang setelah reboot.

Di `SystemEventReceiver.kt`, di cabang `ACTION_MY_PACKAGE_REPLACED`, tambahkan `WatchdogReceiver.ensureArmed(app)` sebelum `Reconciler.restartAll(...)`.

Di `AndroidManifest.xml`, tambahkan setelah receiver `JobReceiver`:

```xml
        <receiver
            android:name="io.github.xdaijobu.dozeless.WatchdogReceiver"
            android:exported="false" />
```

Di `lib/src/dozeless_api.dart`, tambahkan di akhir class `Dozeless`:

```dart
  /// Debug: cancel [id]'s alarm and mark it 3 intervals late, as if the OEM dropped it.
  static Future<void> debugSimulateLostAlarm(String id) =>
      channel.invokeMethod<void>('debugSimulateLostAlarm', {'id': id});

  /// Debug: run the hourly watchdog check now.
  static Future<void> debugRunWatchdog() => channel.invokeMethod<void>('debugRunWatchdog');
```

Di `example/lib/main.dart`, tambahkan tombol ini sebelum tombol `Hapus baris`:

```dart
            OutlinedButton(
                onPressed: () => _act(() async {
                      await Dozeless.debugSimulateLostAlarm(spikeJobId);
                      await Dozeless.debugRunWatchdog();
                    }),
                child: const Text('Simulasi alarm hilang')),
```

- [ ] **Step 4: Jalankan test**

Run (dari `example/android`): `./gradlew :dozeless:testDebugUnitTest` → Expected: 40 test lolos
Run: `flutter test` → Expected: `All tests passed!` (25)
Run (dari `example/`, HP terhubung): `flutter test integration_test/dozeless_test.dart -d <DEVICE_ID> --no-uninstall` → Expected: `All tests passed!` (5)

- [ ] **Step 5: Cek di HP**

`adb shell dumpsys alarm | grep -B1 -A4 "dozeless.WATCHDOG"` menampilkan alarm `ELAPSED_WAKEUP` dengan `repeatInterval=3600000`. Di app, tekan **Simulasi alarm hilang**. Expected di logcat: `watchdog id=spike … -> watchdog at …`, lalu `fire id=spike trigger=watchdog`.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: hourly watchdog that repairs broken alarm chains"
```

---

### Task 12: Antrean event sistem + perubahan jam dan zona waktu

**Files:**
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/EventLog.kt`
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/TimeJump.kt`
- Modify (tulis ulang): `ContextBuilder.kt`, `Housekeeping.kt`, `SystemEventReceiver.kt`
- Modify: `JobRunner.kt` (ack + prune), `Jobs.kt` (kursor job baru), `JobStore.kt` (`timeRef`, `lastTimezone`), `Reconciler.kt` (`BootHandler`), `AndroidManifest.xml`
- Test: `android/src/test/kotlin/io/github/xdaijobu/dozeless/EventsTest.kt`

**Interfaces:**
- Consumes: `JobState.ackedEventSeq`, `BuiltContext.deliveredSeq`.
- Produces:
  - `data class SystemEvent(seq, type, at, data)`, `EventLogPolicy.append/pending/nextAck/prune`, `EventLogPolicy.MAX_EVENTS = 500`, `EventCodec.encodeAll/decodeAll/toMap`, `EventStore(context).lastSeq/all/append/pendingFor/prune`
  - `TimeJump.jumpMs(refWall, refElapsed, nowWall, nowElapsed): Long?`, `TimeJump.isSignificant(jumpMs, autoTime)`, `TimeJump.SIGNIFICANT_MS = 60000`
  - `JobStore.timeRef: Pair<Long, Long>?` (wall, elapsed), `JobStore.lastTimezone: String?`
  - Event `timeChanged {jumpMs, autoTime}` dan `timezoneChanged {from, to}` di `ctx.systemEvents`. Kalau jam bergeser cukup jauh (signifikan), semua job aktif jalan sekitar 1 detik kemudian dengan `trigger=timeChanged`.

- [ ] **Step 1: Tulis test yang gagal**

`android/src/test/kotlin/io/github/xdaijobu/dozeless/EventsTest.kt` (test `exitReasonNames` ditambahkan di Task 13):

```kotlin
package io.github.xdaijobu.dozeless

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class EventsTest {
    private fun log(vararg seqs: Long) = seqs.map { SystemEvent(it, "boot", it * 10, emptyMap()) }

    @Test
    fun appendNumbersEventsAfterTheLastSeq() {
        val (events, seq) = EventLogPolicy.append(log(1, 2), lastSeq = 2, type = "timeChanged", at = 99, data = mapOf("jumpMs" to -3_600_000L))
        assertEquals(3, seq)
        assertEquals(listOf(1L, 2L, 3L), events.map { it.seq })
    }

    @Test
    fun appendDropsTheOldestBeyondTheCap() {
        val full = (1L..EventLogPolicy.MAX_EVENTS).map { SystemEvent(it, "processExit", it, emptyMap()) }
        val (events, _) = EventLogPolicy.append(full, EventLogPolicy.MAX_EVENTS.toLong(), "boot", 0, emptyMap())
        assertEquals(EventLogPolicy.MAX_EVENTS, events.size)
        assertEquals(2L, events.first().seq)
    }

    @Test
    fun pendingIsEverythingAfterTheJobsCursor() =
        assertEquals(listOf(3L, 4L), EventLogPolicy.pending(log(2, 3, 4), ackedSeq = 2).map { it.seq })

    @Test
    fun aNewJobStartingAtLastSeqSeesNoOlderEvents() =
        assertEquals(emptyList(), EventLogPolicy.pending(log(1, 2, 3), ackedSeq = 3))

    @Test
    fun aSuccessfulRunAcknowledgesWhatItWasGiven() =
        assertEquals(7L, EventLogPolicy.nextAck(acked = 4, delivered = 7, succeeded = true))

    @Test
    fun aFailedRunAcknowledgesNothingSoEventsComeAgain() =
        assertEquals(4L, EventLogPolicy.nextAck(acked = 4, delivered = 7, succeeded = false))

    @Test
    fun pruneKeepsWhatTheSlowestJobHasNotSeen() =
        assertEquals(listOf(3L, 4L), EventLogPolicy.prune(log(1, 2, 3, 4), ackedSeqs = listOf(4L, 2L)).map { it.seq })

    @Test
    fun pruneWithoutJobsClearsTheLog() =
        assertEquals(emptyList(), EventLogPolicy.prune(log(1, 2), ackedSeqs = emptyList()))

    @Test
    fun codecRoundTripsDataIncludingNulls() {
        val events = listOf(
            SystemEvent(1, "timezoneChanged", 5, mapOf("from" to null, "to" to "Asia/Jakarta")),
            SystemEvent(2, "timeChanged", 6, mapOf("jumpMs" to -3_600_000L, "autoTime" to false)),
        )
        assertEquals(events, EventCodec.decodeAll(EventCodec.encodeAll(events)))
    }

    @Test
    fun noJumpWhenBothClocksMovedTogether() =
        assertEquals(0L, TimeJump.jumpMs(refWall = 1_000_000, refElapsed = 5_000, nowWall = 1_060_000, nowElapsed = 65_000))

    @Test
    fun clockSetBackOneHourIsANegativeJump() =
        assertEquals(-3_600_000L, TimeJump.jumpMs(refWall = 10_000_000, refElapsed = 5_000, nowWall = 6_460_000, nowElapsed = 65_000))

    @Test
    fun referenceFromAnEarlierBootGivesNoJump() =
        assertNull(TimeJump.jumpMs(refWall = 1_000_000, refElapsed = 900_000, nowWall = 2_000_000, nowElapsed = 10_000))

    @Test
    fun smallCorrectionsWithAutomaticTimeAreIgnored() {
        assertFalse(TimeJump.isSignificant(59_999, autoTime = true))
        assertTrue(TimeJump.isSignificant(-60_000, autoTime = true))
        assertFalse(TimeJump.isSignificant(null, autoTime = true))
    }

    @Test
    fun anyChangeWithAutomaticTimeOffIsSignificant() =
        assertTrue(TimeJump.isSignificant(1_000, autoTime = false))
}
```

- [ ] **Step 2: Jalankan dan pastikan gagal**

Run (dari `example/android`): `./gradlew :dozeless:testDebugUnitTest --tests "io.github.xdaijobu.dozeless.EventsTest"` → Expected: FAIL `Unresolved reference: SystemEvent`

- [ ] **Step 3: Implementasi bagian murni**

`android/src/main/kotlin/io/github/xdaijobu/dozeless/EventLog.kt`:

```kotlin
package io.github.xdaijobu.dozeless

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/** Something the plugin saw outside a job run; delivered once to every job through `ctx.systemEvents`. */
internal data class SystemEvent(val seq: Long, val type: String, val at: Long, val data: Map<String, Any?>)

internal object EventLogPolicy {
    const val MAX_EVENTS = 500

    fun append(events: List<SystemEvent>, lastSeq: Long, type: String, at: Long, data: Map<String, Any?>): Pair<List<SystemEvent>, Long> {
        val seq = lastSeq + 1
        return (events + SystemEvent(seq, type, at, data)).takeLast(MAX_EVENTS) to seq
    }

    fun pending(events: List<SystemEvent>, ackedSeq: Long): List<SystemEvent> = events.filter { it.seq > ackedSeq }

    /** A failed run acknowledges nothing, so the same events are delivered again next time. */
    fun nextAck(acked: Long, delivered: Long, succeeded: Boolean): Long = if (succeeded) maxOf(acked, delivered) else acked

    /** Keeps what at least one job has not acknowledged yet. */
    fun prune(events: List<SystemEvent>, ackedSeqs: Collection<Long>): List<SystemEvent> {
        val min = ackedSeqs.minOrNull() ?: return emptyList()
        return events.filter { it.seq > min }
    }
}

internal object EventCodec {
    fun encodeAll(events: List<SystemEvent>): String = JSONArray(
        events.map { e ->
            val data = JSONObject()
            e.data.forEach { (k, v) -> data.put(k, v ?: JSONObject.NULL) }
            JSONObject().put("seq", e.seq).put("type", e.type).put("at", e.at).put("data", data)
        },
    ).toString()

    fun decodeAll(json: String?): List<SystemEvent> {
        if (json.isNullOrEmpty()) return emptyList()
        val array = JSONArray(json)
        return List(array.length()) { i ->
            val o = array.getJSONObject(i)
            val d = o.getJSONObject("data")
            SystemEvent(
                seq = o.getLong("seq"),
                type = o.getString("type"),
                at = o.getLong("at"),
                data = d.keys().asSequence().associateWith { k ->
                    when (val v = d.get(k)) {
                        JSONObject.NULL -> null
                        is Int -> v.toLong()
                        else -> v
                    }
                },
            )
        }
    }

    fun toMap(e: SystemEvent): Map<String, Any?> = mapOf("seq" to e.seq, "type" to e.type, "at" to e.at, "data" to e.data)
}

internal class EventStore(context: Context) {
    private val prefs = context.getSharedPreferences("dozeless_events", Context.MODE_PRIVATE)

    val lastSeq: Long get() = prefs.getLong(KEY_LAST_SEQ, 0L)

    fun all(): List<SystemEvent> = EventCodec.decodeAll(prefs.getString(KEY_EVENTS, null))

    fun append(type: String, at: Long, data: Map<String, Any?>) {
        val (events, seq) = EventLogPolicy.append(all(), lastSeq, type, at, data)
        prefs.edit().putString(KEY_EVENTS, EventCodec.encodeAll(events)).putLong(KEY_LAST_SEQ, seq).commit()
        Log.i(TAG, "event #$seq $type $data")
    }

    fun pendingFor(ackedSeq: Long): List<SystemEvent> = EventLogPolicy.pending(all(), ackedSeq)

    fun prune(ackedSeqs: Collection<Long>) {
        prefs.edit().putString(KEY_EVENTS, EventCodec.encodeAll(EventLogPolicy.prune(all(), ackedSeqs))).commit()
    }

    private companion object {
        const val KEY_EVENTS = "events"
        const val KEY_LAST_SEQ = "lastSeq"
    }
}
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/TimeJump.kt`:

```kotlin
package io.github.xdaijobu.dozeless

import kotlin.math.abs

internal object TimeJump {
    const val SIGNIFICANT_MS = 60_000L

    /** How far the wall clock moved relative to elapsedRealtime, or null if the reference is from an earlier boot. */
    fun jumpMs(refWall: Long, refElapsed: Long, nowWall: Long, nowElapsed: Long): Long? =
        if (nowElapsed < refElapsed) null else (nowWall - refWall) - (nowElapsed - refElapsed)

    /** Spec §6 TIME_CHANGED: a jump of at least 60 s, or any change while automatic time is off. */
    fun isSignificant(jumpMs: Long?, autoTime: Boolean): Boolean =
        !autoTime || (jumpMs != null && abs(jumpMs) >= SIGNIFICANT_MS)
}
```

- [ ] **Step 4: Jalankan test bagian murni**

Run (dari `example/android`): `./gradlew :dozeless:testDebugUnitTest` → Expected: 54 test lolos

- [ ] **Step 5: Sambungkan ke Android**

`android/src/main/kotlin/io/github/xdaijobu/dozeless/ContextBuilder.kt` (tulis ulang):

```kotlin
package io.github.xdaijobu.dozeless

import android.content.Context

internal class BuiltContext(val map: Map<String, Any?>, val deliveredSeq: Long)

/** Builds the map that becomes `JobContext` in Dart (spec §3 JobContext table). */
internal object ContextBuilder {
    fun build(app: Context, job: Job, trigger: String, scheduledAt: Long, firedAt: Long): BuiltContext {
        val boot = BootInfo.read(app)
        val s = job.state
        val events = EventStore(app).pendingFor(s.ackedEventSeq)
        val map = mapOf(
            "jobId" to job.spec.id,
            "trigger" to trigger,
            "scheduledAt" to scheduledAt,
            "firedAt" to firedAt,
            "delayMs" to firedAt - scheduledAt,
            "timeoutMs" to job.spec.timeoutMs,
            "mode" to s.mode.wire,
            "lastRunAt" to s.lastRunAt,
            "lastError" to s.lastError,
            "stoppedAt" to s.stoppedAt,
            "boot" to mapOf(
                "bootCount" to boot.bootCount,
                "bootTime" to boot.bootTime,
                "firstJobSinceBoot" to boot.isFirstRunSinceBoot(s.lastRunAt),
            ),
            "systemEvents" to events.map(EventCodec::toMap),
            "prerequisites" to PrereqReader.read(app).toMap(),
            "device" to DeviceState.read(app),
        )
        return BuiltContext(map, deliveredSeq = events.maxOfOrNull { it.seq } ?: s.ackedEventSeq)
    }
}
```

Di `JobRunner.kt`, di dalam `finish`, tambahkan baris `ackedEventSeq = …` ke `copy(...)` dan baris `EventStore(...).prune(...)` setelah `store.update`. Hasilnya:

```kotlin
            store.update(id) {
                it.copy(
                    lastRunAt = firedAt,
                    lastFinishedAt = end,
                    lastDurationMs = end - firedAt,
                    lastError = error,
                    lastTrigger = runTrigger,
                    runCount = it.runCount + 1,
                    ackedEventSeq = EventLogPolicy.nextAck(it.ackedEventSeq, built.deliveredSeq, succeeded = error == null),
                    stoppedAt = if (runTrigger == Triggers.RESUMED && error == null) null else it.stoppedAt,
                )
            }
            EventStore(app).prune(store.all().map { it.state.ackedEventSeq })
```

Di `Jobs.schedule`, ganti `val state = existing?.state ?: JobState()` dengan:

```kotlin
        // A new job starts after the newest event, so it never receives events from before it existed.
        val state = existing?.state ?: JobState(ackedEventSeq = EventStore(app).lastSeq)
```

Di `JobStore.kt`, tambahkan property ini setelah `stopText`:

```kotlin
    /** Wall clock and elapsedRealtime read at the same moment, to measure clock jumps. */
    var timeRef: Pair<Long, Long>?
        get() = longOrNull(KEY_REF_WALL)?.let { it to prefs.getLong(KEY_REF_ELAPSED, 0L) }
        set(value) {
            if (value != null) edit { putLong(KEY_REF_WALL, value.first).putLong(KEY_REF_ELAPSED, value.second) }
        }

    var lastTimezone: String?
        get() = prefs.getString(KEY_TIMEZONE, null)
        set(value) = edit { putString(KEY_TIMEZONE, value) }
```

dan konstanta ini ke `companion object`:

```kotlin
        const val KEY_REF_WALL = "timeRefWall"
        const val KEY_REF_ELAPSED = "timeRefElapsed"
        const val KEY_TIMEZONE = "lastTimezone"
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/Housekeeping.kt` (tulis ulang):

```kotlin
package io.github.xdaijobu.dozeless

import android.content.Context
import android.os.SystemClock
import java.util.TimeZone

/** Cheap upkeep at the start of every job run. */
internal object Housekeeping {
    fun onJobStart(app: Context) {
        WatchdogReceiver.ensureArmed(app)
        val store = JobStore(app)
        store.timeRef = System.currentTimeMillis() to SystemClock.elapsedRealtime()
        if (store.lastTimezone == null) store.lastTimezone = TimeZone.getDefault().id
    }
}
```

Di `Reconciler.kt`, tambahkan `import android.os.SystemClock`, lalu di `BootHandler.handleIfNew` sisipkan baris ini tepat setelah `store.handledBoot = boot`. Referensi jam dari boot sebelumnya tidak valid lagi.

```kotlin
        store.timeRef = System.currentTimeMillis() to SystemClock.elapsedRealtime()
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/SystemEventReceiver.kt` (tulis ulang):

```kotlin
package io.github.xdaijobu.dozeless

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import java.util.TimeZone

/** Manifest receiver for boot, app update and clock changes (spec §3 SystemEventReceiver). Never opens UI. */
class SystemEventReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, ACTION_QUICKBOOT_POWERON -> BootHandler.handleIfNew(app, viaBroadcast = true)
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                Log.i(TAG, "package replaced")
                WatchdogReceiver.ensureArmed(app)
                Reconciler.restartAll(app, Triggers.PACKAGE_REPLACED)
            }
            Intent.ACTION_TIME_CHANGED -> onTimeSet(app)
            Intent.ACTION_TIMEZONE_CHANGED -> onTimezoneChanged(app, intent.getStringExtra(EXTRA_TIME_ZONE))
        }
    }

    private fun onTimeSet(app: Context) {
        val store = JobStore(app)
        val nowWall = System.currentTimeMillis()
        val nowElapsed = SystemClock.elapsedRealtime()
        val jump = store.timeRef?.let { TimeJump.jumpMs(it.first, it.second, nowWall, nowElapsed) }
        val autoTime = Settings.Global.getInt(app.contentResolver, Settings.Global.AUTO_TIME, 1) == 1
        store.timeRef = nowWall to nowElapsed
        if (!TimeJump.isSignificant(jump, autoTime)) return
        EventStore(app).append("timeChanged", nowWall, mapOf("jumpMs" to jump, "autoTime" to autoTime))
        // RTC alarms follow the wall clock: after a jump back the next alarm would come far too late.
        val scheduler = AlarmScheduler(app)
        for (job in store.all()) {
            if (job.state.mode == Mode.STOPPED) continue
            scheduler.armAndRecord(store, job.spec.id, nowWall + SchedulePolicy.REARM_DELAY_MS, Triggers.TIME_CHANGED)
        }
        Log.i(TAG, "time changed jumpMs=$jump autoTime=$autoTime")
    }

    private fun onTimezoneChanged(app: Context, newZone: String?) {
        val store = JobStore(app)
        val to = newZone ?: TimeZone.getDefault().id
        val from = store.lastTimezone
        store.lastTimezone = to
        if (from == to) return
        EventStore(app).append("timezoneChanged", System.currentTimeMillis(), mapOf("from" to from, "to" to to))
    }

    private companion object {
        const val ACTION_QUICKBOOT_POWERON = "android.intent.action.QUICKBOOT_POWERON"
        const val EXTRA_TIME_ZONE = "time-zone"
    }
}
```

Di `AndroidManifest.xml`, tambahkan dua action ini ke `<intent-filter>` milik `SystemEventReceiver`. Keduanya termasuk broadcast implisit yang masih dikecualikan sejak Android 8.

```xml
                <action android:name="android.intent.action.TIME_SET" />
                <action android:name="android.intent.action.TIMEZONE_CHANGED" />
```

- [ ] **Step 6: Jalankan semua test**

Run (dari `example/android`): `./gradlew :dozeless:testDebugUnitTest` → Expected: 54 test lolos
Run: `flutter test` → Expected: `All tests passed!` (25)
Run (dari `example/`, HP terhubung): `flutter test integration_test/dozeless_test.dart -d <DEVICE_ID> --no-uninstall` → Expected: `All tests passed!` (5)

- [ ] **Step 7: Cek manual di HP (Review Focus #3)**

Pasang build baru, buka app, spike harus jalan. Jalankan `adb logcat -s Dozeless:I flutter:I`.
1. Pengaturan → Tanggal & waktu → matikan "Waktu otomatis" → mundurkan jam 1 jam. Expected: `event #N timeChanged {jumpMs=-36xxxxx, autoTime=false}`, `time changed …`, lalu dalam beberapa detik `fire id=spike trigger=timeChanged`. Baris spike berikutnya menampilkan `· timeChanged` di daftar.
2. Ganti zona waktu, misalnya ke Asia/Makassar. Expected: `event #N timezoneChanged {from=Asia/Jakarta, to=Asia/Makassar}` dan baris berikutnya menampilkan `· timezoneChanged`.
3. Kembalikan waktu dan zona ke otomatis. Lompatan maju akan tercatat lagi sebagai `timeChanged`.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: deliver system events per job and handle clock and timezone changes"
```

---

### Task 13: Penanda shutdown, event boot, dan riwayat exit proses

**Files:**
- Modify: `BootInfo.kt` (tambah `ShutdownGuess`)
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/ProcessStartHook.kt`
- Create: `android/src/main/kotlin/io/github/xdaijobu/dozeless/ExitInfoReader.kt`
- Modify (tulis ulang): `Reconciler.kt`, `Housekeeping.kt`, `AndroidManifest.xml`
- Modify: `JobStore.kt` (`shutdownMarkerAt`, `lastExitReadAt`)
- Test: `RecoveryTest.kt`, `EventsTest.kt`

**Interfaces:**
- Consumes: `EventStore.append`, `BootHandler`, `JobState.lastFinishedAt`.
- Produces:
  - `ShutdownGuess.of(markerAt, lastAliveAt, bootTime): Pair<Long?, String>` dengan sumber `marker` · `lastJob` · `unknown`
  - `ExitReasons.name(code): String`, `ExitInfoReader.collect(app)`
  - `ProcessStartHook` (ContentProvider), `ShutdownWatcher.register(app)`
  - `JobStore.shutdownMarkerAt: Long?`, `JobStore.lastExitReadAt: Long?`
  - Event `boot {bootCount, bootTime, shutdownAt, shutdownSource, viaBroadcast}` dan `processExit {reason, reasonCode, importance, description}`. Untuk tracking_jobs: `shutdownSource=marker` → `SHUTDOWN`; `lastJob` → `BATTERY_DEAD_LIKELY` kalau baterai terakhir ≤ 3% dan tidak charging, kalau tidak `UNKNOWN`; `processExit` dengan reason `USER_REQUESTED`/`USER_STOPPED` → `APP_FORCE_STOPPED`, reason lain → `APP_KILLED` (spec §6).

- [ ] **Step 1: Tulis test yang gagal**

Tambahkan ke `RecoveryTest.kt`:

```kotlin
    @Test
    fun shutdownMarkerWinsOverLastJob() =
        assertEquals(900L to "marker", ShutdownGuess.of(markerAt = 900, lastAliveAt = 800, bootTime = 1_000))

    @Test
    fun withoutMarkerTheLastJobIsTheBestGuess() =
        assertEquals(800L to "lastJob", ShutdownGuess.of(markerAt = null, lastAliveAt = 800, bootTime = 1_000))

    @Test
    fun markerFromAfterTheBootIsIgnored() =
        assertEquals(800L to "lastJob", ShutdownGuess.of(markerAt = 1_200, lastAliveAt = 800, bootTime = 1_000))

    @Test
    fun nothingKnownGivesUnknown() =
        assertEquals(null to "unknown", ShutdownGuess.of(markerAt = null, lastAliveAt = null, bootTime = 1_000))
```

Tambahkan ke `EventsTest.kt`:

```kotlin
    @Test
    fun exitReasonNames() {
        assertEquals("USER_REQUESTED", ExitReasons.name(10))
        assertEquals("LOW_MEMORY", ExitReasons.name(3))
        assertEquals("REASON_99", ExitReasons.name(99))
    }
```

- [ ] **Step 2: Jalankan dan pastikan gagal**

Run (dari `example/android`): `./gradlew :dozeless:testDebugUnitTest` → Expected: FAIL `Unresolved reference: ShutdownGuess`, `ExitReasons`

- [ ] **Step 3: Implementasi**

Tambahkan di akhir `BootInfo.kt`:

```kotlin
internal object ShutdownGuess {
    /** Best guess of when the phone went down before the boot at [bootTime] (spec §6 DEVICE_SHUTDOWN). */
    fun of(markerAt: Long?, lastAliveAt: Long?, bootTime: Long): Pair<Long?, String> = when {
        markerAt != null && markerAt <= bootTime -> markerAt to "marker"
        lastAliveAt != null && lastAliveAt <= bootTime -> lastAliveAt to "lastJob"
        else -> null to "unknown"
    }
}
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/ExitInfoReader.kt`:

```kotlin
package io.github.xdaijobu.dozeless

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.util.Log

internal object ExitReasons {
    /** ApplicationExitInfo.REASON_* codes; spelled out so the names survive older compile SDKs. */
    fun name(code: Int): String = when (code) {
        0 -> "UNKNOWN"
        1 -> "EXIT_SELF"
        2 -> "SIGNALED"
        3 -> "LOW_MEMORY"
        4 -> "CRASH"
        5 -> "CRASH_NATIVE"
        6 -> "ANR"
        7 -> "INITIALIZATION_FAILURE"
        8 -> "PERMISSION_CHANGE"
        9 -> "EXCESSIVE_RESOURCE_USAGE"
        10 -> "USER_REQUESTED"
        11 -> "USER_STOPPED"
        12 -> "DEPENDENCY_DIED"
        13 -> "OTHER"
        14 -> "FREEZER"
        15 -> "PACKAGE_STATE_CHANGE"
        16 -> "PACKAGE_UPDATED"
        else -> "REASON_$code"
    }
}

/** Turns new getHistoricalProcessExitReasons entries (Android 11+) into `processExit` events. */
internal object ExitInfoReader {
    fun collect(app: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val store = JobStore(app)
        val infos = try {
            app.getSystemService(ActivityManager::class.java).getHistoricalProcessExitReasons(app.packageName, 0, 0)
        } catch (e: Exception) {
            Log.w(TAG, "exit reasons unavailable", e)
            return
        }
        val since = store.lastExitReadAt
        if (since == null) {
            // First read ever: history from before this plugin was installed is not ours to report.
            store.lastExitReadAt = infos.maxOfOrNull { it.timestamp } ?: System.currentTimeMillis()
            return
        }
        val fresh = infos.filter { it.timestamp > since }.sortedBy { it.timestamp }
        if (fresh.isEmpty()) return
        val events = EventStore(app)
        for (info in fresh) {
            events.append(
                "processExit",
                info.timestamp,
                mapOf(
                    "reason" to ExitReasons.name(info.reason),
                    "reasonCode" to info.reason.toLong(),
                    "importance" to info.importance.toLong(),
                    "description" to info.description,
                ),
            )
        }
        store.lastExitReadAt = fresh.last().timestamp
    }
}
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/ProcessStartHook.kt`:

```kotlin
package io.github.xdaijobu.dozeless

import android.content.BroadcastReceiver
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.util.Log

/**
 * Its onCreate runs every time the app process starts, including when an alarm wakes it, so the runtime-only
 * ACTION_SHUTDOWN receiver is registered whenever the process is alive (spec §3 ProcessStartHook).
 */
class ProcessStartHook : ContentProvider() {
    override fun onCreate(): Boolean {
        context?.applicationContext?.let(ShutdownWatcher::register)
        return true
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null

    override fun getType(uri: Uri): String? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}

internal object ShutdownWatcher {
    private var registered = false

    fun register(app: Context) {
        if (registered) return
        registered = true
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                JobStore(context).shutdownMarkerAt = System.currentTimeMillis()
                Log.i(TAG, "shutdown marker written")
            }
        }
        val filter = IntentFilter(Intent.ACTION_SHUTDOWN)
        // ACTION_SHUTDOWN is a protected broadcast: only the system can send it, so exporting is safe.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            app.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            app.registerReceiver(receiver, filter)
        }
    }
}
```

Di `JobStore.kt`, tambahkan property ini setelah `lastTimezone`:

```kotlin
    var shutdownMarkerAt: Long?
        get() = longOrNull(KEY_SHUTDOWN)
        set(value) = edit { if (value == null) remove(KEY_SHUTDOWN) else putLong(KEY_SHUTDOWN, value) }

    var lastExitReadAt: Long?
        get() = longOrNull(KEY_EXIT_READ)
        set(value) {
            if (value != null) edit { putLong(KEY_EXIT_READ, value) }
        }
```

dan konstanta ini ke `companion object`:

```kotlin
        const val KEY_SHUTDOWN = "shutdownMarkerAt"
        const val KEY_EXIT_READ = "lastExitReadAt"
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/Housekeeping.kt` (tulis ulang):

```kotlin
package io.github.xdaijobu.dozeless

import android.content.Context
import android.os.SystemClock
import java.util.TimeZone

/** Cheap upkeep at the start of every job run. */
internal object Housekeeping {
    fun onJobStart(app: Context) {
        WatchdogReceiver.ensureArmed(app)
        val store = JobStore(app)
        store.timeRef = System.currentTimeMillis() to SystemClock.elapsedRealtime()
        if (store.lastTimezone == null) store.lastTimezone = TimeZone.getDefault().id
        ExitInfoReader.collect(app)
    }
}
```

`android/src/main/kotlin/io/github/xdaijobu/dozeless/Reconciler.kt` (tulis ulang, versi akhir):

```kotlin
package io.github.xdaijobu.dozeless

import android.content.Context
import android.os.SystemClock
import android.util.Log

internal object ReconcilePolicy {
    enum class Action { NONE, REARM, STOP, RESUME }

    /**
     * Active jobs are always re-armed: a force stop deletes every alarm, but on Android 14 the PendingIntents survive,
     * so "is it armed" cannot be trusted. Re-arming the same PendingIntent replaces the alarm and is harmless.
     */
    fun decide(mode: Mode, missing: List<Prereq>): Action = when {
        mode == Mode.STOPPED && missing.isEmpty() -> Action.RESUME
        mode == Mode.STOPPED -> Action.NONE
        missing.isNotEmpty() -> Action.STOP
        else -> Action.REARM
    }
}

/** Runs when the app starts or comes back to the foreground (Dozeless.initialize and every resume). */
internal object Reconciler {
    fun reconcile(app: Context) {
        ExitInfoReader.collect(app)
        WatchdogReceiver.ensureArmed(app, force = true)
        val dispatched = BootHandler.handleIfNew(app, viaBroadcast = false)
        val store = JobStore(app)
        val scheduler = AlarmScheduler(app)
        val prereqs = PrereqReader.read(app)
        val now = System.currentTimeMillis()
        for (job in store.all()) {
            val id = job.spec.id
            if (id in dispatched) continue
            when (ReconcilePolicy.decide(job.state.mode, prereqs.missing(job.spec.effectiveRequires))) {
                ReconcilePolicy.Action.REARM -> {
                    val at = SchedulePolicy.rearmAt(job.state.nextRunAt, now)
                    scheduler.armAndRecord(store, id, at)
                    Log.i(TAG, "reconcile armed id=$id at=$at")
                }
                ReconcilePolicy.Action.STOP -> JobReceiver.dispatch(app, id, Triggers.PREREQUISITE_LOST)
                ReconcilePolicy.Action.RESUME -> {
                    // Arm right away: resume often fires twice, and a second reconcile must see an armed job.
                    store.update(id) { it.copy(missing = emptyList()) }
                    scheduler.armAndRecord(store, id, now + job.spec.everyMs)
                    JobReceiver.dispatch(app, id, Triggers.RESUMED)
                    Log.i(TAG, "reconcile resumed id=$id")
                }
                ReconcilePolicy.Action.NONE -> Unit
            }
        }
        if (store.all().none { it.state.mode == Mode.STOPPED }) Notifier.clear(app)
    }

    /** Boot or app update: run every active job now; each run re-arms its own chain. */
    fun restartAll(app: Context, trigger: String): Set<String> {
        val ids = JobStore(app).all().filter { it.state.mode != Mode.STOPPED }.map { it.spec.id }.toSet()
        ids.forEach { JobReceiver.dispatch(app, it, trigger) }
        return ids
    }
}

/** Handles each boot exactly once, from BOOT_COMPLETED or, if that never came, from the next app start. */
internal object BootHandler {
    fun handleIfNew(app: Context, viaBroadcast: Boolean): Set<String> {
        val store = JobStore(app)
        val boot = BootInfo.read(app)
        val kind = BootDedupe.classify(store.handledBoot, boot)
        if (kind == BootKind.SAME_BOOT) return emptySet()
        store.handledBoot = boot
        store.timeRef = System.currentTimeMillis() to SystemClock.elapsedRealtime()
        WatchdogReceiver.ensureArmed(app)
        if (kind == BootKind.FIRST_SEEN) return emptySet()

        val lastAlive = store.all().mapNotNull { it.state.lastFinishedAt }.maxOrNull()
        val (shutdownAt, source) = ShutdownGuess.of(store.shutdownMarkerAt, lastAlive, boot.bootTime)
        store.shutdownMarkerAt = null
        EventStore(app).append(
            "boot",
            boot.bootTime,
            mapOf(
                "bootCount" to boot.bootCount?.toLong(),
                "bootTime" to boot.bootTime,
                "shutdownAt" to shutdownAt,
                "shutdownSource" to source,
                "viaBroadcast" to viaBroadcast,
            ),
        )
        Log.i(TAG, "boot bootCount=${boot.bootCount} viaBroadcast=$viaBroadcast shutdown=$source")
        return Reconciler.restartAll(app, Triggers.BOOT)
    }
}
```

Event `boot` ditulis **sebelum** `restartAll`, supaya run dengan `trigger=boot` langsung menerimanya.

`android/src/main/AndroidManifest.xml` (tulis ulang, versi akhir):

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
  package="io.github.xdaijobu.dozeless">

    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
    <uses-permission android:name="android.permission.WAKE_LOCK" />
    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />

    <application>
        <receiver
            android:name="io.github.xdaijobu.dozeless.JobReceiver"
            android:exported="false" />
        <receiver
            android:name="io.github.xdaijobu.dozeless.WatchdogReceiver"
            android:exported="false" />
        <receiver
            android:name="io.github.xdaijobu.dozeless.SystemEventReceiver"
            android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.TIME_SET" />
                <action android:name="android.intent.action.TIMEZONE_CHANGED" />
            </intent-filter>
        </receiver>
        <provider
            android:name="io.github.xdaijobu.dozeless.ProcessStartHook"
            android:authorities="${applicationId}.dozeless.start"
            android:exported="false" />
    </application>
</manifest>
```

- [ ] **Step 4: Jalankan semua test dan build**

Run (dari `example/android`): `./gradlew :dozeless:testDebugUnitTest` → Expected: `BUILD SUCCESSFUL`, **59** test lolos
Run: `flutter test` → Expected: `All tests passed!` (25)
Run (dari `example/`): `flutter test` (7), `flutter analyze` (No issues), `flutter build apk --debug` (√ Built)

- [ ] **Step 5: Cek di HP**

Pasang build baru dan buka app. Jalankan `adb logcat -s Dozeless:I flutter:I`.
1. **Reboot dengan Autostart aktif.** `adb reboot`, jangan buka app. Expected: `boot bootCount=… viaBroadcast=true shutdown=marker` (atau `lastJob` kalau proses sedang mati saat HP dimatikan), lalu `event #N boot {…}` dan `fire id=spike trigger=boot`. Setelah app dibuka, baris `spike/boot` menampilkan `· boot`.
2. **Force stop.** `adb shell am force-stop io.github.xdaijobu.dozeless_example`, lalu buka app. Expected: `event #N processExit {reason=USER_REQUESTED, …}` dan baris spike berikutnya menampilkan `· processExit`.
3. **Autostart dimatikan.** Matikan Autostart example di Keamanan, lalu `adb reboot`. Tidak boleh ada `fire` sampai app dibuka. Buka app → `boot … viaBroadcast=false`, lalu run `boot`. Setelah itu nyalakan lagi Autostart.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: record boot, shutdown guess and process exit reasons as system events"
```

---

### Task 14: README plugin, verifikasi akhir, dan catatan fase 2

**Files:**
- Modify (tulis ulang): `README.md`
- Create: `docs/phase2-verification.md`

**Interfaces:**
- Consumes: seluruh plugin.
- Produces: dokumentasi pemakaian untuk plan `tracking_jobs` berikutnya, dan bukti verifikasi.

- [ ] **Step 1: Tulis README**

> README final repo ini ada di `README.md` root dan ditulis dalam bahasa Inggris, mengikuti kebiasaan plugin di pub.dev. Draf di bawah adalah versi awal berbahasa Indonesia.

`README.md`:

````markdown
# dozeless

Job runner Android untuk Flutter yang hanya memakai AlarmManager: tanpa WorkManager, tanpa foreground service, tanpa notifikasi permanen. Logika job ditulis di Dart lalu dijalankan di FlutterEngine headless. Spesifikasi lengkap ada di `docs/spec/flutter-background-tracking-spec.html`.

## Pakai

```yaml
dependencies:
  dozeless:
    path: packages/dozeless   # atau git: {url: ..., path: ...}
```

```dart
@pragma('vm:entry-point')
Future<void> getJob(JobContext ctx) async {
  // ctx.trigger, ctx.delayMs, ctx.systemEvents, ctx.prerequisites, ctx.device, ctx.deadline
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Dozeless.initialize(stopNotification: const StopNotification(title: '…', body: '…'));
  await Dozeless.schedule(
    id: 'get',
    callback: getJob,
    every: const Duration(minutes: 5),
    requires: {Prereq.location, Prereq.backgroundLocation},
  );
  runApp(const MyApp());
}
```

- `schedule` aman dipanggil setiap app start. Alarm yang masih aktif tidak digeser.
- Callback harus fungsi top-level atau static dengan `@pragma('vm:entry-point')`. Closure ditolak dengan `ArgumentError`.
- `timeout` maksimal 50 detik, interval minimal 1 menit.
- `batteryUnrestricted` dan `notBackgroundRestricted` diwajibkan untuk semua job di semua versi Android. Izin `SCHEDULE_EXACT_ALARM` tidak perlu diminta, karena baterai "Tidak dibatasi" sudah membuat exact alarm jalan di Android 14+.
- Wizard izin: `Dozeless.checkPrerequisites()` dan `Dozeless.openSettings(Setting.batteryOptimization | appDetails | exactAlarm | autostart)`.

## Manifest app

Plugin sudah menambahkan `RECEIVE_BOOT_COMPLETED`, `SCHEDULE_EXACT_ALARM`, `WAKE_LOCK`, `ACCESS_WIFI_STATE`, semua receiver, dan provider. App perlu menambahkan sendiri `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`, `INTERNET`, `ACCESS_NETWORK_STATE`, dan `POST_NOTIFICATIONS`. Jangan pakai `android:installLocation="preferExternal"`.

## Isi `JobStatus.lastError`

| Nilai | Arti |
|---|---|
| `JOB_TIMEOUT` | callback belum selesai saat timeout; run berikutnya `skippedBusy` sampai callback kembali atau 3× timeout |
| `JOB_FAILED: …` | callback melempar exception |
| `CALLBACK_NOT_FOUND: …` | handle callback tidak dikenal di build ini |
| `ENGINE_START_FAILED: DISPATCHER_NOT_INITIALIZED …` | app belum pernah dibuka sejak install |
| `ENGINE_START_FAILED: DISPATCHER_NOT_FOUND …` | handle dispatcher tidak ada di build ini; buka app sekali |
| `ENGINE_START_FAILED: ENGINE_START_TIMEOUT` | dispatcher tidak siap dalam 15 detik |

## Event di `ctx.systemEvents`

`boot` · `timeChanged` · `timezoneChanged` · `processExit`. Isi `data` masing-masing ada di doc `SystemEvent` (`lib/src/models.dart`). Event dikirim ulang kalau run gagal.

## Debug

```bash
adb logcat -s Dozeless:I flutter:I
adb shell dumpsys alarm | grep -A3 dozeless://          # alarm per job
adb shell dumpsys alarm | grep -A4 dozeless.WATCHDOG   # watchdog
adb shell dumpsys deviceidle whitelist +<pkg>          # baterai tidak dibatasi (uji)
adb shell am get-standby-bucket <pkg>
```

Setelah mengubah kode job Dart, lakukan hot restart atau matikan proses app. Engine background terpisah dari UI, jadi hot reload tidak berpengaruh ke job. Setelah mengubah Kotlin, stop lalu `flutter run` ulang.
````

- [ ] **Step 2: Verifikasi lengkap**

Dari root repo, dengan `JAVA_HOME` sudah diset dan HP terhubung:

```bash
flutter analyze
flutter test
cd example
flutter analyze
flutter test
flutter build apk --debug
flutter test integration_test/dozeless_test.dart -d <DEVICE_ID> --no-uninstall
cd android
./gradlew :dozeless:testDebugUnitTest
```

Expected: analyzer `No issues found!` dua kali. Dart plugin 25 lolos. Example 7 lolos. APK ter-build. Integration 5 lolos. Kotlin 59 lolos.

- [ ] **Step 3: Catat hasil cek manual fase 2**

`docs/phase2-verification.md`:

```markdown
# Verifikasi fase 2 dozeless

Tanggal: <yyyy-mm-dd> · HP: <merek model, HyperOS versi> · Commit: <hash>

| Task | Cek | Hasil | Bukti (potongan logcat / screenshot) |
|------|-----|-------|---------------------------------------|
| 9  | Optimasi baterai / App info / Autostart terbuka | ✅/❌ | |
| 10 | Baterai dicabut → stopped + notifikasi + prerequisiteLost; dipulihkan → resumed | ✅/❌ | |
| 10 | Lokasi background dicabut → hanya spike berhenti | ✅/❌ | |
| 10 | RUN_ANY_IN_BACKGROUND ignore → stop saat app dibuka | ✅/❌ | |
| 11 | Simulasi alarm hilang → trigger=watchdog | ✅/❌ | |
| 12 | Jam mundur 1 jam → timeChanged + run dalam detik | ✅/❌ | |
| 12 | Ganti zona → timezoneChanged | ✅/❌ | |
| 13 | Reboot → event boot + run boot | ✅/❌ | |
| 13 | Force stop → processExit USER_REQUESTED saat app dibuka | ✅/❌ | |
| 13 | Autostart mati → boot viaBroadcast=false saat app dibuka | ✅/❌ | |

Catatan / masalah yang ditemukan:
```

Isi tabel dari hasil Step 5–7 Task 9–13. Ulangi cek yang belum dilakukan.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "docs: plugin README and phase 2 verification notes"
```

---

## Setelah plan ini

1. Jawab Q1–Q4 di spec §12. Nama package final, kalau beda dari `dozeless`, di-rename di sini sebelum dipakai app lain.
2. Putuskan cara menangani lokasi di background berdasarkan angka "segar" dari Uji 1 (lihat "Hasil uji di emulator" #4). Minimal, `tracking_jobs` wajib menyimpan `fixTime` dan umur fix, lalu menandai baris `STALE` kalau umurnya lebih dari ±2× interval, supaya posisi cache tidak terlihat seperti posisi sekarang (spec §10).
3. Buat plan kedua untuk package `tracking_jobs` (spec §5–§8): getJob, sendJob, tabel SQLite record, katalog event, adapter upload, batas 20.000 baris, dan `ERROR` 1× per jam per kode. Plan itu memakai API di atas: `JobContext.systemEvents` untuk DEVICE_SHUTDOWN/BOOT/APP_FORCE_STOPPED/TIME_CHANGED, `trigger` untuk TRACKING_STOPPED/RESUMED, `mode` untuk `ALARM_EXACT_DENIED`, `lastError` untuk `JOB_TIMEOUT`/`ENGINE_START_FAILED`, dan `deadline` untuk membatasi waktu setiap langkah.


