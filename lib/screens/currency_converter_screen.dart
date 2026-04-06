import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
//  CURRENCY CONVERTER SCREEN
//  Uses exchangerate-api.com free tier (no API key needed for base USD).
//  Falls back to built-in approximate rates when offline.
// ─────────────────────────────────────────────────────────────────────────────

class CurrencyConverterScreen extends StatefulWidget {
  const CurrencyConverterScreen({super.key});
  @override
  State<CurrencyConverterScreen> createState() => _CurrencyConverterScreenState();
}

class _CurrencyConverterScreenState extends State<CurrencyConverterScreen> {

  // ── Currency list ──────────────────────────────────────────────────────────
  static const List<Map<String, String>> _currencies = [
    {'code': 'USD', 'name': 'US Dollar',           'flag': '🇺🇸'},
    {'code': 'EUR', 'name': 'Euro',                 'flag': '🇪🇺'},
    {'code': 'GBP', 'name': 'British Pound',        'flag': '🇬🇧'},
    {'code': 'BDT', 'name': 'Bangladeshi Taka',     'flag': '🇧🇩'},
    {'code': 'INR', 'name': 'Indian Rupee',         'flag': '🇮🇳'},
    {'code': 'SAR', 'name': 'Saudi Riyal',          'flag': '🇸🇦'},
    {'code': 'AED', 'name': 'UAE Dirham',           'flag': '🇦🇪'},
    {'code': 'JPY', 'name': 'Japanese Yen',         'flag': '🇯🇵'},
    {'code': 'CNY', 'name': 'Chinese Yuan',         'flag': '🇨🇳'},
    {'code': 'CAD', 'name': 'Canadian Dollar',      'flag': '🇨🇦'},
    {'code': 'AUD', 'name': 'Australian Dollar',    'flag': '🇦🇺'},
    {'code': 'CHF', 'name': 'Swiss Franc',          'flag': '🇨🇭'},
    {'code': 'MYR', 'name': 'Malaysian Ringgit',    'flag': '🇲🇾'},
    {'code': 'SGD', 'name': 'Singapore Dollar',     'flag': '🇸🇬'},
    {'code': 'KWD', 'name': 'Kuwaiti Dinar',        'flag': '🇰🇼'},
    {'code': 'QAR', 'name': 'Qatari Riyal',         'flag': '🇶🇦'},
    {'code': 'TRY', 'name': 'Turkish Lira',         'flag': '🇹🇷'},
    {'code': 'PKR', 'name': 'Pakistani Rupee',      'flag': '🇵🇰'},
    {'code': 'IDR', 'name': 'Indonesian Rupiah',    'flag': '🇮🇩'},
    {'code': 'KRW', 'name': 'South Korean Won',     'flag': '🇰🇷'},
  ];

  // Fallback offline rates (relative to USD)
  static const Map<String, double> _fallbackRates = {
    'USD': 1.0,    'EUR': 0.92,   'GBP': 0.79,   'BDT': 110.0,
    'INR': 83.5,   'SAR': 3.75,   'AED': 3.67,   'JPY': 149.5,
    'CNY': 7.24,   'CAD': 1.36,   'AUD': 1.53,   'CHF': 0.90,
    'MYR': 4.72,   'SGD': 1.34,   'KWD': 0.307,  'QAR': 3.64,
    'TRY': 32.1,   'PKR': 278.5,  'IDR': 15800.0,'KRW': 1325.0,
  };

  // ── State ──────────────────────────────────────────────────────────────────
  Map<String, double> _rates = Map.from(_fallbackRates);
  bool   _loadingRates  = false;
  bool   _isOffline     = false;
  String _lastUpdated   = 'Offline rates';

  String _fromCode = 'USD';
  String _toCode   = 'BDT';

  final TextEditingController _amountCtrl = TextEditingController(text: '1');
  double _result = 110.0;

  // Quick amount shortcuts
  final List<double> _quickAmounts = [1, 10, 50, 100, 500, 1000];

  @override
  void initState() {
    super.initState();
    _fetchRates();
    _convert();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  // ── Fetch live rates ───────────────────────────────────────────────────────
  Future<void> _fetchRates() async {
    setState(() => _loadingRates = true);
    try {
      final res = await http.get(
        Uri.parse('https://open.er-api.com/v6/latest/USD'),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        if (data['result'] == 'success') {
          final raw = data['rates'] as Map<String, dynamic>;
          final Map<String, double> fetched = {};
          for (final c in _currencies) {
            final code = c['code']!;
            if (raw.containsKey(code)) {
              fetched[code] = (raw[code] as num).toDouble();
            }
          }
          final timeStr = data['time_last_update_utc']?.toString() ?? '';
          setState(() {
            _rates        = fetched;
            _isOffline    = false;
            _lastUpdated  = timeStr.isNotEmpty
                ? 'Updated: ${timeStr.substring(0, 16)}'
                : 'Live rates';
          });
          _convert();
          return;
        }
      }
    } catch (_) {}
    setState(() { _isOffline = true; _lastUpdated = 'Offline — approximate rates'; });
    _convert();
  }

  // ── Convert ────────────────────────────────────────────────────────────────
  void _convert() {
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    final fromRate = _rates[_fromCode] ?? 1.0;
    final toRate   = _rates[_toCode]   ?? 1.0;
    final result   = amount / fromRate * toRate;
    if (mounted) setState(() => _result = result);
  }

  void _swap() {
    setState(() {
      final tmp = _fromCode;
      _fromCode = _toCode;
      _toCode   = tmp;
    });
    _convert();
  }

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(2)}M';
    if (v >= 1000)    return v.toStringAsFixed(2);
    if (v < 0.01)     return v.toStringAsFixed(6);
    return v.toStringAsFixed(4);
  }

  String _flag(String code) =>
      _currencies.firstWhere((c) => c['code'] == code,
        orElse: () => {'flag': '💱'})['flag']!;

  String _name(String code) =>
      _currencies.firstWhere((c) => c['code'] == code,
        orElse: () => {'name': code})['name']!;

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F0FF),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF4527A0),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Row(children: [
          Text('💱', style: TextStyle(fontSize: 20)),
          SizedBox(width: 8),
          Text('Currency Converter', style: TextStyle(
            fontWeight: FontWeight.w800, fontSize: 18)),
        ]),
        actions: [
          if (_loadingRates)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _fetchRates,
              tooltip: 'Refresh rates',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          // Rate status bar
          _buildStatusBar(),
          const SizedBox(height: 16),

          // Main converter card
          _buildConverterCard(),
          const SizedBox(height: 16),

          // Quick amounts
          _buildQuickAmounts(),
          const SizedBox(height: 16),

          // All rates table
          _buildRatesTable(),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  // ── Status bar ─────────────────────────────────────────────────────────────
  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: _isOffline ? const Color(0xFFFFF3E0) : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isOffline ? const Color(0xFFFFCC80) : const Color(0xFFA5D6A7)),
      ),
      child: Row(children: [
        Icon(_isOffline ? Icons.wifi_off : Icons.check_circle,
          size: 14,
          color: _isOffline ? const Color(0xFFE65100) : const Color(0xFF2E7D32)),
        const SizedBox(width: 8),
        Expanded(child: Text(_lastUpdated,
          style: TextStyle(fontSize: 11,
            color: _isOffline ? const Color(0xFFBF360C) : const Color(0xFF2E7D32),
            fontWeight: FontWeight.w600))),
        if (_isOffline)
          GestureDetector(
            onTap: _fetchRates,
            child: const Text('Retry', style: TextStyle(
              fontSize: 11, color: Color(0xFF4527A0),
              decoration: TextDecoration.underline)),
          ),
      ]),
    );
  }

  // ── Main converter card ────────────────────────────────────────────────────
  Widget _buildConverterCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(
          color: const Color(0xFF4527A0).withOpacity(0.12),
          blurRadius: 24, offset: const Offset(0, 8),
        )],
      ),
      child: Column(children: [

        // FROM field
        _buildCurrencyField(
          label: 'From',
          code: _fromCode,
          isFrom: true,
        ),

        // Swap button
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: GestureDetector(
            onTap: _swap,
            child: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4527A0), Color(0xFF7B1FA2)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                  color: const Color(0xFF4527A0).withOpacity(0.3),
                  blurRadius: 10, offset: const Offset(0, 4),
                )],
              ),
              child: const Icon(Icons.swap_vert, color: Colors.white, size: 24),
            ),
          ),
        ),

        // TO field
        _buildCurrencyField(
          label: 'To',
          code: _toCode,
          isFrom: false,
        ),

        const SizedBox(height: 20),

        // Result display
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF4527A0), Color(0xFF7B1FA2)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(children: [
            Text(
              '${_flag(_fromCode)} ${_amountCtrl.text.isEmpty ? '0' : _amountCtrl.text} ${_fromCode}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const Text('=', style: TextStyle(color: Colors.white54, fontSize: 16)),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('${_flag(_toCode)} ', style: const TextStyle(fontSize: 28)),
              Text(_fmt(_result), style: const TextStyle(
                color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900,
                letterSpacing: -1,
              )),
              const SizedBox(width: 8),
              Text(_toCode, style: const TextStyle(
                color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 4),
            Text(
              '1 $_fromCode = ${_fmt((_rates[_toCode] ?? 1) / (_rates[_fromCode] ?? 1))} $_toCode',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ]),
        ),

        // Copy result button
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: _fmt(_result)));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${_fmt(_result)} $_toCode copied!'),
                duration: const Duration(seconds: 2),
                backgroundColor: const Color(0xFF4527A0)),
            );
          },
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.copy, size: 13, color: Color(0xFF4527A0)),
            const SizedBox(width: 4),
            const Text('Copy result', style: TextStyle(
              fontSize: 11, color: Color(0xFF4527A0),
              decoration: TextDecoration.underline)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildCurrencyField({
    required String label,
    required String code,
    required bool isFrom,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(
        fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey,
        letterSpacing: 1)),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F0FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD1C4E9)),
        ),
        child: Row(children: [
          // Currency picker
          GestureDetector(
            onTap: () => _pickCurrency(isFrom),
            child: Row(children: [
              Text(_flag(code), style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(code, style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 15,
                  color: Color(0xFF4527A0))),
                Text(_name(code), style: const TextStyle(
                  fontSize: 10, color: Colors.grey)),
              ]),
              const Icon(Icons.arrow_drop_down, color: Color(0xFF4527A0)),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: isFrom
              ? TextField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A0050)),
                  decoration: const InputDecoration(
                    border: InputBorder.none, hintText: '0',
                    hintStyle: TextStyle(color: Colors.grey)),
                  onChanged: (_) => _convert(),
                )
              : Text(
                  _fmt(_result),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A0050)),
                ),
          ),
        ]),
      ),
    ]);
  }

  // ── Quick amounts ──────────────────────────────────────────────────────────
  Widget _buildQuickAmounts() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(left: 4, bottom: 8),
        child: Text('Quick amounts', style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF4527A0))),
      ),
      Wrap(spacing: 8, runSpacing: 8,
        children: _quickAmounts.map((amt) {
          return GestureDetector(
            onTap: () {
              _amountCtrl.text = amt % 1 == 0 ? amt.toInt().toString() : amt.toString();
              _convert();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFD1C4E9)),
                boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: Text(
                amt % 1 == 0 ? amt.toInt().toString() : amt.toString(),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                  color: Color(0xFF4527A0)),
              ),
            ),
          );
        }).toList(),
      ),
    ]);
  }

  // ── All rates table ────────────────────────────────────────────────────────
  Widget _buildRatesTable() {
    final fromRate = _rates[_fromCode] ?? 1.0;
    final amount   = double.tryParse(_amountCtrl.text) ?? 1.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 12, offset: const Offset(0, 4),
        )],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Row(children: [
            const Icon(Icons.table_chart_outlined, size: 16, color: Color(0xFF4527A0)),
            const SizedBox(width: 6),
            Text('All rates for $amount $_fromCode',
              style: const TextStyle(fontWeight: FontWeight.w700,
                fontSize: 13, color: Color(0xFF1A0050))),
          ]),
        ),
        const Divider(height: 1),
        ..._currencies.where((c) => c['code'] != _fromCode).map((c) {
          final code      = c['code']!;
          final toRate    = _rates[code] ?? 1.0;
          final converted = amount / fromRate * toRate;
          final isSelected = code == _toCode;
          return GestureDetector(
            onTap: () {
              setState(() => _toCode = code);
              _convert();
            },
            child: Container(
              color: isSelected
                ? const Color(0xFFF5F0FF)
                : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(children: [
                Text(c['flag']!, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(code, style: TextStyle(fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isSelected
                        ? const Color(0xFF4527A0)
                        : const Color(0xFF1A0050))),
                    Text(c['name']!, style: const TextStyle(
                      fontSize: 10, color: Colors.grey)),
                  ])),
                Text(_fmt(converted), style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 14,
                  color: isSelected
                    ? const Color(0xFF4527A0)
                    : const Color(0xFF1A0050))),
                if (isSelected)
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.check_circle, size: 14,
                      color: Color(0xFF4527A0)),
                  ),
              ]),
            ),
          );
        }),
      ]),
    );
  }

  // ── Currency picker dialog ─────────────────────────────────────────────────
  Future<void> _pickCurrency(bool isFrom) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CurrencyPickerSheet(
        currencies: _currencies,
        selected: isFrom ? _fromCode : _toCode,
      ),
    );
    if (selected != null) {
      setState(() {
        if (isFrom) _fromCode = selected;
        else        _toCode   = selected;
      });
      _convert();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  CURRENCY PICKER BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _CurrencyPickerSheet extends StatefulWidget {
  final List<Map<String, String>> currencies;
  final String selected;
  const _CurrencyPickerSheet({required this.currencies, required this.selected});
  @override State<_CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends State<_CurrencyPickerSheet> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.currencies.where((c) {
      final q = _search.toLowerCase();
      return c['code']!.toLowerCase().contains(q) ||
             c['name']!.toLowerCase().contains(q);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        const SizedBox(height: 12),
        Container(width: 40, height: 4,
          decoration: BoxDecoration(color: Colors.grey[300],
            borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        const Text('Select Currency', style: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1A0050))),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search currency…',
              prefixIcon: const Icon(Icons.search, color: Color(0xFF4527A0)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFD1C4E9)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF4527A0), width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (ctx, i) {
              final c = filtered[i];
              final isSelected = c['code'] == widget.selected;
              return ListTile(
                leading: Text(c['flag']!, style: const TextStyle(fontSize: 26)),
                title: Text(c['code']!, style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isSelected ? const Color(0xFF4527A0) : const Color(0xFF1A0050))),
                subtitle: Text(c['name']!, style: const TextStyle(fontSize: 12)),
                trailing: isSelected
                  ? const Icon(Icons.check_circle, color: Color(0xFF4527A0))
                  : null,
                tileColor: isSelected ? const Color(0xFFF5F0FF) : null,
                onTap: () => Navigator.pop(ctx, c['code']),
              );
            },
          ),
        ),
      ]),
    );
  }
}
