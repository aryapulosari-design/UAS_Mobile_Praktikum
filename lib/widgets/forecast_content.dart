import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/city.dart';
import '../models/weather.dart';
import '../utils/weather_display.dart';
import 'weather_content.dart';

class ForecastContent extends StatefulWidget {
  const ForecastContent({super.key, required this.city, required this.weather});

  final City city;
  final Weather weather;

  @override
  State<ForecastContent> createState() => _ForecastContentState();
}

class _ForecastContentState extends State<ForecastContent> {
  bool _daily = false;
  bool _rain = false;

  @override
  Widget build(BuildContext context) {
    final weather = widget.weather;
    final unit = _rain ? '%' : '°C';
    final metric = _rain ? 'Peluang hujan' : 'Suhu';
    final values = [
      for (final hour in weather.hourly)
        _rain ? hour.rainProbability?.toDouble() : hour.temperature,
    ];
    final available = values.whereType<double>();
    final min = _rain
        ? 0.0
        : (available.isEmpty
              ? 0.0
              : available.reduce(math.min).floorToDouble());
    final max = _rain
        ? 100.0
        : (available.isEmpty
              ? 1.0
              : math.max(min + 1, available.reduce(math.max).ceilToDouble()));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('24 Jam')),
            ButtonSegment(value: true, label: Text('7 Hari')),
          ],
          selected: {_daily},
          onSelectionChanged: (value) => setState(() => _daily = value.single),
        ),
        const SizedBox(height: 16),
        if (_daily)
          DailyForecastList(city: widget.city, weather: weather)
        else ...[
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Suhu')),
              ButtonSegment(value: true, label: Text('Peluang hujan')),
            ],
            selected: {_rain},
            onSelectionChanged: (value) => setState(() => _rain = value.single),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '$metric ($unit) · ${weather.timezone}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  if (available.isEmpty)
                    const Text('Data grafik tidak tersedia.')
                  else ...[
                    SizedBox(
                      height: 124,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${max.round()}$unit'),
                              Text('${min.round()}$unit'),
                            ],
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: CustomPaint(
                              painter: _ForecastChart(
                                values,
                                min,
                                max,
                                Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final index in {
                          0,
                          weather.hourly.length ~/ 2,
                          weather.hourly.length - 1,
                        })
                          Text(clockLabel(weather.hourly[index].time)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final hour in weather.hourly)
            ListTile(
              title: Text(
                '${clockLabel(hour.time)} · ${hour.time.day}/${hour.time.month}',
              ),
              subtitle: Text(weatherLabel(hour.code)),
              trailing: Text(
                '${hour.temperature?.round() ?? '—'} °C\nHujan ${hour.rainProbability ?? '—'} %',
                textAlign: TextAlign.end,
              ),
            ),
        ],
      ],
    );
  }
}

class _ForecastChart extends CustomPainter {
  const _ForecastChart(this.values, this.min, this.max, this.color);

  final List<double?> values;
  final double min;
  final double max;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 4.0;
    final width = math.max(0.0, size.width - padding * 2);
    final height = size.height - padding * 2;
    final grid = Paint()..color = color.withValues(alpha: 0.15);
    for (final y in [padding, size.height / 2, size.height - padding]) {
      canvas.drawLine(Offset(padding, y), Offset(padding + width, y), grid);
    }
    final line = Paint()
      ..color = color
      ..strokeWidth = 2;
    Offset? previous;
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value == null) {
        previous = null;
        continue;
      }
      final point = Offset(
        padding + width * i / math.max(1, values.length - 1),
        padding + height * (1 - (value.clamp(min, max) - min) / (max - min)),
      );
      if (previous != null) canvas.drawLine(previous, point, line);
      canvas.drawCircle(point, 2, line);
      previous = point;
    }
  }

  @override
  bool shouldRepaint(_ForecastChart oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.min != min ||
      oldDelegate.max != max ||
      oldDelegate.color != color;
}
