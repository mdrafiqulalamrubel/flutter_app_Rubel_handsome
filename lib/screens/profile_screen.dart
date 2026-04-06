import 'package:flutter/material.dart';
import '../services/user_service.dart';
import '../services/api_service.dart';
import 'onboarding_screen.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback onLocationUpdated;
  const ProfileScreen({super.key, required this.onLocationUpdated});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _userService  = UserService();
  final _apiKeyCtrl   = TextEditingController();
  Map<String, String> _user = {};
  bool _apiKeyVisible = false;
  bool _apiKeySaved   = false;
  String _currentKey  = '';

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadApiKey();
  }

  Future<void> _loadUser() async {
    final user = await _userService.getUser();
    setState(() => _user = user);
  }

  Future<void> _loadApiKey() async {
    final key = await _userService.getNewsApiKey();
    setState(() {
      _currentKey = key;
      _apiKeyCtrl.text = key;
    });
  }

  Future<void> _saveApiKey() async {
    final key = _apiKeyCtrl.text.trim();
    if (key.isEmpty) {
      _showSnack('Please enter your NewsAPI key.', error: true);
      return;
    }
    // Basic validation — NewsAPI keys are 32 hex chars
    if (key.length < 20) {
      _showSnack('That doesn\'t look like a valid key.', error: true);
      return;
    }
    await _userService.saveNewsApiKey(key);
    setState(() { _currentKey = key; _apiKeySaved = true; });
    _showSnack('API key saved! News will now load live.', error: false);
    // Trigger a news refresh on home
    widget.onLocationUpdated();
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.redAccent : Colors.green,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B00)),
            child:
                const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _userService.logout();
      if (!mounted) return;
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const OnboardingScreen()));
    }
  }

  @override
  void dispose() {
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initials = (_user['name']?.isNotEmpty == true)
        ? _user['name']!
            .split(' ')
            .map((e) => e[0])
            .take(2)
            .join()
            .toUpperCase()
        : 'U';

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F5),
      body: CustomScrollView(
        slivers: [
          // ── Profile Header ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFF6B00), Color(0xFFFF9A3C)],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 20,
                bottom: 32,
                left: 20,
                right: 20,
              ),
              child: Column(children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: Colors.white,
                  child: Text(initials,
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFF6B00))),
                ),
                const SizedBox(height: 14),
                // ── Company logo ──────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 8, offset: const Offset(0, 3))],
                  ),
                  child: Image.asset(
                    'assets/images/daffodil_logo.jpg',
                    height: 32,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 12),
                Text(_user['name'] ?? '',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold)),
                Text(_user['phone'] ?? '',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '${_user['city']}, ${_user['country']}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // ── Account Info ─────────────────────────────────────────
                const _SectionLabel('Account Settings'),
                const SizedBox(height: 12),
                _buildTile(Icons.person_outline,  'Full Name', _user['name']    ?? ''),
                _buildTile(Icons.phone_outlined,  'Phone',     _user['phone']   ?? ''),
                _buildTile(Icons.location_city_outlined, 'City', _user['city']  ?? ''),
                _buildTile(Icons.flag_outlined,   'Country',   _user['country'] ?? ''),
                const SizedBox(height: 24),

                // ── 🔑 NewsAPI Key Section ────────────────────────────────
                const _SectionLabel('📰 News API Key'),
                const SizedBox(height: 8),

                // Status banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _currentKey.isNotEmpty
                        ? Colors.green.withOpacity(0.1)
                        : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _currentKey.isNotEmpty
                          ? Colors.green
                          : Colors.orange,
                      width: 1,
                    ),
                  ),
                  child: Row(children: [
                    Icon(
                      _currentKey.isNotEmpty
                          ? Icons.check_circle_outline
                          : Icons.warning_amber_rounded,
                      color: _currentKey.isNotEmpty
                          ? Colors.green
                          : Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _currentKey.isNotEmpty
                            ? '✅ API key active — live news is enabled'
                            : '⚠️ No API key — showing demo news only',
                        style: TextStyle(
                          fontSize: 13,
                          color: _currentKey.isNotEmpty
                              ? Colors.green[800]
                              : Colors.orange[800],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),

                // How to get key - expandable help card
                _HowToGetKeyCard(),
                const SizedBox(height: 12),

                // Key input field
                TextField(
                  controller: _apiKeyCtrl,
                  obscureText: !_apiKeyVisible,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Paste your NewsAPI key here',
                    labelStyle:
                        const TextStyle(color: Color(0xFFFF6B00)),
                    hintText: 'e.g. a1b2c3d4e5f6...',
                    prefixIcon: const Icon(Icons.key_outlined,
                        color: Color(0xFFFF6B00)),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _apiKeyVisible
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.grey,
                      ),
                      onPressed: () => setState(
                          () => _apiKeyVisible = !_apiKeyVisible),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: Color(0xFFFFE0C7)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: Color(0xFFFFE0C7)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                          color: Color(0xFFFF6B00), width: 2),
                    ),
                  ),
                  onChanged: (_) =>
                      setState(() => _apiKeySaved = false),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _saveApiKey,
                    icon: const Icon(Icons.save_outlined,
                        color: Colors.white),
                    label: Text(
                      _apiKeySaved ? '✅ Saved!' : 'Save API Key',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _apiKeySaved
                          ? Colors.green
                          : const Color(0xFFFF6B00),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── About ────────────────────────────────────────────────
                const _SectionLabel('About'),
                const SizedBox(height: 12),
                _buildInfoTile(Icons.info_outline,    'Version',        '2.0.0'),
                _buildInfoTile(Icons.newspaper_outlined, 'News Source', 'NewsAPI.org'),
                _buildInfoTile(Icons.cloud_outlined,  'Weather Source', 'Open-Meteo (Free)'),
                _buildInfoTile(Icons.map_outlined,    'Geocoding',      'OpenStreetMap Nominatim'),
                const SizedBox(height: 24),

                // ── Logout ───────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _logout,
                    icon: const Icon(Icons.logout,
                        color: Colors.redAccent),
                    label: const Text('Logout',
                        style: TextStyle(
                            color: Colors.redAccent, fontSize: 16)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // ── Footer ───────────────────────────────────────────────
                Column(children: [
                  const Divider(color: Color(0xFFFFE0C7)),
                  const SizedBox(height: 12),
                  Image.asset(
                    'assets/images/daffodil_logo.jpg',
                    height: 28,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 6),
                  const Text('Daffodil Software Limited',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                      color: Color(0xFFFF6B00))),
                  const SizedBox(height: 8),
                  Text(
                    '© ${DateTime.now().year} Daffodil Software Limited',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                ]),

              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04), blurRadius: 8)
        ],
      ),
      child: Row(children: [
        Icon(icon, color: const Color(0xFFFF6B00), size: 20),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(value,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04), blurRadius: 8)
        ],
      ),
      child: Row(children: [
        Icon(icon, color: const Color(0xFFFF6B00), size: 20),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: Colors.grey)),
        const Spacer(),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ── Section label widget ──────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF555555)),
      );
}

// ── How to get API key — expandable help card ─────────────────────────────────
class _HowToGetKeyCard extends StatefulWidget {
  @override
  State<_HowToGetKeyCard> createState() => _HowToGetKeyCardState();
}

class _HowToGetKeyCardState extends State<_HowToGetKeyCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFCC80)),
      ),
      child: Column(children: [
        // Header tap row
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            child: Row(children: [
              const Icon(Icons.help_outline,
                  color: Color(0xFFFF6B00), size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'How to get a FREE NewsAPI key?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFBF360C),
                  ),
                ),
              ),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                color: const Color(0xFFFF6B00),
              ),
            ]),
          ),
        ),

        // Expandable steps
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(color: Color(0xFFFFCC80)),
                const SizedBox(height: 4),
                _step('1', 'Open your browser and go to:',
                    'https://newsapi.org'),
                _step('2', 'Click "Get API Key" (top right button)', ''),
                _step('3', 'Sign up with your email address', ''),
                _step('4',
                    'Check your email — verify your account', ''),
                _step('5',
                    'Log in → your API key is shown on the dashboard',
                    ''),
                _step('6',
                    'Copy the key and paste it in the field above', ''),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFFFFCC80)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.info_outline,
                        size: 14, color: Colors.grey),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Free plan: 100 requests/day · No credit card needed',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
      ]),
    );
  }

  Widget _step(String num, String text, String url) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Color(0xFFFF6B00),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(num,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF444444))),
                if (url.isNotEmpty)
                  Text(url,
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF1565C0),
                          fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
