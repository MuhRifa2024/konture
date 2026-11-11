#!/usr/bin/env bash
# macOS/Linux: membuat folder ios/ dan menambah izin ke Info.plist.
set -e
flutter create --platforms=ios --org id.kontur --project-name kontur_survey .
python3 - <<'PY'
import re
p = "ios/Runner/Info.plist"
c = open(p).read()
if "NSBluetoothAlwaysUsageDescription" not in c:
    add = """\t<key>NSLocationWhenInUseUsageDescription</key>
\t<string>Lokasi dipakai untuk mencatat posisi titik survei.</string>
\t<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
\t<string>Lokasi tetap dicatat saat layar mati selama survei.</string>
\t<key>NSBluetoothAlwaysUsageDescription</key>
\t<string>Bluetooth dipakai untuk sinkronisasi antar HP dan receiver RTK.</string>
\t<key>NSBluetoothPeripheralUsageDescription</key>
\t<string>Bluetooth dipakai untuk menyiarkan data HP Base.</string>
\t<key>NSMotionUsageDescription</key>
\t<string>Sensor tekanan udara dipakai untuk mengukur beda tinggi.</string>
\t<key>UIBackgroundModes</key>
\t<array>
\t\t<string>location</string>
\t\t<string>bluetooth-central</string>
\t\t<string>bluetooth-peripheral</string>
\t</array>
"""
    c = re.sub(r"</dict>\s*</plist>", lambda m: add + "</dict>\n</plist>", c)
    open(p, "w").write(c)
    print("Info.plist diperbarui.")
PY
