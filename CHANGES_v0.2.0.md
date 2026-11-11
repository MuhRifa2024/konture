# Perubahan v0.2.0
- HAPUS file lama: `lib/sensors/ble_nmea_source.dart`
- Dependensi BLE diganti: `flutter_blue_plus` -> `bluetooth_low_energy` (central + peripheral, Android + iOS)
- BARU: `lib/ble/*`, `lib/ui/ble_tab.dart`, `test/sync_protocol_test.dart`
- UBAH: `lib/data/app_state.dart`, `lib/data/models.dart`, `lib/sensors/sensor_service.dart`, `lib/ui/home_page.dart`, `pubspec.yaml`
- BARU: `tools/setup_ios.ps1`, `tools/setup_ios.sh`, `.github/workflows/ios-build.yml`
- MANUAL: tambahkan di AndroidManifest.xml
  <uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE"/>
