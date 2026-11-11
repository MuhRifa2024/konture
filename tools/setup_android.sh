#!/usr/bin/env bash
# Jalankan sekali setelah clone: membuat folder android/ dan menambah izin.
set -e
flutter create --platforms=android --org id.kontur --project-name kontur_survey .
M=android/app/src/main/AndroidManifest.xml
PERMS='    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
    <uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE"/>
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
    <uses-feature android:name="android.hardware.sensor.barometer" android:required="false"/>'
if ! grep -q ACCESS_FINE_LOCATION "$M"; then
  awk -v p="$PERMS" '/<application/ && !d {print p; d=1} {print}' "$M" > "$M.tmp" && mv "$M.tmp" "$M"
fi
echo "Selesai. Lanjut: atur signing release (lihat README bagian 3), lalu 'flutter run'."
