import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const MyRunningGuideApp());
}

class MyRunningGuideApp extends StatelessWidget {
  const MyRunningGuideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Running Guide',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
      ),
      home: const MainPage(),
    );
  }
}

class RunRecord {
  final String id;
  final DateTime dateTime;
  final double distanceMeters;
  final int durationSeconds;
  final String pace;
  final List<LatLng> route;

  RunRecord({
    required this.id,
    required this.dateTime,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.pace,
    required this.route,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'dateTime': dateTime.toIso8601String(),
        'distanceMeters': distanceMeters,
        'durationSeconds': durationSeconds,
        'pace': pace,
        'route': route.map((e) => {'lat': e.latitude, 'lng': e.longitude}).toList(),
      };

  factory RunRecord.fromJson(Map<String, dynamic> json) {
    final route = (json['route'] as List<dynamic>)
        .map((e) => LatLng((e['lat'] as num).toDouble(), (e['lng'] as num).toDouble()))
        .toList();
    return RunRecord(
      id: json['id'] as String,
      dateTime: DateTime.parse(json['dateTime'] as String),
      distanceMeters: (json['distanceMeters'] as num).toDouble(),
      durationSeconds: json['durationSeconds'] as int,
      pace: json['pace'] as String,
      route: route,
    );
  }
}

class RunStorage {
  static const _key = 'my_running_guide_runs';

  static Future<List<RunRecord>> getRuns() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString(_key);
    if (s == null) return [];
    return (jsonDecode(s) as List<dynamic>)
        .map((e) => RunRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> saveRuns(List<RunRecord> runs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(runs.map((r) => r.toJson()).toList()));
  }

  static Future<void> addRun(RunRecord run) async {
    final runs = await getRuns();
    runs.insert(0, run);
    await saveRuns(runs);
  }

  static Future<void> deleteRun(String id) async {
    final runs = await getRuns();
    runs.removeWhere((r) => r.id == id);
    await saveRuns(runs);
  }
}

enum AppTab { run, history }

class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  AppTab _tab = AppTab.run;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab == AppTab.run ? 0 : 1,
        children: const [RunPage(), HistoryPage()],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab == AppTab.run ? 0 : 1,
        onTap: (i) => setState(() => _tab = i == 0 ? AppTab.run : AppTab.history),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.directions_run), label: 'Kos'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Gecmis'),
        ],
      ),
    );
  }
}
class RunPage extends StatefulWidget {
  const RunPage({super.key});
  @override
  State<RunPage> createState() => _RunPageState();
}

class _RunPageState extends State<RunPage> {
  final MapController _mapController = MapController();

  bool _isRunning = false;
  bool _showResult = false;
  String _targetDistanceText = '400';
  double _currentDistance = 0;
  int _elapsedSeconds = 0;
  String _pace = '0:00 min/km';
  LatLng? _currentPosition;
  List<LatLng> _route = [];

  Timer? _timer;
  StreamSubscription<Position>? _positionSubscription;

  @override
  void dispose() {
    _timer?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }

  double _haversineDistance(LatLng a, LatLng b) {
    const double R = 6371000;
    double toRad(double x) => x * pi / 180;
    final dLat = toRad(b.latitude - a.latitude);
    final dLon = toRad(b.longitude - a.longitude);
    final lat1 = toRad(a.latitude);
    final lat2 = toRad(b.latitude);
    final a1 = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a1), sqrt(1 - a1));
    return R * c;
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _calculatePace(int seconds, double meters) {
    if (meters <= 0 || seconds <= 0) return '0:00 min/km';
    final km = meters / 1000;
    final minPerKm = seconds / 60 / km;
    final minutes = minPerKm.floor();
    final secs = ((minPerKm - minutes) * 60).round();
    return '${minutes}:${secs.toString().padLeft(2, '0')} min/km';
  }

  Future<void> _startRun() async {
    final target = double.tryParse(_targetDistanceText);
    if (target == null || target <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lutfen gecerli bir hedef mesafe (metre) girin.')),
      );
      return;
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konum hizmeti kapali. Lutfen acin.')),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Konum izni reddedildi.')),
        );
        return;
      }
    }

    setState(() {
      _isRunning = true;
      _showResult = false;
      _currentDistance = 0;
      _elapsedSeconds = 0;
      _pace = '0:00 min/km';
      _route = [];
      _currentPosition = null;
    });

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((position) {
      final newPos = LatLng(position.latitude, position.longitude);

      if (_currentPosition != null) {
        final added = _haversineDistance(_currentPosition!, newPos);
        setState(() {
          _currentDistance += added;
          _route.add(newPos);
        });
      } else {
        setState(() => _route.add(newPos));
      }

      setState(() => _currentPosition = newPos);
      _mapController.move(newPos, 16);

      if (_currentDistance >= target) {
        _finishRun();
      }
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsedSeconds++);
      _pace = _calculatePace(_elapsedSeconds, _currentDistance);
    });
  }

  Future<void> _finishRun() async {
    _timer?.cancel();
    _timer = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;

    final run = RunRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      dateTime: DateTime.now(),
      distanceMeters: _currentDistance,
      durationSeconds: _elapsedSeconds,
      pace: _pace,
      route: List<LatLng>.from(_route),
    );

    await RunStorage.addRun(run);

    if (!mounted) return;
    setState(() {
      _isRunning = false;
      _showResult = true;
    });
  }

  void _resetRun() {
    setState(() {
      _showResult = false;
      _currentDistance = 0;
      _elapsedSeconds = 0;
      _pace = '0:00 min/km';
      _route = [];
      _currentPosition = null;
    });
  }

  void _showResultDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Hedef Ulasildi!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Mesafe: ${_currentDistance.toStringAsFixed(0)} metre'),
            Text('Sure: ${_formatTime(_elapsedSeconds)}'),
            Text('Pace: $_pace'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _resetRun();
            },
            child: const Text('Yeniden Basla'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition ?? const LatLng(41.0082, 28.9784),
              initialZoom: 16,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.kosu.app',
              ),
              if (_route.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(points: _route, color: Colors.green, strokeWidth: 4),
                  ],
                ),
              if (_currentPosition != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _currentPosition!,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.location_on, color: Colors.red, size: 40),
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (_isRunning)
          Container(
            color: Colors.black.withOpacity(0.6),
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Text('Hedef: ${_targetDistanceText} m', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Katkedilen: ${_currentDistance.toStringAsFixed(0)} m', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Sure: ${_formatTime(_elapsedSeconds)}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                children: [
                  const Text('Hedef Mesafe (metre): ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      enabled: !_isRunning && !_showResult,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(hintText: '400', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                      onChanged: (v) => _targetDistanceText = v,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (!_isRunning && !_showResult)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _startRun,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Kosmaya Basla'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              if (_isRunning)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _finishRun();
                      _showResultDialog();
                    },
                    icon: const Icon(Icons.stop),
                    label: const Text('Durdur'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              if (_showResult) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text('Kosu Tamamlandi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Text('Mesafe: ${_currentDistance.toStringAsFixed(0)} metre'),
                        Text('Sure: ${_formatTime(_elapsedSeconds)}'),
                        Text('Pace: $_pace'),
                        const SizedBox(height: 10),
                        SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () { setState(() => _showResult = false); _resetRun(); }, child: const Text('Yeniden Basla'))),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<RunRecord> _runs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final runs = await RunStorage.getRuns();
    setState(() {
      _runs = runs;
      _loading = false;
    });
  }

  Future<void> _delete(String id) async {
    await RunStorage.deleteRun(id);
    _load();
  }

  String _dateTimeString(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _runs.isEmpty
              ? const Center(child: Text('Hic kosu kaydi yok.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _runs.length,
                  itemBuilder: (ctx, i) {
                    final r = _runs[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: const Icon(Icons.directions_run, color: Colors.green),
                        title: Text('${r.distanceMeters.toStringAsFixed(0)} m'),
                        subtitle: Text('${_dateTimeString(r.dateTime)} - ${r.pace}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _delete(r.id),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _load,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}
