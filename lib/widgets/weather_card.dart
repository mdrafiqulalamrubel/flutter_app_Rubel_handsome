import 'package:flutter/material.dart';
import '../models/news_model.dart';

class WeatherCard extends StatelessWidget {
  final WeatherData weather;
  const WeatherCard({super.key, required this.weather});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF283593), Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A237E).withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── Left: location + temp + condition ──────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Location
                Row(children: [
                  const Icon(Icons.location_on, size: 13, color: Colors.white70),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      weather.country.isNotEmpty
                          ? '${weather.city}, ${weather.country}'
                          : weather.city,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                // Temperature
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${weather.temperature.round()}°',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.w200,
                        height: 1,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text(
                        'C',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 18,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ),
                  ],
                ),
                // Condition label
                Text(
                  weather.description.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),

          // ── Right: emoji + details ──────────────────────────────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Weather emoji (from WMO code — no image URL needed)
              Text(weather.icon, style: const TextStyle(fontSize: 52)),
              const SizedBox(height: 8),
              _detail(Icons.water_drop_outlined, '${weather.humidity}%'),
              const SizedBox(height: 4),
              _detail(Icons.air, '${weather.windSpeed.round()} m/s'),
              const SizedBox(height: 4),
              _detail(Icons.thermostat_outlined,
                  'Feels ${weather.feelsLike.round()}°C'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detail(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.white70),
        const SizedBox(width: 4),
        Text(text,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }
}
