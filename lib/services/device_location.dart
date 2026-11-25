import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../models/city.dart';
import 'weather_service.dart';

class DeviceLocation {
  bool get _windows => defaultTargetPlatform == TargetPlatform.windows;
  bool get supported =>
      !kIsWeb && (_windows || defaultTargetPlatform == TargetPlatform.android);
  LocationPermission? _windowsPermission;

  Future<String> status() async {
    if (!supported) return 'Tersedia di aplikasi Android dan Windows.';
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Layanan lokasi mati.';
    }
    // On Windows the plugin's permission check can open the permission prompt.
    final permission = _windows
        ? _windowsPermission
        : await Geolocator.checkPermission();
    return switch (permission) {
      null => 'Periksa izin dengan Gunakan Lokasi Saya.',
      LocationPermission.always || LocationPermission.whileInUse => 'Diizinkan',
      LocationPermission.deniedForever =>
        'Ditolak permanen. Buka pengaturan perangkat.',
      _ => 'Belum diizinkan',
    };
  }

  Future<void> openSettings() async {
    final opened = await Geolocator.isLocationServiceEnabled()
        ? await Geolocator.openAppSettings()
        : await Geolocator.openLocationSettings();
    if (!opened) {
      throw const WeatherException('Pengaturan perangkat tidak dapat dibuka.');
    }
  }

  Future<City> locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const WeatherException(
        'Aktifkan layanan lokasi atau pilih kota secara manual.',
      );
    }
    var permission = _windows
        ? await Geolocator.requestPermission()
        : await Geolocator.checkPermission();
    if (!_windows && permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (_windows) _windowsPermission = permission;
    if (permission == LocationPermission.deniedForever) {
      throw const WeatherException(
        'Izin lokasi ditolak permanen. Buka Pengaturan perangkat atau pilih kota.',
      );
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      throw const WeatherException(
        'Izin lokasi ditolak. Kamu tetap bisa memilih kota.',
      );
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        timeLimit: Duration(seconds: 15),
      ),
    );
    String? name;
    String? region;
    if (!_windows) {
      try {
        final places = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        ).timeout(const Duration(seconds: 5));
        name = places.firstOrNull?.locality;
        region = places.firstOrNull?.administrativeArea;
      } catch (_) {
        // GPS remains usable without a reverse-geocoded place name.
      }
    }
    return City(
      name: name != null && name.trim().isNotEmpty ? name : 'Lokasi saya',
      region: region ?? '',
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }
}
