import 'package:flutter/material.dart';

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

  double get productionProgress =>
      ProductionData.currentProduction / ProductionData.dailyProductionGoal;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _progressAnimation =
        Tween<double>(
          begin: 0,
          end: productionProgress.clamp(0.0, 1.0),
        ).animate(
          CurvedAnimation(
            parent: _progressController,
            curve: Curves.easeOutCubic,
          ),
        );
    _progressController.forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
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
            const Text(
              'Production Today',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            AnimatedBuilder(
              animation: _progressAnimation,
              builder: (context, child) {
                final blockCount =
                    (_progressAnimation.value *
                            ProductionData.currentProduction)
                        .clamp(0, ProductionData.currentProduction)
                        .round();
                return Text(
                  '$blockCount blocks',
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
                  "${percent.toStringAsFixed(0)}% of daily goal",
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
    final inventoryData = [
      {'type': 'Ice Block', 'inStock': 140, 'inProduction': 10},
      {'type': 'Ice Cube', 'inStock': 75, 'inProduction': 8},
    ];

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
                Container(
                  alignment: Alignment.center,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: const Text(
                    'Inventory',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F8AA3),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                DataTable(
                  columnSpacing: 30,
                  columns: [
                    DataColumn(
                      label: Container(
                        alignment: Alignment.centerLeft,
                        child: const Text(
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
                      label: Container(
                        alignment: Alignment.center,
                        width: 70,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 14.0),
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
                    DataColumn(
                      label: Container(
                        alignment: Alignment.center,
                        width: 80,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8.0),
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
                  ],
                  rows: inventoryData.map((row) {
                    return DataRow(
                      cells: [
                        DataCell(
                          Container(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              row['type'].toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          Container(
                            alignment: Alignment.center,
                            width: 70,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 14.0),
                              child: Text(
                                '${row['inStock']}',
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.black),
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
                              child: Text(
                                '${row['inProduction']}',
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.black),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
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
                Container(
                  alignment: Alignment.center,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.warning, color: Colors.orange, size: 22),
                      SizedBox(width: 8),
                      const Text(
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
                DataTable(
                  columnSpacing: 15,
                  columns: [
                    DataColumn(
                      label: Container(
                        alignment: Alignment.centerLeft,
                        child: const Text(
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
                      label: Container(
                        alignment: Alignment.center,
                        child: const Text(
                          'Shift',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Container(
                        alignment: Alignment.center,
                        child: const Text(
                          'Expected',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Container(
                        alignment: Alignment.center,
                        child: const Text(
                          'Actual',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Container(
                        alignment: Alignment.center,
                        child: const Text(
                          'Diff',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ],
                  rows: ProductionData.discrepancies.map((row) {
                    Color statusColor = row['difference'] < 0
                        ? Colors.red
                        : Colors.green;
                    return DataRow(
                      cells: [
                        DataCell(
                          Container(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              row['type'].toString(),
                              style: const TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          Container(
                            alignment: Alignment.center,
                            child: Text(
                              row['shift'].toString().replaceAll('Shift ', 'S'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.black),
                            ),
                          ),
                        ),
                        DataCell(
                          Container(
                            alignment: Alignment.center,
                            child: Text(
                              '${row['expected']}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.black),
                            ),
                          ),
                        ),
                        DataCell(
                          Container(
                            alignment: Alignment.center,
                            child: Text(
                              '${row['actual']}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.black),
                            ),
                          ),
                        ),
                        DataCell(
                          Container(
                            alignment: Alignment.center,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: statusColor.withOpacity(0.3),
                                ),
                              ),
                              child: Text(
                                '${row['difference']}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openShiftDetails(Map<String, dynamic> shift) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Shift Details',
      pageBuilder: (_, __, ___) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: AnimatedContainer(
              duration: Duration(milliseconds: 320),
              curve: Curves.decelerate,
              padding: EdgeInsets.all(12),
              width: MediaQuery.of(context).size.width * .87,
              constraints: BoxConstraints(maxWidth: 370),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: List<Color>.from(shift['gradient']),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 40,
                    spreadRadius: 6,
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: _buildShiftDetailContent(shift),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curved = Curves.easeOutBack.transform(anim1.value);
        return Transform.scale(
          scale: 0.7 + curved * 0.3,
          child: Transform.translate(
            offset: Offset(0, 80 * (1 - curved)),
            child: child,
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
          child: GestureDetector(
            onTap: () => widget.onShiftTap(_shifts[indices[i]]),
            child: _ShiftCard(
              shiftName: _shifts[indices[i]]["shiftName"],
              time: _shifts[indices[i]]["time"],
              count: _shifts[indices[i]]["count"],
              color: _shifts[indices[i]]["color"],
              gradientColors: List<Color>.from(_shifts[indices[i]]["gradient"]),
              iconPath: 'assets/shift.png',
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
