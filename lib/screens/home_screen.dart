import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../models/news_model.dart';
import '../services/api_service.dart';
import '../services/user_service.dart';
import '../widgets/news_card.dart';
import '../widgets/weather_card.dart';
import 'search_screen.dart';
import 'profile_screen.dart';
import 'prayer_compass_screen.dart';
import 'weather_forecast_screen.dart';
import 'step_counter_screen.dart';
import 'currency_converter_screen.dart';

// ── Change app name here ─────────────────────────────────────────────────────
const String kAppName = "Rubel Handsome";

const List<Map<String, dynamic>> kCategories = [
  {'label': 'Top Stories',   'icon': Icons.auto_awesome,       'value': 'general'},  
  {'label': 'Technology',    'icon': Icons.computer,           'value': 'technology'},
  {'label': 'Business',      'icon': Icons.business_center,    'value': 'business'},
  {'label': 'Sports',        'icon': Icons.sports_soccer,      'value': 'sports'},
  {'label': 'Health',        'icon': Icons.health_and_safety,  'value': 'health'},
  {'label': 'Science',       'icon': Icons.science,            'value': 'science'},
  {'label': 'Entertainment', 'icon': Icons.movie,              'value': 'entertainment'},
];

// ════════════════════════════════════════════════════════════════════════════
//  CUSTOM PERSISTENT HEADER DELEGATE
//  This guarantees ONE set of buttons — no SliverAppBar title/flexibleSpace
//  overlap problem. The header shrinks as the user scrolls.
// ════════════════════════════════════════════════════════════════════════════
class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  final String userName;
  final String greeting;
  final String timeStr;
  final String dateStr;
  final VoidCallback onRefresh;
  final VoidCallback onNotification;

  const _HeaderDelegate({
    required this.userName,
    required this.greeting,
    required this.timeStr,
    required this.dateStr,
    required this.onRefresh,
    required this.onNotification,
  });

  static const double _maxH = 130.0;
  static const double _minH = 60.0;

  @override double get maxExtent => _maxH;
  @override double get minExtent => _minH;
  @override bool shouldRebuild(_HeaderDelegate old) => true;

  @override
  Widget build(BuildContext ctx, double shrinkOffset, bool overlapsContent) {
    // 0.0 = fully expanded, 1.0 = fully collapsed
    final t = (shrinkOffset / (_maxH - _minH)).clamp(0.0, 1.0);
    final showDetail = t < 0.5; // show greeting/date row only when expanded

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFF6B00), Color(0xFFFF8C2A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Always-visible row: app name + ONE bell + ONE refresh ──
              Row(
                children: [
                  const Icon(Icons.newspaper_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      kAppName,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: showDetail ? 22 : 18,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 🔔 Notification button
                  _Btn(
                    icon: Icons.notifications_active_outlined,
                    onTap: onNotification,
                    badge: true,   // orange dot = "active"
                  ),
                  const SizedBox(width: 8),
                  // 🔄 ONE refresh button only
                  _Btn(icon: Icons.refresh_rounded, onTap: onRefresh),
                ],
              ),

              // ── Collapsible: greeting + date/time ─────────────────────
              if (showDetail) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    // Greeting
                    Expanded(
                      child: Text(
                        '$greeting, ${userName.split(' ').first}! 👋',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Date
                    const Icon(Icons.calendar_today_rounded,
                        color: Colors.white70, size: 12),
                    const SizedBox(width: 4),
                    Text(dateStr,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11)),
                    const SizedBox(width: 10),
                    // Time
                    const Icon(Icons.access_time_rounded,
                        color: Colors.white70, size: 12),
                    const SizedBox(width: 4),
                    Text(
                      timeStr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Small icon button used inside the header
class _Btn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool badge;
  const _Btn({required this.icon, required this.onTap, this.badge = false});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.white.withOpacity(0.22),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
          ),
        ),
        if (badge)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFFFFD600),
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  HOME SCREEN
// ════════════════════════════════════════════════════════════════════════════
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _apiService = ApiService();
  final _userService = UserService();

  List<NewsArticle> _articles = [];
  WeatherData? _weather;
  bool _loadingNews = true;
  bool _loadingWeather = true;
  int _selectedCategory = 0;
  String _userName = '';
  String _userCity = '';
  late DateTime _now;
  Timer? _clockTimer;
  int _currentTab = 0;
  int _notifCount = 0;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _loadUser();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final user = await _userService.getUser();
    setState(() {
      _userName = user['name'] ?? '';
      _userCity  = user['city'] ?? '';
    });
    _loadNews();
    _loadWeather();
  }

  Future<void> _loadNews({String? category}) async {
    setState(() => _loadingNews = true);
    final cat = category ?? kCategories[_selectedCategory]['value'] as String;
    final articles = await _apiService.getTopHeadlines(category: cat);
    setState(() {
      _articles = articles;
      _loadingNews = false;
      // Simulate a new notification badge when news refreshes
      if (articles.isNotEmpty) _notifCount++;
    });
  }

  Future<void> _loadWeather() async {
    setState(() => _loadingWeather = true);
    WeatherData? weather;
    try {
      final ok = await Geolocator.isLocationServiceEnabled();
      if (ok) {
        var perm = await Geolocator.checkPermission();
        // Request permission if not yet granted
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.always ||
            perm == LocationPermission.whileInUse) {
          final pos = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.medium);
          // getWeatherByCoords now auto-reverse-geocodes the city name
          weather = await _apiService.getWeatherByCoords(
              pos.latitude, pos.longitude);
        }
      }
    } catch (_) {}
    // Fall back to saved city from profile
    if (weather == null && _userCity.isNotEmpty) {
      weather = await _apiService.getWeatherByCity(_userCity);
    }
    setState(() {
      _weather = weather;
      _loadingWeather = false;
    });
  }

  Future<void> _doRefresh() async {
    await Future.wait([_loadNews(), _loadWeather()]);
  }

  void _onNotificationTap() {
    setState(() => _notifCount = 0);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.notifications_active, color: Color(0xFFFF6B00)),
          SizedBox(width: 8),
          Text('Notifications'),
        ]),
        content: const Text(
          'You are up to date!\nPull down to refresh for the latest news.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK',
                style: TextStyle(color: Color(0xFFFF6B00))),
          ),
        ],
      ),
    );
  }

  String get _greeting {
    final h = _now.hour;
    if (h < 12) return 'Good Morning';
    if (h < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  // ════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F5),
      body: IndexedStack(
        index: _currentTab,
        children: [
          _buildNewsTab(),
          SearchScreen(apiService: _apiService),
          const WeatherForecastScreen(),
          const PrayerCompassScreen(),
          const StepCounterScreen(),
          const CurrencyConverterScreen(),
          ProfileScreen(onLocationUpdated: _loadUser),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  void _onTabTap(int i) => setState(() => _currentTab = i);

  // ── NEWS TAB ─────────────────────────────────────────────────────────────
  Widget _buildNewsTab() {
    final timeStr = DateFormat('hh:mm:ss a').format(_now);
    final dateStr = DateFormat('EEE, d MMM yyyy').format(_now);

    return RefreshIndicator(
      color: const Color(0xFFFF6B00),
      onRefresh: _doRefresh,
      child: CustomScrollView(
        slivers: [
          // ── Custom persistent header — guaranteed NO duplicate buttons ──
          SliverPersistentHeader(
            pinned: true,
            delegate: _HeaderDelegate(
              userName:    _userName,
              greeting:    _greeting,
              timeStr:     timeStr,
              dateStr:     dateStr,
              onRefresh:   _doRefresh,
              onNotification: _onNotificationTap,
            ),
          ),

          // ── Weather + category chips ─────────────────────────────────
          SliverToBoxAdapter(child: _buildBelowHeader()),

          // ── News list ────────────────────────────────────────────────
          if (_loadingNews)
            const SliverFillRemaining(
              child: Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFFFF6B00))),
            )
          else if (_articles.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.newspaper_outlined,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('No news available',
                          style: TextStyle(color: Colors.grey[600])),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _loadNews,
                        child: const Text('Retry',
                            style: TextStyle(color: Color(0xFFFF6B00))),
                      ),
                    ]),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => NewsCard(article: _articles[i]),
                  childCount: _articles.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── WEATHER CARD + CATEGORY CHIPS ────────────────────────────────────────
  Widget _buildBelowHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),

        // Weather
        if (_loadingWeather)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(
              color: Color(0xFFFF6B00),
              backgroundColor: Color(0xFFFFE0C7),
              minHeight: 3,
            ),
          ),
        if (!_loadingWeather && _weather != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: WeatherCard(weather: _weather!),
          ),
        if (!_loadingWeather && _weather == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFE0C7)),
              ),
              child: const Row(children: [
                Icon(Icons.cloud_off_outlined,
                    color: Color(0xFFFF6B00), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Weather unavailable – GPS or city not found',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ]),
            ),
          ),

        const SizedBox(height: 10),

        // Category chips
        SizedBox(
          height: 46,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: kCategories.length,
            itemBuilder: (ctx, i) {
              final sel = _selectedCategory == i;
              return GestureDetector(
                onTap: () {
                  setState(() => _selectedCategory = i);
                  _loadNews(
                      category: kCategories[i]['value'] as String);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 13, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: sel
                        ? const LinearGradient(colors: [
                            Color(0xFFFF6B00),
                            Color(0xFFFF9A3C)
                          ])
                        : null,
                    color: sel ? null : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel
                          ? Colors.transparent
                          : const Color(0xFFFFE0C7),
                    ),
                    boxShadow: sel
                        ? [
                            BoxShadow(
                              color: const Color(0xFFFF6B00)
                                  .withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : [],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        kCategories[i]['icon'] as IconData,
                        size: 13,
                        color: sel
                            ? Colors.white
                            : const Color(0xFFFF6B00),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        kCategories[i]['label'] as String,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: sel
                              ? Colors.white
                              : const Color(0xFF555555),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  // ── BOTTOM NAV ────────────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, -5),
          )
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: _onTabTap,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFFFF6B00),
        unselectedItemColor: Colors.grey,
        selectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 10),
        unselectedLabelStyle: const TextStyle(fontSize: 10),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.search_outlined),
              activeIcon: Icon(Icons.search),
              label: 'Search'),
          BottomNavigationBarItem(
              icon: Icon(Icons.cloud_outlined),
              activeIcon: Icon(Icons.cloud),
              label: 'Weather'),
          BottomNavigationBarItem(
              icon: Icon(Icons.explore_outlined),
              activeIcon: Icon(Icons.explore),
              label: 'Qibla'),
          BottomNavigationBarItem(
              icon: Icon(Icons.directions_walk_outlined),
              activeIcon: Icon(Icons.directions_walk),
              label: 'Steps'),
          BottomNavigationBarItem(
              icon: Icon(Icons.currency_exchange_outlined),
              activeIcon: Icon(Icons.currency_exchange),
              label: 'Currency'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
      ),
    );
  }
}

