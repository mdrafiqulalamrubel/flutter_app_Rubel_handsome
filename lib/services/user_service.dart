import 'package:shared_preferences/shared_preferences.dart';

class UserService {
  static const _keyName       = 'user_name';
  static const _keyPhone      = 'user_phone';
  static const _keyCity       = 'user_city';
  static const _keyCountry    = 'user_country';
  static const _keyRegistered = 'is_registered';
  static const _keyNewsApiKey = 'news_api_key';

  Future<void> saveUser({
    required String name,
    required String phone,
    required String city,
    required String country,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyName, name);
    await prefs.setString(_keyPhone, phone);
    await prefs.setString(_keyCity, city);
    await prefs.setString(_keyCountry, country);
    await prefs.setBool(_keyRegistered, true);
  }

  Future<Map<String, String>> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'name':    prefs.getString(_keyName)    ?? '',
      'phone':   prefs.getString(_keyPhone)   ?? '',
      'city':    prefs.getString(_keyCity)    ?? '',
      'country': prefs.getString(_keyCountry) ?? '',
    };
  }

  Future<void> updateLocation(String city, String country) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCity, city);
    await prefs.setString(_keyCountry, country);
  }

  // ── API Key management ────────────────────────────────────────────────────
  Future<String> getNewsApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyNewsApiKey) ?? '';
  }

  Future<void> saveNewsApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNewsApiKey, key.trim());
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
