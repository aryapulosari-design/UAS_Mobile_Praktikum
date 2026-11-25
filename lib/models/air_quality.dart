class AirQuality {
  AirQuality.fromJson(Map<String, dynamic> json)
    : timezone = json['timezone'] is String ? json['timezone'] as String : '',
      _current = _object(json['current']),
      _units = _object(json['current_units']);

  static const pollutants = {
    'pm2_5': (
      label: 'PM2.5',
      explanation: 'Partikel sangat halus, misalnya dari asap.',
    ),
    'pm10': (
      label: 'PM10',
      explanation: 'Partikel kecil, misalnya dari debu jalan atau konstruksi.',
    ),
    'carbon_monoxide': (
      label: 'Karbon monoksida (CO)',
      explanation: 'Gas dari pembakaran, misalnya dari knalpot.',
    ),
    'nitrogen_dioxide': (
      label: 'Nitrogen dioksida (NO₂)',
      explanation: 'Gas yang banyak berasal dari lalu lintas.',
    ),
    'sulphur_dioxide': (
      label: 'Sulfur dioksida (SO₂)',
      explanation: 'Gas dari pembakaran bahan bakar yang mengandung belerang.',
    ),
    'ozone': (
      label: 'Ozon (O₃)',
      explanation:
          'Gas yang terbentuk saat sinar matahari bereaksi dengan polusi lain.',
    ),
  };

  final String timezone;
  final Map<String, dynamic> _current;
  final Map<String, dynamic> _units;

  DateTime? get time => DateTime.tryParse('${_current['time']}Z');
  int? get index => _number('us_aqi')?.round();
  bool get isEmpty =>
      index == null && pollutants.keys.every((key) => _number(key) == null);

  AirQualityLevel? get level {
    final score = index;
    if (score == null) return null;
    return AirQualityLevel.values.firstWhere(
      (level) => level.upperBound == null || score <= level.upperBound!,
    );
  }

  String reading(String key) {
    final value = _number(key);
    final unit = _units[key];
    if (value == null || unit is! String || unit.isEmpty) {
      return 'Tidak tersedia';
    }
    return '${value.toStringAsFixed(1)} $unit';
  }

  num? _number(String key) {
    final value = _current[key];
    return value is num && value.isFinite && value >= 0 ? value : null;
  }

  static Map<String, dynamic> _object(Object? value) {
    if (value == null) return {};
    if (value is Map<String, dynamic>) return value;
    throw const FormatException('Objek kualitas udara tidak valid.');
  }
}

enum AirQualityLevel {
  good(50, 'Baik', 'Tingkat pencemaran udara rendah.'),
  moderate(
    100,
    'Sedang',
    'Orang yang sangat peka terhadap polusi mulai bisa terdampak.',
  ),
  sensitive(
    150,
    'Tidak sehat bagi kelompok sensitif',
    'Kelompok sensitif, misalnya orang dengan asma, lebih mungkin merasakan dampaknya.',
  ),
  unhealthy(
    200,
    'Tidak sehat',
    'Sebagian orang bisa terdampak, terutama kelompok sensitif.',
  ),
  veryUnhealthy(
    300,
    'Sangat tidak sehat',
    'Risiko gangguan kesehatan meningkat untuk semua orang.',
  ),
  hazardous(
    null,
    'Berbahaya',
    'Semua orang lebih mungkin terdampak oleh tingkat pencemaran ini.',
  );

  const AirQualityLevel(this.upperBound, this.label, this.explanation);

  final int? upperBound;
  final String label;
  final String explanation;

  String get range {
    final lowerBound = index == 0 ? 0 : values[index - 1].upperBound! + 1;
    return upperBound == null ? '$lowerBound+' : '$lowerBound–$upperBound';
  }
}
