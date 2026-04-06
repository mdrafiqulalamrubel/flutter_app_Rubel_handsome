import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/news_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  WEATHER FORECAST SCREEN
//  • Users can search weather by city name, country, or coordinates
//  • Uses Open-Meteo (free, no API key) + Open-Meteo Geocoding API
//  • Shows current conditions + 7-day forecast
// ─────────────────────────────────────────────────────────────────────────────

class WeatherForecastScreen extends StatefulWidget {
  const WeatherForecastScreen({super.key});

  @override
  State<WeatherForecastScreen> createState() => _WeatherForecastScreenState();
}

class _WeatherForecastScreenState extends State<WeatherForecastScreen> {
  static const String _weatherBase = 'https://api.open-meteo.com/v1/forecast';
  static const String _geoBase = 'https://geocoding-api.open-meteo.com/v1/search';

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  WeatherData? _current;
  List<_DayForecast> _forecast = [];
  List<_GeoResult> _suggestions = [];

  bool _loadingSearch = false;
  bool _loadingWeather = false;
  bool _showSuggestions = false;
  String _error = '';
  String _selectedCity = '';
  String _selectedCountry = '';

  // Popular cities for quick access
  final List<Map<String, String>> _popularCities = [
    {'name': 'Dhaka', 'country': 'Bangladesh', 'emoji': '🇧🇩'},
    {'name': 'London', 'country': 'United Kingdom', 'emoji': '🇬🇧'},
    {'name': 'New York', 'country': 'United States', 'emoji': '🇺🇸'},
    {'name': 'Dubai', 'country': 'UAE', 'emoji': '🇦🇪'},
    {'name': 'Singapore', 'country': 'Singapore', 'emoji': '🇸🇬'},
    {'name': 'Mecca', 'country': 'Saudi Arabia', 'emoji': '🇸🇦'},
    {'name': 'Tokyo', 'country': 'Japan', 'emoji': '🇯🇵'},
    {'name': 'Sydney', 'country': 'Australia', 'emoji': '🇦🇺'},
  ];

  @override
  void initState() {
    super.initState();
    // Load Dhaka weather by default
    _loadWeatherByCity('Dhaka', 'Bangladesh');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Geocoding search ───────────────────────────────────────────────────────
  Future<void> _onSearchChanged(String q) async {
    if (q.trim().length < 2) {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
      return;
    }
    setState(() => _loadingSearch = true);
    try {
      final uri = Uri.parse(_geoBase).replace(queryParameters: {
        'name': q.trim(),
        'count': '6',
        'language': 'en',
        'format': 'json',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final results = (data['results'] as List?) ?? [];
        setState(() {
          _suggestions = results
              .map((r) => _GeoResult.fromJson(r as Map<String, dynamic>))
              .toList();
          _showSuggestions = _suggestions.isNotEmpty;
        });
      }
    } catch (_) {}
    setState(() => _loadingSearch = false);
  }

  Future<void> _selectSuggestion(_GeoResult geo) async {
    _searchCtrl.text = '${geo.name}, ${geo.country}';
    _searchFocus.unfocus();
    setState(() {
      _showSuggestions = false;
      _suggestions = [];
    });
    await _loadWeatherByCoords(geo.lat, geo.lon, geo.name, geo.country);
  }

  Future<void> _onSearchSubmit() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    _searchFocus.unfocus();
    setState(() => _showSuggestions = false);
    await _loadWeatherByCity(q, '');
  }

  // ── Weather loading ────────────────────────────────────────────────────────
  Future<void> _loadWeatherByCity(String city, String country) async {
    setState(() {
      _loadingWeather = true;
      _error = '';
    });
    try {
      final uri = Uri.parse(_geoBase).replace(queryParameters: {
        'name': city, 'count': '1', 'language': 'en', 'format': 'json',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final results = (json.decode(res.body)['results'] as List?) ?? [];
        if (results.isNotEmpty) {
          final place = results.first as Map<String, dynamic>;
          await _loadWeatherByCoords(
            (place['latitude'] as num).toDouble(),
            (place['longitude'] as num).toDouble(),
            place['name'] as String? ?? city,
            place['country'] as String? ?? country,
          );
          return;
        }
      }
      setState(() {
        _error = 'City "$city" not found. Try a different spelling.';
        _loadingWeather = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Network error. Please check your connection.';
        _loadingWeather = false;
      });
    }
  }

  Future<void> _loadWeatherByCoords(
      double lat, double lon, String city, String country) async {
    setState(() {
      _loadingWeather = true;
      _error = '';
      _selectedCity = city;
      _selectedCountry = country;
    });
    try {
      final uri = Uri.parse(_weatherBase).replace(queryParameters: {
        'latitude': lat.toStringAsFixed(4),
        'longitude': lon.toStringAsFixed(4),
        'current':
            'temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,precipitation',
        'daily':
            'weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,wind_speed_10m_max',
        'wind_speed_unit': 'ms',
        'timezone': 'auto',
        'forecast_days': '7',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        _current = WeatherData.fromOpenMeteo(data, city, country);
        _forecast = _parseForecast(data);
        setState(() => _loadingWeather = false);
        return;
      }
    } catch (_) {}
    setState(() {
      _error = 'Could not fetch weather data. Try again.';
      _loadingWeather = false;
    });
  }

  List<_DayForecast> _parseForecast(Map<String, dynamic> data) {
    final daily = data['daily'] as Map<String, dynamic>? ?? {};
    final dates = (daily['time'] as List?)?.cast<String>() ?? [];
    final codes = (daily['weather_code'] as List?)?.cast<int>() ?? [];
    final maxTemps = (daily['temperature_2m_max'] as List?)
            ?.map((v) => (v as num).toDouble())
            .toList() ??
        [];
    final minTemps = (daily['temperature_2m_min'] as List?)
            ?.map((v) => (v as num).toDouble())
            .toList() ??
        [];
    final precips = (daily['precipitation_sum'] as List?)
            ?.map((v) => (v as num).toDouble())
            .toList() ??
        [];
    final winds = (daily['wind_speed_10m_max'] as List?)
            ?.map((v) => (v as num).toDouble())
            .toList() ??
        [];

    final result = <_DayForecast>[];
    for (int i = 0; i < dates.length && i < 7; i++) {
      result.add(_DayForecast(
        date: dates[i],
        code: i < codes.length ? codes[i] : 0,
        maxTemp: i < maxTemps.length ? maxTemps[i] : 0,
        minTemp: i < minTemps.length ? minTemps[i] : 0,
        precipitation: i < precips.length ? precips[i] : 0,
        windSpeed: i < winds.length ? winds[i] : 0,
      ));
    }
    return result;
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Row(children: [
          Text('⛅', style: TextStyle(fontSize: 20)),
          SizedBox(width: 8),
          Text('Weather Forecast',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        ]),
      ),
      body: GestureDetector(
        onTap: () {
          _searchFocus.unfocus();
          setState(() => _showSuggestions = false);
        },
        child: Stack(
          children: [
            Column(
              children: [
                // ── Search bar ─────────────────────────────────────────
                _buildSearchBar(),
                // ── Body content ───────────────────────────────────────
                Expanded(
                  child: _loadingWeather
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: Color(0xFF1A237E)))
                      : _error.isNotEmpty
                          ? _buildError()
                          : _buildWeatherContent(),
                ),
              ],
            ),
            // ── Autocomplete dropdown ──────────────────────────────────
            if (_showSuggestions) _buildSuggestionsOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: const Color(0xFF1A237E),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              onChanged: _onSearchChanged,
              onSubmitted: (_) => _onSearchSubmit(),
              decoration: InputDecoration(
                hintText: 'Search city, country (e.g. Tokyo, Japan)…',
                hintStyle:
                    const TextStyle(color: Colors.grey, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF1A237E)),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_loadingSearch)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF1A237E)),
                        ),
                      ),
                    if (_searchCtrl.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        color: Colors.grey,
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {
                            _suggestions = [];
                            _showSuggestions = false;
                          });
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.send_rounded,
                          color: Color(0xFF1A237E), size: 20),
                      onPressed: _onSearchSubmit,
                    ),
                  ],
                ),
                border: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsOverlay() {
    return Positioned(
      top: 72,
      left: 16,
      right: 16,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 280),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: _suggestions.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final s = _suggestions[i];
              return ListTile(
                dense: true,
                leading: const Icon(Icons.location_city,
                    color: Color(0xFF1A237E), size: 20),
                title: Text(s.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text(
                  [s.admin1, s.country]
                      .where((v) => v.isNotEmpty)
                      .join(', '),
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: Text(s.countryCode,
                    style: const TextStyle(
                        fontSize: 20)),
                onTap: () => _selectSuggestion(s),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildError() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('⛅', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              Text(_error,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 15, color: Colors.black54)),
              const SizedBox(height: 24),
              // Popular cities quick pick
              const Text('Try a popular city:',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A237E))),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: _popularCities.take(4).map((c) {
                  return ActionChip(
                    label: Text('${c['emoji']} ${c['name']}'),
                    onPressed: () =>
                        _loadWeatherByCity(c['name']!, c['country']!),
                    backgroundColor: const Color(0xFFE8EAF6),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      );

  Widget _buildWeatherContent() {
    if (_current == null) return const SizedBox.shrink();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Current weather card ─────────────────────────────────────
          _buildCurrentCard(),
          const SizedBox(height: 16),
          // ── Quick city picks ─────────────────────────────────────────
          _buildQuickPicks(),
          const SizedBox(height: 16),
          // ── 7-day forecast ───────────────────────────────────────────
          if (_forecast.isNotEmpty) ...[
            const Text(
              '7-DAY FORECAST',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                  color: Color(0xFF1A237E)),
            ),
            const SizedBox(height: 8),
            _buildForecastList(),
          ],
        ],
      ),
    );
  }

  Widget _buildCurrentCard() {
    final w = _current!;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF283593), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A237E).withOpacity(0.35),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Location
          Row(children: [
            const Icon(Icons.location_on, color: Colors.white70, size: 15),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                w.country.isNotEmpty
                    ? '${w.city}, ${w.country}'
                    : w.city,
                style: const TextStyle(
                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: () =>
                  _loadWeatherByCity(_selectedCity, _selectedCountry),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.refresh, color: Colors.white, size: 16),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${w.temperature.round()}°',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 72,
                            fontWeight: FontWeight.w100,
                            height: 1,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text('C',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w300)),
                        ),
                      ],
                    ),
                    Text(
                      w.description.toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(w.icon, style: const TextStyle(fontSize: 64)),
                  const SizedBox(height: 8),
                  _statRow(Icons.water_drop_outlined, '${w.humidity}% humidity'),
                  const SizedBox(height: 4),
                  _statRow(Icons.air, '${w.windSpeed.round()} m/s wind'),
                  const SizedBox(height: 4),
                  _statRow(Icons.thermostat_outlined,
                      'Feels ${w.feelsLike.round()}°C'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statRow(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white70),
          const SizedBox(width: 4),
          Text(text,
              style:
                  const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      );

  Widget _buildQuickPicks() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'QUICK SEARCH',
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: Color(0xFF1A237E)),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _popularCities.length,
            itemBuilder: (ctx, i) {
              final c = _popularCities[i];
              final isSelected = _selectedCity == c['name'];
              return GestureDetector(
                onTap: () {
                  _searchCtrl.text = '${c['name']}, ${c['country']}';
                  _loadWeatherByCity(c['name']!, c['country']!);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? const LinearGradient(colors: [
                            Color(0xFF1A237E),
                            Color(0xFF283593)
                          ])
                        : null,
                    color: isSelected ? null : Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                        color: isSelected
                            ? Colors.transparent
                            : const Color(0xFFBFC8E2)),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(0xFF1A237E).withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : [],
                  ),
                  child: Text(
                    '${c['emoji']} ${c['name']}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF374151),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildForecastList() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: _forecast.asMap().entries.map((e) {
          final isLast = e.key == _forecast.length - 1;
          return _ForecastRow(day: e.value, isLast: isLast);
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  FORECAST ROW
// ─────────────────────────────────────────────────────────────────────────────
class _ForecastRow extends StatelessWidget {
  final _DayForecast day;
  final bool isLast;
  const _ForecastRow({required this.day, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(day.date);
    final dayName = date != null
        ? _dayName(date.weekday)
        : day.date;
    final isToday = date != null &&
        date.day == DateTime.now().day &&
        date.month == DateTime.now().month;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  isToday ? 'Today' : dayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isToday
                        ? const Color(0xFF1A237E)
                        : const Color(0xFF374151),
                  ),
                ),
              ),
              Text(
                WeatherData.wmoEmoji(day.code),
                style: const TextStyle(fontSize: 22),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  WeatherData.wmoDescription(day.code),
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF6B7280)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Temp range
              Row(
                children: [
                  Text(
                    '${day.minTemp.round()}°',
                    style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w600),
                  ),
                  const Text(' / ',
                      style: TextStyle(color: Color(0xFFBDBDBD))),
                  Text(
                    '${day.maxTemp.round()}°',
                    style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF1A237E),
                        fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              // Precipitation
              Row(
                children: [
                  const Icon(Icons.water_drop,
                      size: 12, color: Color(0xFF60A5FA)),
                  const SizedBox(width: 2),
                  Text(
                    '${day.precipitation.toStringAsFixed(0)}mm',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!isLast) const Divider(height: 1, indent: 16),
      ],
    );
  }

  String _dayName(int weekday) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[(weekday - 1).clamp(0, 6)];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DATA MODELS
// ─────────────────────────────────────────────────────────────────────────────
class _DayForecast {
  final String date;
  final int code;
  final double maxTemp;
  final double minTemp;
  final double precipitation;
  final double windSpeed;

  const _DayForecast({
    required this.date,
    required this.code,
    required this.maxTemp,
    required this.minTemp,
    required this.precipitation,
    required this.windSpeed,
  });
}

class _GeoResult {
  final String name;
  final String admin1;
  final String country;
  final String countryCode;
  final double lat;
  final double lon;

  const _GeoResult({
    required this.name,
    required this.admin1,
    required this.country,
    required this.countryCode,
    required this.lat,
    required this.lon,
  });

  factory _GeoResult.fromJson(Map<String, dynamic> j) => _GeoResult(
        name: j['name'] as String? ?? '',
        admin1: j['admin1'] as String? ?? '',
        country: j['country'] as String? ?? '',
        countryCode: _flag(j['country_code'] as String? ?? ''),
        lat: (j['latitude'] as num).toDouble(),
        lon: (j['longitude'] as num).toDouble(),
      );

  static String _flag(String code) {
    if (code.length != 2) return '🌍';
    final base = 0x1F1E6;
    final chars = code.toUpperCase().codeUnits;
    return String.fromCharCode(base + chars[0] - 65) +
        String.fromCharCode(base + chars[1] - 65);
  }
}
