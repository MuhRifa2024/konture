# Jalankan di PowerShell dari root proyek:  .\tools\setup_ios.ps1
# Membuat folder ios/ dan menambah izin + background mode ke Info.plist.
flutter create --platforms=ios --org id.kontur --project-name kontur_survey .
$plist = "ios/Runner/Info.plist"
$c = Get-Content $plist -Raw
if ($c -notmatch "NSBluetoothAlwaysUsageDescription") {
$add = @"
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>Lokasi dipakai untuk mencatat posisi titik survei.</string>
	<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
	<string>Lokasi tetap dicatat saat layar mati selama survei.</string>
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>Bluetooth dipakai untuk sinkronisasi antar HP dan receiver RTK.</string>
	<key>NSBluetoothPeripheralUsageDescription</key>
	<string>Bluetooth dipakai untuk menyiarkan data HP Base.</string>
	<key>NSMotionUsageDescription</key>
	<string>Sensor tekanan udara dipakai untuk mengukur beda tinggi.</string>
	<key>UIBackgroundModes</key>
	<array>
		<string>location</string>
		<string>bluetooth-central</string>
		<string>bluetooth-peripheral</string>
	</array>
"@
$c = [regex]::Replace($c, "</dict>\s*</plist>", { param($m) $add + "</dict>`n</plist>" })
Set-Content -Path $plist -Value $c -NoNewline
Write-Host "Info.plist diperbarui."
} else { Write-Host "Info.plist sudah berisi izin Bluetooth, dilewati." }
