import 'package:flutter/material.dart';
import 'dart:math';

import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/sales_repository.dart';
import '../services/discrepancy_repository.dart';
import '../services/camera_repository.dart';
import '../services/performance_repository.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  bool _isMonitoringExpanded = false;
  final Random _random = Random();
  List<double> _salesData = [];
  List<double> _salesBlocksData = [];
  List<double> _salesCubesData = [];
  List<double> _productionData = [];
  List<double> _revenueData = [];
  List<double> _discrepancyData = [];
  double _currentSales = 480.0;
  double _currentProduction = 520.0;
  double _currentRevenue = 19200.0;
  double _currentDiscrepancy = 40.0;
  int _selectedChart = 0;

  final double _dailyProductionGoal = 1000.0;
  final double _dailySalesGoal = 900.0;
  final double _dailyRevenueGoal = 30000.0;
  final double _optimalDiscrepancyMax = 50.0;

  double _systemHealth = 92.0;
  double _temperature = -5.0;
  double _humidity = 45.0;
  double _energyUsage = 78.0;

  late final SalesRepository _salesRepo;
  StreamSubscription<List<Map<String, dynamic>>>? _salesStreamSub;
  Timer? _salesPollTimer;
  bool _isSalesFetch = false;
  int _salesTodayBlocks = 0;
  int _salesTodayCubes = 0;
  // For spike computation based on sale amounts
  bool _salesSpikesInitialized = false;
  double _prevBlocksAmount = 0.0;
  double _prevCubesAmount = 0.0;
  int _prevBlocksQty = 0;
  int _prevCubesQty = 0;
  // Decay state for fading spikes
  double _decayedBlocks = 0.0;
  double _decayedCubes = 0.0;
  DateTime? _lastSalesUpdateAt;
  final double _spikeHalfLifeSec = 5.0; // user preference

  // Live discrepancies total (Ice Block only)
  late final DiscrepancyRepository _discRepo;
  StreamSubscription<List<Map<String, dynamic>>>? _discStreamSub;
  Timer? _discPollTimer;
  bool _isDiscFetch = false;
  int _discTotalBlocks = 0;

  // Camera battery monitor
  late final CameraRepository _camRepo;
  Timer? _camPollTimer;

  // Performance metrics publisher
  PerformanceRepository? _perfRepo;
  Timer? _perfTimer;

  @override
  void initState() {
    super.initState();
    _initializeChartData();
    _startDataUpdates();
    _setupSalesToday();
    _setupDiscrepanciesTotal();
    _setupBatteryMonitor();
  }

  void _initializeChartData() {
    _salesData = List.generate(
      20,
      (index) =>
          _dailySalesGoal * 0.4 + _random.nextDouble() * _dailySalesGoal * 0.4,
    );
    _salesBlocksData = List<double>.filled(20, 0.0);
    _salesCubesData = List<double>.filled(20, 0.0);
    _productionData = List.generate(
      20,
      (index) =>
          _dailyProductionGoal * 0.4 +
          _random.nextDouble() * _dailyProductionGoal * 0.4,
    );
    _revenueData = List.generate(
      20,
      (index) =>
          _dailyRevenueGoal * 0.4 +
          _random.nextDouble() * _dailyRevenueGoal * 0.4,
    );
    _discrepancyData = List.generate(
      20,
      (index) => _productionData[index] - _salesData[index],
    );
    _currentSales = _salesData.last;
    _currentProduction = _productionData.last;
    _currentRevenue = _revenueData.last;
    _currentDiscrepancy = _discrepancyData.last;
  }

  void _startDataUpdates() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          final double salesProgress = _currentSales / _dailySalesGoal;
          double salesChange = (_random.nextDouble() * 40 - 20);
          if (salesProgress < 0.8) salesChange += 5;
          double newSales = _currentSales + salesChange;
          newSales = newSales.clamp(0.0, _dailySalesGoal * 1.1);
          _salesData.removeAt(0);
          _salesData.add(newSales);
          _currentSales = newSales;

          double productionChange = (_random.nextDouble() * 30 - 10);
          if (_currentDiscrepancy > _optimalDiscrepancyMax * 1.5) {
            productionChange -= 5;
          } else if (_currentDiscrepancy < 0) {
            productionChange += 5;
          }
          double newProduction = _currentProduction + productionChange;
          newProduction = newProduction.clamp(0.0, _dailyProductionGoal * 1.2);
          _productionData.removeAt(0);
          _productionData.add(newProduction);
          _currentProduction = newProduction;

          // Revenue now computed from actual sales; no random updates here

          // Discrepancy series is driven by Aerospike data in _applyDiscrepanciesTotal

          if (_camPollTimer == null) {
            _systemHealth = 90.0 + _random.nextDouble() * 8;
          }
          _temperature = -7.0 + _random.nextDouble() * 4;
          _humidity = 40.0 + _random.nextDouble() * 10;
          _energyUsage = 75.0 + _random.nextDouble() * 10;
        });
        _startDataUpdates();
      }
    });
  }

  void _applySalesToday(List<Map<String, dynamic>> list) {
    int totalBlocks = 0;
    int totalCubes = 0;
    double totalBlocksAmount = 0.0;
    double totalCubesAmount = 0.0;
    double lastBlockUnitPrice = 0.0;
    double lastCubeUnitPrice = 0.0;
    for (final r in list) {
      final type = (r['type'] ?? '').toString().toLowerCase();
      final q = r['qty'];
      final qty = q is num ? q.toInt() : int.tryParse(q?.toString() ?? '') ?? 0;
      final amtRaw = r['amount'];
      final amount = amtRaw is num
          ? amtRaw.toDouble()
          : double.tryParse(amtRaw?.toString() ?? '') ?? 0.0;
      final upRaw = r['unitPrice'];
      final unitPrice = upRaw is num
          ? upRaw.toDouble()
          : double.tryParse(upRaw?.toString() ?? '') ?? 0.0;
      final amountComputed = amount > 0.0
          ? amount
          : (unitPrice > 0.0 ? unitPrice * qty : 0.0);
      if (type.contains('block')) totalBlocks += qty;
      if (type.contains('cube')) totalCubes += qty;
      if (type.contains('block')) {
        totalBlocksAmount += amountComputed;
        if (unitPrice > 0) lastBlockUnitPrice = unitPrice;
      }
      if (type.contains('cube')) {
        totalCubesAmount += amountComputed;
        if (unitPrice > 0) lastCubeUnitPrice = unitPrice;
      }
    }
    if (!mounted) return;
    final now = DateTime.now();
    setState(() {
      _salesTodayBlocks = totalBlocks;
      _salesTodayCubes = totalCubes;
      // Compute per-update spike height from amount deltas (proportional to amount)
      if (!_salesSpikesInitialized) {
        // Avoid a giant spike on first load; set baselines and push zeros
        _prevBlocksAmount = totalBlocksAmount;
        _prevCubesAmount = totalCubesAmount;
        _prevBlocksQty = totalBlocks;
        _prevCubesQty = totalCubes;
        _decayedBlocks = 0.0;
        _decayedCubes = 0.0;
        _lastSalesUpdateAt = now;
        _salesSpikesInitialized = true;
        if (_salesBlocksData.isNotEmpty) _salesBlocksData.removeAt(0);
        _salesBlocksData.add(0.0);
        if (_salesCubesData.isNotEmpty) _salesCubesData.removeAt(0);
        _salesCubesData.add(0.0);
      } else {
        final dBlkAmt = (totalBlocksAmount - _prevBlocksAmount).clamp(
          0.0,
          double.infinity,
        );
        final dCubAmt = (totalCubesAmount - _prevCubesAmount).clamp(
          0.0,
          double.infinity,
        );
        final dBlkQty = totalBlocks - _prevBlocksQty;
        final dCubQty = totalCubes - _prevCubesQty;
        _prevBlocksAmount = totalBlocksAmount;
        _prevCubesAmount = totalCubesAmount;
        _prevBlocksQty = totalBlocks;
        _prevCubesQty = totalCubes;

        // Convert amount to approximate unit count using last seen unitPrice (fallback to 40)
        final blkPrice = lastBlockUnitPrice > 0 ? lastBlockUnitPrice : 40.0;
        final cubPrice = lastCubeUnitPrice > 0 ? lastCubeUnitPrice : 40.0;
        final blkSpike = dBlkAmt > 0
            ? (dBlkAmt / blkPrice)
            : (dBlkQty > 0 ? dBlkQty.toDouble() : 0.0);
        final cubSpike = dCubAmt > 0
            ? (dCubAmt / cubPrice)
            : (dCubQty > 0 ? dCubQty.toDouble() : 0.0);

        // Exponential decay with half-life
        double dtSec = 0.0;
        if (_lastSalesUpdateAt != null) {
          dtSec = now.difference(_lastSalesUpdateAt!).inMilliseconds / 1000.0;
        }
        final double decayFactor = dtSec > 0
            ? (pow(0.5, dtSec / _spikeHalfLifeSec)).toDouble()
            : 1.0;
        final double nextBlocks = (blkSpike > _decayedBlocks * decayFactor)
            ? blkSpike
            : (_decayedBlocks * decayFactor);
        final double nextCubes = (cubSpike > _decayedCubes * decayFactor)
            ? cubSpike
            : (_decayedCubes * decayFactor);
        _decayedBlocks = nextBlocks;
        _decayedCubes = nextCubes;
        _lastSalesUpdateAt = now;

        if (_salesBlocksData.isNotEmpty) _salesBlocksData.removeAt(0);
        _salesBlocksData.add(_decayedBlocks);
        if (_salesCubesData.isNotEmpty) _salesCubesData.removeAt(0);
        _salesCubesData.add(_decayedCubes);
      }
      // Update revenue series from actual sales amounts (blocks + cubes)
      final totalRevenue = (totalBlocksAmount + totalCubesAmount).clamp(
        0.0,
        _dailyRevenueGoal * 10,
      );
      _currentRevenue = totalRevenue;
      if (_revenueData.isNotEmpty) _revenueData.removeAt(0);
      _revenueData.add(totalRevenue);
    });
  }

  Future<void> _fetchSalesToday() async {
    if (_isSalesFetch) return;
    _isSalesFetch = true;
    try {
      final list = await _salesRepo.fetchAllSales();
      _applySalesToday(list);
    } catch (_) {
    } finally {
      _isSalesFetch = false;
    }
  }

  Future<void> _setupSalesToday() async {
    String? token;
    try {
      token = await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}
    _salesRepo = SalesRepository(
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      },
    );
    try {
      await _salesRepo.ensureTableMetadata();
    } catch (_) {}
    await _fetchSalesToday();
    try {
      await _salesStreamSub?.cancel();
      // Use stream as a trigger and always recompute from full dataset
      _salesStreamSub = _salesRepo.streamSalesHistory().listen((_) {
        _fetchSalesToday();
      });
    } catch (_) {}
    _salesPollTimer?.cancel();
    _salesPollTimer = Timer.periodic(
      const Duration(milliseconds: 150),
      (_) => _fetchSalesToday(),
    );
    // Initialize performance metrics publisher after sales repo setup
    await _setupPerformancePublisher();
  }

  Future<void> _setupPerformancePublisher() async {
    try {
      String? token;
      try {
        token = await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {}
      _perfRepo = PerformanceRepository(
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
      );
      await _perfRepo!.ensureTableMetadata();
    } catch (_) {}
    _perfTimer?.cancel();
    _perfTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_perfRepo == null) return;
      try {
        await _perfRepo!.upsertMetric(
          metricKey: 'main-sales_today_blocks',
          metric: 'sales_today_blocks',
          value: _salesTodayBlocks,
        );
      } catch (_) {}
      try {
        await _perfRepo!.upsertMetric(
          metricKey: 'main-sales_today_cubes',
          metric: 'sales_today_cubes',
          value: _salesTodayCubes,
        );
      } catch (_) {}
    });
  }

  Future<void> _setupBatteryMonitor() async {
    String? token;
    try {
      token = await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}
    _camRepo = CameraRepository(
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      },
    );
    _camPollTimer?.cancel();
    _camPollTimer = Timer.periodic(const Duration(milliseconds: 500), (
      _,
    ) async {
      try {
        final b = await _camRepo.fetchLatestBatteryPercent();
        if (b != null && mounted) {
          setState(() {
            _systemHealth = b.clamp(0, 100).toDouble();
          });
        }
      } catch (_) {}
    });
  }

  void _applyDiscrepanciesTotal(List<Map<String, dynamic>> list) {
    int total = 0;
    final nowUtc = DateTime.now().toUtc();
    for (final r in list) {
      final tsRaw = r['timestamp']?.toString();
      DateTime? ts;
      if (tsRaw != null) {
        try {
          ts = DateTime.tryParse(tsRaw)?.toUtc();
        } catch (_) {}
      }
      final bool isTodayUtc =
          ts == null ||
          (ts.year == nowUtc.year &&
              ts.month == nowUtc.month &&
              ts.day == nowUtc.day);
      if (!isTodayUtc) continue;
      final d = r['difference'];
      final diff = d is num
          ? d.toInt()
          : int.tryParse(d?.toString() ?? '') ?? 0;
      if (diff < 0) total += -diff; // sum under-production across all types
    }
    if (!mounted) return;
    setState(() {
      _discTotalBlocks =
          total; // reuse field to display total discrepancy count
      _currentDiscrepancy = total.toDouble();
      if (_discrepancyData.isNotEmpty) _discrepancyData.removeAt(0);
      _discrepancyData.add(total.toDouble());
    });
  }

  Future<void> _fetchDiscrepanciesTotal() async {
    if (_isDiscFetch) return;
    _isDiscFetch = true;
    try {
      final list = await _discRepo.fetchAllDiscrepancies();
      _applyDiscrepanciesTotal(list);
    } catch (_) {
    } finally {
      _isDiscFetch = false;
    }
  }

  Future<void> _setupDiscrepanciesTotal() async {
    String? token;
    try {
      token = await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}
    _discRepo = DiscrepancyRepository(
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      },
    );
    try {
      await _discRepo.ensureTableMetadata();
    } catch (_) {}
    await _fetchDiscrepanciesTotal();
    try {
      await _discStreamSub?.cancel();
      _discStreamSub = _discRepo.streamDiscrepancies().listen(
        (list) => _applyDiscrepanciesTotal(list),
      );
    } catch (_) {}
    _discPollTimer?.cancel();
    _discPollTimer = Timer.periodic(
      const Duration(milliseconds: 150),
      (_) => _fetchDiscrepanciesTotal(),
    );
  }

  @override
  void dispose() {
    _salesStreamSub?.cancel();
    _salesPollTimer?.cancel();
    _discStreamSub?.cancel();
    _discPollTimer?.cancel();
    _camPollTimer?.cancel();
    _perfTimer?.cancel();
    super.dispose();
  }

  double get _productionProgress => _currentProduction / _dailyProductionGoal;
  double get _salesProgress => _currentSales / _dailySalesGoal;
  double get _revenueProgress => _currentRevenue / _dailyRevenueGoal;
  double get _discrepancySeverity {
    if (_currentDiscrepancy.abs() < _optimalDiscrepancyMax) return 0.0;
    return (_currentDiscrepancy.abs() - _optimalDiscrepancyMax) /
        (_dailyProductionGoal * 0.2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        color: Colors.white,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(
            context,
          ).copyWith(overscroll: false, physics: const ClampingScrollPhysics()),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(22.0, 22.0, 22.0, 100.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dashboard',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F8AA3),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Live Performance Metrics',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildChartSelectorButton(
                          title: "Production/Sales",
                          isSelected: _selectedChart == 0,
                          onTap: () => setState(() => _selectedChart = 0),
                        ),
                      ),
                      Expanded(
                        child: _buildChartSelectorButton(
                          title: "Revenue",
                          isSelected: _selectedChart == 1,
                          onTap: () => setState(() => _selectedChart = 1),
                        ),
                      ),
                      Expanded(
                        child: _buildChartSelectorButton(
                          title: "Discrepancy",
                          isSelected: _selectedChart == 2,
                          onTap: () => setState(() => _selectedChart = 2),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildMainChart(),
                const SizedBox(height: 24),
                Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildProductionCard(
                            title: "Production Today",
                            value: "${_currentProduction.toInt()} blocks",
                            progress: _productionProgress,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildSalesCard(
                            title: "Sales Today",
                            value: "${_salesTodayBlocks} blocks",
                            progress: (_salesTodayBlocks / _dailySalesGoal),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!_isMonitoringExpanded)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildMonitoringContainer(context)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildDiscrepancyCard(
                              title: "Discrepancy",
                              value: "${_discTotalBlocks} blocks",
                              progress:
                                  (_discTotalBlocks / _optimalDiscrepancyMax)
                                      .clamp(0.0, 1.0),
                              isPositive: _currentDiscrepancy >= 0,
                            ),
                          ),
                        ],
                      ),
                    if (_isMonitoringExpanded)
                      Column(
                        children: [
                          _buildMonitoringContainer(context),
                          const SizedBox(height: 12),
                          _buildDiscrepancyCard(
                            title: "Discrepancy",
                            value: "${_discTotalBlocks} blocks",
                            progress:
                                (_discTotalBlocks / _optimalDiscrepancyMax)
                                    .clamp(0.0, 1.0),
                            isPositive: _currentDiscrepancy >= 0,
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _legendSwatch({required Color? color}) {
    final c = color ?? Colors.grey;
    return Container(
      width: 14,
      height: 3,
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildChartSelectorButton({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0F8AA3) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildAchievementsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Production Achievements',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _AchievementBadge(
              icon: Icons.emoji_events,
              color: Colors.amber,
              title: "Record Breaker!",
              subtitle: "Highest production achieved today!",
            ),
            _AchievementBadge(
              icon: Icons.star,
              color: Colors.blueAccent,
              title: "Zero Discrepancy",
              subtitle: "All shifts balanced with zero losses.",
            ),
            _AchievementBadge(
              icon: Icons.bolt,
              color: Colors.green,
              title: "Energy Saver",
              subtitle: "Lowest power used across shifts.",
            ),
          ],
        ),
        const SizedBox(height: 24),
        _MotivationalHighlight(
          message:
              "Every block counts. Keep pushing for efficiency and teamwork!",
          author: "OIP Sentinel",
        ),
      ],
    );
  }

  // All previous chart, card, monitoring, discrepancy, painter and achievement widgets below...
  Widget _buildMainChart() {
    String title;
    double currentValue;
    double previousValue;
    List<double> data;
    List<double>? secondaryData;
    String valueSuffix;
    Color primaryColor;
    Color? secondaryColor;
    bool isCurrency;

    switch (_selectedChart) {
      case 0:
        title = "PRODUCTION & SALES";
        currentValue = _currentProduction;
        previousValue = _productionData.length > 1
            ? _productionData[_productionData.length - 2]
            : _currentProduction;
        data = _productionData;
        secondaryData = _salesBlocksData; // green line 1: blocks
        final List<double> tertiaryData =
            _salesCubesData; // green line 2: cubes
        valueSuffix = " blocks";
        primaryColor = Colors.blue;
        secondaryColor = Colors.green[600];
        isCurrency = false;
        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.grey[300]!, width: 1),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.white,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      '${isCurrency ? '₱' : ''}${currentValue.toStringAsFixed(isCurrency ? 0 : 1)}$valueSuffix',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.arrow_upward, size: 14, color: primaryColor),
                    const SizedBox(width: 4),
                    Text(
                      '—',
                      style: TextStyle(
                        fontSize: 12,
                        color: primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _legendSwatch(color: primaryColor),
                    const SizedBox(width: 6),
                    const Text(
                      'Production',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(width: 12),
                    _legendSwatch(color: secondaryColor),
                    const SizedBox(width: 6),
                    const Text(
                      'Blocks',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(width: 12),
                    _legendSwatch(color: Colors.greenAccent),
                    const SizedBox(width: 6),
                    const Text(
                      'Cubes',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 180,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[200]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: CustomPaint(
                    painter: _MultiChartPainter(
                      primaryData: data,
                      secondaryData: secondaryData,
                      tertiaryData: tertiaryData,
                      primaryColor: primaryColor,
                      secondaryColor: secondaryColor,
                      tertiaryColor: Colors.green[300],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        break;
      case 1:
        title = "REVENUE STREAM";
        currentValue = _currentRevenue;
        previousValue = _revenueData.length > 1
            ? _revenueData[_revenueData.length - 2]
            : _currentRevenue;
        data = _revenueData;
        valueSuffix = "";
        primaryColor = Colors.teal;
        isCurrency = true;
        break;
      case 2:
        title = "DISCREPANCY";
        currentValue = _currentDiscrepancy;
        previousValue = _discrepancyData.length > 1
            ? _discrepancyData[_discrepancyData.length - 2]
            : _currentDiscrepancy;
        data = _discrepancyData;
        valueSuffix = " blocks";
        primaryColor = _currentDiscrepancy >= 0 ? Colors.red : Colors.green;
        isCurrency = false;
        break;
      default:
        title = "PRODUCTION & SALES";
        currentValue = _currentProduction;
        previousValue = _productionData.length > 1
            ? _productionData[_productionData.length - 2]
            : _currentProduction;
        data = _productionData;
        secondaryData = _salesData;
        valueSuffix = " blocks";
        primaryColor = Colors.blue;
        secondaryColor = Colors.green;
        isCurrency = false;
    }

    final bool isPositive = currentValue >= previousValue;
    final double change = currentValue - previousValue;
    final double changePercent = previousValue != 0
        ? (change / previousValue) * 100
        : 0;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[300]!, width: 1),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  '${isCurrency ? '₱' : ''}${currentValue.toStringAsFixed(isCurrency ? 0 : 1)}$valueSuffix',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: primaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 14,
                  color: isPositive ? primaryColor : primaryColor,
                ),
                const SizedBox(width: 4),
                Text(
                  '${change.toStringAsFixed(isCurrency ? 0 : 1)} (${changePercent.toStringAsFixed(1)}%)',
                  style: TextStyle(
                    fontSize: 12,
                    color: isPositive ? primaryColor : primaryColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_selectedChart == 1) ...[
              Row(
                children: [
                  _legendSwatch(color: Colors.green),
                  const SizedBox(width: 6),
                  const Text(
                    'Blocks',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(width: 12),
                  _legendSwatch(color: Colors.greenAccent),
                  const SizedBox(width: 6),
                  const Text(
                    'Cubes',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[200]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: CustomPaint(
                painter: _MultiChartPainter(
                  primaryData: data,
                  secondaryData: secondaryData,
                  primaryColor: primaryColor,
                  secondaryColor: secondaryColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductionCard({
    required String title,
    required String value,
    required double progress,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
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
              decoration: BoxDecoration(
                color: const Color(0xFF0F8AA3).withOpacity(0.4),
                shape: BoxShape.circle,
              ),
              child: Transform.scale(
                scale: 3.5,
                child: Image.asset(
                  'assets/ice_block.png',
                  width: 28,
                  height: 28,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Container(
                      width: constraints.maxWidth * progress.clamp(0.0, 1.0),
                      decoration: BoxDecoration(
                        color: progress >= 1.0
                            ? Colors.greenAccent
                            : progress >= 0.7
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
            Text(
              "${(progress * 100).toStringAsFixed(0)}% of daily goal",
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesCard({
    required String title,
    required String value,
    required double progress,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.green.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withOpacity(0.4),
                shape: BoxShape.circle,
              ),
              child: Transform.scale(
                scale: 2.5,
                child: Image.asset('assets/sales.png', width: 28, height: 28),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Container(
                      width: constraints.maxWidth * progress.clamp(0.0, 1.0),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "${(progress * 100).toStringAsFixed(0)}% of daily goal",
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscrepancyCard({
    required String title,
    required String value,
    required double progress,
    required bool isPositive,
  }) {
    final double discrepancy = _currentProduction - _currentSales;
    final String status;
    final Color statusColor;

    status = "Warning";
    statusColor = Colors.deepOrangeAccent;

    return SizedBox(
      height: 180,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFF5722), Color(0xFFFF8A65)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.deepOrange.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5722).withOpacity(0.4),
                  shape: BoxShape.circle,
                ),
                child: Transform.scale(
                  scale: 2.5,
                  child: Image.asset(
                    'assets/discrepancy.png',
                    width: 28,
                    height: 28,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Container(
                        width: constraints.maxWidth * progress.clamp(0.0, 1.0),
                        decoration: BoxDecoration(
                          color: Color.lerp(
                            Colors.yellowAccent,
                            Colors.redAccent,
                            progress.clamp(0.0, 1.0),
                          )!,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                status,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonitoringContainer(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isMonitoringExpanded = !_isMonitoringExpanded;
        });
      },
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF9C27B0), Color(0xFFBA68C8)],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.purple.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Transform.scale(
                scale: 2.5,
                child: Image.asset('assets/monitor.png', width: 28, height: 48),
              ),
              const SizedBox(height: 12),
              Text(
                "Monitoring",
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "System Status",
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Container(
                        width: constraints.maxWidth * (_systemHealth / 100),
                        decoration: BoxDecoration(
                          color: _systemHealth < 20
                              ? Colors.redAccent
                              : _systemHealth < 50
                              ? Colors.yellowAccent
                              : Colors.greenAccent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "${_systemHealth.toStringAsFixed(0)}% system health",
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),

              if (_isMonitoringExpanded) ...[
                const SizedBox(height: 16),
                Divider(color: Colors.white.withOpacity(0.3), height: 1),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildMonitorItem(
                      icon: Icons.thermostat,
                      title: "Temperature",
                      value: "${_temperature.toStringAsFixed(1)}°C",
                      status: _temperature >= -8 && _temperature <= -2
                          ? "Optimal"
                          : "Warning",
                      statusColor: _temperature >= -8 && _temperature <= -2
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                    ),
                    _buildMonitorItem(
                      icon: Icons.water_drop,
                      title: "Humidity",
                      value: "${_humidity.toStringAsFixed(0)}%",
                      status: _humidity >= 40 && _humidity <= 60
                          ? "Normal"
                          : "Warning",
                      statusColor: _humidity >= 40 && _humidity <= 60
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                    ),
                    _buildMonitorItem(
                      icon: Icons.energy_savings_leaf,
                      title: "Energy Usage",
                      value: "${_energyUsage.toStringAsFixed(0)} kWh",
                      status: _energyUsage <= 85 ? "Normal" : "High",
                      statusColor: _energyUsage <= 85
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  "Machine Status:",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatusIndicator("Ice Maker 1", Colors.greenAccent),
                    _buildStatusIndicator(
                      "Ice Maker 2",
                      _systemHealth > 70
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                    ),
                    _buildStatusIndicator(
                      "Compressor",
                      _energyUsage < 80
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                    ),
                    _buildStatusIndicator(
                      "Cooling",
                      _temperature <= -4
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
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

  Widget _buildMonitorItem({
    required IconData icon,
    required String title,
    required String value,
    required String status,
    required Color statusColor,
  }) {
    return Column(
      children: [
        Icon(icon, size: 32, color: Colors.white),
        const SizedBox(height: 8),
        Text(
          title,
          style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.8)),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          status,
          style: TextStyle(
            fontSize: 12,
            color: statusColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusIndicator(String label, Color color) {
    return Column(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8)),
        ),
      ],
    );
  }
}

class _AchievementBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _AchievementBadge({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withOpacity(0.8), Colors.white.withOpacity(0.2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 36),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: color,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MotivationalHighlight extends StatelessWidget {
  final String message;
  final String author;

  const _MotivationalHighlight({required this.message, required this.author});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.teal.withOpacity(0.10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.format_quote, color: Colors.teal, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 15,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      "- $author",
                      style: const TextStyle(fontSize: 12, color: Colors.teal),
                    ),
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

class _MultiChartPainter extends CustomPainter {
  final List<double> primaryData;
  final List<double>? secondaryData; // first green line (e.g., blocks)
  final List<double>? tertiaryData; // second green line (e.g., cubes)
  final Color primaryColor;
  final Color? secondaryColor;
  final Color? tertiaryColor;

  _MultiChartPainter({
    required this.primaryData,
    this.secondaryData,
    this.tertiaryData,
    required this.primaryColor,
    this.secondaryColor,
    this.tertiaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (primaryData.isEmpty) return;

    double pMin = primaryData.reduce((a, b) => a < b ? a : b);
    double pMax = primaryData.reduce((a, b) => a > b ? a : b);
    pMin = pMin * 0.9;
    pMax = pMax * 1.1;
    final double pRange = pMax - pMin;
    final double pScaleY = pRange > 0 ? size.height / pRange : 1;

    double sMin = pMin;
    double sMax = pMax;
    double sScaleY = pScaleY;
    if (secondaryData != null && secondaryData!.isNotEmpty) {
      sMin = secondaryData!.reduce((a, b) => a < b ? a : b) * 0.9;
      sMax = secondaryData!.reduce((a, b) => a > b ? a : b) * 1.1;
      final r = sMax - sMin;
      sScaleY = r > 0 ? size.height / r : 1;
    }

    double tMin = pMin;
    double tMax = pMax;
    double tScaleY = pScaleY;
    if (tertiaryData != null && tertiaryData!.isNotEmpty) {
      tMin = tertiaryData!.reduce((a, b) => a < b ? a : b) * 0.9;
      tMax = tertiaryData!.reduce((a, b) => a > b ? a : b) * 1.1;
      final r = tMax - tMin;
      tScaleY = r > 0 ? size.height / r : 1;
    }

    final Paint primaryLinePaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Paint primaryFillPaint = Paint()
      ..color = primaryColor.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    Paint? secondaryLinePaint;
    Paint? secondaryFillPaint;
    Paint? tertiaryLinePaint;
    Paint? tertiaryFillPaint;

    if (secondaryData != null && secondaryColor != null) {
      secondaryLinePaint = Paint()
        ..color = secondaryColor!
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      secondaryFillPaint = Paint()
        ..color = secondaryColor!.withOpacity(0.1)
        ..style = PaintingStyle.fill;
    }

    final Path primaryLinePath = Path();
    final Path primaryFillPath = Path();
    final double stepX = size.width / (primaryData.length - 1);

    for (int i = 0; i < primaryData.length; i++) {
      final double x = i * stepX;
      final double y = size.height - ((primaryData[i] - pMin) * pScaleY);

      if (i == 0) {
        primaryLinePath.moveTo(x, y);
        primaryFillPath.moveTo(x, size.height);
        primaryFillPath.lineTo(x, y);
      } else {
        primaryLinePath.lineTo(x, y);
        primaryFillPath.lineTo(x, y);
      }

      if (i == primaryData.length - 1) {
        primaryFillPath.lineTo(x, size.height);
        primaryFillPath.close();
      }
    }

    canvas.drawPath(primaryFillPath, primaryFillPaint);
    canvas.drawPath(primaryLinePath, primaryLinePaint);

    if (secondaryData != null &&
        secondaryData!.isNotEmpty &&
        secondaryLinePaint != null &&
        secondaryFillPaint != null) {
      final Path secondaryLinePath = Path();
      final Path secondaryFillPath = Path();

      for (int i = 0; i < secondaryData!.length; i++) {
        final double x = i * stepX;
        final double y = size.height - ((secondaryData![i] - sMin) * sScaleY);

        if (i == 0) {
          secondaryLinePath.moveTo(x, y);
          secondaryFillPath.moveTo(x, size.height);
          secondaryFillPath.lineTo(x, y);
        } else {
          secondaryLinePath.lineTo(x, y);
          secondaryFillPath.lineTo(x, y);
        }

        if (i == secondaryData!.length - 1) {
          secondaryFillPath.lineTo(x, size.height);
          secondaryFillPath.close();
        }
      }

      canvas.drawPath(secondaryFillPath, secondaryFillPaint);
      canvas.drawPath(secondaryLinePath, secondaryLinePaint);
    }

    // Tertiary line (second green) for cubes
    if (tertiaryData != null &&
        tertiaryData!.isNotEmpty &&
        tertiaryLinePaint != null &&
        tertiaryFillPaint != null) {
      final Path tertiaryLinePath = Path();
      final Path tertiaryFillPath = Path();

      for (int i = 0; i < tertiaryData!.length; i++) {
        final double x = i * stepX;
        final double y = size.height - ((tertiaryData![i] - tMin) * tScaleY);

        if (i == 0) {
          tertiaryLinePath.moveTo(x, y);
          tertiaryFillPath.moveTo(x, size.height);
          tertiaryFillPath.lineTo(x, y);
        } else {
          tertiaryLinePath.lineTo(x, y);
          tertiaryFillPath.lineTo(x, y);
        }

        if (i == tertiaryData!.length - 1) {
          tertiaryFillPath.lineTo(x, size.height);
          tertiaryFillPath.close();
        }
      }

      canvas.drawPath(tertiaryFillPath, tertiaryFillPaint);
      canvas.drawPath(tertiaryLinePath, tertiaryLinePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
