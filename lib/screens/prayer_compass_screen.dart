import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
//  QIBLA COMPASS
//  Uses raw accelerometer + magnetometer with low-pass filter + circular mean
//  Same method as Android SensorManager.getOrientation()
//
//  Windows / desktop: sensors_plus has no Windows implementation.
//  Sensor streams are skipped on non-mobile platforms — compass displays in
//  static mode (Qibla bearing shown, no live heading rotation).
// ─────────────────────────────────────────────────────────────────────────────

class PrayerCompassScreen extends StatefulWidget {
  const PrayerCompassScreen({super.key});
  @override
  State<PrayerCompassScreen> createState() => _PrayerCompassScreenState();
}

class _PrayerCompassScreenState extends State<PrayerCompassScreen> {
  // Kaaba, Mecca
  static const double _kaabaLat = 21.4225;
  static const double _kaabaLon = 39.8262;

  // FIX W2 / Windows: sensors_plus only works on Android & iOS.
  // This flag lets the UI show a "compass unavailable" note on desktop.
  static bool get _sensorsAvailable =>
      Platform.isAndroid || Platform.isIOS;

  // ── Sensor state ───────────────────────────────────────────────────────────
  final List<double> _gravity = [0.0, 0.0, 9.81];
  final List<double> _geomag  = [0.0, 30.0, -45.0];

  // Separate filter strengths — accel for tilt, mag needs heavier smoothing
  static const double _alphaAcc = 0.15;
  static const double _alphaMag = 0.05;

  final List<double> _headingBuf = [];
  static const int   _bufLen     = 15;

  // Magnetic declination correction (degrees). Dhaka, BD ≈ -0.5 (West)
  // Increase/decrease if still slightly off after figure-8 calibration.
  double _declination = 0.0;

  // Calibration tracking
  bool   _calibrated    = false;
  int    _calibProgress = 0;
  final List<double> _magMinMax = [9999, -9999, 9999, -9999, 9999, -9999]; // xMin,xMax,yMin,yMax,zMin,zMax

  double _heading    = 0.0;
  double _qibla      = 0.0;
  bool   _gpsReady   = false;
  bool   _loading    = true;
  String _error      = '';
  String _location   = '';
  Map<String, String> _prayerTimes = {};

  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<MagnetometerEvent>?  _magSub;

  @override
  void initState() {
    super.initState();
    _startSensors();
    _fetchGPS();
  }

  @override
  void dispose() {
    _accSub?.cancel();
    _magSub?.cancel();
    super.dispose();
  }

  // ── Sensors ────────────────────────────────────────────────────────────────
  void _startSensors() {
    // FIX ROOT CAUSE 1: sensors_plus has NO Windows/Linux/macOS implementation.
    // Calling accelerometerEventStream() on Windows throws MissingPluginException
    // and crashes the app. Skip sensor init on any non-mobile platform.
    if (!_sensorsAvailable) return;

    try {
      _accSub = accelerometerEventStream(
        samplingPeriod: const Duration(milliseconds: 50),
      ).listen((e) {
        // Only update gravity vector — heading is computed in the mag listener
        _gravity[0] = _alphaAcc * e.x + (1 - _alphaAcc) * _gravity[0];
        _gravity[1] = _alphaAcc * e.y + (1 - _alphaAcc) * _gravity[1];
        _gravity[2] = _alphaAcc * e.z + (1 - _alphaAcc) * _gravity[2];
      });
    } catch (_) {
      // Accelerometer not available on this device
    }

    try {
      _magSub = magnetometerEventStream(
        samplingPeriod: const Duration(milliseconds: 50),
      ).listen((e) {
        _geomag[0] = _alphaMag * e.x + (1 - _alphaMag) * _geomag[0];
        _geomag[1] = _alphaMag * e.y + (1 - _alphaMag) * _geomag[1];
        _geomag[2] = _alphaMag * e.z + (1 - _alphaMag) * _geomag[2];
        // Track min/max for calibration quality indicator
        _magMinMax[0] = _magMinMax[0] > e.x ? e.x : _magMinMax[0];
        _magMinMax[1] = _magMinMax[1] < e.x ? e.x : _magMinMax[1];
        _magMinMax[2] = _magMinMax[2] > e.y ? e.y : _magMinMax[2];
        _magMinMax[3] = _magMinMax[3] < e.y ? e.y : _magMinMax[3];
        _magMinMax[4] = _magMinMax[4] > e.z ? e.z : _magMinMax[4];
        _magMinMax[5] = _magMinMax[5] < e.z ? e.z : _magMinMax[5];
        // Calibration: measure coverage — good coverage = large min/max spread across all axes
        final xRange = _magMinMax[1] - _magMinMax[0];
        final yRange = _magMinMax[3] - _magMinMax[2];
        final zRange = _magMinMax[5] - _magMinMax[4];
        final coverage = ((xRange / 80).clamp(0,1) + (yRange / 80).clamp(0,1) + (zRange / 60).clamp(0,1)) / 3;
        final newProg = (coverage * 100).round().clamp(0, 100);
        if (newProg != _calibProgress) {
          _calibrated = newProg >= 80;
          if (mounted) setState(() => _calibProgress = newProg);
        }
        _computeHeading();
      });
    } catch (_) {
      // Magnetometer not available on this device
    }
  }

  // ── Heading: exact Android SensorManager.getRotationMatrix + getOrientation ──
  //
  // This is a direct port of Android's internal C++ implementation.
  // It is the same algorithm used by Google Maps, Muslim Pro, and every
  // reliable compass app on Android. No guesswork, no sign flips.
  //
  // sensors_plus axis convention (matches Android hardware axes):
  //   Accelerometer: X = right, Y = up-screen, Z = out-of-screen
  //   Magnetometer:  same axes
  //
  void _computeHeading() {
    final double ax = _gravity[0], ay = _gravity[1], az = _gravity[2];
    final double mx = _geomag[0],  my = _geomag[1],  mz = _geomag[2];

    // ── getRotationMatrix() ───────────────────────────────────────────────────
    // Normalise accelerometer (gravity) vector
    final double normA2 = ax*ax + ay*ay + az*az;
    if (normA2 < 0.01) return;
    final double invA = 1.0 / math.sqrt(normA2);
    final double gx = ax * invA, gy = ay * invA, gz = az * invA;

    // Cross product: H = M × A  (East vector, perpendicular to both)
    double hx = my * gz - mz * gy;
    double hy = mz * gx - mx * gz;
    double hz = mx * gy - my * gx;
    final double normH2 = hx*hx + hy*hy + hz*hz;
    if (normH2 < 0.01) return;   // device near magnetic field or on magnetic surface
    final double invH = 1.0 / math.sqrt(normH2);
    hx *= invH; hy *= invH; hz *= invH;

    // North vector: M2 = A × H  (tilt-compensated North, in device frame)
    final double m2x = gy * hz - gz * hy;
    final double m2y = gz * hx - gx * hz;
    // m2z = gx * hy - gy * hx  (not needed for azimuth)

    // Rotation matrix R (row-major, Android convention):
    // R[0]=hx  R[1]=hy  R[2]=hz
    // R[3]=m2x R[4]=m2y R[5]=m2z
    // R[6]=gx  R[7]=gy  R[8]=gz

    // ── getOrientation() ──────────────────────────────────────────────────────
    // azimuth = atan2(R[1], R[4])  i.e. atan2(hy, m2y)
    // This is exactly what Android returns as "azimuth" (rotation around -Z axis)
    double azimuth = math.atan2(hy, m2y) * 180 / math.pi;
    azimuth = (azimuth + _declination + 360) % 360;

    // ── Circular mean smoothing (prevents 0°/360° wrap-around glitch) ─────────
    _headingBuf.add(azimuth);
    if (_headingBuf.length > _bufLen) _headingBuf.removeAt(0);

    double sinSum = 0, cosSum = 0;
    for (final h in _headingBuf) {
      sinSum += math.sin(h * math.pi / 180);
      cosSum += math.cos(h * math.pi / 180);
    }
    double smoothed = math.atan2(sinSum / _headingBuf.length,
                                  cosSum / _headingBuf.length) * 180 / math.pi;
    smoothed = (smoothed + 360) % 360;

    if ((smoothed - _heading).abs() > 0.5) {
      if (mounted) setState(() => _heading = smoothed);
    }
  }

  // ── GPS ────────────────────────────────────────────────────────────────────
  Future<void> _fetchGPS() async {
    setState(() { _loading = true; _error = ''; });
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        setState(() { _error = 'GPS disabled. Enable location services.'; _loading = false; });
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        setState(() { _error = 'Location permission denied.'; _loading = false; });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      _qibla       = _calcQibla(pos.latitude, pos.longitude);
      _prayerTimes = _calcPrayerTimes(pos.latitude, pos.longitude);
      _gpsReady    = true;
      try { _location = await _reverseGeocode(pos.latitude, pos.longitude); }
      catch (_) { _location = '${pos.latitude.toStringAsFixed(2)}°, ${pos.longitude.toStringAsFixed(2)}°'; }
      setState(() => _loading = false);
    } catch (e) {
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  // ── Qibla bearing (great circle) ───────────────────────────────────────────
  double _calcQibla(double lat, double lon) {
    final double phi1  = lat * math.pi / 180;
    final double phi2  = _kaabaLat * math.pi / 180;
    final double dLambda  = (_kaabaLon - lon) * math.pi / 180;
    final double y   = math.sin(dLambda) * math.cos(phi2);
    final double x   = math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dLambda);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  // ── Prayer times (MWL method) ──────────────────────────────────────────────
  Map<String, String> _calcPrayerTimes(double lat, double lon) {
    final now = DateTime.now();
    final jd  = _jd(now.year, now.month, now.day);
    final tz  = now.timeZoneOffset.inMinutes / 60.0;
    final D   = jd - 2451545.0;
    final g   = (357.529 + 0.98560028 * D) % 360;
    final q   = (280.459 + 0.98564736 * D) % 360;
    final L   = (q + 1.915 * _sin(g) + 0.020 * _sin(2*g)) % 360;
    final e   = 23.439 - 0.00000036 * D;
    final RA  = math.atan2(_cos(e)*_sin(L), _cos(L)) * 180/math.pi / 15;
    final dec = math.asin((_sin(e)*_sin(L)).clamp(-1.0, 1.0)) * 180/math.pi;
    double EqT = q/15 - RA;
    if (EqT > 12) EqT -= 24;
    if (EqT < -12) EqT += 24;
    final noon = 12 - EqT - lon/15 + tz;

    // FIX E2/E3: Clamp acos argument to [-1,1] — prevents NaN/crash at polar latitudes
    double ha(double angle) {
      final double cosArg = (-_sin(angle) - _sin(lat) * _sin(dec))
          / (_cos(lat) * _cos(dec));
      return math.acos(cosArg.clamp(-1.0, 1.0)) * 180 / math.pi / 15;
    }

    final asrA = math.atan(1 / (1 + math.tan((lat - dec).abs() * math.pi / 180))) * 180 / math.pi;
    final double asrCosArg = (_sin(asrA) - _sin(lat * math.pi / 180) * _sin(dec * math.pi / 180))
        / (_cos(lat * math.pi / 180) * _cos(dec * math.pi / 180));
    final asr = noon + math.acos(asrCosArg.clamp(-1.0, 1.0)) * 180 / math.pi / 15;

    String f(double t) {
      t = ((t % 24) + 24) % 24;
      final h = t.floor(), m = ((t-h)*60).round();
      final hh = h==0?12:h>12?h-12:h;
      return '${hh.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')} ${h<12?'AM':'PM'}';
    }
    return {
      'Fajr':    f(noon - ha(18)),
      'Sunrise': f(noon - ha(0.833)),
      'Dhuhr':   f(noon + 0.033),
      'Asr':     f(asr),
      'Maghrib': f(noon + ha(0.833)),
      'Isha':    f(noon + ha(17)),
    };
  }

  double _jd(int y,int m,int d){if(m<=2){y--;m+=12;}final A=(y/100).floor();return(365.25*(y+4716)).floor()+(30.6001*(m+1)).floor()+d+2-A+(A/4).floor()-1524.5;}
  double _sin(double d)=>math.sin(d*math.pi/180);
  double _cos(double d)=>math.cos(d*math.pi/180);

  // FIX I1: Corrected User-Agent header
  Future<String> _reverseGeocode(double lat, double lon) async {
    final r = await http.get(
      Uri.parse('https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lon&format=json'),
      headers: {'User-Agent': 'RubelHandsome/1.0'},
    ).timeout(const Duration(seconds: 8));
    if (r.statusCode == 200) {
      final a = (json.decode(r.body) as Map)['address'] as Map?;
      final c  = a?['city'] ?? a?['town'] ?? a?['village'] ?? a?['county'] ?? '';
      final co = a?['country'] ?? '';
      if (c.toString().isNotEmpty) return '$c, $co';
    }
    return '${lat.toStringAsFixed(2)}°, ${lon.toStringAsFixed(2)}°';
  }

  String _nextPrayer() {
    // FIX W1: Guard against empty map
    if (_prayerTimes.isEmpty) return '';
    final now = TimeOfDay.now();
    final nowM = now.hour * 60 + now.minute;
    for (final e in _prayerTimes.entries) {
      if (e.key == 'Sunrise') continue;
      final p = e.value.split(' '); final hm = p[0].split(':');
      var h = int.parse(hm[0]); final m = int.parse(hm[1]);
      if (p[1] == 'PM' && h != 12) h += 12;
      if (p[1] == 'AM' && h == 12) h = 0;
      if (h * 60 + m > nowM) return e.key;
    }
    return 'Fajr';
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7F4),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Row(children: [
          Text('🕌', style: TextStyle(fontSize: 20)),
          SizedBox(width: 8),
          Text('Prayer Compass', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        ]),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchGPS)],
      ),
      body: _loading
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              CircularProgressIndicator(color: Color(0xFF2E7D32)),
              SizedBox(height: 16),
              Text('Getting location…', style: TextStyle(color: Color(0xFF2E7D32))),
            ]))
          : _error.isNotEmpty
              ? Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.location_off, color: Color(0xFF2E7D32), size: 60),
                    const SizedBox(height: 16),
                    Text(_error, textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, color: Colors.black54)),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(onPressed: _fetchGPS,
                      icon: const Icon(Icons.refresh), label: const Text('Try Again'),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    ),
                  ])))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    // Location bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(color: const Color(0xFF2E7D32),
                          borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        const Icon(Icons.location_on, color: Colors.white70, size: 16),
                        const SizedBox(width: 6),
                        Expanded(child: Text(_location.isNotEmpty ? _location : 'Your Location',
                            style: const TextStyle(color: Colors.white, fontSize: 13),
                            overflow: TextOverflow.ellipsis)),
                        Text('Qibla: ${_qibla.toStringAsFixed(1)}°',
                            style: const TextStyle(color: Colors.white70, fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),

                    // Windows / desktop sensor notice
                    if (!_sensorsAvailable) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFFCC80))),
                        child: const Row(children: [
                          Icon(Icons.info_outline, size: 16, color: Color(0xFFE65100)),
                          SizedBox(width: 8),
                          Expanded(child: Text(
                            'Live compass requires a mobile device with magnetometer. '
                            'Qibla direction and prayer times are still accurate.',
                            style: TextStyle(fontSize: 11, color: Color(0xFFBF360C)),
                          )),
                        ]),
                      ),
                    ],

                    const SizedBox(height: 20),
                    _buildCalibrationBar(),
                    const SizedBox(height: 12),
                    _buildCompass(),
                    const SizedBox(height: 12),
                    _buildDeclinationAdjuster(),
                    const SizedBox(height: 16),
                    _buildPrayerTimes(),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFA5D6A7))),
                      child: const Row(children: [
                        Icon(Icons.tips_and_updates_outlined, size: 16, color: Color(0xFF2E7D32)),
                        SizedBox(width: 8),
                        Expanded(child: Text(
                          'Hold phone flat. Wave in figure-8 to calibrate. Keep away from metal & magnets.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF388E3C)),
                        )),
                      ]),
                    ),
                  ]),
                ),
    );
  }

  // ── Compass ────────────────────────────────────────────────────────────────
  Widget _buildCompass() {
    // The dial rotates by -_heading (so N always points to real North).
    // The needle must point to Qibla in real-world space, so its angle
    // relative to the (already-rotated) dial = qibla - heading.
    final double needleDeg = _gpsReady ? (_qibla - _heading + 360) % 360 : 0;
    double turn = needleDeg > 180 ? needleDeg - 360 : needleDeg;
    final String turnStr = !_gpsReady
        ? 'Getting GPS…'
        : !_sensorsAvailable
            ? 'Qibla is ${_qibla.toStringAsFixed(1)}° from North'
            : turn.abs() < 3
                ? '✅ You are facing Qibla!'
                : turn > 0
                    ? 'Turn ${turn.toStringAsFixed(0)}° Right ➡'
                    : 'Turn ${turn.abs().toStringAsFixed(0)}° Left ⬅';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: const Color(0xFF2E7D32).withOpacity(0.15),
            blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Column(children: [
        const Text('QIBLA COMPASS', style: TextStyle(fontSize: 12,
            fontWeight: FontWeight.w800, letterSpacing: 2, color: Color(0xFF2E7D32))),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: turn.abs() < 3 ? const Color(0xFFE8F5E9) : const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(turnStr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
              color: turn.abs() < 3 ? const Color(0xFF2E7D32) : const Color(0xFFE65100))),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 280, height: 280,
          child: Stack(alignment: Alignment.center, children: [
            Container(
              width: 280, height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFE8F5E9), Color(0xFFC8E6C9)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                boxShadow: [BoxShadow(color: const Color(0xFF2E7D32).withOpacity(0.2),
                    blurRadius: 20, spreadRadius: 2)],
              ),
            ),
            Transform.rotate(
              angle: -_heading * math.pi / 180,
              child: CustomPaint(size: const Size(260, 260), painter: _DialPainter()),
            ),
            Transform.rotate(
              angle: needleDeg * math.pi / 180,
              child: CustomPaint(size: const Size(260, 260), painter: _NeedlePainter()),
            ),
            Container(
              width: 24, height: 24,
              decoration: const BoxDecoration(color: Color(0xFF1B5E20), shape: BoxShape.circle),
              child: const Center(child: Icon(Icons.circle, size: 10, color: Colors.white)),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _stat('📱 Heading', _sensorsAvailable ? '${_heading.toStringAsFixed(0)}°' : 'N/A'),
          Container(width: 1, height: 32, color: Colors.grey[300]),
          _stat('🕋 Qibla', '${_qibla.toStringAsFixed(0)}°'),
          Container(width: 1, height: 32, color: Colors.grey[300]),
          _stat('↩ Turn', _sensorsAvailable ? '${turn.toStringAsFixed(0)}°' : 'N/A'),
        ]),
      ]),
    );
  }

  Widget _stat(String label, String value) => Column(children: [
    Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
    const SizedBox(height: 2),
    Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
        color: Color(0xFF1B5E20))),
  ]);

  // ── Calibration bar ───────────────────────────────────────────────────────
  Widget _buildCalibrationBar() {
    final Color barColor = _calibProgress < 40
        ? const Color(0xFFD32F2F)
        : _calibProgress < 80
            ? const Color(0xFFF57C00)
            : const Color(0xFF2E7D32);
    final String label = _calibProgress < 40
        ? '⚠️ Poor — wave phone in figure-8 shape to calibrate'
        : _calibProgress < 80
            ? '🔄 Calibrating… keep waving in figure-8'
            : '✅ Calibrated — compass is accurate';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: barColor.withOpacity(0.4)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Magnetometer Calibration',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: barColor)),
          const Spacer(),
          Text('$_calibProgress%',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: barColor)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _calibProgress / 100,
            minHeight: 7,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]),
    );
  }

  // ── Declination adjuster ───────────────────────────────────────────────────
  Widget _buildDeclinationAdjuster() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        const Icon(Icons.tune, size: 16, color: Color(0xFF2E7D32)),
        const SizedBox(width: 8),
        const Expanded(
          child: Text('Fine-tune correction',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: Color(0xFF1B5E20))),
        ),
        IconButton(
          padding: EdgeInsets.zero, constraints: const BoxConstraints(),
          icon: const Icon(Icons.remove_circle_outline, color: Color(0xFF2E7D32)),
          onPressed: () => setState(() =>
            _declination = (_declination - 1).clamp(-30.0, 30.0)),
        ),
        SizedBox(
          width: 52,
          child: Text(
            '${_declination >= 0 ? '+' : ''}${_declination.toStringAsFixed(0)}°',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800,
              fontSize: 14, color: Color(0xFF1B5E20)),
          ),
        ),
        IconButton(
          padding: EdgeInsets.zero, constraints: const BoxConstraints(),
          icon: const Icon(Icons.add_circle_outline, color: Color(0xFF2E7D32)),
          onPressed: () => setState(() =>
            _declination = (_declination + 1).clamp(-30.0, 30.0)),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () => setState(() => _declination = 0.0),
          child: const Text('Reset',
            style: TextStyle(fontSize: 10, color: Colors.grey,
              decoration: TextDecoration.underline)),
        ),
      ]),
    );
  }

    // ── Prayer times ───────────────────────────────────────────────────────────
  Widget _buildPrayerTimes() {
    final next = _nextPrayer();
    final prayers = [
      {'n':'Fajr',    'i':'🌅','a':'الفجر'},
      {'n':'Sunrise', 'i':'☀️', 'a':'الشروق'},
      {'n':'Dhuhr',   'i':'🌞','a':'الظهر'},
      {'n':'Asr',     'i':'🌤️','a':'العصر'},
      {'n':'Maghrib', 'i':'🌇','a':'المغرب'},
      {'n':'Isha',    'i':'🌙','a':'العشاء'},
    ];
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06),
              blurRadius: 16, offset: const Offset(0, 4))]),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16,14,16,8),
          child: Row(children: [
            const Icon(Icons.access_time, color: Color(0xFF2E7D32), size: 18),
            const SizedBox(width: 6),
            const Text('Prayer Times Today', style: TextStyle(fontWeight: FontWeight.w800,
                fontSize: 15, color: Color(0xFF1B5E20))),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(20)),
              child: Text('Next: $next', style: const TextStyle(fontSize: 11,
                  color: Color(0xFF2E7D32), fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        const Divider(height: 1),
        ...prayers.asMap().entries.map((e) {
          final p=e.value; final name=p['n']!; final isNext=name==next; final isSun=name=='Sunrise';
          return Column(children: [
            Container(
              color: isNext ? const Color(0xFFE8F5E9) : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                Text(p['i']!, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14,
                      color: isSun ? const Color(0xFF757575) : const Color(0xFF1B5E20))),
                  Text(p['a']!, style: const TextStyle(fontSize: 12,
                      color: Color(0xFF9E9E9E), fontStyle: FontStyle.italic)),
                ])),
                if (isNext) Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(color: const Color(0xFF2E7D32),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Text('NEXT', style: TextStyle(color: Colors.white,
                      fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1)),
                ),
                Text(_prayerTimes[name] ?? '--:--', style: TextStyle(fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isSun ? const Color(0xFF9E9E9E) : const Color(0xFF1B5E20))),
              ]),
            ),
            if (e.key < prayers.length-1) const Divider(height: 1, indent: 56),
          ]);
        }),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DIAL PAINTER
// ─────────────────────────────────────────────────────────────────────────────
class _DialPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width/2, cy = size.height/2;
    final r  = math.min(cx, cy) - 2;
    canvas.drawCircle(Offset(cx,cy), r, Paint()..color = Colors.white);
    canvas.drawCircle(Offset(cx,cy), r, Paint()
      ..style = PaintingStyle.stroke..strokeWidth = 2.5
      ..color = const Color(0xFF2E7D32));
    for (int i = 0; i < 360; i += 5) {
      final rad = i * math.pi / 180;
      final isMain = i % 90 == 0;
      final isMid  = i % 45 == 0;
      final len    = isMain ? 18.0 : isMid ? 12.0 : 6.0;
      canvas.drawLine(
        Offset(cx + (r-1)*math.sin(rad), cy - (r-1)*math.cos(rad)),
        Offset(cx + (r-1-len)*math.sin(rad), cy - (r-1-len)*math.cos(rad)),
        Paint()..strokeWidth = isMain ? 2.5 : isMid ? 1.5 : 0.8
               ..color = isMain ? const Color(0xFF212121) : const Color(0xFFBBBBBB),
      );
    }
    final labels = ['N','E','S','W'];
    final colors = [const Color(0xFFD32F2F), const Color(0xFF212121),
                    const Color(0xFF212121), const Color(0xFF212121)];
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i < 4; i++) {
      final rad = i * math.pi / 2;
      tp.text = TextSpan(text: labels[i],
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colors[i]));
      tp.layout();
      tp.paint(canvas, Offset(
        cx + (r-38)*math.sin(rad) - tp.width/2,
        cy - (r-38)*math.cos(rad) - tp.height/2,
      ));
    }
    final tp2 = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 45; i < 360; i += 90) {
      final rad = i * math.pi / 180;
      tp2.text = TextSpan(text: '$i°',
        style: const TextStyle(fontSize: 9, color: Color(0xFF9E9E9E), fontWeight: FontWeight.w600));
      tp2.layout();
      tp2.paint(canvas, Offset(
        cx + (r-36)*math.sin(rad) - tp2.width/2,
        cy - (r-36)*math.cos(rad) - tp2.height/2,
      ));
    }
  }
  @override bool shouldRepaint(_DialPainter o) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
//  NEEDLE PAINTER
// ─────────────────────────────────────────────────────────────────────────────
class _NeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width/2, cy = size.height/2;
    final r  = math.min(cx, cy) - 2;
    final tip  = Offset(cx, cy - r*0.60);
    final tail = Offset(cx, cy + r*0.25);
    const w    = 12.0;
    final left = Offset(cx-w, cy - r*0.05);
    final rght = Offset(cx+w, cy - r*0.05);
    final tipPath = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(tail.dx, tail.dy)
      ..lineTo(rght.dx, rght.dy)
      ..close();
    canvas.drawPath(tipPath, Paint()..shader = LinearGradient(
      colors: const [Color(0xFFFFEC6E), Color(0xFFFFD700), Color(0xFFFFA000)],
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
    ).createShader(Rect.fromPoints(tip, tail)));
    canvas.drawPath(tipPath, Paint()
      ..style = PaintingStyle.stroke..color = const Color(0xFFFF8F00)..strokeWidth = 1.5);
    final tp = TextPainter(
      text: const TextSpan(text: '🕋', style: TextStyle(fontSize: 24)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(tip.dx - tp.width/2, tip.dy - tp.height - 2));
    final tailPath = Path()
      ..moveTo(tail.dx, tail.dy)
      ..lineTo(cx-6, cy+r*0.05)
      ..lineTo(cx+6, cy+r*0.05)
      ..close();
    canvas.drawPath(tailPath, Paint()..color = Colors.grey[400]!);
  }
  // FIX I2: returns true — new painter instance is passed each rebuild
  @override bool shouldRepaint(_NeedlePainter o) => true;
}
