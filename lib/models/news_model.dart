class NewsArticle {
  final String title;
  final String description;
  final String url;
  final String? urlToImage;
  final String? publishedAt;
  final String? sourceName;
  final String? author;
  final String? content;

  NewsArticle({
    required this.title,
    required this.description,
    required this.url,
    this.urlToImage,
    this.publishedAt,
    this.sourceName,
    this.author,
    this.content,
  });

  factory NewsArticle.fromJson(Map<String, dynamic> json) {
    return NewsArticle(
      title: json['title'] ?? 'No Title',
      description: json['description'] ?? 'No description available.',
      url: json['url'] ?? '',
      urlToImage: json['urlToImage'],
      publishedAt: json['publishedAt'],
      sourceName: json['source']?['name'],
      author: json['author'],
      content: json['content'],
    );
  }
}

// ── Weather model now uses Open-Meteo fields ──────────────────────────────────
class WeatherData {
  final String city;
  final String country;
  final double temperature;
  final double feelsLike;
  final String description;
  final String icon;       // emoji icon derived from WMO weather code
  final int humidity;
  final double windSpeed;

  WeatherData({
    required this.city,
    required this.country,
    required this.temperature,
    required this.feelsLike,
    required this.description,
    required this.icon,
    required this.humidity,
    required this.windSpeed,
  });

  // ── WMO weather code → human label + emoji ──────────────────────────────
  static String wmoDescription(int code) {
    if (code == 0)              return 'Clear Sky';
    if (code <= 2)              return 'Partly Cloudy';
    if (code == 3)              return 'Overcast';
    if (code <= 49)             return 'Foggy';
    if (code <= 57)             return 'Drizzle';
    if (code <= 67)             return 'Rainy';
    if (code <= 77)             return 'Snowy';
    if (code <= 82)             return 'Rain Showers';
    if (code <= 86)             return 'Snow Showers';
    if (code <= 99)             return 'Thunderstorm';
    return 'Unknown';
  }

  static String wmoEmoji(int code) {
    if (code == 0)              return '☀️';
    if (code <= 2)              return '⛅';
    if (code == 3)              return '☁️';
    if (code <= 49)             return '🌫️';
    if (code <= 57)             return '🌦️';
    if (code <= 67)             return '🌧️';
    if (code <= 77)             return '❄️';
    if (code <= 82)             return '🌦️';
    if (code <= 86)             return '🌨️';
    if (code <= 99)             return '⛈️';
    return '🌡️';
  }

  /// Build WeatherData from Open-Meteo /v1/forecast JSON response
  /// [cityName] and [countryName] come from the geocoding step.
  factory WeatherData.fromOpenMeteo(
      Map<String, dynamic> json, String cityName, String countryName) {
    final current = json['current'] as Map<String, dynamic>? ?? {};
    final temp     = (current['temperature_2m']      ?? 0).toDouble();
    final apparent = (current['apparent_temperature'] ?? temp).toDouble();
    final humidity = (current['relative_humidity_2m'] ?? 0).toInt();
    final wind     = (current['wind_speed_10m']       ?? 0).toDouble();
    final code     = (current['weather_code']          ?? 0).toInt();

    return WeatherData(
      city:        cityName,
      country:     countryName,
      temperature: temp,
      feelsLike:   apparent,
      description: wmoDescription(code),
      icon:        wmoEmoji(code),
      humidity:    humidity,
      windSpeed:   wind,
    );
  }
}
