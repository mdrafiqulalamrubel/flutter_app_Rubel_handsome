import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/news_model.dart';
import 'user_service.dart';

class ApiService {
  static const String _newsBase    = 'https://newsapi.org/v2';
  static const String _weatherBase = 'https://api.open-meteo.com/v1/forecast';
  static const String _geoBase     = 'https://geocoding-api.open-meteo.com/v1/search';

  Future<String> _getApiKey() => UserService().getNewsApiKey();

  // ── NEWS ──────────────────────────────────────────────────────────────────

  Future<List<NewsArticle>> getTopHeadlines({
    String category = 'general',
    String? query,
  }) async {
    if (category == 'bangladesh') return _fetchBangladeshNews();
    if (query != null && query.isNotEmpty) return searchNews(query);

    final key = await _getApiKey();
    if (key.isEmpty) return _demoForCategory(category);

    final url =
        '$_newsBase/top-headlines?apiKey=$key&pageSize=30&country=us'
        '${category != 'general' ? '&category=$category' : ''}';
    final results = await _fetchNews(url);
    return results.isEmpty ? _demoForCategory(category) : results;
  }

  // ── BANGLADESH NEWS ───────────────────────────────────────────────────────
  Future<List<NewsArticle>> _fetchBangladeshNews() async {
    final key = await _getApiKey();

    if (key.isNotEmpty) {
      final sourceUrl =
          '$_newsBase/everything?apiKey=$key'
          '&sources=the-times-of-india,bbc-news,reuters,al-jazeera-english'
          '&q=Bangladesh+OR+Dhaka+OR+Bangladesh+government+OR+Bangladesh+economy'
          '&sortBy=publishedAt&pageSize=30&language=en';
      var results = await _fetchNews(sourceUrl);
      if (results.isNotEmpty) return results;

      final kwUrl =
          '$_newsBase/everything?apiKey=$key'
          '&q=%22Bangladesh%22+OR+%22Dhaka%22+OR+%22Prothom+Alo%22+OR+%22Daily+Star+BD%22'
          '&sortBy=publishedAt&pageSize=30&language=en';
      results = await _fetchNews(kwUrl);
      if (results.isNotEmpty) return results;
    }

    return _demoBangladeshNews();
  }

  Future<List<NewsArticle>> searchNews(String query) async {
    final key = await _getApiKey();
    if (key.isEmpty) return _demoForCategory('general');

    final enc = Uri.encodeComponent(query.trim());
    final url =
        '$_newsBase/everything?apiKey=$key&q=$enc'
        '&sortBy=publishedAt&pageSize=30&language=en';
    final results = await _fetchNews(url);
    return results.isEmpty ? _demoForCategory('general') : results;
  }

  Future<List<NewsArticle>> _fetchNews(String url) async {
    try {
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final list = (data['articles'] as List)
            .where((a) =>
                a['title'] != null &&
                a['title'] != '[Removed]' &&
                a['url'] != null)
            .map((a) => NewsArticle.fromJson(a))
            .toList();
        return list;
      }
    } catch (_) {}
    return [];
  }

  // ── WEATHER (Open-Meteo) ──────────────────────────────────────────────────

  Future<WeatherData?> getWeatherByCoords(double lat, double lon,
      {String city = '', String country = ''}) async {
    try {
      String resolvedCity    = city;
      String resolvedCountry = country;
      if (resolvedCity.isEmpty) {
        final geo = await _reverseGeocode(lat, lon);
        resolvedCity    = geo['city']    ?? 'Your Location';
        resolvedCountry = geo['country'] ?? '';
      }

      final url = Uri.parse(_weatherBase).replace(queryParameters: {
        'latitude':  lat.toStringAsFixed(4),
        'longitude': lon.toStringAsFixed(4),
        'current':
            'temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code',
        'wind_speed_unit': 'ms',
        'timezone': 'auto',
      });
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        return WeatherData.fromOpenMeteo(
            json.decode(res.body), resolvedCity, resolvedCountry);
      }
    } catch (_) {}
    return null;
  }

  Future<WeatherData?> getWeatherByCity(String cityName) async {
    try {
      final geoUrl = Uri.parse(_geoBase).replace(queryParameters: {
        'name': cityName, 'count': '1', 'language': 'en', 'format': 'json',
      });
      final geoRes =
          await http.get(geoUrl).timeout(const Duration(seconds: 8));
      if (geoRes.statusCode != 200) return null;

      final results =
          (json.decode(geoRes.body)['results'] as List?) ?? [];
      if (results.isEmpty) return null;

      final place   = results.first as Map<String, dynamic>;
      final lat     = (place['latitude']  as num).toDouble();
      final lon     = (place['longitude'] as num).toDouble();
      final city    = place['name']    as String? ?? cityName;
      final country = place['country'] as String? ?? '';
      return getWeatherByCoords(lat, lon, city: city, country: country);
    } catch (_) {}
    return null;
  }

  // ── REVERSE GEOCODE via Nominatim ─────────────────────────────────────────
  // FIX I1: User-Agent corrected from 'RublesNewsAI/1.0' copy-paste leftover
  Future<Map<String, String>> _reverseGeocode(double lat, double lon) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=json',
      );
      final res = await http
          .get(url, headers: {'User-Agent': 'NewsAIApp/1.0'})
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final address =
            (json.decode(res.body)['address']) as Map<String, dynamic>?;
        return {
          'city': address?['city'] ??
              address?['town'] ??
              address?['village'] ??
              address?['county'] ??
              'Your Location',
          'country': address?['country'] ?? '',
        };
      }
    } catch (_) {}
    return {'city': 'Your Location', 'country': ''};
  }

  Future<Map<String, String>> reverseGeocode(double lat, double lon) =>
      _reverseGeocode(lat, lon);

  // ── DEMO / FALLBACK DATA ──────────────────────────────────────────────────

  List<NewsArticle> _demoBangladeshNews() => [
    NewsArticle(
      title: 'Bangladesh Economy Shows Strong Growth in 2026',
      description:
          'Garment exports hit record highs as Bangladesh GDP growth outpaces regional peers, according to the latest World Bank report.',
      url: 'https://www.thedailystar.net',
      urlToImage:
          'https://images.unsplash.com/photo-1604594849809-dfedbc827105?w=800',
      publishedAt: DateTime.now().toIso8601String(),
      sourceName: 'The Daily Star',
      author: 'Staff Reporter',
    ),
    NewsArticle(
      title: 'Dhaka Metro Rail Expansion Phase 3 Begins',
      description:
          'Dhaka Mass Transit Company announces Phase 3 route connecting Gazipur to Narayanganj, easing the capital\'s severe traffic congestion.',
      url: 'https://www.prothomalo.com/bangladesh',
      urlToImage:
          'https://images.unsplash.com/photo-1544620347-c4fd4a3d5957?w=800',
      publishedAt:
          DateTime.now().subtract(const Duration(hours: 1)).toIso8601String(),
      sourceName: 'Prothom Alo',
      author: 'Dhaka Correspondent',
    ),
    NewsArticle(
      title: 'Bangladesh Cricket Team Wins Series Against Pakistan',
      description:
          'Tigers clinch ODI series 3-1 at Sher-e-Bangla National Cricket Stadium, Mirpur in a thrilling final match.',
      url: 'https://www.cricbuzz.com',
      urlToImage:
          'https://images.unsplash.com/photo-1531415074968-036ba1b575da?w=800',
      publishedAt:
          DateTime.now().subtract(const Duration(hours: 3)).toIso8601String(),
      sourceName: 'BDCricTime',
      author: 'Sports Desk',
    ),
    NewsArticle(
      title: 'Bangladesh Launches National Digital ID Card Initiative',
      description:
          'Government rolls out smart NID cards with biometric data to 50 million citizens, improving access to banking and government services.',
      url: 'https://www.thedailystar.net',
      urlToImage:
          'https://images.unsplash.com/photo-1540910419892-4a36d2c3266c?w=800',
      publishedAt:
          DateTime.now().subtract(const Duration(hours: 5)).toIso8601String(),
      sourceName: 'The Daily Star',
      author: 'Digital Desk',
    ),
    NewsArticle(
      title: 'Padma Bridge Boosts Southern Bangladesh Economy',
      description:
          'One year since the Padma Bridge opened, economic activity in southern Bangladesh districts has surged by over 20%, reports the Bangladesh Bureau of Statistics.',
      url: 'https://www.newagebd.net',
      urlToImage:
          'https://images.unsplash.com/photo-1477959858617-67f85cf4f1df?w=800',
      publishedAt:
          DateTime.now().subtract(const Duration(hours: 7)).toIso8601String(),
      sourceName: 'New Age BD',
      author: 'Economic Reporter',
    ),
    NewsArticle(
      title: 'Chittagong Port Becomes South Asia\'s Fastest Growing Port',
      description:
          'Container throughput at Chittagong Port grew 18% year-on-year, positioning it as one of the fastest growing ports in the entire South Asian region.',
      url: 'https://www.thedailystar.net',
      urlToImage:
          'https://images.unsplash.com/photo-1578575437130-527eed3abbec?w=800',
      publishedAt:
          DateTime.now().subtract(const Duration(hours: 9)).toIso8601String(),
      sourceName: 'The Daily Star',
      author: 'Trade Reporter',
    ),
  ];

  List<NewsArticle> _demoForCategory(String category) {
    final Map<String, List<NewsArticle>> demos = {
      'general': [
        NewsArticle(
          title: 'Global Leaders Gather for Climate Summit 2026',
          description:
              'World leaders convene to discuss new emission targets and climate financing for developing nations.',
          url: 'https://www.bbc.com/news',
          urlToImage:
              'https://images.unsplash.com/photo-1504711434969-e33886168f5c?w=800',
          publishedAt: DateTime.now().toIso8601String(),
          sourceName: 'BBC News',
          author: 'Jane Smith',
        ),
        NewsArticle(
          title: 'Renewable Energy Now Powers 40% of Global Electricity',
          description:
              'A new IEA report shows renewables have hit a historic milestone in global power generation.',
          url: 'https://www.iea.org',
          urlToImage:
              'https://images.unsplash.com/photo-1509391366360-2e959784a276?w=800',
          publishedAt: DateTime.now()
              .subtract(const Duration(hours: 3))
              .toIso8601String(),
          sourceName: 'IEA',
          author: 'Mark Green',
        ),
      ],
      'technology': [
        NewsArticle(
          title: 'AI Chip Breakthrough Doubles Processing Speed',
          description:
              'New semiconductor design enables faster AI inference at dramatically lower power.',
          url: 'https://techcrunch.com',
          urlToImage:
              'https://images.unsplash.com/photo-1518770660439-4636190af475?w=800',
          publishedAt: DateTime.now().toIso8601String(),
          sourceName: 'TechCrunch',
          author: 'Tech Reporter',
        ),
      ],
      'business': [
        NewsArticle(
          title: 'Markets Rally as Inflation Data Shows Cooling Trend',
          description:
              'Stock markets worldwide surged after the latest inflation reports indicated a significant slowdown.',
          url: 'https://www.reuters.com',
          urlToImage:
              'https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=800',
          publishedAt: DateTime.now().toIso8601String(),
          sourceName: 'Reuters',
          author: 'Alice Johnson',
        ),
      ],
      'sports': [
        NewsArticle(
          title: 'World Cup Qualifier Results Round Up',
          description:
              'Key matches decided as teams fight for remaining spots in the upcoming World Cup.',
          url: 'https://bbc.com/sport',
          urlToImage:
              'https://images.unsplash.com/photo-1579952363873-27f3bade9f55?w=800',
          publishedAt: DateTime.now().toIso8601String(),
          sourceName: 'BBC Sport',
          author: 'Sports Desk',
        ),
      ],
      'health': [
        NewsArticle(
          title: 'WHO Reports Decline in Global Infectious Disease Rates',
          description:
              'WHO announces significant progress in reducing disease rates across multiple continents.',
          url: 'https://www.who.int',
          urlToImage:
              'https://images.unsplash.com/photo-1576091160399-112ba8d25d1d?w=800',
          publishedAt: DateTime.now().toIso8601String(),
          sourceName: 'WHO',
          author: 'Dr. Sarah Lee',
        ),
      ],
      'science': [
        NewsArticle(
          title: 'James Webb Telescope Reveals Oldest Known Galaxy',
          description:
              'Astronomers confirm the discovery of a galaxy formed just 300 million years after the Big Bang.',
          url: 'https://www.nasa.gov',
          urlToImage:
              'https://images.unsplash.com/photo-1462331940025-496dfbfc7564?w=800',
          publishedAt: DateTime.now().toIso8601String(),
          sourceName: 'NASA',
          author: 'Astronomy Team',
        ),
      ],
      'entertainment': [
        NewsArticle(
          title: 'Box Office Records Shattered by Summer Blockbuster',
          description:
              'The latest action franchise entry breaks opening weekend records across 47 countries.',
          url: 'https://variety.com',
          urlToImage:
              'https://images.unsplash.com/photo-1489599849927-2ee91cede3ba?w=800',
          publishedAt: DateTime.now().toIso8601String(),
          sourceName: 'Variety',
          author: 'Entertainment Desk',
        ),
      ],
    };
    return demos[category] ?? demos['general']!;
  }
}
