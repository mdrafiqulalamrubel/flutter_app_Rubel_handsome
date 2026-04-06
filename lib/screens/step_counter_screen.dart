import 'dart:async';
import 'dart:math' as math;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  STEP COUNTER SCREEN
//  Uses accelerometer peak-detection (no pedometer plugin needed).
//  Works on Android & iOS. Shows "not supported" gracefully on Windows.
// ─────────────────────────────────────────────────────────────────────────────

class StepCounterScreen extends StatefulWidget {
  const StepCounterScreen({super.key});
  @override
  State<StepCounterScreen> createState() => _StepCounterScreenState();
}

class _StepCounterScreenState extends State<StepCounterScreen>
    with SingleTickerProviderStateMixin {

  static bool get _supported => Platform.isAndroid || Platform.isIOS;

  // ── Step detection state ──────────────────────────────────────────────────
  int    _steps       = 0;
  int    _savedSteps  = 0;   // steps saved to prefs from today
  double _magnitude   = 0;
  double _lastMag     = 0;
  bool   _stepPending = false;

  // Tuning
  static const double _threshold  = 11.5; // magnitude spike to count a step
  static const double _minMag     = 9.0;  // ignore tiny movements (phone on table)
  static const int    _cooldownMs = 300;  // min ms between two steps
  int _lastStepTime = 0;

  // Low-pass filter
  final List<double> _magBuf = [];
  static const int   _magBufLen = 5;

  // Goal
  static const int _goal = 10000;

  // Prefs keys
  static const String _kSteps = 'steps_today';
  static const String _kDate  = 'steps_date';

  StreamSubscription<AccelerometerEvent>? _sub;

  // Animation
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeOut),
    );
    _loadSteps();
    if (_supported) _startListening();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Persistence ───────────────────────────────────────────────────────────
  Future<void> _loadSteps() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    final savedDate = prefs.getString(_kDate) ?? '';
    if (savedDate == today) {
      final saved = prefs.getInt(_kSteps) ?? 0;
      if (mounted) setState(() { _savedSteps = saved; _steps = saved; });
    } else {
      // New day — reset
      await prefs.setString(_kDate, today);
      await prefs.setInt(_kSteps, 0);
    }
  }

  Future<void> _saveSteps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDate, _todayKey());
    await prefs.setInt(_kSteps, _steps);
  }

  String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2,'0')}-${n.day.toString().padLeft(2,'0')}';
  }

  // ── Accelerometer step detection ──────────────────────────────────────────
  void _startListening() {
    _sub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 30),
    ).listen(_onAccel);
  }

  void _onAccel(AccelerometerEvent e) {
    final raw = math.sqrt(e.x*e.x + e.y*e.y + e.z*e.z);

    // Smooth magnitude with small buffer average
    _magBuf.add(raw);
    if (_magBuf.length > _magBufLen) _magBuf.removeAt(0);
    final mag = _magBuf.reduce((a, b) => a + b) / _magBuf.length;

    final now = DateTime.now().millisecondsSinceEpoch;

    // Peak detection: rising above threshold then falling
    if (!_stepPending && mag > _threshold && _lastMag <= _threshold) {
      _stepPending = true;
    }
    if (_stepPending && mag < _threshold) {
      _stepPending = false;
      if (raw > _minMag && now - _lastStepTime > _cooldownMs) {
        _lastStepTime = now;
        _steps++;
        _saveSteps();
        _pulseCtrl.forward(from: 0);
        if (mounted) setState(() => _magnitude = mag);
      }
    }
    _lastMag = mag;
    if (mounted && (_magnitude - mag).abs() > 0.3) {
      setState(() => _magnitude = mag);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  double get _progress => (_steps / _goal).clamp(0.0, 1.0);
  double get _km       => _steps * 0.000762; // avg stride 76.2 cm
  double get _cal      => _steps * 0.04;     // ~0.04 kcal per step

  String _fmt(double v, int dec) => v.toStringAsFixed(dec);

  void _resetSteps() async {
    setState(() { _steps = 0; });
    await _saveSteps();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F8FF),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF1565C0),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Row(children: [
          Text('👟', style: TextStyle(fontSize: 20)),
          SizedBox(width: 8),
          Text('Step Counter', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset today',
            onPressed: () => _confirmReset(context),
          ),
        ],
      ),
      body: !_supported
          ? _buildUnsupported()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                const SizedBox(height: 8),
                _buildRingCard(),
                const SizedBox(height: 16),
                _buildStatsRow(),
                const SizedBox(height: 16),
                _buildProgressBar(),
                const SizedBox(height: 16),
                _buildTips(),
                const SizedBox(height: 16),
                _buildActivityBar(),
              ]),
            ),
    );
  }

  // ── Ring card ─────────────────────────────────────────────────────────────
  Widget _buildRingCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(
          color: const Color(0xFF1565C0).withOpacity(0.12),
          blurRadius: 24, offset: const Offset(0, 8),
        )],
      ),
      child: Column(children: [
        const Text('TODAY\'S STEPS', style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w800,
          letterSpacing: 2, color: Color(0xFF1565C0),
        )),
        const SizedBox(height: 20),
        ScaleTransition(
          scale: _pulseAnim,
          child: SizedBox(
            width: 220, height: 220,
            child: Stack(alignment: Alignment.center, children: [
              // Background ring
              SizedBox(width: 220, height: 220,
                child: CircularProgressIndicator(
                  value: 1.0,
                  strokeWidth: 14,
                  color: const Color(0xFFE3EFFF),
                ),
              ),
              // Progress ring
              SizedBox(width: 220, height: 220,
                child: CircularProgressIndicator(
                  value: _progress,
                  strokeWidth: 14,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _progress >= 1.0
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFF1976D2),
                  ),
                ),
              ),
              // Centre text
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(
                  _steps.toString(),
                  style: const TextStyle(
                    fontSize: 52, fontWeight: FontWeight.w900,
                    color: Color(0xFF0D47A1), height: 1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'of $_goal steps',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _progress >= 1.0
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFE3EFFF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _progress >= 1.0
                      ? '🎉 Goal reached!'
                      : '${(_goal - _steps).clamp(0, _goal)} to go',
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: _progress >= 1.0
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFF1565C0),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        // Live magnitude bar
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.sensors, size: 13, color: Colors.grey),
            const SizedBox(width: 4),
            Text('Sensor activity: ${_fmt(_magnitude, 1)} m/s²',
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (_magnitude / 20).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: const Color(0xFFE3EFFF),
              color: _magnitude > _threshold
                ? const Color(0xFF43A047)
                : const Color(0xFF1976D2),
            ),
          ),
        ]),
      ]),
    );
  }

  // ── Stats row ─────────────────────────────────────────────────────────────
  Widget _buildStatsRow() {
    return Row(children: [
      _statCard('🔥', '${_fmt(_cal, 0)} kcal', 'Calories'),
      const SizedBox(width: 12),
      _statCard('📍', '${_fmt(_km, 2)} km', 'Distance'),
      const SizedBox(width: 12),
      _statCard('⏱️', _fmt(_steps / 100, 0) + ' min', 'Active time'),
    ]);
  }

  Widget _statCard(String icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10, offset: const Offset(0, 4),
          )],
        ),
        child: Column(children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0D47A1),
          )),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ]),
      ),
    );
  }

  // ── Progress bar ──────────────────────────────────────────────────────────
  Widget _buildProgressBar() {
    final pct = (_progress * 100).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10, offset: const Offset(0, 4),
        )],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Daily Goal Progress',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
              color: Color(0xFF0D47A1))),
          Text('$pct%', style: const TextStyle(
            fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF1976D2),
          )),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: _progress,
            minHeight: 12,
            backgroundColor: const Color(0xFFE3EFFF),
            valueColor: AlwaysStoppedAnimation<Color>(
              _progress >= 1.0
                ? const Color(0xFF2E7D32)
                : const Color(0xFF1976D2),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('0', style: TextStyle(fontSize: 10, color: Colors.grey)),
          Text('$_goal steps', style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ]),
      ]),
    );
  }

  // ── Tips ──────────────────────────────────────────────────────────────────
  Widget _buildTips() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE3EFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF90CAF9)),
      ),
      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 16, color: Color(0xFF1565C0)),
        SizedBox(width: 8),
        Expanded(child: Text(
          'Keep your phone in your pocket or hand while walking for best accuracy. '
          'Steps reset automatically at midnight each day.',
          style: TextStyle(fontSize: 11, color: Color(0xFF0D47A1)),
        )),
      ]),
    );
  }

  // ── Activity zones ────────────────────────────────────────────────────────
  Widget _buildActivityBar() {
    final zones = [
      {'label': 'Sedentary', 'max': 2500,  'color': const Color(0xFFEF9A9A), 'icon': '🛋️'},
      {'label': 'Low',       'max': 5000,  'color': const Color(0xFFFFCC80), 'icon': '🚶'},
      {'label': 'Active',    'max': 7500,  'color': const Color(0xFF81D4FA), 'icon': '🏃'},
      {'label': 'Goal',      'max': 10000, 'color': const Color(0xFFA5D6A7), 'icon': '🎯'},
    ];
    String current = 'Sedentary 🛋️';
    if (_steps >= 7500) current = 'Goal 🎯';
    else if (_steps >= 5000) current = 'Active 🏃';
    else if (_steps >= 2500) current = 'Low 🚶';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 10, offset: const Offset(0, 4),
        )],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Activity Zone', style: TextStyle(
            fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0D47A1),
          )),
          const Spacer(),
          Text('Now: $current', style: const TextStyle(
            fontSize: 11, color: Color(0xFF1976D2), fontWeight: FontWeight.w600,
          )),
        ]),
        const SizedBox(height: 12),
        Row(children: zones.map((z) {
          final max = z['max'] as int;
          final min = max - 2500;
          final inZone = _steps >= min && _steps < max;
          return Expanded(child: Column(children: [
            Text(z['icon'] as String, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            Container(
              height: 8, margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: inZone ? z['color'] as Color : const Color(0xFFEEEEEE),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Text(z['label'] as String, style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w600,
              color: inZone ? const Color(0xFF0D47A1) : Colors.grey,
            )),
          ]));
        }).toList()),
      ]),
    );
  }

  // ── Unsupported platform ──────────────────────────────────────────────────
  Widget _buildUnsupported() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.phone_android, size: 64, color: Color(0xFF1565C0)),
          SizedBox(height: 16),
          Text('Step Counter requires a mobile device',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
              color: Color(0xFF0D47A1))),
          SizedBox(height: 8),
          Text('This feature uses your phone\'s accelerometer sensor '
            'and is not available on desktop.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey)),
        ]),
      ),
    );
  }

  // ── Reset confirm dialog ──────────────────────────────────────────────────
  void _confirmReset(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reset Steps?'),
        content: const Text('This will clear today\'s step count.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () { Navigator.pop(ctx); _resetSteps(); },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}
