import 'package:flutter/material.dart';
import 'dart:async';

class SalesTab extends StatefulWidget {
  const SalesTab({super.key});
  @override
  State<SalesTab> createState() => _SalesTabState();
}

class _SalesTabState extends State<SalesTab> with TickerProviderStateMixin {
  static const double _cardWidth = 165;
  static const double _cardHeight = 185;
  static const double _cardBorderRadius = 16;
  static const double _cardPadding = 16;
  static const EdgeInsets _screenPadding = EdgeInsets.fromLTRB(
    22.0,
    22.0,
    22.0,
    100.0,
  );
  static const Color _primaryColor = Color(0xFF4CAF50);
  static const Color _secondaryColor = Color(0xFF66BB6A);

  double dailySalesGoal = 800;
  double todaySales = 256;
  int todayOrders = 42;
  double todayRevenue = 35200;
  bool isLoading = true;
  bool isOffline = false;
  bool hasUnsyncedSales = true;
  bool showOnboarding = true;
  bool showLowStockAlert = true;
  bool showOrdersMetric = true;
  bool showRevenueMetric = true;
  bool showPasswordStrength = true;
  bool show2FAIndicator = true;

  Map<String, int> inventory = {"Ice Block": 120, "Ice Cube": 150};
  Map<String, double> prices = {"Ice Block": 120, "Ice Cube": 10};

  List<Map<String, dynamic>> salesHistory = [
    {
      "date": "2025-10-26",
      "ref": "TXN10001",
      "qty": 30,
      "total": 4150,
      "cashier": "Angela",
    },
    {
      "date": "2025-10-26",
      "ref": "TXN10002",
      "qty": 10,
      "total": 1440,
      "cashier": "Jomar",
    },
  ];

  late final AnimationController _progressController;
  late final Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _progressAnimation =
        Tween<double>(begin: 0, end: todaySales / dailySalesGoal).animate(
          CurvedAnimation(
            parent: _progressController,
            curve: Curves.easeOutCubic,
          ),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 1), () {
        setState(() {
          isLoading = false;
        });
        _progressController.forward();
      });
    });
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  void _showNotification(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color ?? Colors.blueAccent),
    );
  }

  void _undoLastSale() {
    if (salesHistory.isNotEmpty) {
      setState(() {
        salesHistory.removeLast();
      });
      _showNotification("Last sale entry undone.", color: Colors.redAccent);
    }
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Export Sales"),
        content: const Text("Mock: Exported sales to CSV (simulated)."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _showPasswordRecovery() {
    _showNotification("Mock: Password recovery link sent.");
  }

  Widget _buildOnboardingBanner() {
    return showOnboarding
        ? Card(
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.only(bottom: 18),
      child: ListTile(
        leading: Icon(Icons.emoji_objects, color: Colors.blue[800]),
        title: const Text("Quick Tip for Sales Tab"),
        subtitle: const Text(
          "Check the export and sales actions at the bottom.",
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => setState(() => showOnboarding = false),
        ),
      ),
    )
        : const SizedBox.shrink();
  }

  Widget _buildLowStockAlert() {
    if (!showLowStockAlert) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: MaterialBanner(
        backgroundColor: Colors.orange[50],
        leading: const Icon(Icons.warning, color: Colors.orange),
        content: const Text(
          "Low stock alert: Only 40 ice blocks left in inventory!",
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() => showLowStockAlert = false),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineWarning() {
    if (!isOffline && !hasUnsyncedSales) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Colors.red[50],
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasUnsyncedSales
                  ? "Warning: Some sales have not been synced! Connect to the internet before logout."
                  : "You are offline.",
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomizationToggles() {
    return Wrap(
      spacing: 12,
      children: [
        FilterChip(
          label: const Text("Orders"),
          selected: showOrdersMetric,
          onSelected: (v) =>
              setState(() => showOrdersMetric = !showOrdersMetric),
        ),
        FilterChip(
          label: const Text("Revenue"),
          selected: showRevenueMetric,
          onSelected: (v) =>
              setState(() => showRevenueMetric = !showRevenueMetric),
        ),
        FilterChip(
          label: const Text("Password Strength"),
          selected: showPasswordStrength,
          onSelected: (v) =>
              setState(() => showPasswordStrength = !showPasswordStrength),
        ),
        FilterChip(
          label: const Text("2FA"),
          selected: show2FAIndicator,
          onSelected: (v) =>
              setState(() => show2FAIndicator = !show2FAIndicator),
        ),
      ],
    );
  }

  Widget _buildPriceStickyNotes() {
    return Row(
      children: [
        Expanded(
          child: _StickyNotePrice(
            imagePath: 'assets/notes.png',
            label: 'Ice Block',
            price: prices["Ice Block"] ?? 0.0,
            onValueChanged: (newPrice) {
              setState(() {
                prices["Ice Block"] = newPrice;
              });
            },
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StickyNotePrice(
            imagePath: 'assets/notes.png',
            label: 'Ice Cube',
            price: prices["Ice Cube"] ?? 0.0,
            onValueChanged: (newPrice) {
              setState(() {
                prices["Ice Cube"] = newPrice;
              });
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: _screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildOfflineWarning(),
              _buildLowStockAlert(),
              const SizedBox(height: 2),
              const Text(
                "Sales Monitoring",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: _primaryColor,
                ),
              ),
              _buildOnboardingBanner(),
              _buildCustomizationToggles(),
              const SizedBox(height: 12),
              _buildPriceStickyNotes(),
              isLoading
                  ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(36.0),
                  child: const CircularProgressIndicator(),
                ),
              )
                  : LayoutBuilder(
                builder: (context, constraints) {
                  double maxWidth = constraints.maxWidth;
                  double space = 18;
                  double cardWidth = 165;
                  int cardCount = show2FAIndicator ? 2 : 1;
                  double totalRequired =
                      cardCount * cardWidth + (cardCount - 1) * space;
                  if (totalRequired > maxWidth) {
                    cardWidth =
                        (maxWidth - (cardCount - 1) * space) / cardCount;
                  }
                  return Wrap(
                    spacing: space,
                    runSpacing: 14,
                    children: [
                      SizedBox(
                        width: cardWidth,
                        height: _cardHeight,
                        child: _buildSalesTodayCard(),
                      ),
                      if (show2FAIndicator)
                        SizedBox(
                          width: cardWidth,
                          child: Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            color: Colors.teal[50],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 24,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment:
                                MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.shield,
                                    color: Colors.teal[700],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "2FA Enabled",
                                    style: TextStyle(
                                      color: Colors.teal[800],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),
              _SalesCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 6),
                    _buildDescription(context),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _SalesMetric(
                          label: "Today's Sales",
                          value:
                          "₱${((todaySales ?? 0) * (prices["Ice Block"] ?? 0)).toStringAsFixed(2)}",
                        ),
                        if (showOrdersMetric)
                          _SalesMetric(
                            label: "Orders",
                            value: todayOrders.toString(),
                          ),
                        if (showRevenueMetric)
                          _SalesMetric(
                            label: "Revenue",
                            value: "₱${todayRevenue.toStringAsFixed(0)}",
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _buildActionButton(),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _buildSalesHistoryTable(),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.start,
                children: [
                  ElevatedButton.icon(
                    onPressed: _showExportDialog,
                    icon: const Icon(Icons.upload_file),
                    label: const Text("Export CSV"),
                  ),
                  ElevatedButton.icon(
                    onPressed: _undoLastSale,
                    icon: const Icon(Icons.undo),
                    label: const Text("Undo Sale"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _showPasswordRecovery,
                    icon: const Icon(Icons.key),
                    label: const Text("Forgot Password"),
                  ),
                ],
              ),
              if (showPasswordStrength)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.lock, color: Colors.green, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: 0.8,
                          minHeight: 6,
                          backgroundColor: Colors.grey[200],
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        "Strong",
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSalesTodayCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardBorderRadius),
      ),
      child: Container(
        padding: const EdgeInsets.all(_cardPadding),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_cardBorderRadius),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_primaryColor, _secondaryColor],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.greenAccent.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: AnimatedBuilder(
          animation: _progressAnimation,
          builder: (context, child) {
            final blockCount = (_progressAnimation.value * todaySales)
                .clamp(0, todaySales)
                .round();
            final percent = (_progressAnimation.value * 100).clamp(0, 100);
            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.33),
                    shape: BoxShape.circle,
                  ),
                  child: Transform.scale(
                    scale: 2.0,
                    child: Image.asset(
                      'assets/sales.png',
                      width: 28,
                      height: 28,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.attach_money,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Sales Today",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "$blockCount blocks",
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
                          width:
                          constraints.maxWidth * _progressAnimation.value,
                          decoration: BoxDecoration(
                            color: _progressAnimation.value >= 1.0
                                ? Colors.greenAccent
                                : _progressAnimation.value >= 0.7
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
                  "${percent.toStringAsFixed(0)}% of daily goal",
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Text(
          "Sales Performance",
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.deepPurple,
          ),
        ),
        Tooltip(
          message: "Key metrics for today’s sales",
          child: Padding(
            padding: const EdgeInsets.only(left: 4.0),
            child: Icon(Icons.info_outline, color: Colors.deepPurple, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildDescription(BuildContext context) {
    return Text(
      "Track your sales, revenue, and customer orders in real time.",
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
    );
  }

  Widget _buildActionButton() {
    return SizedBox(
      width: double.infinity,
      child: Tooltip(
        message: "See full sales breakdown",
        child: _SalesActionButton(
          onPressed: () => _showNotification("Mock: View sales page."),
        ),
      ),
    );
  }

  Widget _buildSalesHistoryTable() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              alignment: Alignment.center,
              margin: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Sales History',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                      letterSpacing: 0.5,
                    ),
                  ),
                  Tooltip(
                    message: "Tap header columns to sort",
                    child: Padding(
                      padding: const EdgeInsets.only(left: 3.0),
                      child: Icon(
                        Icons.help_outline,
                        color: Colors.green[400],
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(label: Text("Date")),
                  DataColumn(label: Text("Ref")),
                  DataColumn(label: Text("Qty")),
                  DataColumn(label: Text("Total")),
                  DataColumn(label: Text("Cashier")),
                ],
                rows: salesHistory.map((row) {
                  return DataRow(
                    cells: [
                      DataCell(Text(row["date"])),
                      DataCell(Text(row["ref"])),
                      DataCell(Text(row["qty"].toString())),
                      DataCell(Text("₱${row["total"]}")),
                      DataCell(Text(row["cashier"])),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Sticky Note Price Widget - Label stays low, price moves up
class _StickyNotePrice extends StatelessWidget {
  final String imagePath;
  final String label;
  final double price;
  final ValueChanged<double> onValueChanged;

  const _StickyNotePrice({
    required this.imagePath,
    required this.label,
    required this.price,
    required this.onValueChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showGeneralDialog(
          context: context,
          barrierDismissible: true,
          barrierLabel: "",
          pageBuilder: (_, __, ___) => const SizedBox.shrink(),
          transitionBuilder: (_, anim, __, ___) {
            return Transform.scale(
              scale: Curves.elasticOut.transform(anim.value),
              child: Opacity(
                opacity: anim.value,
                child: _StickyNoteEditDialog(
                  label: label,
                  price: price,
                  onValueChanged: onValueChanged,
                ),
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 350),
        );
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: 1.2,
            child: Image.asset(
              imagePath,
              fit: BoxFit.contain,
              alignment: Alignment.topCenter,
              errorBuilder: (context, error, stackTrace) => Container(
                decoration: BoxDecoration(
                  color: Colors.yellow[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(Icons.note, size: 50, color: Colors.brown),
                ),
              ),
            ),
          ),
          // Move label lower
          Positioned(
            top: 38,
            left: 0,
            right: 0,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 19,
                color: Colors.brown[700],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          // Move price further up
          Positioned(
            left: 0,
            right: 0,
            child: Container(
              alignment: Alignment.center,
              margin: const EdgeInsets.only(top: 28), // <-- Updated position
              child: Text(
                "₱${price.toStringAsFixed(2)}",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 26,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StickyNoteEditDialog extends StatefulWidget {
  final String label;
  final double price;
  final ValueChanged<double> onValueChanged;

  const _StickyNoteEditDialog({
    required this.label,
    required this.price,
    required this.onValueChanged,
  });

  @override
  State<_StickyNoteEditDialog> createState() => _StickyNoteEditDialogState();
}

class _StickyNoteEditDialogState extends State<_StickyNoteEditDialog> {
  bool isEditing = false;
  late TextEditingController controller;
  late double localPrice;

  @override
  void initState() {
    super.initState();
    localPrice = widget.price;
    controller = TextEditingController(text: localPrice.toStringAsFixed(2));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.only(
        top: 10,
        left: 20,
        right: 20,
        bottom: 40,
      ),
      child: Center(
        child: Container(
          width: 310,
          height: 250,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            image: DecorationImage(
              image: const AssetImage('assets/notes.png'),
              fit: BoxFit.contain,
              alignment: Alignment.topCenter,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 18,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: 70,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      color: Colors.brown[700],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 42,
                right: 72,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(100),
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      child: Image.asset('assets/x.png', width: 20, height: 20),
                    ),
                  ),
                ),
              ),
              Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: !isEditing
                      ? Row(
                    key: const ValueKey('display'),
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        "₱${localPrice.toStringAsFixed(2)}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 36,
                          color: Colors.black,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => isEditing = true),
                        child: Image.asset(
                          'assets/edit.png',
                          width: 27,
                          height: 27,
                        ),
                      ),
                    ],
                  )
                      : Row(
                    key: const ValueKey('editing'),
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 120,
                        alignment: Alignment.center,
                        child: TextField(
                          controller: controller,
                          textAlign: TextAlign.center,
                          keyboardType:
                          const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              vertical: 4,
                            ),
                            prefixText: "₱",
                            prefixStyle: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                            ),
                            border: UnderlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            localPrice =
                                double.tryParse(controller.text) ??
                                    widget.price;
                            isEditing = false;
                            widget.onValueChanged(localPrice);
                          });
                        },
                        child: const Icon(
                          Icons.save,
                          color: Colors.green,
                          size: 27,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SalesCard extends StatelessWidget {
  final Widget child;
  const _SalesCard({required this.child});
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    );
  }
}

class _SalesMetric extends StatelessWidget {
  final String label;
  final String value;

  const _SalesMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}

class _SalesActionButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _SalesActionButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.shopping_cart_checkout),
      label: const Text("View Sales"),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 2,
      ),
    );
  }
}
