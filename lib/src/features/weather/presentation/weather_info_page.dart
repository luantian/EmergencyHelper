import 'package:emergency_helper/src/core/theme/app_theme.dart';
import 'package:emergency_helper/src/features/weather/data/free_weather_service.dart';
import 'package:flutter/material.dart';
import 'package:weather_animation/weather_animation.dart';

class WeatherInfoPage extends StatefulWidget {
  const WeatherInfoPage({super.key});

  @override
  State<WeatherInfoPage> createState() => _WeatherInfoPageState();
}

class _WeatherInfoPageState extends State<WeatherInfoPage> {
  late final FreeWeatherService _service;
  Future<WeatherSnapshot>? _future;

  @override
  void initState() {
    super.initState();
    _service = FreeWeatherService();
    _future = _service.fetchShenyangForecast();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6FC),
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        title: const Text('\u5929\u6c14\u4fe1\u606f'),
      ),
      body: FutureBuilder<WeatherSnapshot>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData) {
            final message =
                (snapshot.error?.toString() ??
                        '\u5929\u6c14\u6570\u636e\u83b7\u53d6\u5931\u8d25')
                    .replaceFirst('Exception: ', '');
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFDCE7F5)),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x140F2239),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '\u5929\u6c14\u6570\u636e\u83b7\u53d6\u5931\u8d25',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2D3D),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF617089),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _future = _service.fetchShenyangForecast();
                          });
                        },
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('\u91cd\u8bd5'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return _WeatherView(data: snapshot.data!);
        },
      ),
    );
  }
}

class _WeatherView extends StatelessWidget {
  const _WeatherView({required this.data});

  final WeatherSnapshot data;

  @override
  Widget build(BuildContext context) {
    final visual = _visualTypeForCode(data.currentWeatherCode);
    final hourlyItems = data.hourly.take(12).toList(growable: false);
    final dailyItems = data.daily.take(6).toList(growable: false);
    final todayMax = dailyItems.isNotEmpty ? dailyItems.first.maxTemp : null;
    final todayMin = dailyItems.isNotEmpty ? dailyItems.first.minTemp : null;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.zero,
              child: SizedBox(
                height: 286,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _sceneByVisual(visual),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x3F000000), Color(0x15000000)],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0x2EFFFFFF),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.location_on_outlined,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      data.cityName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              Text(
                                _weatherText(data.currentWeatherCode),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${data.currentTemp.round()}°',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 72,
                                        height: 0.9,
                                        fontWeight: FontWeight.w300,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    if (todayMax != null && todayMin != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: Text(
                                          '${todayMax.round()}° / ${todayMin.round()}°',
                                          style: const TextStyle(
                                            color: Color(0xE3FFFFFF),
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                width: 76,
                                height: 76,
                                decoration: BoxDecoration(
                                  color: const Color(0x22FFFFFF),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0x45FFFFFF),
                                    width: 1,
                                  ),
                                ),
                                child: Icon(
                                  _iconForCode(data.currentWeatherCode),
                                  color: Colors.white,
                                  size: 42,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              _NowMetricChip(
                                icon: Icons.opacity_rounded,
                                label: '\u6e7f\u5ea6 ${data.currentHumidity}%',
                              ),
                              _NowMetricChip(
                                icon: Icons.air_rounded,
                                label:
                                    '\u98ce\u901f ${data.currentWindSpeed.toStringAsFixed(1)} km/h',
                              ),
                            ],
                          ),
                          const Spacer(),
                          _HourlyForecastStrip(items: hourlyItems),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: const Color(0xFFDDE8F5)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x100F2239),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  children: [
                    const _SectionHeader(title: '\u672a\u6765\u516d\u5929'),
                    const SizedBox(height: 8),
                    for (var index = 0; index < dailyItems.length; index++)
                      _DailyRow(
                        item: dailyItems[index],
                        isLast: index == dailyItems.length - 1,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: const Color(0xFFDDE8F5)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x100F2239),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _BottomInfoItem(
                      label: '\u6e29\u5ea6',
                      value: '${data.currentTemp.round()}\u00B0',
                    ),
                  ),
                  Expanded(
                    child: _BottomInfoItem(
                      label: '\u7d2b\u5916\u7ebf',
                      value: dailyItems.isNotEmpty
                          ? dailyItems.first.uvIndex.toStringAsFixed(1)
                          : '--',
                    ),
                  ),
                  Expanded(
                    child: _BottomInfoItem(
                      label: '\u65e5\u51fa',
                      value: _formatClock(data.sunrise),
                    ),
                  ),
                  Expanded(
                    child: _BottomInfoItem(
                      label: '\u65e5\u843d',
                      value: _formatClock(data.sunset),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: AppTheme.primaryBlue,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF1E2D3E),
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _NowMetricChip extends StatelessWidget {
  const _NowMetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x2BFFFFFF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HourlyForecastStrip extends StatelessWidget {
  const _HourlyForecastStrip({required this.items});

  final List<WeatherHour> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x24FFFFFF),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SizedBox(
        height: 88,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 4),
          itemBuilder: (context, index) {
            final item = items[index];
            return SizedBox(
              width: 62,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatHour(item.time),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Icon(
                    _iconForCode(item.weatherCode),
                    color: Colors.white,
                    size: 18,
                  ),
                  Text(
                    '${item.temperature.round()}°',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DailyRow extends StatelessWidget {
  const _DailyRow({required this.item, required this.isLast});

  final WeatherDay item;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final weekday = _weekdayCn(item.date.weekday);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0xFFEAF1FA), width: 1),
              ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(
              '${item.date.month}/${item.date.day}\n$weekday',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6A7990),
                height: 1.35,
              ),
            ),
          ),
          Icon(
            _iconForCodeByTemp(item.maxTemp, item.minTemp),
            size: 20,
            color: const Color(0xFF475E7B),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${item.maxTemp.round()}° / ${item.minTemp.round()}°',
              style: const TextStyle(
                color: Color(0xFF1F2D3E),
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            '\u964d\u6c34 ${item.rainProbability}%',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF7A879B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomInfoItem extends StatelessWidget {
  const _BottomInfoItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF8090A6),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              color: Color(0xFF1F2D3E),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

Widget _sceneByVisual(_WeatherVisual visual) {
  switch (visual) {
    case _WeatherVisual.sunny:
      return const WrapperScene(
        colors: [Color(0xFF3A8BEB), Color(0xFF69B0FF)],
        children: [SunWidget(), CloudWidget(), WindWidget()],
      );
    case _WeatherVisual.cloudy:
      return const WrapperScene(
        colors: [Color(0xFF4E6F9E), Color(0xFF8199BF)],
        children: [CloudWidget(), CloudWidget(), WindWidget()],
      );
    case _WeatherVisual.rainy:
      return const WrapperScene(
        colors: [Color(0xFF3D5E8D), Color(0xFF5F7CA3)],
        children: [CloudWidget(), RainWidget(), WindWidget()],
      );
    case _WeatherVisual.snowy:
      return const WrapperScene(
        colors: [Color(0xFF627C9E), Color(0xFF91A8C3)],
        children: [CloudWidget(), SnowWidget()],
      );
  }
}

enum _WeatherVisual { sunny, cloudy, rainy, snowy }

_WeatherVisual _visualTypeForCode(int code) {
  if (code >= 400 && code < 500) {
    return _WeatherVisual.snowy;
  }
  if (code >= 300 && code < 400) {
    return _WeatherVisual.rainy;
  }
  if (code == 100 || code == 150) {
    return _WeatherVisual.sunny;
  }
  if ((code >= 101 && code <= 104) || (code >= 151 && code <= 154)) {
    return _WeatherVisual.cloudy;
  }
  return _WeatherVisual.cloudy;
}

String _weatherText(int code) {
  if (code == 100 || code == 150) {
    return '\u6674';
  }
  if ((code >= 101 && code <= 104) || (code >= 151 && code <= 154)) {
    return '\u591a\u4e91';
  }
  if (code >= 300 && code < 400) {
    return '\u96e8';
  }
  if (code >= 400 && code < 500) {
    return '\u96ea';
  }
  return '\u591a\u4e91';
}

IconData _iconForCode(int code) {
  if (code == 100 || code == 150) {
    return Icons.wb_sunny_rounded;
  }
  if ((code >= 101 && code <= 104) || (code >= 151 && code <= 154)) {
    return Icons.wb_cloudy_rounded;
  }
  if (code >= 300 && code < 400) {
    return Icons.grain_rounded;
  }
  if (code >= 400 && code < 500) {
    return Icons.ac_unit_rounded;
  }
  return Icons.cloud_queue_rounded;
}

IconData _iconForCodeByTemp(double maxTemp, double minTemp) {
  if (maxTemp <= 0 || minTemp <= 0) {
    return Icons.ac_unit_rounded;
  }
  if (maxTemp >= 30) {
    return Icons.wb_sunny_rounded;
  }
  return Icons.wb_cloudy_rounded;
}

String _weekdayCn(int weekday) {
  switch (weekday) {
    case DateTime.monday:
      return '\u5468\u4e00';
    case DateTime.tuesday:
      return '\u5468\u4e8c';
    case DateTime.wednesday:
      return '\u5468\u4e09';
    case DateTime.thursday:
      return '\u5468\u56db';
    case DateTime.friday:
      return '\u5468\u4e94';
    case DateTime.saturday:
      return '\u5468\u516d';
    default:
      return '\u5468\u65e5';
  }
}

String _formatHour(DateTime value) {
  return '${value.hour.toString().padLeft(2, '0')}:00';
}

String _formatClock(DateTime? value) {
  if (value == null) {
    return '--';
  }
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
