import 'package:flutter/material.dart';
import 'dart:math';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  bool _isMonitoringExpanded = false;
  final Random _random = Random();
  List<double> _salesData = [];
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

  @override
  void initState() {
    super.initState();
    _initializeChartData();
    _startDataUpdates();
  }

  void _initializeChartData() {
    _salesData = List.generate(
      20,
      (index) =>
          _dailySalesGoal * 0.4 + _random.nextDouble() * _dailySalesGoal * 0.4,
    );
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

          double newRevenue = _currentSales * 40;
          newRevenue += _random.nextDouble() * 2000 - 1000;
          newRevenue = newRevenue.clamp(0.0, _dailyRevenueGoal * 1.2);
          _revenueData.removeAt(0);
          _revenueData.add(newRevenue);
          _currentRevenue = newRevenue;

          double newDiscrepancy = newProduction - newSales;
          _discrepancyData.removeAt(0);
          _discrepancyData.add(newDiscrepancy);
          _currentDiscrepancy = newDiscrepancy;

          _systemHealth = 90.0 + _random.nextDouble() * 8;
          _temperature = -7.0 + _random.nextDouble() * 4;
          _humidity = 40.0 + _random.nextDouble() * 10;
          _energyUsage = 75.0 + _random.nextDouble() * 10;
        });
        _startDataUpdates();
      }
    });
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
                            value: "${_currentSales.toInt()} blocks",
                            progress: _salesProgress,
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
                              value:
                                  "${(_currentProduction - _currentSales).toInt()} blocks",
                              progress: _discrepancySeverity,
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
                            value:
                                "${(_currentProduction - _currentSales).toInt()} blocks",
                            progress: _discrepancySeverity,
                            isPositive: _currentDiscrepancy >= 0,
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 40),
                _buildAchievementsSection(),
              ],
            ),
          ),
        ),
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
        secondaryData = _salesData;
        valueSuffix = " blocks";
        primaryColor = Colors.blue;
        secondaryColor = Colors.green;
        isCurrency = false;
        break;
      case 1:
        title = "REVENUE STREAM";
        currentValue = _currentRevenue;
        previousValue = _revenueData.length > 1
            ? _revenueData[_revenueData.length - 2]
            : _currentRevenue;
        data = _revenueData;
        valueSuffix = " ₱";
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
                        color: progress >= 1.0
                            ? Colors.greenAccent
                            : progress >= 0.7
                            ? Colors.lightGreenAccent
                            : Colors.green[100],
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

    if (discrepancy.abs() < _optimalDiscrepancyMax) {
      status = "Optimal";
      statusColor = Colors.greenAccent;
    } else if (discrepancy > 0) {
      status = "Overproduction";
      statusColor = Colors.orangeAccent;
    } else {
      status = "Underproduction";
      statusColor = Colors.redAccent;
    }

    return SizedBox(
      height: 180,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isPositive
                  ? [const Color(0xFFFF5722), const Color(0xFFFF8A65)]
                  : [const Color(0xFF4CAF50), const Color(0xFF66BB6A)],
            ),
            boxShadow: [
              BoxShadow(
                color: (isPositive ? Colors.orange : Colors.green).withOpacity(
                  0.3,
                ),
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
                  color:
                      (isPositive
                              ? const Color(0xFFFF5722)
                              : const Color(0xFF4CAF50))
                          .withOpacity(0.4),
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
                          color: Colors.white,
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
                  color: statusColor,
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
                          color: _systemHealth > 80
                              ? Colors.greenAccent
                              : _systemHealth > 60
                              ? Colors.orangeAccent
                              : Colors.redAccent,
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
  final List<double>? secondaryData;
  final Color primaryColor;
  final Color? secondaryColor;

  _MultiChartPainter({
    required this.primaryData,
    this.secondaryData,
    required this.primaryColor,
    this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (primaryData.isEmpty) return;

    double minValue = primaryData.reduce((a, b) => a < b ? a : b);
    double maxValue = primaryData.reduce((a, b) => a > b ? a : b);

    if (secondaryData != null && secondaryData!.isNotEmpty) {
      double secondaryMin = secondaryData!.reduce((a, b) => a < b ? a : b);
      double secondaryMax = secondaryData!.reduce((a, b) => a > b ? a : b);
      minValue = min(minValue, secondaryMin);
      maxValue = max(maxValue, secondaryMax);
    }

    minValue = minValue * 0.9;
    maxValue = maxValue * 1.1;

    final double range = maxValue - minValue;
    final double scaleY = range > 0 ? size.height / range : 1;

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
      final double y = size.height - ((primaryData[i] - minValue) * scaleY);

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
        final double y =
            size.height - ((secondaryData![i] - minValue) * scaleY);

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
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
