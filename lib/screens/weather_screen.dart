import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/air_quality.dart';
import '../models/city.dart';
import '../models/weather.dart';
import '../services/device_location.dart';
import '../services/rain_notifications.dart';
import '../services/weather_service.dart';
import '../services/favorites_store.dart';
import '../widgets/air_quality_content.dart';
import '../widgets/forecast_content.dart';
import '../widgets/status_panel.dart';
import '../widgets/weather_content.dart';
import 'city_search_screen.dart';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key, this.service, this.favoritesStore});
  final WeatherService? service;
  final FavoritesStore? favoritesStore;

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  late final WeatherService _service;
  Future<Weather>? _weather;
  Future<AirQuality>? _air;
  Weather? _latestWeather;
  City _city = City.presets.first;
  int _tab = 0;
  int _locationChoice = 0;
  bool _usesGps = false;
  bool _locating = false;
  bool _ready = false;
  bool _rainEnabled = false;
  bool _savingSettings = false;
  bool _testingNotification = false;
  int _threshold = 70;
  Future<String>? _gpsStatus;
  Future<String>? _rainStatus;
  String? _rainError;
  late final SharedPreferencesAsync _preferences;
  late final RainNotifications _rain;
  late final AppLifecycleListener _lifecycle;
  final _gps = DeviceLocation();
  Future<void> _cityWrite = Future.value();
  static const _cityKey = 'langit_kita.manual_city.v1';
  static const _settingsKey = 'langit_kita.rain_settings.v1';
  late final FavoritesStore _favoritesStore;
  List<City> _favorites = [];
  bool _favoritesReady = false;
  bool _favoritesError = false;
  bool _savingFavorite = false;
  bool get _isFavorite => _favorites.any((city) => city.id == _city.id);

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? WeatherService();
    _favoritesStore = widget.favoritesStore ?? FavoritesStore();
    _preferences = _favoritesStore.preferences ?? SharedPreferencesAsync();
    _rain = RainNotifications(_preferences);
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (_tab == 3) _refreshPermissions();
        if (_ready) _syncRain();
      },
    );
    _loadFavorites();
    _restoreSettings();
  }

  Future<void> _restoreSettings() async {
    City? savedCity;
    List<String>? rain;
    try {
      final saved = await _preferences.getStringList(_cityKey);
      if (saved != null && saved.length == 1) {
        savedCity = City.fromJson(
          jsonDecode(saved.single) as Map<String, dynamic>,
        );
      }
    } catch (_) {
      // A missing or damaged choice falls back to Jakarta.
    }
    try {
      rain = await _preferences.getStringList(_settingsKey);
    } catch (_) {
      // Defaults keep notifications off if preferences cannot be read.
    }
    if (!mounted) return;
    final threshold = rain?.length == 2 ? int.tryParse(rain![1]) : null;
    setState(() {
      _city = savedCity ?? _city;
      _rainEnabled = rain?.firstOrNull == 'true';
      _threshold = threshold != null && threshold >= 0 && threshold <= 100
          ? threshold
          : 70;
      _ready = true;
    });
    _syncRain();
    _reload();
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _syncRain({bool changed = false}) async {
    try {
      await _rain.update(
        city: _city,
        weather: _latestWeather,
        enabled: _rainEnabled,
        threshold: _threshold,
        changed: changed,
      );
      if (mounted && _rainError != null) setState(() => _rainError = null);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _rainError = 'Pengingat hujan belum dapat diperbarui. Coba lagi.',
        );
      }
    }
  }

  void _refreshPermissions() => setState(() {
    _gpsStatus = _gps.status();
    _rainStatus = _notificationPermission();
  });

  Future<String> _notificationPermission() async {
    if (!_rain.supported) return 'Tersedia di aplikasi Android.';
    return await _rain.permission()
        ? 'Diizinkan'
        : 'Belum diizinkan. Tinjau izin LangitKita di pengaturan perangkat.';
  }

  Future<void> _changeRain({bool? enabled, int? threshold}) async {
    if (!_ready || _savingSettings) return;
    setState(() => _savingSettings = true);
    try {
      final nextEnabled = enabled ?? _rainEnabled;
      final nextThreshold = threshold ?? _threshold;
      if (enabled == true && !await _rain.requestPermission()) {
        _message(
          'Izin notifikasi belum diberikan. Tinjau izin LangitKita di pengaturan perangkat.',
        );
        return;
      }
      await _preferences.setStringList(_settingsKey, [
        '$nextEnabled',
        '$nextThreshold',
      ]);
      if (!mounted) return;
      setState(() {
        _rainEnabled = nextEnabled;
        _threshold = nextThreshold;
      });
      await _syncRain(changed: true);
    } catch (_) {
      _message('Preferensi notifikasi belum tersimpan. Silakan coba lagi.');
    } finally {
      if (mounted) {
        setState(() => _savingSettings = false);
        _refreshPermissions();
      }
    }
  }

  Future<void> _testNotification() async {
    setState(() => _testingNotification = true);
    try {
      final sent = await _rain.test();
      _message(
        sent
            ? 'Tes LangitKita dikirim.'
            : 'Izin notifikasi belum diberikan. Tinjau pengaturan perangkat.',
      );
      if (sent) await _syncRain();
    } catch (_) {
      _message('Notifikasi tes gagal. Silakan coba lagi.');
    } finally {
      if (mounted) {
        setState(() => _testingNotification = false);
        _refreshPermissions();
      }
    }
  }

  Future<void> _loadFavorites() async {
    try {
      final cities = await _favoritesStore.load();
      if (mounted) {
        setState(() {
          _favorites = cities;
          _favoritesReady = true;
          _favoritesError = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _favoritesError = true);
    }
  }

  Future<void> _toggleFavorite() async {
    if (!_favoritesReady || _savingFavorite) return;
    final city = _city;
    final removing = _isFavorite;
    final next = removing
        ? _favorites.where((item) => item.id != city.id).toList()
        : [..._favorites, city];
    setState(() => _savingFavorite = true);
    try {
      await _favoritesStore.save(next);
      if (mounted) {
        setState(() => _favorites = next);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${city.name} ${removing ? 'dihapus dari' : 'ditambahkan ke'} favorit.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Favorit belum tersimpan. Silakan coba lagi.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingFavorite = false);
    }
  }

  Future<void> _reload([City? city, bool gps = false]) async {
    if (!_ready) return;
    final changed = city != null && (city.id != _city.id || gps != _usesGps);
    setState(() {
      if (city != null) {
        _locationChoice++;
        _locating = false;
        _city = city;
        _usesGps = gps;
      }
      if (changed) _latestWeather = null;
      _weather = _service.fetchWeather(_city);
      if (changed || _air == null || _tab == 2) _loadAir();
    });
    if (city != null && !gps) {
      _cityWrite = _cityWrite.then((_) async {
        try {
          await _preferences.setStringList(_cityKey, [
            jsonEncode(city.toJson()),
          ]);
        } catch (_) {
          _message('Kota pilihan belum bisa disimpan untuk sesi berikutnya.');
        }
      });
    }
    if (changed) _syncRain(changed: true);
    final request = _weather!;
    try {
      final data = await request;
      if (mounted && identical(request, _weather)) {
        _latestWeather = data;
        _syncRain();
      }
    } catch (_) {
      // Pesan error ditampilkan FutureBuilder; RefreshIndicator tetap selesai.
    }
  }

  void _loadAir() {
    _air = _service.fetchAirQuality(_city);
    _air!.ignore();
  }

  Future<void> _locate() async {
    final choice = ++_locationChoice;
    setState(() => _locating = true);
    try {
      final city = await _gps.locate();
      if (mounted && choice == _locationChoice) await _reload(city, true);
    } catch (error) {
      if (mounted && choice == _locationChoice) {
        _message(
          error is WeatherException
              ? error.message
              : 'Lokasi perangkat belum ditemukan. Coba lagi atau pilih kota.',
        );
      }
    } finally {
      if (mounted && choice == _locationChoice) {
        setState(() => _locating = false);
      }
      if (mounted && _tab == 3) _refreshPermissions();
    }
  }

  Future<void> _search() async {
    final city = await Navigator.of(context).push<City>(
      MaterialPageRoute(
        builder: (_) => CitySearchScreen(
          service: _service,
          favorites: _favorites,
          onUseLocation: _gps.supported && !_locating ? _locate : null,
        ),
      ),
    );
    if (mounted && city != null) await _reload(city);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    if (widget.service == null) _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wb_cloudy_outlined, size: 26),
          SizedBox(width: 10),
          Flexible(
            child: Text(
              'LangitKita',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: !_ready || _tab == 3 ? null : _refreshTab,
          tooltip: _tab == 2 ? 'Perbarui kualitas udara' : 'Perbarui cuaca',
          icon: const Icon(Icons.refresh_rounded),
        ),
        IconButton(
          onPressed: () => showAboutDialog(
            context: context,
            applicationName: 'LangitKita',
            applicationVersion: '2.0.0',
            applicationIcon: const Icon(Icons.wb_cloudy_rounded, size: 36),
            children: const [
              Text(
                'Aplikasi cuaca untuk UAS Mobile Programming G.\n\n'
                'Cuaca dan kualitas udara: Open-Meteo. Kualitas udara: CAMS ENSEMBLE. Kota: GeoNames. '
                'Lisensi data CC BY 4.0 (creativecommons.org/licenses/by/4.0/).\n\n'
                'Cuaca saat ini merupakan estimasi model. Prakiraan dapat berubah.',
              ),
            ],
          ),
          tooltip: 'Tentang aplikasi',
          icon: const Icon(Icons.info_outline_rounded),
        ),
        const SizedBox(width: 8),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (tab) {
        setState(() => _tab = tab);
        if (tab == 3) _refreshPermissions();
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'Beranda',
        ),
        NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          label: 'Prakiraan',
        ),
        NavigationDestination(icon: Icon(Icons.air), label: 'Kualitas Udara'),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: 'Pengaturan',
        ),
      ],
    ),
    body: _tab == 0 ? _home() : _otherTab(),
  );

  Future<void> _refreshTab() async {
    if (_tab != 2) return _reload();
    setState(_loadAir);
    try {
      await _air;
    } catch (_) {
      // FutureBuilder displays the error.
    }
  }

  Widget _locationLabel() =>
      Text('${_city.name} · ${_usesGps ? 'GPS' : 'Manual'}');

  Widget _locationButton() => OutlinedButton.icon(
    onPressed: !_ready || !_gps.supported || _locating ? null : _locate,
    icon: const Icon(Icons.my_location),
    label: Text(
      _locating ? 'Mencari lokasi perangkat…' : 'Gunakan Lokasi Saya',
    ),
  );

  Widget _otherTab() => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760),
      child: ListView(
        key: ValueKey(_tab),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        children: [
          Text(switch (_tab) {
            1 => 'Prakiraan',
            2 => 'Kualitas Udara',
            _ => 'Pengaturan',
          }, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          _locationLabel(),
          const SizedBox(height: 16),
          switch (_tab) {
            1 => _weatherPanel(
              (data) => ForecastContent(city: _city, weather: data),
            ),
            2 => FutureBuilder<AirQuality>(
              future: _air,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const StatusPanel(
                    icon: Icons.air,
                    loading: true,
                    title: 'Memuat kualitas udara…',
                    message: 'Menyiapkan data untuk lokasi aktif.',
                  );
                }
                final data = snapshot.data;
                if (data == null) {
                  return StatusPanel(
                    icon: Icons.cloud_off_outlined,
                    title: 'Kualitas udara belum dapat dimuat',
                    message: snapshot.error?.toString() ?? 'Silakan coba lagi.',
                    onRetry: _refreshTab,
                  );
                }
                return AirQualityContent(data: data, onRetry: _refreshTab);
              },
            ),
            _ => _settings(),
          },
        ],
      ),
    ),
  );

  Widget _settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OutlinedButton.icon(
        onPressed: _ready ? _search : null,
        icon: const Icon(Icons.search),
        label: const Text('Cari kota di Indonesia'),
      ),
      _locationButton(),
      FutureBuilder<String>(
        future: _gpsStatus,
        builder: (context, snapshot) => ListTile(
          title: const Text('Izin lokasi'),
          subtitle: Text(
            snapshot.hasError
                ? 'Status izin lokasi tidak dapat diperiksa.'
                : snapshot.data ?? 'Memeriksa izin…',
          ),
          trailing: _gps.supported
              ? IconButton(
                  onPressed: _openLocationSettings,
                  tooltip: 'Buka pengaturan lokasi perangkat',
                  icon: const Icon(Icons.open_in_new),
                )
              : null,
        ),
      ),
      const Divider(),
      FutureBuilder<String>(
        future: _rainStatus,
        builder: (context, snapshot) => ListTile(
          title: const Text('Izin notifikasi'),
          subtitle: Text(
            snapshot.hasError
                ? 'Status izin notifikasi tidak dapat diperiksa.'
                : snapshot.data ?? 'Memeriksa izin…',
          ),
        ),
      ),
      SwitchListTile(
        title: const Text('Notifikasi hujan'),
        value: _rainEnabled,
        onChanged: _ready && _rain.supported && !_savingSettings
            ? (value) => _changeRain(enabled: value)
            : null,
      ),
      ListTile(
        title: const Text('Ambang peluang hujan'),
        subtitle: Text('$_threshold%'),
        trailing: _rain.supported
            ? IconButton(
                onPressed: _ready && !_savingSettings ? _chooseThreshold : null,
                tooltip: 'Ubah ambang hujan',
                icon: const Icon(Icons.edit_outlined),
              )
            : null,
      ),
      FilledButton.tonalIcon(
        onPressed: _rain.supported && !_testingNotification
            ? _testNotification
            : null,
        icon: const Icon(Icons.notifications_active_outlined),
        label: const Text('Tes notifikasi'),
      ),
      if (_rainError case final error?)
        TextButton(onPressed: _syncRain, child: Text(error)),
      const Divider(),
      const ListTile(
        title: Text('Sumber data'),
        subtitle: Text(
          'Cuaca dan kualitas udara Open-Meteo. Model udara CAMS ENSEMBLE. Lokasi kota GeoNames.',
        ),
      ),
    ],
  );

  Future<void> _openLocationSettings() async {
    try {
      await _gps.openSettings();
    } catch (_) {
      _message('Buka pengaturan lokasi langsung dari perangkat.');
    }
  }

  Future<void> _chooseThreshold() async {
    var draft = _threshold.toDouble();
    final value = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Ambang hujan ${draft.round()}%'),
          content: Slider(
            value: draft,
            max: 100,
            divisions: 100,
            label: '${draft.round()}%',
            semanticFormatterCallback: (value) => '${value.round()} persen',
            onChanged: (value) => setDialogState(() => draft = value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, draft.round()),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    if (mounted && value != null && value != _threshold) {
      await _changeRain(threshold: value);
    }
  }

  Widget _home() => RefreshIndicator(
    onRefresh: _reload,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            const Text(
              'Kenali langit,\nrencanakan harimu.',
              style: TextStyle(
                fontSize: 32,
                height: 1.15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF173E38),
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Cuaca di sekitarmu, dalam satu pandangan.',
              style: TextStyle(color: Color(0xFF64766A)),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _ready ? _search : null,
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 18,
                ),
                side: const BorderSide(color: Color(0xFFDAE2D8)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              icon: const Icon(Icons.search_rounded),
              label: Text(
                _locating
                    ? 'Mencari lokasi perangkat…'
                    : 'Cari kota di Indonesia',
              ),
            ),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final city in City.presets)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(city.name),
                        showCheckmark: false,
                        selected:
                            _city.name == city.name &&
                            _city.latitude == city.latitude,
                        onSelected: _ready ? (_) => _reload(city) : null,
                      ),
                    ),
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed:
                    _ready && !_usesGps && _favoritesReady && !_savingFavorite
                    ? _toggleFavorite
                    : null,
                icon: Icon(
                  _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                ),
                label: Text(
                  _isFavorite ? 'Hapus dari favorit' : 'Simpan kota ke favorit',
                ),
              ),
            ),
            if (_favoritesError)
              TextButton.icon(
                onPressed: _loadFavorites,
                icon: const Icon(Icons.refresh),
                label: const Text('Muat ulang kota favorit'),
              ),
            if (_favorites.isNotEmpty) ...[
              const Text(
                'Kota favorit',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final city in _favorites)
                    InputChip(
                      avatar: const Icon(Icons.star_rounded, size: 16),
                      label: Text(city.name),
                      selected: city.id == _city.id,
                      onPressed: () => _reload(city),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 22),
            _weatherPanel(
              (data) =>
                  WeatherContent(city: _city, weather: data, usesGps: _usesGps),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _weatherPanel(Widget Function(Weather) content) =>
      FutureBuilder<Weather>(
        future: _weather,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return StatusPanel(
              icon: Icons.cloud_sync_outlined,
              loading: true,
              title: 'Memuat cuaca ${_city.name}...',
              message: 'Menyiapkan prakiraan terbaru untukmu.',
            );
          }
          if (snapshot.hasError) {
            return StatusPanel(
              icon: Icons.cloud_off_outlined,
              title: 'Cuaca belum dapat dimuat',
              message: snapshot.error is WeatherException
                  ? snapshot.error.toString()
                  : 'Terjadi kesalahan. Silakan coba lagi.',
              onRetry: () => _reload(),
            );
          }
          final data = snapshot.data;
          if (data == null || data.daily.isEmpty) {
            return StatusPanel(
              icon: Icons.cloud_queue_rounded,
              title: 'Data cuaca belum tersedia',
              message: 'Coba kota lain atau muat ulang beberapa saat lagi.',
              onRetry: () => _reload(),
            );
          }
          return content(data);
        },
      );
}
