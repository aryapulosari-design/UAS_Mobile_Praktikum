import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:langit_kita/models/city.dart';
import 'package:langit_kita/models/weather.dart';
import 'package:langit_kita/services/rain_notifications.dart';

import 'fakes/memory_preferences.dart';
import 'fixtures/weather_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final city = City.presets.first;
  final now = DateTime.utc(DateTime.now().year + 1, 10, 19, 1);
  late bool allowed;
  late MemoryPreferences preferences;
  late RainNotifications notifications;

  Weather forecast(List<int?> chances) {
    final json = weatherFixture();
    final hourly = json['hourly'] as Map;
    final times = hourly['time'] as List<String>;
    hourly['time'] = times
        .map((time) => time.replaceFirst('2026', '${now.year}'))
        .toList();
    hourly['precipitation_probability'] = [
      ...chances,
      ...List.filled(24 - chances.length, 10),
    ];
    return Weather.fromJson(json);
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls.clear();
    allowed = true;
    preferences = MemoryPreferences();
    notifications = RainNotifications(preferences);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'areNotificationsEnabled' ||
        'requestNotificationsPermission' => allowed,
        'initialize' => true,
        _ => null,
      };
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    '69% dilewati, 70% memenuhi ambang, 90% tidak menduplikasi alarm',
    () async {
      final weather = forecast([69, 70, 90]);
      await notifications.update(
        city: city,
        weather: weather,
        enabled: true,
        threshold: 70,
        now: now,
      );
      await notifications.update(
        city: city,
        weather: weather,
        enabled: true,
        threshold: 70,
        now: now,
      );
      final schedules = calls.where((call) => call.method == 'zonedSchedule');
      expect(schedules, hasLength(1));
      expect(
        schedules.single.arguments['body'],
        contains('10:00 (Asia/Jakarta), peluang hujan 70%'),
      );
      expect(schedules.single.arguments['timeZoneName'], 'Asia/Jakarta');
      expect(
        schedules.single.arguments['scheduledDateTime'],
        startsWith('${now.year}-10-19T09:30'),
      );

      final reopened = RainNotifications(preferences);
      await reopened.update(
        city: city,
        weather: weather,
        enabled: true,
        threshold: 70,
        now: now.add(const Duration(hours: 2, minutes: 5)),
      );
      expect(
        calls.where((call) => call.method == 'zonedSchedule'),
        hasLength(1),
      );
    },
  );

  test(
    'Ambang dan kota baru mengganti alarm lama, toggle mati membatalkan',
    () async {
      final weather = forecast([69, 70, 90]);
      await notifications.update(
        city: city,
        weather: weather,
        enabled: true,
        threshold: 70,
        now: now,
      );
      await notifications.update(
        city: city,
        weather: weather,
        enabled: true,
        threshold: 90,
        changed: true,
        now: now,
      );
      await notifications.update(
        city: City.presets[1],
        weather: weather,
        enabled: true,
        threshold: 90,
        changed: true,
        now: now,
      );
      await notifications.update(
        city: City.presets[1],
        weather: weather,
        enabled: false,
        threshold: 90,
        changed: true,
        now: now,
      );
      final operations = calls
          .where((call) => ['zonedSchedule', 'cancel'].contains(call.method))
          .toList();
      expect(operations.map((call) => call.method), [
        'zonedSchedule',
        'cancel',
        'zonedSchedule',
        'cancel',
        'zonedSchedule',
        'cancel',
      ]);
      expect(operations[2].arguments['body'], contains('peluang hujan 90%'));
      expect(operations[4].arguments['title'], 'Potensi hujan di Bandung');
    },
  );

  test(
    'Slot yang terlalu dekat dan izin ditolak melewati penjadwalan',
    () async {
      final weather = forecast([null, 70, 90]);
      await notifications.update(
        city: city,
        weather: weather,
        enabled: true,
        threshold: 70,
        now: now.add(const Duration(hours: 1, minutes: 40)),
      );
      allowed = false;
      await notifications.update(
        city: city,
        weather: weather,
        enabled: true,
        threshold: 70,
        now: now,
      );
      expect(calls.where((call) => call.method == 'zonedSchedule'), isEmpty);
      expect(await notifications.test(), isFalse);
      allowed = true;
      expect(await notifications.test(), isTrue);
      expect(
        calls.singleWhere((call) => call.method == 'show').arguments['title'],
        'Tes LangitKita',
      );
    },
  );
}
