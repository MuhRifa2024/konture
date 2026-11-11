# KonturSurvey

Aplikasi Android (Flutter) untuk survei kontur di bukit/gunung: GNSS + barometer
(Base/Rover), solver trilaterasi, kontur IDW + marching squares, ekspor/merge GeoJSON,
rilis APK otomatis lewat GitHub Actions.

## 1. Persiapan lokal
```bash
git clone <repo> && cd kontur_survey
./tools/setup_android.sh      # membuat folder android/ + izin
flutter pub get
flutter test                  # uji solver, barometer, kontur, NMEA
flutter run                   # HP Android terhubung
```

## 2. Cara survei (3 HP)
1. **HP Base**: tab Ukur → pilih *Base*. Letakkan diam di titik terbuka dan stabil. Catat elevasi titik itu (BM/DEM).
2. **HP Rover A & B**: pilih *Rover*, jalani jalur survei, berhenti 30-60 dtk lalu *Ukur titik*.
3. Selesai: di Base, tab Ekspor → *Ekspor sesi Base*. Di Rover, *Impor sesi Base* (elevasi Base diisi di tab Titik).
4. Gabungkan titik dari Rover A & B (ekspor GeoJSON titik, gabungkan di QGIS, atau tambahkan fitur impor titik).
5. Tab Kontur → pilih interval → *Hitung kontur* → tab Ekspor (impor GeoJSON lama dulu bila ingin merge).

Tips: kalibrasi silang barometer 3 HP (letakkan berdampingan 5 menit di awal dan akhir),
lakukan loop closure, hindari hujan/kabut.

## 3. Signing release APK
Tambahkan di `android/app/build.gradle.kts` (sebelum `android {`):
```kotlin
import java.util.Properties
val keystoreProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(f.inputStream())
}
```
Di dalam `android { }`:
```kotlin
signingConfigs {
    create("release") {
        if (keystoreProps.isNotEmpty()) {
            keyAlias = keystoreProps["keyAlias"] as String
            keyPassword = keystoreProps["keyPassword"] as String
            storeFile = file(keystoreProps["storeFile"] as String)
            storePassword = keystoreProps["storePassword"] as String
        }
    }
}
buildTypes {
    release {
        signingConfig = if (keystoreProps.isNotEmpty())
            signingConfigs.getByName("release") else signingConfigs.getByName("debug")
    }
}
```
Buat keystore: `keytool -genkey -v -keystore upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`
lalu isi GitHub Secrets: `KEYSTORE_BASE64` (`base64 -w0 upload.jks`), `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.
Tanpa secrets, APK tetap terbentuk dengan kunci debug (cukup untuk uji internal).

## 4. Rilis
Naikkan `version:` di `pubspec.yaml` (mis. `0.1.1+2`), commit, push ke `main`.
Workflow membuat tag `v0.1.1` dan GitHub Release berisi `kontur-survey-v0.1.1.apk`.

## 5. Struktur
- `lib/core` trilaterasi (LM + GDOP), barometer, UTM
- `lib/sensors` GNSS/barometer service, parser NMEA, sumber BLE RTK (kerangka)
- `lib/survey` rata-rata titik henti + QA
- `lib/contour` IDW, marching squares, penghalusan
- `lib/data` model, state, GeoJSON export/merge
- `lib/ui` layar

## 6. BLE (v0.2.0)
- **Sinkronisasi Base → Rover via BLE**: tab BLE. Base menyalakan *Siarkan log Base*, Rover menekan *Cari HP Base* lalu *Ambil log*. Jarak dekat (±20 m).
- **Receiver RTK/GNSS via BLE**: tab BLE → *Cari receiver*. Aplikasi berlangganan ke semua karakteristik notify dan mengurai NMEA (GGA/GST). Aktifkan *Pakai RTK untuk Ukur titik* agar posisi dan tinggi diambil dari receiver.
- Android 12+: tambahkan izin `BLUETOOTH_ADVERTISE` di `AndroidManifest.xml` (sudah ada di `tools/setup_android.sh`).

## 7. iOS
```powershell
.\tools\setup_ios.ps1     # Windows (atau ./tools/setup_ios.sh di macOS)
```
Skrip membuat folder `ios/` dan mengisi `Info.plist` (lokasi, Bluetooth, sensor gerak, background mode).
Build iOS hanya bisa dilakukan di macOS (Xcode atau runner GitHub `macos-latest`, lihat `.github/workflows/ios-build.yml`).
Memasang ke iPhone butuh signing: Xcode + Apple ID (gratis, berlaku 7 hari) atau Apple Developer Program (TestFlight).

## 8. Batasan versi ini
- Akurasi: GNSS HP + barometer, bukan geodetik. Untuk cm-level pakai receiver RTK lewat BLE (belum teruji dengan alat nyata).
- Trilaterasi (`core/trilaterate.dart`) sudah teruji unit tetapi belum punya layar input jarak laser/UWB.
- Penyimpanan memakai JSON; ganti ke SQLite (drift) untuk data besar.
- Belum ada peta offline, penggabungan titik Rover A+B otomatis, fusi DEM, dan modul LLM.
