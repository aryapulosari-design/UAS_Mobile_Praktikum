import 'package:flutter/material.dart';

import '../models/air_quality.dart';
import '../utils/weather_display.dart';
import 'status_panel.dart';

class AirQualityContent extends StatelessWidget {
  const AirQualityContent({
    super.key,
    required this.data,
    required this.onRetry,
  });

  final AirQuality data;
  final VoidCallback onRetry;

  static const _scaleColors = [
    Color(0xFF429A62),
    Color(0xFFF2CC55),
    Color(0xFFF39443),
    Color(0xFFE15F58),
    Color(0xFFA273BA),
    Color(0xFF873351),
  ];

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return StatusPanel(
        icon: Icons.air_outlined,
        title: 'Data kualitas udara belum tersedia',
        message: 'Coba lagi untuk memeriksa data di lokasi ini.',
        onRetry: onRetry,
      );
    }
    final theme = Theme.of(context);
    final time = data.time;
    final level = data.level;
    final primary = theme.colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      level?.label ?? 'Indeks belum tersedia',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (level != null)
                      Text(
                        '${data.index} US AQI',
                        style: theme.textTheme.titleMedium,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  level?.explanation ?? 'Rincian partikel dan gas yang tersedia tetap bisa dibaca di bawah.',
                ),
                if (level != null) ...[
                  const SizedBox(height: 12),
                  Text('Skala kategori · rentang ${level.range}'),
                  const SizedBox(height: 4),
                  ExcludeSemantics(
                    child: Row(
                      children: [
                        for (final segment in AirQualityLevel.values)
                          Expanded(
                            child: Container(
                              height: segment == level ? 14 : 8,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: _scaleColors[segment.index],
                                borderRadius: BorderRadius.circular(4),
                                border: segment == level
                                    ? Border.all(color: primary, width: 2)
                                    : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(child: Text('Baik')),
                      Flexible(
                        child: Text('Berbahaya', textAlign: TextAlign.end),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Makin tinggi angka US AQI, makin buruk kualitas udara.',
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  time == null
                      ? 'Waktu data tidak tersedia'
                      : 'Perkiraan ${dateLabel(time)}, ${clockLabel(time)} · ${data.timezone}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Partikel dan gas di udara',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Arti satuan µg/m³',
              icon: const Icon(Icons.info_outline_rounded),
              style: IconButton.styleFrom(
                minimumSize: const Size.square(48),
                visualDensity: VisualDensity.standard,
              ),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Arti satuan µg/m³'),
                  content: const Text(
                    'Angka ini menunjukkan jumlah mikrogram zat dalam satu meter kubik udara.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('Tutup'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        Card(
          child: Column(
            children: [
              for (final pollutant in AirQuality.pollutants.entries) ...[
                if (pollutant.key != AirQuality.pollutants.keys.first)
                  const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  title: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: pollutant.value.label,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: ' · ${pollutant.value.explanation}'),
                      ],
                    ),
                  ),
                  subtitle: Text(data.reading(pollutant.key)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Perkiraan untuk lokasi ini dari Open-Meteo dan CAMS ENSEMBLE.',
        ),
      ],
    );
  }
}
