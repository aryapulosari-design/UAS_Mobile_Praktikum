import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as zones;
import 'package:timezone/timezone.dart' as tz;

import '../models/city.dart';
import '../models/weather.dart';
import '../utils/weather_display.dart';

({tz.TZDateTime slot, tz.TZDateTime at, int chance})? _firstRainSlot(
  Weather weather,
  int threshold,
  DateTime now,
) {
  zones.initializeTimeZones();
  final zone = tz.getLocation(weather.timezone);
  for (final hour in weather.hourly) {
    final chance = hour.rainProbability;
    if (chance == null || chance < threshold || chance > 100) continue;
    final time = hour.time;
    final slot = tz.TZDateTime(
      zone,
      time.year,
      time.month,
      time.day,
      time.hour,
      time.minute,
    );
    if (!slot.isAfter(now)) continue;
    return (
      slot: slot,
      at: slot.subtract(const Duration(minutes: 30)),
      chance: chance,
    );
  }
  return null;
}

class RainNotifications {
  RainNotifications(this.preferences);

  final SharedPreferencesAsync preferences;
  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void> _queue = Future.value();
  bool _initialized = false;
  static const _id = 1;
  static const _pendingKey = 'langit_kita.rain_pending.v1';
  static const _usedKey = 'langit_kita.rain_used.v1';
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'rain',
      'Pengingat hujan',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<bool> permission() async =>
      supported && await _android?.areNotificationsEnabled() == true;

  Future<bool> requestPermission() async {
    if (await permission()) return true;
    return supported &&
        await _android?.requestNotificationsPermission() == true;
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _initialized = true;
  }

  Future<bool> test() async {
    if (!await requestPermission()) return false;
    await _initialize();
    await _plugin.show(
      id: 2,
      title: 'Tes LangitKita',
      body: 'Notifikasi perangkat siap digunakan.',
      notificationDetails: _details,
    );
    return true;
  }

  Future<void> update({
    required City city,
    required Weather? weather,
    required bool enabled,
    required int threshold,
    bool changed = false,
    DateTime? now,
  }) {
    if (!supported) return Future.value();
    final job = _queue.then(
      (_) => _update(
        city: city,
        weather: weather,
        enabled: enabled,
        threshold: threshold,
        changed: changed,
        now: now ?? DateTime.now(),
      ),
    );
    _queue = job.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return job;
  }

  Future<void> _update({
    required City city,
    required Weather? weather,
    required bool enabled,
    required int threshold,
    required bool changed,
    required DateTime now,
  }) async {
    final pending = await preferences.getStringList(_pendingKey) ?? [];
    final canNotify = enabled && await permission();
    final plan = canNotify && weather != null
        ? _firstRainSlot(weather, threshold, now)
        : null;
    if (plan == null && pending.isEmpty) return;
    final day = plan?.slot.toIso8601String().substring(0, 10);
    final key = day == null ? null : '$day|${city.id}';
    final at = plan?.at.millisecondsSinceEpoch;
    final slot = plan?.slot.millisecondsSinceEpoch;
    final used = (await preferences.getStringList(_usedKey) ?? []).toSet();
    if (pending.length == 5) {
      final pendingAt = int.tryParse(pending[1]) ?? 0;
      final pendingSlot = int.tryParse(pending[4]) ?? 0;
      final due = pendingAt <= now.millisecondsSinceEpoch;
      final sameRules =
          !changed &&
          canNotify &&
          pending[2] == city.id &&
          pending[3] == '$threshold';
      final samePlan =
          pending[0] == key && pendingAt == at && pendingSlot == slot;
      if (sameRules && (weather == null || samePlan)) return;
      if (due) {
        used.add(pending[0]);
        final cutoff = now
            .toUtc()
            .subtract(const Duration(days: 2))
            .toIso8601String()
            .substring(0, 10);
        used.removeWhere((entry) => entry.compareTo(cutoff) < 0);
        await preferences.setStringList(_usedKey, used.toList());
      }
      await _plugin.cancel(id: _id);
      await preferences.setStringList(_pendingKey, []);
    }
    if (plan == null || !plan.at.isAfter(now) || used.contains(key)) return;
    await _initialize();
    await preferences.setStringList(_pendingKey, [
      key!,
      '$at',
      city.id,
      '$threshold',
      '$slot',
    ]);
    try {
      await _plugin.zonedSchedule(
        id: _id,
        title: 'Potensi hujan di ${city.name}',
        body:
            'Pukul ${clockLabel(plan.slot)} (${weather!.timezone}), peluang hujan ${plan.chance}%. Siapkan payung.',
        scheduledDate: plan.at,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {
      await preferences.setStringList(_pendingKey, []);
      rethrow;
    }
  }
}
