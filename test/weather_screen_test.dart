import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:langit_kita/app.dart';
import 'package:langit_kita/services/weather_service.dart';
import 'package:langit_kita/services/favorites_store.dart';
import 'package:langit_kita/widgets/weather_content.dart';
import 'package:langit_kita/widgets/hourly_forecast_strip.dart';

import 'fixtures/weather_fixture.dart';
import 'fakes/memory_preferences.dart';

Widget testApp(WeatherService service, {FavoritesStore? store, Key? key}) =>
    LangitKitaApp(
      key: key,
      service: service,
      favoritesStore: store ?? FavoritesStore(preferences: MemoryPreferences()),
    );

void main() {
  WeatherService createService() => WeatherService(
    client: MockClient(
      (_) async => http.Response(jsonEncode(weatherFixture()), 200),
    ),
  );

  testWidgets(
    'Detail harian menampilkan tanggal, matahari dan angka dari API',
    (tester) async {
      final service = createService();
      addTearDown(service.close);
      await tester.pumpWidget(testApp(service));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Hari ini').hitTestable(),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hari ini').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text('Detail prakiraan'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Matahari terbenam').hitTestable(),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('05:05'), findsOneWidget);
      expect(find.text('17:23'), findsOneWidget);
      expect(find.text('9.5'), findsOneWidget);
      expect(find.text('2.4 mm'), findsOneWidget);
    },
  );

  testWidgets('Favorit pulih setelah halaman dibuat ulang dan bisa dihapus', (
    tester,
  ) async {
    final service = createService();
    final prefs = MemoryPreferences();
    final store = FavoritesStore(preferences: prefs);
    addTearDown(service.close);
    await tester.pumpWidget(
      testApp(service, store: store, key: const ValueKey('awal')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan kota ke favorit'));
    await tester.pumpAndSettle();
    expect(find.text('Kota favorit'), findsOneWidget);
    await tester.pumpWidget(
      testApp(
        service,
        store: FavoritesStore(preferences: prefs),
        key: const ValueKey('ulang'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kota favorit'), findsOneWidget);
    await tester.tap(find.text('Hapus dari favorit'));
    await tester.pumpAndSettle();
    expect(find.text('Kota favorit'), findsNothing);
    expect(await store.load(), isEmpty);
  });

  testWidgets(
    'Simpan favorit gagal memberi pesan dan tidak menambah favorit semu',
    (tester) async {
      final service = createService();
      final prefs = MemoryPreferences()..failWrites = true;
      addTearDown(service.close);
      await tester.pumpWidget(
        testApp(service, store: FavoritesStore(preferences: prefs)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Simpan kota ke favorit'));
      await tester.pumpAndSettle();
      expect(
        find.text('Favorit belum tersimpan. Silakan coba lagi.'),
        findsOneWidget,
      );
      expect(find.text('Kota favorit'), findsNothing);
    },
  );

  testWidgets('Prakiraan per jam dapat digeser hingga hari berikutnya', (
    tester,
  ) async {
    final service = createService();
    addTearDown(service.close);
    await tester.pumpWidget(testApp(service));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(HourlyForecastStrip).hitTestable(),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(HourlyForecastStrip), const Offset(-1800, 0));
    await tester.pumpAndSettle();
    expect(find.text('Hujan 60%'), findsWidgets);
    expect(find.text('20/10'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FutureBuilder menampilkan loading kemudian data sukses', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final service = WeatherService(client: MockClient((_) => pending.future));
    addTearDown(service.close);
    await tester.pumpWidget(testApp(service));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Memuat cuaca Jakarta...'), findsOneWidget);
    pending.complete(http.Response(jsonEncode(weatherFixture()), 200));
    await tester.pumpAndSettle();
    expect(find.text('32°').first, findsOneWidget);
    expect(find.text('CUACA SAAT INI'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Error dapat dicoba ulang dan berhasil mengambil data baru', (
    tester,
  ) async {
    var requests = 0;
    final service = WeatherService(
      client: MockClient((request) async {
        if (request.url.path == '/v1/air-quality') {
          return http.Response('{}', 200);
        }
        requests++;
        return requests == 1
            ? http.Response('{}', 500)
            : http.Response(jsonEncode(weatherFixture()), 200);
      }),
    );
    addTearDown(service.close);
    await tester.pumpWidget(testApp(service));
    await tester.pumpAndSettle();
    expect(find.text('Cuaca belum dapat dimuat'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Coba lagi').hitTestable(),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(find.text('CUACA SAAT INI'), findsOneWidget);
    expect(requests, 2);
  });

  testWidgets(
    'Ganti kota mengambil koordinat baru tanpa request akibat rebuild',
    (tester) async {
      final latitudes = <String?>[];
      final service = WeatherService(
        client: MockClient((request) async {
          if (request.url.path == '/v1/air-quality') {
            return http.Response('{}', 200);
          }
          latitudes.add(request.url.queryParameters['latitude']);
          return http.Response(jsonEncode(weatherFixture()), 200);
        }),
      );
      addTearDown(service.close);
      await tester.pumpWidget(testApp(service));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bandung').first);
      await tester.pumpAndSettle();
      expect(latitudes, ['-6.2', '-6.9222']);
      await tester.pump();
      expect(latitudes, hasLength(2));
      expect(find.text('Jawa Barat, Indonesia'), findsOneWidget);
    },
  );

  testWidgets('Pencarian memvalidasi input dan menangani hasil kosong', (
    tester,
  ) async {
    final service = WeatherService(
      client: MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.host.startsWith('geocoding') ? {} : weatherFixture(),
          ),
          200,
        ),
      ),
    );
    addTearDown(service.close);
    await tester.pumpWidget(testApp(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cari kota di Indonesia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cari lokasi'));
    await tester.pumpAndSettle();
    expect(find.text('Masukkan minimal 3 karakter.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'zzzzzz');
    await tester.tap(find.text('Cari lokasi'));
    await tester.pumpAndSettle();
    expect(find.text('Lokasi tidak ditemukan'), findsOneWidget);
  });

  testWidgets('Memilih hasil pencarian menampilkan cuaca kota yang dipilih', (
    tester,
  ) async {
    final service = WeatherService(
      client: MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.host.startsWith('geocoding')
                ? {
                    'results': [
                      {
                        'name': 'Malang',
                        'admin1': 'Jawa Timur',
                        'latitude': -7.98,
                        'longitude': 112.63,
                      },
                    ],
                  }
                : weatherFixture(),
          ),
          200,
        ),
      ),
    );
    addTearDown(service.close);
    await tester.pumpWidget(testApp(service));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cari kota di Indonesia'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Malang');
    await tester.tap(find.text('Cari lokasi'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Malang'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(WeatherContent),
        matching: find.text('Malang'),
      ),
      findsOneWidget,
    );
    expect(find.text('Jawa Timur, Indonesia'), findsOneWidget);
  });

  testWidgets('Layar kecil tetap dapat digulir tanpa overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = WeatherService(
      client: MockClient(
        (_) async => http.Response(jsonEncode(weatherFixture()), 200),
      ),
    );
    addTearDown(service.close);
    await tester.pumpWidget(testApp(service));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Prakiraan 7 hari'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Minggu'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Minggu'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Respons cuaca dan AQI lama tidak menimpa lokasi terbaru', (
    tester,
  ) async {
    final oldWeather = Completer<http.Response>();
    final oldAir = Completer<http.Response>();
    http.Response air(int index) => http.Response(
      jsonEncode({
        'current': {'us_aqi': index},
      }),
      200,
    );
    final service = WeatherService(
      client: MockClient((request) async {
        final latitude = request.url.queryParameters['latitude'];
        final isAir = request.url.path == '/v1/air-quality';
        if (latitude == '-7.9797') {
          return isAir ? oldAir.future : oldWeather.future;
        }
        if (isAir) return air(latitude == '-7.2575' ? 81 : 41);
        return http.Response(
          jsonEncode(
            weatherFixture(temperature: latitude == '-7.2575' ? 34 : 31.5),
          ),
          200,
        );
      }),
    );
    addTearDown(service.close);
    await tester.pumpWidget(testApp(service));
    await tester.pumpAndSettle();
    Future<void> choose(String name) async {
      final city = find.widgetWithText(ChoiceChip, name);
      await tester.ensureVisible(city);
      await tester.tap(city);
      await tester.pump();
    }

    await choose('Malang');
    await choose('Surabaya');
    oldWeather.complete(
      http.Response(jsonEncode(weatherFixture(temperature: 27)), 200),
    );
    oldAir.complete(air(155));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(WeatherContent),
        matching: find.text('Surabaya'),
      ),
      findsOneWidget,
    );
    expect(find.text('Manual'), findsOneWidget);
    expect(find.text('34°'), findsAtLeastNWidgets(1));
    expect(find.text('27°'), findsNothing);
    await tester.tap(
      find.widgetWithText(NavigationDestination, 'Kualitas Udara'),
    );
    await tester.pumpAndSettle();
    expect(find.text('81 US AQI'), findsOneWidget);
    expect(find.text('155 US AQI'), findsNothing);
    expect(find.text('Surabaya · Manual'), findsOneWidget);
  });

  testWidgets('Prakiraan beralih grafik dan membuka detail pada layar kecil', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = createService();
    addTearDown(service.close);
    await tester.pumpWidget(testApp(service));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, 'Prakiraan'));
    await tester.pumpAndSettle();
    expect(find.text('Suhu (°C) · Asia/Jakarta'), findsOneWidget);
    await tester.tap(find.text('Peluang hujan'));
    await tester.pumpAndSettle();
    expect(find.text('Peluang hujan (%) · Asia/Jakarta'), findsOneWidget);
    await tester.tap(find.text('7 Hari'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hari ini'));
    await tester.pumpAndSettle();
    expect(find.text('Detail prakiraan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Kesalahan AQI dapat dicoba ulang tanpa mengganggu cuaca', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var airRequests = 0;
    final service = WeatherService(
      client: MockClient((request) async {
        if (request.url.path != '/v1/air-quality') {
          return http.Response(jsonEncode(weatherFixture()), 200);
        }
        airRequests++;
        return airRequests == 1
            ? http.Response('{}', 500)
            : http.Response(
                jsonEncode({
                  'current': {'us_aqi': 51, 'pm2_5': 12.1},
                  'current_units': {'pm2_5': 'μg/m³'},
                }),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
      }),
    );
    addTearDown(service.close);
    await tester.pumpWidget(testApp(service));
    await tester.pumpAndSettle();
    expect(find.text('CUACA SAAT INI'), findsOneWidget);
    await tester.tap(
      find.widgetWithText(NavigationDestination, 'Kualitas Udara'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kualitas udara belum dapat dimuat'), findsOneWidget);
    await tester.tap(find.text('Coba lagi'));
    await tester.pumpAndSettle();
    expect(find.text('Sedang'), findsOneWidget);
    expect(find.text('51 US AQI'), findsOneWidget);
    expect(find.text('Skala kategori · rentang 51–100'), findsOneWidget);
    expect(
      find.textContaining('Orang yang sangat peka terhadap polusi'),
      findsOneWidget,
    );
    expect(
      find.text('PM2.5 · Partikel sangat halus, misalnya dari asap.'),
      findsOneWidget,
    );
    expect(find.text('12.1 μg/m³'), findsOneWidget);
    expect(find.text('Tidak tersedia'), findsWidgets);

    final info = find.byTooltip('Arti satuan µg/m³');
    await tester.scrollUntilVisible(info.hitTestable(), 140);
    expect(tester.getSize(info).shortestSide, greaterThanOrEqualTo(48));
    await tester.tap(info);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(740, 375);
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(find.textContaining('jumlah mikrogram zat'), findsOneWidget);
    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'AQI kosong tetap dapat dicoba ulang dan rincian terbaca pada layar sempit',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var airRequests = 0;
      final service = WeatherService(
        client: MockClient((request) async {
          if (request.url.path != '/v1/air-quality') {
            return http.Response(jsonEncode(weatherFixture()), 200);
          }
          airRequests++;
          return http.Response(
            airRequests == 1
                ? '{}'
                : jsonEncode({
                    'current': {'pm10': 0},
                    'current_units': {'pm10': 'μg/m³'},
                  }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(service.close);
      await tester.pumpWidget(testApp(service));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(NavigationDestination, 'Kualitas Udara'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Data kualitas udara belum tersedia'), findsOneWidget);
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      expect(find.text('Indeks belum tersedia'), findsOneWidget);
      expect(find.textContaining('Skala kategori'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('0.0 μg/m³').hitTestable(),
        150,
      );
      expect(find.text('0.0 μg/m³').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
