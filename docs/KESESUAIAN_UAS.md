# LangitKita 2.0 · Catatan implementasi UAS

Ruang lingkup UAS meneruskan fitur dari [versi UTS](KESESUAIAN_UTS.md). Tampilan memakai judul, tata letak, dan palet dari [screenshot Beranda UTS](screenshots/02-cuaca-jakarta.png). Prototipe UAS dipakai untuk memeriksa cakupan layar. Penyempurnaan Kualitas Udara diperiksa dengan skill Superpowers `verification-before-completion`.

| Bagian | UTS | Implementasi UAS |
| --- | --- | --- |
| Lokasi | Kota cepat, pencarian, dan pilihan manual | Satu lokasi aktif untuk semua tab. Lokasi perangkat diambil setelah tombol ditekan. Pilihan manual terakhir disimpan. Windows memakai nama cadangan **Lokasi saya**. Android mencoba mendapatkan nama wilayah dari layanan perangkat. |
| Cuaca | Cuaca saat ini, metrik, refresh, dan coba lagi | Beranda memakai lokasi bersama serta menunjukkan sumber pilihan dan waktu data. Respons lama diabaikan setelah pengguna pindah kota. |
| Favorit | Penyimpanan kota lokal | Kunci penyimpanan UTS tetap dipakai. Favorit tampil di Beranda dan pemilih kota Pengaturan. |
| Prakiraan | Kartu 24 jam, tujuh hari, dan detail harian | Tab Prakiraan menyediakan grafik suhu atau peluang hujan dan daftar per jam. Nilai kosong meninggalkan celah pada grafik. Daftar 7 Hari membuka detail UTS. |
| Kualitas udara | — | Kategori tampil bersama angka US AQI, diikuti arti kategori dan rentangnya. Enam polutan disertai contoh sehari-hari dan tersedia tombol info satuan. Status pemuatan, kosong, dan gagal tampil terpisah dari cuaca. |
| Pengaturan | Favorit lokal | Status izin lokasi dan notifikasi, sakelar pengingat, ambang 70% sebagai default, dan Tes notifikasi di Android. |
| Notifikasi | — | Pengingat lokal Android, maksimal satu per kota per hari prakiraan dan satu jadwal aktif. Tes independen dari ambang. |

## Data dan waktu

- Weather Forecast memakai endpoint `/v1/forecast` dengan `forecast_hours=24`, `forecast_days=7`, dan `timezone=auto`. Grafik memakai sampel per jam yang sama dengan daftar. Beranda menampilkan waktu data dari API. [Dokumentasi Weather Forecast](https://open-meteo.com/en/docs)
- Air Quality memakai `/v1/air-quality` dengan `current=us_aqi,pm2_5,pm10,carbon_monoxide,nitrogen_dioxide,sulphur_dioxide,ozone` dan `timezone=auto`. Lokasi Malang menghasilkan `current`, `current_units`, dan `timezone=Asia/Jakarta` dalam pemeriksaan respons langsung. Satuan polutan bersumber dari `current_units`. Data adalah estimasi model dari Open-Meteo dan CAMS ENSEMBLE. [Dokumentasi Air Quality](https://open-meteo.com/en/docs/air-quality-api)
- Rentang dan arti kategori US AQI mengacu pada panduan AirNow. Pita warna menunjukkan enam kategori secara berurutan. [Panduan AQI AirNow](https://www.airnow.gov/aqi/aqi-basics/)
- Aplikasi memakai layanan lokasi sistem Android atau Windows. Lokasi perangkat yang aktif dikirim sebagai koordinat ke Open-Meteo agar cuaca dan kualitas udara sesuai dengan titik itu. Lokasi manual terakhir digunakan kembali setelah aplikasi dibuka ulang. [Dokumentasi geolocator](https://pub.dev/packages/geolocator)

## Pengingat hujan di Android

Setelah prakiraan tersedia, aplikasi memilih slot mendatang pertama yang mencapai ambang, lalu memasang alarm untuk 30 menit sebelum slot di zona waktu prakiraan. Jika waktu pengingat untuk slot itu telah lewat, penjadwalan ditunda sampai pemeriksaan berikutnya. Aplikasi membatasi satu alarm yang telah mencapai waktu nominal untuk setiap kota dan tanggal prakiraan. Pergantian kota, ambang, atau sakelar memeriksa kembali jadwal yang tersimpan. Tes tampil sebagai **Tes LangitKita** dengan izin notifikasi.

Alarm bersifat *inexact*. Android dapat menunda pengiriman sesuai kondisi perangkat, sehingga pengingat bisa muncul mendekati atau setelah slot hujan. Aplikasi menghitung ulang ketika prakiraan atau pengaturan berubah dan tidak meminta izin alarm presisi. [Dokumentasi plugin notifikasi](https://pub.dev/packages/flutter_local_notifications/versions/22.3.2)

## Menjalankan dan verifikasi

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter run -d windows --no-pub
```

| Pemeriksaan | Hasil |
| --- | --- |
| Baseline UTS | `flutter analyze --no-pub` bersih dan 34 tes lulus sebelum perubahan. |
| API nyata Malang | Forecast dan Air Quality mengembalikan HTTP 200. Sampel cuaca berisi 24 jam yang melewati tengah malam setempat. |
| Analisis 2.0 | `flutter analyze --no-pub` bersih. |
| Tes 2.0 | `flutter test --no-pub --reporter expanded` lulus 43 tes. Cakupan AQI meliputi batas keenam kategori, gangguan koneksi, data kosong dan parsial, serta layar 320 piksel dengan teks diperbesar. |
| Windows | `flutter run -d windows --no-pub` membangun dan menjalankan aplikasi. Beranda, prakiraan, dan AQI tampil dengan data Open-Meteo. |
| Lokasi perangkat Windows | Tombol dan status tersedia. Pengambilan koordinat perangkat belum diperiksa dalam sesi ini. |
| Android | Izin sistem dan pengiriman notifikasi menunggu pengujian di perangkat. Permintaan pengujian sesi ini diarahkan ke Windows. |

## Bukti tampilan Windows

Tangkapan berikut diambil dari frame Flutter Windows pada 25–26 November 2026.

- [Beranda Malang](screenshots/uas-windows-beranda.png)
- [Daftar prakiraan tujuh hari](screenshots/uas-windows-prakiraan-7-hari.png)
- [Kualitas udara Malang](screenshots/uas-windows-kualitas-udara.png)

## Temuan selama verifikasi

- Pemeriksaan API melalui `curl.exe` awalnya gagal terhubung dari lingkungan terbatas. Pemeriksaan diulang dan kedua endpoint mengembalikan data.
- `dart format lib test` sempat gagal memperbarui berkas telemetri di luar workspace. Format diulang dengan `--suppress-analytics`.
- `flutter analyze --no-pub` sempat melaporkan blok `if` tanpa kurung kurawal. Analisis ulang bersih setelah perbaikan.
- `flutter test --no-pub --reporter expanded` sempat gagal karena mock plugin Android belum diregistrasi, tanggal contoh telah lewat, dan tombol **Coba lagi** berada di luar viewport tes. Mock, tanggal, dan langkah gulir diperbaiki. Seluruh tes kemudian lulus.

Notifikasi suhu panas dan ringkasan pagi menunggu verifikasi pengingat di Android. Cache offline dan pembaruan prakiraan berkala tetap bersifat opsional.
