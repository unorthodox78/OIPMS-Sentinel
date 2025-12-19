import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../services/inventory_repository.dart';
import '../services/inventory_stream.dart';
import '../services/discrepancy_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProductionData {
  static int currentProduction = 166;
  static int dailyProductionGoal = 320;
  static int soldToday = 120;
  static int inventoryStock = 40;
  static List<Map<String, dynamic>> shifts = [
    {
      "shiftName": "Shift 1",
      "time": "6AM - 2PM",
      "count": "100 blocks",
      "expected": 110,
      "actual": 100,
      "presentStaff": ['Anna', 'John'],
      "color": Color(0xFF43EA7E),
      "gradient": [Color(0xFF43EA7E), Color(0xFF81E6C2)],
    },
    {
      "shiftName": "Shift 2",
      "time": "2PM - 10PM",
      "count": "50 blocks",
      "expected": 50,
      "actual": 50,
      "presentStaff": ['Mia'],
      "color": Color(0xFFFFB74D),
      "gradient": [Color(0xFFFFB74D), Color(0xFFFFD580)],
    },
    {
      "shiftName": "Shift 3",
      "time": "10PM - 6AM",
      "count": "16 blocks",
      "expected": 25,
      "actual": 16,
      "presentStaff": ['Sam', 'Lyn'],
      "color": Color(0xFF1976D2),
      "gradient": [Color(0xFF42A5F5), Color(0xFF1976D2)],
    },
  ];

  static List<Map<String, dynamic>> discrepancies = [
    {
      'type': 'Ice Block',
      'expected': 110,
      'actual': 100,
      'difference': -10,
      'shift': 'Shift 1',
      'status': 'Under-production',
    },
    {
      'type': 'Ice Block',
      'expected': 25,
      'actual': 16,
      'difference': -9,
      'shift': 'Shift 3',
      'status': 'Under-production',
    },
    {
      'type': 'Ice Cube',
      'expected': 40,
      'actual': 35,
      'difference': -5,
      'shift': 'Shift 2',
      'status': 'Under-production',
    },
    {
      'type': 'Ice Block',
      'expected': 80,
      'actual': 78,
      'difference': -2,
      'shift': 'Shift 1',
      'status': 'Under-production',
    },
    {
      'type': 'Ice Cube',
      'expected': 55,
      'actual': 57,
      'difference': 2,
      'shift': 'Shift 2',
      'status': 'Over-production',
    },
    {
      'type': 'Ice Block',
      'expected': 60,
      'actual': 58,
      'difference': -2,
      'shift': 'Shift 3',
      'status': 'Under-production',
    },
    {
      'type': 'Ice Cube',
      'expected': 45,
      'actual': 42,
      'difference': -3,
      'shift': 'Shift 1',
      'status': 'Under-production',
    },
  ];
}

class ProductionTab extends StatefulWidget {
  const ProductionTab({super.key});
  @override
  State<ProductionTab> createState() => _ProductionTabState();
}

class _ProductionTabState extends State<ProductionTab>
    with TickerProviderStateMixin {
  static const Color _primaryColor = Color(0xFF0F8AA3);

  late final AnimationController _progressController;
  late final Animation<double> _progressAnimation;
  late Timer _inventoryTimer;
  late Timer _productionTimer;
  final Random _rng = Random();
  // Notifier to trigger rebuilds in the popup dialog when data updates
  final ValueNotifier<int> _uiTick = ValueNotifier<int>(0);

  // Live inventory data (prev/current to compute delta) read from VM API
  List<Map<String, int>> _inventoryData = [
    {'inStock': 0, 'prevInStock': 0, 'inProduction': 0, 'prevInProduction': 0},
    {'inStock': 0, 'prevInStock': 0, 'inProduction': 0, 'prevInProduction': 0},
  ];
  late final InventoryRepository _inventoryRepo;
  InventoryLiveStream? _live;
  StreamSubscription<List<InventoryItemLive>>? _liveSub;
  // Track when last change happened to auto-hide delta indicators
  static const Duration _deltaTTL = Duration(seconds: 4);
  final List<DateTime?> _stockChangeAt = [null, null];
  final List<DateTime?> _prodChangeAt = [null, null];
  // Suspend polling briefly after a manual edit so it won't be overwritten
  DateTime? _pollSuspendUntil;

  late final DiscrepancyRepository _discrepancyRepo;
  StreamSubscription<List<Map<String, dynamic>>>? _discrepancyStreamSub;
  Timer? _discrepancyPollTimer;
  bool _isDiscrepancyFetching = false;
  List<Map<String, dynamic>> _discrepancies = [];

  Future<List<String>> _fetchActiveCashiers([
    Duration window = const Duration(minutes: 15),
  ]) async {
    try {
      final since = Timestamp.fromDate(DateTime.now().subtract(window));
      final qs = await FirebaseFirestore.instance
          .collection('audit_logs_cashier')
          .where('timestamp', isGreaterThan: since)
          .where('route_name', isEqualTo: 'PosSale')
          .orderBy('timestamp', descending: true)
          .limit(200)
          .get();
      final set = <String>{};
      for (final d in qs.docs) {
        final u = (d.data()['username'] as String?)?.trim();
        if (u != null && u.isNotEmpty) set.add(u);
      }
      if (set.isEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        final email = user?.email ?? '';
        final name =
            user?.displayName ??
            (email.contains('@') ? email.split('@').first : 'Cashier');
        return [name];
      }
      return set.toList();
    } catch (_) {
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email ?? '';
      final name =
          user?.displayName ??
          (email.contains('@') ? email.split('@').first : 'Cashier');
      return [name];
    }
  }

  Future<String?> _getAdminName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final n = prefs.getString('admin_display_name');
      return (n != null && n.trim().isNotEmpty) ? n.trim() : null;
    } catch (_) {
      return null;
    }
  }

  List<String> _filterOutAdmin(List<String> names) {
    final set = <String>{};
    set.addAll(names.where((e) => e.trim().isNotEmpty).map((e) => e.trim()));
    return set.toList();
  }

  String _shiftDocId(Map<String, dynamic> shift) {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final dateIso = '$y-$m-$d';
    final sn = (shift['shiftName'] ?? 'Shift').toString().replaceAll(' ', '_');
    return '${dateIso}_$sn';
  }

  Future<List<String>> _loadShiftStaffOverride(
    Map<String, dynamic> shift,
  ) async {
    try {
      final id = _shiftDocId(shift);
      final doc = await FirebaseFirestore.instance
          .collection('shift_present_staff')
          .doc(id)
          .get();
      final data = doc.data();
      if (data == null) return const <String>[];
      final list =
          (data['staff'] as List?)?.map((e) => e.toString()).toList() ??
          const <String>[];
      return list;
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> _saveShiftStaffOverride(
    Map<String, dynamic> shift,
    List<String> names,
  ) async {
    try {
      final now = DateTime.now();
      final y = now.year.toString().padLeft(4, '0');
      final m = now.month.toString().padLeft(2, '0');
      final d = now.day.toString().padLeft(2, '0');
      final dateIso = '$y-$m-$d';
      final id = _shiftDocId(shift);
      final clean = names
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      await FirebaseFirestore.instance
          .collection('shift_present_staff')
          .doc(id)
          .set({
            'date': dateIso,
            'shiftName': (shift['shiftName'] ?? 'Shift').toString(),
            'time': (shift['time'] ?? '').toString(),
            'staff': clean,
            'updatedAt': Timestamp.now(),
          }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<List<String>> _getPresentStaff(Map<String, dynamic> shift) async {
    final override = await _loadShiftStaffOverride(shift);
    List<String> base = override.isNotEmpty
        ? override
        : await _fetchActiveCashiers(const Duration(minutes: 20));
    base = _filterOutAdmin(base);
    final adminName = (await _getAdminName())?.toLowerCase();
    if (adminName != null && adminName.isNotEmpty) {
      base = base.where((n) => n.toLowerCase() != adminName).toList();
    }
    return base;
  }

  Future<void> _showEditStaffDialog(
    BuildContext ctx,
    Map<String, dynamic> shift,
    List<String> current,
  ) async {
    final controller = TextEditingController(text: current.join(', '));
    await showDialog(
      context: ctx,
      builder: (dCtx) {
        return AlertDialog(
          title: const Text('Edit Present Staff'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Enter names separated by commas',
            ),
            minLines: 1,
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final raw = controller.text;
                final parts = raw
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                final adminName = (await _getAdminName())?.toLowerCase();
                final filtered = adminName == null
                    ? parts
                    : parts.where((n) => n.toLowerCase() != adminName).toList();
                await _saveShiftStaffOverride(shift, filtered);
                if (mounted) setState(() {});
                if (context.mounted) Navigator.of(dCtx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  double get productionProgress =>
      _productionMax == 0 ? 0.0 : _productionToday / _productionMax;

  // Mock production-today state (max capacity 200 blocks)
  static const int _productionMax = 200;
  int _productionToday = 0;
  int _prevProductionToday = 0;
  int _prodDirection = 1; // 1 = increasing, -1 = decreasing

  // Separate mock production for Ice Cube
  static const int _cubeProductionMax = 200;
  int _cubeProductionToday = 0;
  int _prevCubeProductionToday = 0;
  int _cubeProdDirection = 1; // 1 = increasing, -1 = decreasing

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.0,
      upperBound: 1.0,
    );
    // Use the controller directly as the animation for simplicity
    _progressAnimation = _progressController;

    // Initialize mock production value and set initial progress
    _productionToday = 100 + _rng.nextInt(41); // 100..140
    _prevProductionToday = 0; // animate number from 0 -> initial on first load
    // Start progress from 0 then animate to initial percentage
    _progressController.value = 0.0;
    _progressController.animateTo(
      productionProgress.clamp(0.0, 1.0),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
    );
    // Ensure Ice Block (row 0) 'In Production' mirrors Production Today
    if (_inventoryData.isNotEmpty) {
      _inventoryData[0]['prevInProduction'] = _prevProductionToday;
      _inventoryData[0]['inProduction'] = _productionToday;
    }

    void _applyDiscrepanciesSnapshot(List<Map<String, dynamic>> list) {
      final out = <Map<String, dynamic>>[];
      for (final r in list) {
        final type = (r['type'] ?? '').toString();
        final shift = (r['shift'] ?? '').toString();
        final e = r['expected'];
        final a = r['actual'];
        final expected = e is num
            ? e.toInt()
            : int.tryParse(e?.toString() ?? '') ?? 0;
        final actual = a is num
            ? a.toInt()
            : int.tryParse(a?.toString() ?? '') ?? 0;
        final d = r['difference'];
        final difference = d is num
            ? d.toInt()
            : int.tryParse(d?.toString() ?? '') ?? (actual - expected);
        final tsRaw = r['timestamp']?.toString();
        int ts = 0;
        if (tsRaw != null) {
          final parsed = DateTime.tryParse(tsRaw);
          if (parsed != null) ts = parsed.millisecondsSinceEpoch;
        }
        out.add({
          'type': type,
          'shift': shift,
          'expected': expected,
          'actual': actual,
          'difference': difference,
          'timestamp': ts,
        });
      }
      out.sort(
        (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int),
      );
      setState(() {
        _discrepancies = out;
      });
      _uiTick.value++;
    }

    Future<void> _fetchAndApplyDiscrepancies() async {
      if (_isDiscrepancyFetching) return;
      _isDiscrepancyFetching = true;
      try {
        final list = await _discrepancyRepo.fetchAllDiscrepancies();
        _applyDiscrepanciesSnapshot(list);
      } catch (_) {
      } finally {
        _isDiscrepancyFetching = false;
      }
    }

    @override
    void didChangeDependencies() {
      super.didChangeDependencies();
      // Clear recent-change timestamps on screen activation so badges
      // don't appear unless a change happens AFTER entering this tab.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          for (int i = 0; i < _stockChangeAt.length; i++) {
            _stockChangeAt[i] = null;
          }
          for (int i = 0; i < _prodChangeAt.length; i++) {
            _prodChangeAt[i] = null;
          }
        });
        _uiTick.value++;
      });
    }

    // Initialize Ice Cube mock production
    _cubeProductionToday = 80 + _rng.nextInt(41); // 80..120
    _prevCubeProductionToday = 0;
    if (_inventoryData.length > 1) {
      _inventoryData[1]['prevInProduction'] = _prevCubeProductionToday;
      _inventoryData[1]['inProduction'] = _cubeProductionToday;
    }

    Future<void> _setupInventory() async {
      String? token;
      try {
        token = await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {}
      // token used in headers below
      _inventoryRepo = InventoryRepository(
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      await _fetchAndApplyInventory();
    }

    Future<void> _setupDiscrepancies() async {
      String? token;
      try {
        token = await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {}
      _discrepancyRepo = DiscrepancyRepository(
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
      );
      await _discrepancyRepo.ensureTableMetadata();
      try {
        final list = await _discrepancyRepo.fetchAllDiscrepancies();
        _applyDiscrepanciesSnapshot(list);
        if (list.isEmpty) {
          for (int i = 0; i < ProductionData.discrepancies.length; i++) {
            final row = ProductionData.discrepancies[i];
            final type = (row['type'] ?? '').toString();
            final e = row['expected'];
            final a = row['actual'];
            final expected = e is num
                ? e.toInt()
                : int.tryParse(e?.toString() ?? '') ?? 0;
            final actual = a is num
                ? a.toInt()
                : int.tryParse(a?.toString() ?? '') ?? 0;
            final shift = row['shift']?.toString();
            final status = row['status']?.toString();
            final safeType = type.replaceAll(' ', '_');
            final safeShift = (shift ?? 'S').replaceAll(' ', '_');
            final id = 'seed_${i}_${safeType}_${safeShift}_${expected}_$actual';
            try {
              await _discrepancyRepo.upsertDiscrepancy(
                id: id,
                type: type,
                expected: expected,
                actual: actual,
                shift: shift,
                status: status,
              );
            } catch (_) {}
          }
          // Refresh after seeding
          final seeded = await _discrepancyRepo.fetchAllDiscrepancies();
          _applyDiscrepanciesSnapshot(seeded);
        }
      } catch (_) {}
      try {
        await _discrepancyStreamSub?.cancel();
        _discrepancyStreamSub = _discrepancyRepo.streamDiscrepancies().listen(
          (list) => _applyDiscrepanciesSnapshot(list),
        );
      } catch (_) {}
      _discrepancyPollTimer?.cancel();
      _discrepancyPollTimer = Timer.periodic(
        const Duration(milliseconds: 150),
        (_) => _fetchAndApplyDiscrepancies(),
      );
    }

    void _applyIncoming(List<InventoryItemLive> items) {
      // Update table immediately from push stream, preserving delta logic
      final block = items.firstWhere(
        (e) => e.type == 'Ice Block',
        orElse: () => items.first,
      );
      final cube = items.firstWhere(
        (e) => e.type == 'Ice Cube',
        orElse: () => items.length > 1 ? items[1] : items.first,
      );
      setState(() {
        // Row 0: Ice Block
        final r0 = _inventoryData[0];
        final int currentStock0 = r0['inStock'] ?? 0;
        final int newStock0 = block.inStock;
        if (newStock0 != currentStock0) {
          r0['prevInStock'] = currentStock0;
          r0['inStock'] = newStock0;
          _stockChangeAt[0] = DateTime.now();
        }
        // Keep production today driving row 0 production
        final int currentProd0 = r0['inProduction'] ?? 0;
        if (_productionToday != currentProd0) {
          r0['prevInProduction'] = _prevProductionToday;
          r0['inProduction'] = _productionToday;
          _prodChangeAt[0] = DateTime.now();
        }

        // Row 1: Ice Cube
        final r1 = _inventoryData[1];
        final int currentStock1 = r1['inStock'] ?? 0;
        final int newStock1 = cube.inStock;
        if (newStock1 != currentStock1) {
          r1['prevInStock'] = currentStock1;
          r1['inStock'] = newStock1;
          _stockChangeAt[1] = DateTime.now();
        }
        final int currentProd1 = r1['inProduction'] ?? 0;
        if (_cubeProductionToday != currentProd1) {
          r1['prevInProduction'] = _prevCubeProductionToday;
          r1['inProduction'] = _cubeProductionToday;
          _prodChangeAt[1] = DateTime.now();
        }
      });
      _uiTick.value++;
    }

    // Initialize repository (with Authorization header if available) and start polling API for inventory
    _setupInventory();
    _inventoryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _fetchAndApplyInventory();
    });
    _setupDiscrepancies();

    // Connect to live push channel (WebSocket preferred, SSE fallback)
    () async {
      String? token;
      try {
        token = await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {}
      _live = InventoryLiveStream(
        wsUrl: 'ws://139.162.46.103:8080/ws/inventory?ns=oipms&set=inventory',
        sseUrl:
            'http://139.162.46.103:8080/api/inventory/stream?ns=oipms&set=inventory',
        headers: {if (token != null) 'Authorization': 'Bearer $token'},
      );
      await _live!.connect();
      _liveSub = _live!.stream.listen((items) {
        _applyIncoming(items);
      });
    }();

    // Periodically update mock production-today value up/down within 0..200
    _productionTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final int step = 4 + _rng.nextInt(13); // 4..16
      // Occasionally flip direction randomly
      if (_rng.nextInt(5) == 0) {
        _prodDirection *= -1;
      }
      _prevProductionToday = _productionToday;
      _productionToday = (_productionToday + _prodDirection * step).clamp(
        0,
        _productionMax,
      );
      // Mark production change time for row 0 (Ice Block)
      _prodChangeAt[0] = DateTime.now();
      // Bounce at bounds
      if (_productionToday == 0 || _productionToday == _productionMax) {
        _prodDirection *= -1;
      }
      final double newProgress = productionProgress.clamp(0.0, 1.0);
      _progressController.animateTo(
        newProgress,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
      );
      // Sync Ice Block row's in-production with production today
      if (_inventoryData.isNotEmpty) {
        _inventoryData[0]['prevInProduction'] = _prevProductionToday;
        _inventoryData[0]['inProduction'] = _productionToday;
      }
      // Update Ice Cube mock production independently and sync row 1
      final int cubeStep = 3 + _rng.nextInt(10); // 3..12
      if (_rng.nextInt(6) == 0) {
        _cubeProdDirection *= -1;
      }
      _prevCubeProductionToday = _cubeProductionToday;
      _cubeProductionToday =
          (_cubeProductionToday + _cubeProdDirection * cubeStep).clamp(
            0,
            _cubeProductionMax,
          );
      _prodChangeAt[1] = DateTime.now();
      if (_cubeProductionToday == 0 ||
          _cubeProductionToday == _cubeProductionMax) {
        _cubeProdDirection *= -1;
      }
      if (_inventoryData.length > 1) {
        _inventoryData[1]['prevInProduction'] = _prevCubeProductionToday;
        _inventoryData[1]['inProduction'] = _cubeProductionToday;
      }
      if (mounted) setState(() {});
      _uiTick.value++;
    });
  }

  @override
  void dispose() {
    _progressController.dispose();
    _inventoryTimer.cancel();
    _productionTimer.cancel();
    _uiTick.dispose();
    _liveSub?.cancel();
    _liveSub = null;
    _live?.dispose();
    _discrepancyStreamSub?.cancel();
    _discrepancyPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchAndApplyInventory() async {
    // If polling is temporarily suspended (after manual edit), skip fetch
    if (_pollSuspendUntil != null &&
        DateTime.now().isBefore(_pollSuspendUntil!)) {
      return;
    }
    try {
      final items = await _inventoryRepo.fetchInventory();
      if (items.isEmpty) return;
      // Ensure we identify both product types even if order varies
      final block = items.firstWhere(
        (e) => e.type == 'Ice Block',
        orElse: () => items.first,
      );
      final cube = items.firstWhere(
        (e) => e.type == 'Ice Cube',
        orElse: () => items.length > 1 ? items[1] : items.first,
      );

      setState(() {
        // Row 0: Ice Block
        final r0 = _inventoryData[0];
        final prevStock0 = r0['inStock'] ?? 0;
        r0['prevInStock'] = prevStock0;
        r0['inStock'] = block.inStock;
        if (r0['inStock'] != r0['prevInStock']) {
          _stockChangeAt[0] = DateTime.now();
        }
        // In production mirrors Production Today progress
        r0['prevInProduction'] = _prevProductionToday;
        r0['inProduction'] = _productionToday;
        if ((r0['inProduction'] ?? 0) != (r0['prevInProduction'] ?? 0)) {
          _prodChangeAt[0] = DateTime.now();
        }

        // Row 1: Ice Cube
        final r1 = _inventoryData[1];
        final prevStock1 = r1['inStock'] ?? 0;
        r1['prevInStock'] = prevStock1;
        r1['inStock'] = cube.inStock;
        if (r1['inStock'] != r1['prevInStock']) {
          _stockChangeAt[1] = DateTime.now();
        }
        r1['prevInProduction'] = _prevCubeProductionToday;
        r1['inProduction'] = _cubeProductionToday;
        if (r1['inProduction'] != r1['prevInProduction']) {
          _prodChangeAt[1] = DateTime.now();
        }
      });
      _uiTick.value++;
    } catch (_) {
      // Ignore transient fetch errors
    }
  }

  Future<void> _generateInventoryReport() async {
    try {
      final pdf = pw.Document();
      final types = ['Ice Block', 'Ice Cube'];

      int totalStock = 0;
      int totalProduction = 0;
      for (int i = 0; i < _inventoryData.length; i++) {
        totalStock += _inventoryData[i]['inStock'] ?? 0;
        totalProduction += _inventoryData[i]['inProduction'] ?? 0;
      }

      pdf.addPage(
        pw.MultiPage(
          pageTheme: const pw.PageTheme(margin: pw.EdgeInsets.all(24)),
          build: (context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Inventory Report',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text('${DateTime.now()}'),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Summary',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Bullet(text: 'Total In Stock: $totalStock'),
              pw.Bullet(text: 'Total In Production: $totalProduction'),
              pw.SizedBox(height: 12),
              pw.Text(
                'Details',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table.fromTextArray(
                headers: ['Type', 'In Stock', 'In Production'],
                data: List.generate(_inventoryData.length, (i) {
                  final row = _inventoryData[i];
                  final type = types[i % types.length];
                  return [
                    type,
                    (row['inStock'] ?? 0).toString(),
                    (row['inProduction'] ?? 0).toString(),
                  ];
                }),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFE0F2F1),
                ),
                cellAlignment: pw.Alignment.centerLeft,
                cellStyle: const pw.TextStyle(fontSize: 11),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1),
                },
              ),
            ];
          },
        ),
      );

      final bytes = await pdf.save();
      // Save to a temporary file and open with a viewer
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/inventory_report_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = await File(path).writeAsBytes(bytes, flush: true);
      await OpenFilex.open(file.path);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Report saved to: ${file.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to generate report: $e')));
    }
  }

  Future<void> _promptEditInStock(int index) async {
    if (index < 0 || index >= _inventoryData.length) return;
    final row = _inventoryData[index];
    final controller = TextEditingController(
      text: (row['inStock'] ?? 0).toString(),
    );
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Text(
            'Edit In Stock',
            style: TextStyle(
              color: Color(0xFF0F8AA3),
              fontWeight: FontWeight.w800,
            ),
          ),
          content: SizedBox(
            width: 260,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Enter new value',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF0F8AA3),
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F8AA3),
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                elevation: 1,
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (result == null) return;
    final parsed = int.tryParse(result);
    if (parsed == null) return;
    setState(() {
      final curr = row['inStock'] ?? 0;
      row['prevInStock'] = curr;
      row['inStock'] = parsed.clamp(0, 999999);
      // Mark change time so delta badges become visible right away
      _stockChangeAt[index] = DateTime.now();
    });
    _uiTick.value++;
    _pollSuspendUntil = DateTime.now().add(const Duration(seconds: 3));
    final type = (index == 0) ? 'Ice Block' : 'Ice Cube';
    try {
      final ok = await _inventoryRepo.updateInventory(
        type: type,
        inStock: parsed,
      );
      if (!ok && mounted) {
        // Revert UI if server rejected
        setState(() {
          row['inStock'] = (row['prevInStock'] ?? 0);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save. Server rejected the update.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          row['inStock'] = (row['prevInStock'] ?? 0);
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Update error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // KEEP YOUR BOTTOM NAVIGATION BAR - ADD YOURS HERE IF NOT PRESENT
      body: SingleChildScrollView(
        child: Padding(
          // Increase bottom padding to ensure full visibility above nav bar
          padding: const EdgeInsets.fromLTRB(
            22.0,
            22.0,
            22.0,
            100.0,
          ), // 100 for nav bar height
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildProductionTodayCard(),
                  Transform.translate(
                    offset: const Offset(16, 23),
                    child: SizedBox(
                      width: 160,
                      child: _StackedSolidShiftCards(
                        onShiftTap: _openShiftDetails,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _buildInventoryTable(),
              const SizedBox(height: 20),
              _buildDiscrepancyTable(),
            ],
          ),
        ),
      ),
      // Example: If you have a nav bar, put it like this!
      // bottomNavigationBar: YourCustomNavBar(),
    );
  }

  void _openDiscrepanciesPopup() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Production Discrepancies',
      pageBuilder: (_, __, ___) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Transform.scale(
              scale: 1.0,
              child: Container(
                width: MediaQuery.of(context).size.width * .9,
                constraints: const BoxConstraints(maxWidth: 560),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 44),
                        const Expanded(
                          child: Text(
                            'Production Discrepancies',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                        const SizedBox(width: 44, height: 44),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: _buildDiscrepanciesDataTable(),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.center,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F8AA3),
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                          elevation: 1,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 8,
                          ),
                          child: Text(
                            'Close',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curved = Curves.easeOutBack.transform(anim1.value);
        return Opacity(
          opacity: anim1.value,
          child: Transform.scale(
            scale: 0.9 + curved * 0.1,
            child: Transform.translate(
              offset: Offset(0, 40 * (1 - curved)),
              child: child,
            ),
          ),
        );
      },
    );
  }

  // Builds only the DataTable body used in the popup for discrepancies
  Widget _buildDiscrepanciesDataTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 18,
        headingRowHeight: 36,
        dividerThickness: 0.45,
        columns: const [
          DataColumn(
            label: Text(
              'Type',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              'Shift',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              'Expected',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              'Actual',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
          DataColumn(
            label: Text(
              'Diff',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
        ],
        rows: _discrepancies
            .where((row) {
              final d = row['difference'];
              final diff = d is num
                  ? d.toInt()
                  : int.tryParse(d?.toString() ?? '') ??
                        (((row['actual'] ?? 0) as int) -
                            ((row['expected'] ?? 0) as int));
              return diff < 0; // show only deductions
            })
            .map((row) {
              final Color statusColor = Colors.red; // red-only as requested
              return DataRow(
                cells: [
                  DataCell(
                    Text(
                      row['type'].toString(),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.black87),
                    ),
                  ),
                  DataCell(
                    Text(
                      row['shift'].toString().replaceAll(
                        'Shift ',
                        'S',
                      ), // match inline format
                      style: const TextStyle(color: Colors.black),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${row['expected']}',
                      style: const TextStyle(color: Colors.black),
                    ),
                  ),
                  DataCell(
                    Text(
                      '${row['actual']}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: statusColor.withOpacity(0.3)),
                      ),
                      child: Text(
                        '${row['difference']}',
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            })
            .toList(),
      ),
    );
  }

  void _openInventoryPopup() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Inventory',
      pageBuilder: (_, __, ___) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Transform.scale(
              scale: 1.0,
              child: Container(
                width: MediaQuery.of(context).size.width * .9,
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 44),
                        const Expanded(
                          child: Text(
                            'Inventory',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F8AA3),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _generateInventoryReport,
                              child: Transform.translate(
                                offset: const Offset(0, -2),
                                child: Image.asset(
                                  'assets/report.png',
                                  width: 26,
                                  height: 26,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: ValueListenableBuilder<int>(
                        valueListenable: _uiTick,
                        builder: (context, _, __) => _buildInventoryDataTable(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.center,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F8AA3),
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                          elevation: 1,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 8,
                          ),
                          child: Text(
                            'Close',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curved = Curves.easeOutBack.transform(anim1.value);
        return Opacity(
          opacity: anim1.value,
          child: Transform.scale(
            scale: 0.9 + curved * 0.1,
            child: Transform.translate(
              offset: Offset(0, 40 * (1 - curved)),
              child: child,
            ),
          ),
        );
      },
    );
  }

  // Builds only the DataTable body used in the popup to avoid duplicating the card chrome
  Widget _buildInventoryDataTable() {
    final types = ['Ice Block', 'Ice Cube'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 18,
        headingRowHeight: 36,
        dividerThickness: 0.45,
        columns: [
          DataColumn(
            label: Padding(
              padding: EdgeInsets.only(left: 12.0),
              child: Text(
                'Type',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          DataColumn(
            label: Builder(
              builder: (context) {
                final fontSize =
                    DefaultTextStyle.of(context).style.fontSize ?? 14.0;
                return Transform.translate(
                  offset: Offset(
                    -(fontSize * 0.6 * 4),
                    0,
                  ), // ~4 backspaces left
                  child: const Text(
                    'In Stock',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black,
                    ),
                  ),
                );
              },
            ),
          ),
          DataColumn(
            label: Builder(
              builder: (context) {
                final fontSize =
                    DefaultTextStyle.of(context).style.fontSize ?? 14.0;
                return Transform.translate(
                  offset: Offset(
                    -(fontSize * 0.6 * 4),
                    0,
                  ), // ~2 backspaces left (moved 1 space right)
                  child: const Text(
                    'In Production',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        rows: List.generate(_inventoryData.length, (i) {
          final row = _inventoryData[i];
          final type = types[i % types.length];
          return DataRow(
            cells: [
              DataCell(
                Builder(
                  builder: (context) {
                    final fontSize =
                        DefaultTextStyle.of(context).style.fontSize ?? 14.0;
                    final double blockSize = fontSize * 5.0;
                    final double iconBox = blockSize;
                    final double iconSize = blockSize;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: iconBox,
                          height: iconBox,
                          child: Center(
                            child: Transform.translate(
                              offset: Offset(-(fontSize * 0.6 * 4), 0),
                              child: Image.asset(
                                type.contains('Cube')
                                    ? 'assets/cube.png'
                                    : 'assets/ice_block.png',
                                width: iconSize,
                                height: iconSize,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          fit: FlexFit.loose,
                          child: Transform.translate(
                            offset: Offset(-(fontSize * 0.6 * 5), 0),
                            child: Text(
                              type,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.black87),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              DataCell(
                Builder(
                  builder: (context) {
                    final fontSize =
                        DefaultTextStyle.of(context).style.fontSize ?? 14.0;
                    return InkWell(
                      onTap: () => _promptEditInStock(i),
                      child: Transform.translate(
                        offset: Offset(-(fontSize * 0.6 * 4), 0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Tooltip(
                              message: 'Tap to edit',
                              child: _deltaValue(
                                (row['prevInStock'] ?? 0),
                                (row['inStock'] ?? 0),
                                lastChange: _stockChangeAt[i],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Tooltip(
                              message: 'Edit In Stock',
                              child: Icon(
                                Icons.edit,
                                size: 14,
                                color: _primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              DataCell(
                Builder(
                  builder: (context) {
                    final fontSize =
                        DefaultTextStyle.of(context).style.fontSize ?? 14.0;
                    // Ensure Ice Block's In Production always mirrors live Production Today
                    final bool isIceBlockRow = i == 0;
                    final int prevProd = isIceBlockRow
                        ? _prevProductionToday
                        : row['prevInProduction']!;
                    final int currProd = isIceBlockRow
                        ? _productionToday
                        : row['inProduction']!;
                    return Transform.translate(
                      offset: Offset(
                        -(fontSize * 0.6 * 3),
                        0,
                      ), // moved 2 more backspaces to the left
                      child: _deltaValue(
                        prevProd,
                        currProd,
                        lastChange: _prodChangeAt[i],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  // Renders an animated numeric value with delta arrow and +/- amount
  Widget _deltaValue(
    int prev,
    int curr, {
    DateTime? lastChange,
    bool onlyUp = false,
  }) {
    final bool up = curr >= prev;
    final int delta = (curr - prev).abs();
    final bool hasDelta = curr != prev;
    final bool showDelta =
        hasDelta &&
        lastChange != null &&
        DateTime.now().difference(lastChange) <= _deltaTTL &&
        (!onlyUp || up);

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: prev.toDouble(), end: curr.toDouble()),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
            builder: (context, value, child) => Text(
              value.toInt().toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black),
            ),
          ),
          if (showDelta) ...[
            const SizedBox(width: 4),
            Icon(
              up ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              color: up ? Colors.green : Colors.red,
              size: 18,
            ),
            const SizedBox(width: 2),
            Text(
              up ? '+$delta' : '-$delta',
              style: TextStyle(
                color: up ? Colors.green : Colors.red,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return const Text(
      'Production Monitoring',
      style: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.bold,
        color: _primaryColor,
      ),
    );
  }

  Widget _buildProductionTodayCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 165,
        height: 185,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F8AA3), Color(0xFF0AA0C4)],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              child: Transform.translate(
                offset: const Offset(4, 0),
                child: Transform.scale(
                  scale: 3.5,
                  child: Image.asset(
                    'assets/ice_block.png',
                    width: 28,
                    height: 28,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Production Today',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: _prevProductionToday.toDouble(),
                end: _productionToday.toDouble(),
              ),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) {
                return Text(
                  '${value.round()} blocks',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Container(
              height: 4,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AnimatedBuilder(
                  animation: _progressAnimation,
                  builder: (context, child) {
                    return Container(
                      width: 133 * _progressAnimation.value,
                      decoration: BoxDecoration(
                        color: _progressAnimation.value >= 1.0
                            ? Colors.greenAccent
                            : _progressAnimation.value >= 0.7
                            ? Colors.blueAccent
                            : Colors.blue[100],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 4),
            AnimatedBuilder(
              animation: _progressAnimation,
              builder: (context, child) {
                final percent = (_progressAnimation.value * 100).clamp(0, 100);
                return Text(
                  "${percent.toStringAsFixed(0)}% of capacity",
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryTable() {
    final types = ['Ice Block', 'Ice Cube'];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 4,
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 28,
                  child: Stack(
                    children: [
                      const Align(
                        alignment: Alignment.center,
                        child: Text(
                          'Inventory',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F8AA3),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12.0),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _openInventoryPopup,
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Center(
                                child: Transform.translate(
                                  offset: const Offset(0, -2),
                                  child: Image.asset(
                                    'assets/maximize.png',
                                    width: 20,
                                    height: 20,
                                    color: Color(0xFF0F8AA3),
                                    colorBlendMode: BlendMode.srcIn,
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: DataTable(
                    columnSpacing: 26,
                    headingRowHeight: 36,
                    dividerThickness: 0.45,
                    columns: [
                      DataColumn(
                        label: Container(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12.0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                SizedBox(width: 10), // ~4 forward spaces
                                Text(
                                  'Type',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Container(
                          alignment: Alignment.center,
                          width: 70,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 14.0),
                            child: Transform.translate(
                              offset: const Offset(-66, 0),
                              child: const Text(
                                'In Stock',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Container(
                          alignment: Alignment.center,
                          width: 80,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Transform.translate(
                              offset: const Offset(-75, 0),
                              child: const Text(
                                'In Production',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.black,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    rows: List.generate(_inventoryData.length, (i) {
                      final row = _inventoryData[i];
                      final type = types[i % types.length];
                      return DataRow(
                        cells: [
                          DataCell(
                            Container(
                              alignment: Alignment.centerLeft,
                              child: Builder(
                                builder: (context) {
                                  final style = const TextStyle(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.normal,
                                  );
                                  final assetPath = type.contains('Cube')
                                      ? 'assets/cube.png'
                                      : 'assets/ice_block.png';
                                  final fontSize =
                                      DefaultTextStyle.of(
                                        context,
                                      ).style.fontSize ??
                                      14.0;
                                  final double blockSize = fontSize * 5.0;
                                  final double iconBox =
                                      blockSize; // fixed box to align rows
                                  final double iconSize =
                                      blockSize; // cube same size as block
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: iconBox,
                                        height: iconBox,
                                        child: Center(
                                          child: Transform.translate(
                                            offset: Offset(
                                              -(fontSize * 0.6 * 4),
                                              0,
                                            ),
                                            child: Image.asset(
                                              assetPath,
                                              width: iconSize,
                                              height: iconSize,
                                              filterQuality: FilterQuality.high,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        fit: FlexFit.loose,
                                        child: Transform.translate(
                                          offset: Offset(
                                            -(fontSize * 0.6 * 5),
                                            0,
                                          ),
                                          child: Text(
                                            type,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: style,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                          DataCell(
                            Container(
                              alignment: Alignment.center,
                              width: 70,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 14.0),
                                child: Transform.translate(
                                  offset: const Offset(-66, 0),
                                  child: _deltaValue(
                                    (row['prevInStock'] ?? 0),
                                    (row['inStock'] ?? 0),
                                    lastChange: _stockChangeAt[i],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            Container(
                              alignment: Alignment.center,
                              width: 80,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8.0),
                                child: Transform.translate(
                                  offset: const Offset(-75, 0),
                                  child: _deltaValue(
                                    (row['prevInProduction'] ?? 0),
                                    (row['inProduction'] ?? 0),
                                    lastChange: _prodChangeAt[i],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiscrepancyTable() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 4,
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 28,
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.warning, color: Colors.orange, size: 22),
                            SizedBox(width: 8),
                            Text(
                              'Production Discrepancies',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: Colors.orange,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12.0),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _openDiscrepanciesPopup,
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Center(
                                child: Transform.translate(
                                  offset: const Offset(0, -2),
                                  child: Image.asset(
                                    'assets/maximize.png',
                                    width: 20,
                                    height: 20,
                                    color: Color(0xFF0F8AA3),
                                    colorBlendMode: BlendMode.srcIn,
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Builder(
                  builder: (context) {
                    const double headerHeight = 36.0;
                    const double rowHeight = 44.0;
                    const int visibleRows = 5;
                    final double bodyHeight = rowHeight * visibleRows;

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Fixed header (inline view: show Type, Shift, Diff only)
                        DataTable(
                          headingRowHeight: headerHeight,
                          dataRowMinHeight: 0,
                          dataRowMaxHeight: 0,
                          horizontalMargin: 0,
                          columnSpacing: 4,
                          columns: [
                            DataColumn(
                              label: SizedBox(
                                width: 76,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: EdgeInsets.only(left: 28),
                                    child: Text(
                                      'Type',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            DataColumn(
                              label: SizedBox(
                                width: 36,
                                child: Align(
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Shift',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            DataColumn(
                              label: SizedBox(
                                width: 54,
                                child: Align(
                                  alignment: Alignment.center,
                                  child: Text(
                                    'Expected',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            DataColumn(
                              label: SizedBox(
                                width: 54,
                                child: Align(
                                  alignment: Alignment.center,
                                  child: Transform.translate(
                                    offset: Offset(-6, 0),
                                    child: Text(
                                      'Actual',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            DataColumn(
                              label: SizedBox(
                                width: 40,
                                child: Align(
                                  alignment: Alignment.center,
                                  child: Transform.translate(
                                    offset: Offset(-6, 0),
                                    child: Text(
                                      'Diff',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          rows: const [],
                        ),
                        // Scrollable rows (5 visible) with matching widths
                        SizedBox(
                          height: bodyHeight,
                          child: SingleChildScrollView(
                            child: DataTable(
                              headingRowHeight: 0,
                              dataRowMinHeight: rowHeight,
                              dataRowMaxHeight: rowHeight,
                              horizontalMargin: 0,
                              columnSpacing: 4,
                              columns: const [
                                DataColumn(label: SizedBox(width: 76)),
                                DataColumn(label: SizedBox(width: 36)),
                                DataColumn(label: SizedBox(width: 54)),
                                DataColumn(label: SizedBox(width: 54)),
                                DataColumn(label: SizedBox(width: 40)),
                              ],
                              rows: _discrepancies
                                  .where((row) {
                                    final d = row['difference'];
                                    final diff = d is num
                                        ? d.toInt()
                                        : int.tryParse(d?.toString() ?? '') ??
                                              (((row['actual'] ?? 0) as int) -
                                                  ((row['expected'] ?? 0)
                                                      as int));
                                    return diff < 0; // show only deductions
                                  })
                                  .map((row) {
                                    Color statusColor = Colors.red;
                                    return DataRow(
                                      cells: [
                                        DataCell(
                                          SizedBox(
                                            width: 76,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Padding(
                                                padding: EdgeInsets.only(
                                                  left: 18,
                                                ),
                                                child: Text(
                                                  row['type'].toString(),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Colors.black87,
                                                    fontWeight:
                                                        FontWeight.normal,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          SizedBox(
                                            width: 36,
                                            child: Align(
                                              alignment: Alignment.center,
                                              child: Text(
                                                row['shift']
                                                    .toString()
                                                    .replaceAll('Shift ', 'S'),
                                                textAlign: TextAlign.center,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.black,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          SizedBox(
                                            width: 54,
                                            child: Align(
                                              alignment: Alignment.center,
                                              child: Text(
                                                '${row['expected']}',
                                                textAlign: TextAlign.center,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.black,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          SizedBox(
                                            width: 54,
                                            child: Align(
                                              alignment: Alignment.center,
                                              child: Transform.translate(
                                                offset: Offset(-6, 0),
                                                child: Text(
                                                  '${row['actual']}',
                                                  textAlign: TextAlign.center,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: statusColor,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        DataCell(
                                          SizedBox(
                                            width: 40,
                                            child: Align(
                                              alignment: Alignment.center,
                                              child: Transform.translate(
                                                offset: Offset(-6, 0),
                                                child: Container(
                                                  padding: EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 3,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: statusColor
                                                        .withOpacity(0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    border: Border.all(
                                                      color: statusColor
                                                          .withOpacity(0.3),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    '${row['difference']}',
                                                    textAlign: TextAlign.center,
                                                    style: TextStyle(
                                                      color: statusColor,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  })
                                  .toList(),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openShiftDetails(Map<String, dynamic> shift) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final List<Color> g = List<Color>.from(
          (shift['gradient'] ?? const [Colors.teal, Colors.greenAccent])
              as List,
        );
        int produced = 0;
        try {
          final m = RegExp(
            r'(\d+)',
          ).firstMatch((shift['count'] ?? '').toString());
          if (m != null) produced = int.parse(m.group(1)!);
        } catch (_) {}
        final int expected = (shift['expected'] is num)
            ? (shift['expected'] as num).toInt()
            : int.tryParse('${shift['expected'] ?? ''}') ?? (produced + 10);
        final int actual = (shift['actual'] is num)
            ? (shift['actual'] as num).toInt()
            : int.tryParse('${shift['actual'] ?? ''}') ?? produced;
        final int discrepancy = actual - expected;
        final List<String> staff =
            (shift['presentStaff'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        return SafeArea(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: g,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.white.withOpacity(0.18),
                            child: Padding(
                              padding: const EdgeInsets.all(2.0),
                              child: Image.asset(
                                'assets/shift.png',
                                width: 26,
                                height: 26,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              (shift['shiftName'] ?? 'Shift').toString(),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              (shift['time'] ?? '').toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _MetricPill(
                            icon: Icons.assignment_turned_in,
                            label: 'Produced',
                            value: '$produced blocks',
                          ),
                          _MetricPill(
                            icon: Icons.new_releases,
                            label: 'Expected',
                            value: '$expected',
                          ),
                          _MetricPill(
                            icon: Icons.verified,
                            label: 'Actual',
                            value: '$actual',
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text(
                            'Present Staff',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FutureBuilder<List<String>>(
                        future: _getPresentStaff(shift),
                        builder: (ctx, snap) {
                          if (snap.connectionState != ConnectionState.done) {
                            return const SizedBox(
                              height: 28,
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          }
                          final names = snap.data ?? const <String>[];
                          if (names.isEmpty) {
                            return const Text(
                              'No staff present.',
                              style: TextStyle(color: Colors.white70),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  for (final name in names)
                                    _StaffChip(
                                      initials: name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : '?',
                                      name: name,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () async {
                                    final current = await _getPresentStaff(
                                      shift,
                                    );
                                    await _showEditStaffDialog(
                                      ctx,
                                      shift,
                                      current,
                                    );
                                    if (mounted) setState(() {});
                                  },
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    'Edit',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Discrepancy: $discrepancy blocks',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {},
                              icon: const Icon(
                                Icons.report_outlined,
                                color: Colors.white,
                              ),
                              label: const Text(
                                'Report',
                                style: TextStyle(color: Colors.white),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.center,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black87,
                            shape: const StadiumBorder(),
                            elevation: 0,
                          ),
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 22.0,
                              vertical: 10,
                            ),
                            child: Text('Close'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildShiftDetailContent(Map<String, dynamic> shift) {
    final discrepancy = (shift['actual'] ?? 0) - (shift['expected'] ?? 0);
    final gradient = shift['gradient'] is List<Color>
        ? shift['gradient']
        : [Colors.grey[200]!, Colors.white];
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
      padding: EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.white.withOpacity(0.18),
                child: Padding(
                  padding: const EdgeInsets.all(2.0),
                  child: Image.asset(
                    'assets/shift.png',
                    width: 30,
                    height: 30,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              SizedBox(width: 14),
              Flexible(
                child: Text(
                  shift['shiftName'] ?? '',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 5, color: Colors.black12)],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white.withOpacity(0.1),
                ),
                child: Text(
                  shift['time'] ?? '',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 26),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.13),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceEvenly,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 21,
              runSpacing: 13,
              children: [
                _detailInfo(
                  Icons.assignment_turned_in,
                  "Produced",
                  shift['count'] ?? '',
                  Colors.white,
                ),
                _detailInfo(
                  Icons.new_releases,
                  "Expected",
                  '${shift['expected'] ?? '-'}',
                  Colors.white,
                ),
                _detailInfo(
                  Icons.verified,
                  "Actual",
                  '${shift['actual'] ?? '-'}',
                  Colors.white,
                ),
              ],
            ),
          ),
          SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Present Staff",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ),
          SizedBox(height: 8),
          StaffCards(staff: List<String>.from(shift['presentStaff'] ?? [])),
          SizedBox(height: 14),
          if (discrepancy != 0) ...[
            Container(
              padding: EdgeInsets.symmetric(vertical: 13, horizontal: 12),
              margin: EdgeInsets.only(bottom: 10, top: 2),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.83),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.white, size: 22),
                  SizedBox(width: 12),
                  Text(
                    "Discrepancy: $discrepancy blocks",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Spacer(),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.redAccent,
                      elevation: 0,
                      padding: EdgeInsets.symmetric(
                        vertical: 0,
                        horizontal: 12,
                      ),
                    ),
                    icon: Icon(Icons.report),
                    label: Text("Report"),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: gradient[0],
                  shape: StadiumBorder(),
                  elevation: 2,
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  child: Text(
                    "Close",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailInfo(IconData icon, String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 24),
        SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 1),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _MetricPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetricPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.22),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffChip extends StatelessWidget {
  final String initials;
  final String name;

  const _StaffChip({required this.initials, required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFF0F8AA3),
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            name,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class StaffCards extends StatelessWidget {
  final List<String> staff;
  const StaffCards({super.key, required this.staff});

  @override
  Widget build(BuildContext context) {
    if (staff.isEmpty) {
      return Text("No staff present.", style: TextStyle(color: Colors.white70));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: staff.map((name) {
        return Container(
          margin: EdgeInsets.symmetric(vertical: 4),
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.92),
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                blurRadius: 8,
                color: Colors.black12,
                offset: Offset(1, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                child: Text(name[0]),
              ),
              SizedBox(width: 12),
              Text(
                name,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _StackedSolidShiftCards extends StatefulWidget {
  final void Function(Map<String, dynamic>) onShiftTap;
  const _StackedSolidShiftCards({super.key, required this.onShiftTap});

  @override
  State<_StackedSolidShiftCards> createState() =>
      _StackedSolidShiftCardsState();
}

class _StackedSolidShiftCardsState extends State<_StackedSolidShiftCards>
    with SingleTickerProviderStateMixin {
  final List<Map<String, dynamic>> _shifts = ProductionData.shifts;
  int _topIndex = 0;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return false;
      setState(() => _isAnimating = true);
      await Future.delayed(const Duration(milliseconds: 700));
      setState(() {
        _topIndex = (_topIndex + 1) % _shifts.length;
        _isAnimating = false;
      });
      return mounted;
    });
  }

  @override
  Widget build(BuildContext context) {
    double verticalOffset = 16.0;
    List<int> indices = [_topIndex, (_topIndex + 1) % 3, (_topIndex + 2) % 3];
    List<Widget> stack = [];
    for (int i = 2; i >= 0; i--) {
      double start = verticalOffset * i;
      double animOffset = 0.0;
      if (_isAnimating) {
        if (i == 0) animOffset = 2 * verticalOffset;
        if (i == 1) animOffset = -verticalOffset;
        if (i == 2) animOffset = -2 * verticalOffset;
      }
      stack.add(
        AnimatedPositioned(
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOut,
          left: 0,
          right: 0,
          top: start + animOffset,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              splashColor: Colors.white24,
              highlightColor: Colors.white10,
              onTap: () => widget.onShiftTap(_shifts[indices[i]]),
              child: _ShiftCard(
                shiftName: _shifts[indices[i]]["shiftName"],
                time: _shifts[indices[i]]["time"],
                count: _shifts[indices[i]]["count"],
                color: _shifts[indices[i]]["color"],
                gradientColors: List<Color>.from(
                  _shifts[indices[i]]["gradient"],
                ),
                iconPath: 'assets/shift.png',
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 190,
      child: Stack(alignment: Alignment.topCenter, children: stack),
    );
  }
}

class _ShiftCard extends StatelessWidget {
  final String shiftName;
  final String time;
  final String count;
  final Color color;
  final String iconPath;
  final List<Color> gradientColors;

  const _ShiftCard({
    required this.shiftName,
    required this.time,
    required this.count,
    required this.color,
    required this.gradientColors,
    required this.iconPath,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white.withOpacity(0.18),
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Image.asset(
                      iconPath,
                      width: 26,
                      height: 26,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    shiftName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              time,
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
            const SizedBox(height: 6),
            Text(
              count,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 16,
                shadows: [
                  Shadow(
                    blurRadius: 6,
                    color: color.withOpacity(0.5),
                    offset: const Offset(1, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
