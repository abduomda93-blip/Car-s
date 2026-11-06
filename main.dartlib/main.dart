// lib/main.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('trip_logs');
  await Hive.openBox('settings');
  runApp(const CarTrackerApp());
}

class CarTrackerApp extends StatefulWidget {
  const CarTrackerApp({super.key});

  @override
  State<CarTrackerApp> createState() => _CarTrackerAppState();
}

class _CarTrackerAppState extends State<CarTrackerApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    final isDark = Hive.box('settings').get('is_dark_mode', defaultValue: false) as bool;
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
  }

  void _toggleTheme(bool isDark) {
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'سجل السيارات اليومي',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'SA'),
      supportedLocales: const [Locale('ar', 'SA')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFFF7F9FC),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: HomeScreen(onToggleTheme: _toggleTheme),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final Function(bool) onToggleTheme;
  const HomeScreen({super.key, required this.onToggleTheme});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final Box tripBox = Hive.box('trip_logs');
  final Box settingsBox = Hive.box('settings');

  @override
  Widget build(BuildContext context) {
    final screens = [
      AddTripScreen(tripBox: tripBox, settingsBox: settingsBox),
      ReportsScreen(tripBox: tripBox),
      SettingsScreen(
        settingsBox: settingsBox,
        tripBox: tripBox,
        onToggleTheme: widget.onToggleTheme,
      ),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.add_road), label: 'تسجيل رحلة'),
          NavigationDestination(icon: Icon(Icons.analytics_outlined), label: 'السجلات والتقارير'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'الإعدادات'),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// الشاشة الأولى: إدخال البيانات اليومية والتعبئة الذكية
// -----------------------------------------------------------------------------
class AddTripScreen extends StatefulWidget {
  final Box tripBox;
  final Box settingsBox;
  const AddTripScreen({super.key, required this.tripBox, required this.settingsBox});

  @override
  State<AddTripScreen> createState() => _AddTripScreenState();
}

class _AddTripScreenState extends State<AddTripScreen> {
  final _formKey = GlobalKey<FormState>();
  final _plateController = TextEditingController();
  final _modelController = TextEditingController();
  final _driverController = TextEditingController();
  final _startMeterController = TextEditingController();
  final _endMeterController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  double _calculatedDistance = 0.0;
  bool _isLoading = false;
  String? _smartFillMessage;

  @override
  void initState() {
    super.initState();
    _startMeterController.addListener(_calculateDistance);
    _endMeterController.addListener(_calculateDistance);
  }

  @override
  void dispose() {
    _plateController.dispose();
    _modelController.dispose();
    _driverController.dispose();
    _startMeterController.dispose();
    _endMeterController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _calculateDistance() {
    final double start = double.tryParse(_startMeterController.text) ?? 0.0;
    final double end = double.tryParse(_endMeterController.text) ?? 0.0;
    setState(() {
      _calculatedDistance = (end >= start) ? (end - start) : 0.0;
    });
  }

  List<String> _getRecentPlates() {
    final trips = widget.tripBox.values.toList();
    final seen = <String>{};
    final result = <String>[];
    for (int i = trips.length - 1; i >= 0; i--) {
      final trip = Map<String, dynamic>.from(trips[i] as Map);
      final plate = (trip['plateNumber'] ?? '').toString().trim();
      if (plate.isNotEmpty && seen.add(plate.toLowerCase())) {
        result.add(plate);
        if (result.length >= 6) break;
      }
    }
    return result;
  }

  // ميزة التعبئة الذكية: جلب آخر عداد رجوع وموديل السيارة لنفس اللوحة
  void _onPlateChanged(String plate) {
    final cleanPlate = plate.trim().toLowerCase();
    if (cleanPlate.isEmpty) {
      setState(() => _smartFillMessage = null);
      return;
    }

    final trips = widget.tripBox.values.toList();
    Map<String, dynamic>? latestTrip;

    for (int i = trips.length - 1; i >= 0; i--) {
      final trip = Map<String, dynamic>.from(trips[i] as Map);
      if (trip['plateNumber'].toString().trim().toLowerCase() == cleanPlate) {
        if (latestTrip == null ||
            (trip['date'] ?? '').toString().compareTo((latestTrip['date'] ?? '').toString()) >= 0) {
          latestTrip = trip;
        }
      }
    }

    if (latestTrip != null) {
      setState(() {
        _startMeterController.text = latestTrip!['endMeter'].toString();
        if (_modelController.text.isEmpty && (latestTrip['carModel'] ?? '').toString().isNotEmpty) {
          _modelController.text = latestTrip['carModel'].toString();
        }
        if (_driverController.text.isEmpty && (latestTrip['driverName'] ?? '').toString().isNotEmpty) {
          _driverController.text = latestTrip['driverName'].toString();
        }
        _smartFillMessage = 'تعبئة ذكية: تم وضع عداد الخروج بآخر عداد رجوع (${latestTrip['endMeter']} كم)';
      });
    } else {
      setState(() => _smartFillMessage = null);
    }
  }

  Future<void> _saveTrip() async {
    if (!_formKey.currentState!.validate()) return;

    final double? start = double.tryParse(_startMeterController.text);
    final double? end = double.tryParse(_endMeterController.text);

    if (start == null || end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال أرقام صحيحة لعدادي الخروج والرجوع'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (end < start) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('خطأ: عداد الرجوع لا يمكن أن يكون أقل من عداد الخروج!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final String tripId = DateTime.now().millisecondsSinceEpoch.toString();
    final newTrip = <String, dynamic>{
      'id': tripId,
      'plateNumber': _plateController.text.trim(),
      'carModel': _modelController.text.trim(),
      'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
      'driverName': _driverController.text.trim(),
      'startMeter': start,
      'endMeter': end,
      'distance': end - start,
      'startTime': _startTime?.format(context) ?? '',
      'endTime': _endTime?.format(context) ?? '',
      'notes': _notesController.text.trim(),
      'synced': false,
    };

    await widget.tripBox.put(tripId, newTrip);

    final scriptUrl = widget.settingsBox.get('sheets_url', defaultValue: '').toString().trim();
    if (scriptUrl.isNotEmpty) {
      try {
        final res = await http.post(
          Uri.parse(scriptUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(newTrip),
        );
        if (res.statusCode == 200 || res.statusCode == 302) {
          newTrip['synced'] = true;
          await widget.tripBox.put(tripId, newTrip);
        }
      } catch (e) {
        debugPrint('Cloud sync error: $e');
      }
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          newTrip['synced'] == true
              ? 'تم حفظ الرحلة ومزامنتها مع Google Sheets بنجاح'
              : 'تم حفظ الرحلة محلياً على الهاتف بنجاح',
        ),
        backgroundColor: Colors.teal,
      ),
    );
    _resetForm();
  }

  void _resetForm() {
    _plateController.clear();
    _modelController.clear();
    _driverController.clear();
    _startMeterController.clear();
    _endMeterController.clear();
    _notesController.clear();
    setState(() {
      _selectedDate = DateTime.now();
      _startTime = null;
      _endTime = null;
      _calculatedDistance = 0.0;
      _smartFillMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final recentPlates = _getRecentPlates();

    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل رحلة يومية'), centerTitle: true),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (recentPlates.isNotEmpty) ...[
                const Text(
                  'اختيار سريع لسيارة مسجلة:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: recentPlates.map((plate) {
                    return ActionChip(
                      avatar: const Icon(Icons.directions_car, size: 16),
                      label: Text(plate),
                      onPressed: () {
                        _plateController.text = plate;
                        _onPlateChanged(plate);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
              ],
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _plateController,
                        decoration: const InputDecoration(
                          labelText: 'رقم اللوحة / السيارة *',
                          prefixIcon: Icon(Icons.directions_car),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'هذا الحقل إجباري' : null,
                        onChanged: _onPlateChanged,
                      ),
                      if (_smartFillMessage != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.teal.withAlpha(30),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.auto_awesome, color: Colors.teal, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _smartFillMessage!,
                                  style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _modelController,
                        decoration: const InputDecoration(
                          labelText: 'موديل / نوع السيارة (اختياري)',
                          prefixIcon: Icon(Icons.car_repair),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _driverController,
                        decoration: const InputDecoration(
                          labelText: 'اسم السائق (اختياري)',
                          prefixIcon: Icon(Icons.person),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.calendar_month, color: Colors.teal),
                        title: Text('تاريخ الرحلة: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}'),
                        trailing: ElevatedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) setState(() => _selectedDate = picked);
                          },
                          child: const Text('تغيير'),
                        ),
                      ),
                      const Divider(),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.access_time),
                              label: Text(_startTime == null ? 'وقت الخروج' : _startTime!.format(context)),
                              onPressed: () async {
                                final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                                if (t != null) setState(() => _startTime = t);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.timelapse),
                              label: Text(_endTime == null ? 'وقت الرجوع' : _endTime!.format(context)),
                              onPressed: () async {
                                final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                                if (t != null) setState(() => _endTime = t);
                              },
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _startMeterController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'عداد الخروج (كم) *',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _endMeterController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'عداد الرجوع (كم) *',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.teal.withAlpha(30),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'إجمالي المسافة المقطوعة:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              '${_calculatedDistance.toStringAsFixed(1)} كم',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.teal),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'ملاحظات (صولار، صيانة، تفاصيل...)',
                          prefixIcon: Icon(Icons.note_alt_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isLoading ? null : _saveTrip,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('حفظ وتسجيل الرحلة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// الشاشة الثانية: السجلات والتقارير والإحصائيات والتعديل والتصدير
// -----------------------------------------------------------------------------
class ReportsScreen extends StatefulWidget {
  final Box tripBox;
  const ReportsScreen({super.key, required this.tripBox});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _searchController = TextEditingController();
  String _searchPlate = '';
  DateTime? _filterMonth;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _getFilteredTrips() {
    final rawList = widget.tripBox.values.toList();
    final List<Map<String, dynamic>> trips = [];
    for (var item in rawList) {
      if (item is Map) {
        trips.add(Map<String, dynamic>.from(item));
      }
    }
    trips.sort((a, b) => (b['date'] ?? '').toString().compareTo((a['date'] ?? '').toString()));

    return trips.where((trip) {
      final plate = (trip['plateNumber'] ?? '').toString().toLowerCase();
      final model = (trip['carModel'] ?? '').toString().toLowerCase();
      final driver = (trip['driverName'] ?? '').toString().toLowerCase();
      final q = _searchPlate.trim().toLowerCase();

      final matchesSearch = q.isEmpty || plate.contains(q) || model.contains(q) || driver.contains(q);

      bool matchesMonth = true;
      if (_filterMonth != null) {
        final targetPrefix = DateFormat('yyyy-MM').format(_filterMonth!);
        matchesMonth = (trip['date'] ?? '').toString().startsWith(targetPrefix);
      }

      return matchesSearch && matchesMonth;
    }).toList();
  }

  String _escapeCsv(dynamic value) {
    final str = (value ?? '').toString().replaceAll('"', '""');
    return '"$str"';
  }

  Future<void> _exportToCsv(List<Map<String, dynamic>> trips) async {
    if (trips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد بيانات لتصديرها')),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.write('\uFEFF'); // UTF-8 BOM لدعم اللغة العربية في Excel
    buffer.writeln([
      'معرف الرحلة',
      'التاريخ',
      'رقم اللوحة',
      'موديل السيارة',
      'اسم السائق',
      'عداد الخروج',
      'عداد الرجوع',
      'المسافة المقطوعة (كم)',
      'وقت الخروج',
      'وقت الرجوع',
      'ملاحظات',
    ].map(_escapeCsv).join(','));

    for (final t in trips) {
      buffer.writeln([
        t['id'],
        t['date'],
        t['plateNumber'],
        t['carModel'],
        t['driverName'],
        t['startMeter'],
        t['endMeter'],
        t['distance'],
        t['startTime'],
        t['endTime'],
        t['notes'],
      ].map(_escapeCsv).join(','));
    }

    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/car_report_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(buffer.toString(), encoding: utf8);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'تقرير سجلات وحركة السيارات اليومية',
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> trip) {
    final plateCtrl = TextEditingController(text: (trip['plateNumber'] ?? '').toString());
    final modelCtrl = TextEditingController(text: (trip['carModel'] ?? '').toString());
    final driverCtrl = TextEditingController(text: (trip['driverName'] ?? '').toString());
    final startCtrl = TextEditingController(text: (trip['startMeter'] ?? '').toString());
    final endCtrl = TextEditingController(text: (trip['endMeter'] ?? '').toString());
    final notesCtrl = TextEditingController(text: (trip['notes'] ?? '').toString());
    String dateStr = (trip['date'] ?? DateFormat('yyyy-MM-dd').format(DateTime.now())).toString();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعديل بيانات الرحلة'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: plateCtrl, decoration: const InputDecoration(labelText: 'رقم اللوحة *')),
              const SizedBox(height: 8),
              TextField(controller: modelCtrl, decoration: const InputDecoration(labelText: 'موديل السيارة')),
              const SizedBox(height: 8),
              TextField(controller: driverCtrl, decoration: const InputDecoration(labelText: 'اسم السائق')),
              const SizedBox(height: 8),
              TextField(
                controller: startCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'عداد الخروج (كم) *'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: endCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'عداد الرجوع (كم) *'),
              ),
              const SizedBox(height: 8),
              TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'ملاحظات')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              final s = double.tryParse(startCtrl.text) ?? 0;
              final e = double.tryParse(endCtrl.text) ?? 0;
              if (plateCtrl.text.trim().isEmpty || e < s) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تأكد من رقم اللوحة وأن عداد الرجوع أكبر من الخروج')),
                );
                return;
              }
              final updated = Map<String, dynamic>.from(trip);
              updated['plateNumber'] = plateCtrl.text.trim();
              updated['carModel'] = modelCtrl.text.trim();
              updated['driverName'] = driverCtrl.text.trim();
              updated['date'] = dateStr;
              updated['startMeter'] = s;
              updated['endMeter'] = e;
              updated['distance'] = e - s;
              updated['notes'] = notesCtrl.text.trim();
              await widget.tripBox.put(trip['id'], updated);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('حفظ التعديل'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.tripBox.listenable(),
      builder: (context, Box box, _) {
        final trips = _getFilteredTrips();
        final totalDist = trips.fold(0.0, (sum, i) => sum + ((i['distance'] as num?)?.toDouble() ?? 0.0));

        return Scaffold(
          appBar: AppBar(
            title: const Text('السجلات والتقارير'),
            actions: [
              IconButton(
                icon: const Icon(Icons.file_download),
                tooltip: 'تصدير Excel (CSV)',
                onPressed: () => _exportToCsv(trips),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade700,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            const Text('إجمالي الكيلومترات', style: TextStyle(color: Colors.white70)),
                            Text(
                              '${totalDist.toStringAsFixed(1)} كم',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade700,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            const Text('إجمالي الرحلات', style: TextStyle(color: Colors.white70)),
                            Text(
                              '${trips.length} رحلة',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: 'بحث برقم اللوحة أو السائق...',
                          prefixIcon: Icon(Icons.search),
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _searchPlate = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      icon: Icon(_filterMonth == null ? Icons.calendar_month : Icons.filter_alt_off),
                      tooltip: 'تصفية حسب الشهر',
                      onPressed: () async {
                        if (_filterMonth != null) {
                          setState(() => _filterMonth = null);
                          return;
                        }
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) setState(() => _filterMonth = picked);
                      },
                    ),
                  ],
                ),
              ),
              if (_filterMonth != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        'تصفية شهر: ${DateFormat('yyyy-MM').format(_filterMonth!)}',
                        style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => setState(() => _filterMonth = null),
                        child: const Text('عرض الكل', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              Expanded(
                child: trips.isEmpty
                    ? const Center(child: Text('لا توجد رحلات مسجلة مطابقة'))
                    : ListView.builder(
                        itemCount: trips.length,
                        itemBuilder: (ctx, i) {
                          final t = trips[i];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              title: Text(
                                '${t['plateNumber']} — ${t['distance']} كم',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                'التاريخ: ${t['date']} | السائق: ${(t['driverName'] ?? '').toString().isEmpty ? 'غير محدد' : t['driverName']}\nالعداد: ${t['startMeter']} ➔ ${t['endMeter']}',
                              ),
                              isThreeLine: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, color: Colors.teal),
                                    onPressed: () => _showEditDialog(t),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    onPressed: () => widget.tripBox.delete(t['id']),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// الشاشة الثالثة: الإعدادات والربط السحابي والنسخ الاحتياطي
// -----------------------------------------------------------------------------
class SettingsScreen extends StatefulWidget {
  final Box settingsBox;
  final Box tripBox;
  final Function(bool) onToggleTheme;
  const SettingsScreen({
    super.key,
    required this.settingsBox,
    required this.tripBox,
    required this.onToggleTheme,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlCtrl = TextEditingController();
  bool _dark = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl.text = widget.settingsBox.get('sheets_url', defaultValue: '').toString();
    _dark = widget.settingsBox.get('is_dark_mode', defaultValue: false) as bool;
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _exportJsonBackup() async {
    final trips = widget.tripBox.values.toList();
    if (trips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد سجلات لعمل نسخة احتياطية')));
      return;
    }
    final jsonStr = const JsonEncoder.withIndent('  ').convert(trips);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/car_logs_backup_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(jsonStr, encoding: utf8);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'نسخة احتياطية لسجل السيارات اليومي'),
    );
  }

  Future<void> _importJsonBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.single;
      String content;
      if (picked.bytes != null) {
        content = utf8.decode(picked.bytes!);
      } else if (picked.path != null) {
        content = await File(picked.path!).readAsString();
      } else {
        return;
      }

      final List<dynamic> decoded = jsonDecode(content) as List<dynamic>;
      int imported = 0;
      for (final item in decoded) {
        if (item is Map && item['id'] != null) {
          await widget.tripBox.put(item['id'].toString(), Map<String, dynamic>.from(item));
          imported++;
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم استرجاع $imported رحلة بنجاح'), backgroundColor: Colors.teal),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر استرجاع النسخة الاحتياطية: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _syncAllPending() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال رابط Google Apps Script وحفظه أولاً')),
      );
      return;
    }
    setState(() => _isSyncing = true);
    int syncedCount = 0;
    for (final key in widget.tripBox.keys) {
      final raw = widget.tripBox.get(key);
      if (raw is Map) {
        final trip = Map<String, dynamic>.from(raw);
        if (trip['synced'] != true) {
          try {
            final res = await http.post(
              Uri.parse(url),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(trip),
            );
            if (res.statusCode == 200 || res.statusCode == 302) {
              trip['synced'] = true;
              await widget.tripBox.put(key, trip);
              syncedCount++;
            }
          } catch (_) {}
        }
      }
    }
    if (!mounted) return;
    setState(() => _isSyncing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تمت مزامنة $syncedCount رحلة مع Google Sheets')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات والربط السحابي')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'الربط السحابي مع Google Sheets',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _urlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Google Apps Script Web App URL',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            widget.settingsBox.put('sheets_url', _urlCtrl.text.trim());
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('تم حفظ رابط المزامنة بنجاح')),
                            );
                          },
                          child: const Text('حفظ الرابط'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSyncing ? null : _syncAllPending,
                          child: Text(_isSyncing ? 'جاري الرفع...' : 'مزامنة المتبقي'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'النسخ الاحتياطي والاسترجاع (JSON)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.upload_file),
                          label: const Text('تصدير JSON'),
                          onPressed: _exportJsonBackup,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.download),
                          label: const Text('استرجاع JSON'),
                          onPressed: _importJsonBackup,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SwitchListTile(
              secondary: const Icon(Icons.dark_mode),
              title: const Text('الوضع الليلي (Dark Mode)'),
              value: _dark,
              onChanged: (v) {
                setState(() => _dark = v);
                widget.settingsBox.put('is_dark_mode', v);
                widget.onToggleTheme(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}
