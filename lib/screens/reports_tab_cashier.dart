import 'package:flutter/material.dart';

class ReportsTab extends StatelessWidget {
  const ReportsTab({super.key});

  // Constants for better maintainability
  static const EdgeInsets _contentPadding = EdgeInsets.all(16);
  static const EdgeInsets _cardPadding = EdgeInsets.all(20);
  static const double _cardBorderRadius = 20;
  static const double _buttonBorderRadius = 12;
  static const double _previewBorderRadius = 16;
  static const double _sectionSpacing = 20;
  static const double _smallSpacing = 10;
  static const double _previewHeight = 200;
  static const double _breakpointWidth = 400;

  // Colors - Fixed definitions
  static const Color _primaryTextColor800 = Color(0xFF37474F); // blueGrey[800]
  static const Color _primaryTextColor700 = Color(0xFF455A64); // blueGrey[700]
  static const Color _primaryTextColor900 = Color(0xFF263238); // blueGrey[900]
  static const Color _secondaryTextColor = Color(0xFF616161); // grey[700]
  static const Color _previewBgColor = Color(0xFFEEEEEE); // grey[200]
  static const Color _previewBorderColor = Color(0xFFBDBDBD); // grey[400]
  static const Color _previewTextColor = Color(0xFF9E9E9E); // grey[500]

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: ScrollConfiguration(
        behavior: const MaterialScrollBehavior().copyWith(overscroll: false),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: _contentPadding,
          child: _ReportCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const SizedBox(height: _smallSpacing),
                _buildDescription(context),
                const SizedBox(height: _sectionSpacing),
                const TabBar(
                  labelColor: Colors.redAccent,
                  unselectedLabelColor: _secondaryTextColor,
                  indicatorColor: Colors.redAccent,
                  tabs: [
                    Tab(text: 'Analytics'),
                    Tab(text: 'Management'),
                  ],
                ),
                const SizedBox(height: _smallSpacing),
                SizedBox(
                  height: 400,
                  child: const TabBarView(
                    children: [
                      _AnalyticsContentCashier(),
                      _ManagementContentCashier(),
                    ],
                  ),
                ),
                const SizedBox(height: _sectionSpacing),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Text(
      "Reports & Analytics",
      style:
          (Theme.of(context).textTheme.headlineSmall ??
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))
              .copyWith(color: _primaryTextColor800),
    );
  }

  Widget _buildDescription(BuildContext context) {
    return Text(
      "Generate detailed reports for sales, payroll, and production to help with decision-making.",
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: _secondaryTextColor),
    );
  }

  Widget _buildButtonSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isNarrow = constraints.maxWidth < _breakpointWidth;

        if (isNarrow) {
          return _buildVerticalButtons(context);
        } else {
          return _buildHorizontalButtons(context);
        }
      },
    );
  }

  Widget _buildVerticalButtons(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReportButton(
          label: "Select Date Range",
          icon: Icons.date_range,
          color: Colors.white,
          foregroundColor: Colors.redAccent,
          onPressed: () => _selectDateRange(context),
        ),
        const SizedBox(height: _smallSpacing),
        _ReportButton(
          label: "Generate Report",
          icon: Icons.analytics_outlined,
          color: Colors.white,
          foregroundColor: Colors.redAccent,
          onPressed: () => _generateReport(context),
        ),
      ],
    );
  }

  Widget _buildHorizontalButtons(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: _ReportButton(
            label: "Select Date Range",
            icon: Icons.date_range,
            color: Colors.white,
            foregroundColor: Colors.redAccent,
            onPressed: () => _selectDateRange(context),
          ),
        ),
        const SizedBox(width: _smallSpacing),
        Flexible(
          child: _ReportButton(
            label: "Generate Report",
            icon: Icons.analytics_outlined,
            color: Colors.white,
            foregroundColor: Colors.redAccent,
            onPressed: () => _generateReport(context),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewSection() {
    return Container(
      height: _previewHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        color: _previewBgColor,
        borderRadius: BorderRadius.circular(_previewBorderRadius),
        border: Border.all(color: _previewBorderColor),
      ),
      child: const Center(child: _PreviewPlaceholder()),
    );
  }

  void _selectDateRange(BuildContext context) {
    // TODO: Implement date range picker
    // Show date range picker dialog
    final now = DateTime.now();
    final initial = DateTimeRange(
      start: DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 6)),
      end: DateTime(now.year, now.month, now.day),
    );
    showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initial,
      saveText: 'Apply',
    ).then((picked) {
      if (picked != null) {
        String fmt(DateTime d) =>
            "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
        _showSnackBar(
          context,
          'Selected: ${fmt(picked.start)} to ${fmt(picked.end)}',
        );
      }
    });
  }

  void _generateReport(BuildContext context) {
    // TODO: Implement report generation
    // Generate and display report
    _showSnackBar(context, 'Report generation coming soon!');
  }

  void _showSnackBar(BuildContext context, String message) {
    // We need to use a Builder to get the context for ScaffoldMessenger
    // This would typically be handled in the widget build method
    // For now, we'll leave the TODOs as is
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AnalyticsContentCashier extends StatefulWidget {
  const _AnalyticsContentCashier();

  @override
  State<_AnalyticsContentCashier> createState() =>
      _AnalyticsContentCashierState();
}

class _AnalyticsContentCashierState extends State<_AnalyticsContentCashier> {
  DateTimeRange? _range;
  String _reportType = _types.first;
  static const List<String> _types = [
    'Sales',
    'Returns and Voids',
    'Discounts',
    'Payment Breakdown',
    'Production',
    'Inventory Add/Loss',
    'Ice Block Production',
    'Ice Cube Production',
    'Discrepancies',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < ReportsTab._breakpointWidth;
            final dropdown = DropdownButtonFormField<String>(
              value: _reportType,
              items: _types
                  .map(
                    (t) => DropdownMenuItem<String>(value: t, child: Text(t)),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _reportType = v ?? _reportType),
              decoration: const InputDecoration(
                labelText: 'Report Type',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            );
            final dateBtn = _ReportButton(
              label: "Select Date Range",
              icon: Icons.date_range,
              color: Colors.white,
              foregroundColor: Colors.redAccent,
              onPressed: _pickRange,
            );
            final genBtn = _ReportButton(
              label: "Generate Report",
              icon: Icons.analytics_outlined,
              color: Colors.white,
              foregroundColor: Colors.redAccent,
              onPressed: _generate,
            );

            if (isNarrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  dropdown,
                  const SizedBox(height: ReportsTab._smallSpacing),
                  dateBtn,
                  const SizedBox(height: ReportsTab._smallSpacing),
                  genBtn,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: dropdown),
                const SizedBox(width: ReportsTab._smallSpacing),
                Expanded(child: dateBtn),
                const SizedBox(width: ReportsTab._smallSpacing),
                Expanded(child: genBtn),
              ],
            );
          },
        ),
        const SizedBox(height: ReportsTab._sectionSpacing),
        Container(
          height: ReportsTab._previewHeight,
          decoration: BoxDecoration(
            color: ReportsTab._previewBgColor,
            borderRadius: BorderRadius.circular(
              ReportsTab._previewBorderRadius,
            ),
            border: Border.all(color: ReportsTab._previewBorderColor),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.analytics_outlined,
                  color: ReportsTab._previewTextColor,
                  size: 40,
                ),
                const SizedBox(height: 8),
                Text(
                  _range == null
                      ? 'Select a date range'
                      : _formatRange(_range!),
                  style: const TextStyle(color: ReportsTab._previewTextColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Type: ' + _reportType,
                  style: TextStyle(
                    color: ReportsTab._previewTextColor.withOpacity(0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final initial =
        _range ??
        DateTimeRange(
          start: DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(const Duration(days: 6)),
          end: DateTime(now.year, now.month, now.day),
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initial,
      saveText: 'Apply',
    );
    if (picked != null) {
      setState(() => _range = picked);
      _snack('Date range updated');
    }
  }

  void _generate() {
    if (_range == null) {
      _snack('Please select a date range first');
      return;
    }
    _snack('Generating report for ${_formatRange(_range!)}');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _formatRange(DateTimeRange r) {
    String d(DateTime dt) =>
        "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}";
    return "${d(r.start)} to ${d(r.end)}";
  }
}

class _ManagementContentCashier extends StatefulWidget {
  const _ManagementContentCashier();

  @override
  State<_ManagementContentCashier> createState() =>
      _ManagementContentCashierState();
}

class _ManagementContentCashierState extends State<_ManagementContentCashier> {
  final List<String> _saved = <String>[
    'Shift Sales - Today',
    'Cashier Summary - This Week',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _ReportButton(
                label: 'Export CSV',
                icon: Icons.table_view,
                color: Colors.white,
                foregroundColor: Colors.redAccent,
                onPressed: () => _snack('Export CSV (cashier) triggered'),
              ),
            ),
            const SizedBox(width: ReportsTab._smallSpacing),
            Expanded(
              child: _ReportButton(
                label: 'Export PDF',
                icon: Icons.picture_as_pdf,
                color: Colors.white,
                foregroundColor: Colors.redAccent,
                onPressed: () => _snack('Export PDF (cashier) triggered'),
              ),
            ),
          ],
        ),
        const SizedBox(height: ReportsTab._sectionSpacing),
        const Text(
          'Saved Reports',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 260,
          child: ListView.separated(
            itemCount: _saved.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final name = _saved[i];
              return ListTile(
                title: Text(name),
                leading: const Icon(Icons.insert_drive_file_outlined),
                trailing: IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                  ),
                  onPressed: () {
                    setState(() => _saved.removeAt(i));
                    _snack('Deleted "$name"');
                  },
                ),
                onTap: () => _snack('Open "$name"'),
              );
            },
          ),
        ),
      ],
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

/// Dedicated widget for the main report card
class _ReportCard extends StatelessWidget {
  final Widget child;

  const _ReportCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ReportsTab._cardBorderRadius),
      ),
      child: Padding(padding: ReportsTab._cardPadding, child: child),
    );
  }
}

/// Dedicated widget for report action buttons
class _ReportButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color? foregroundColor;
  final VoidCallback onPressed;

  const _ReportButton({
    required this.label,
    required this.icon,
    required this.color,
    this.foregroundColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: foregroundColor ?? Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ReportsTab._buttonBorderRadius),
        ),
      ),
    );
  }
}

/// Dedicated widget for report preview placeholder
class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.analytics_outlined,
          size: 48,
          color: ReportsTab._previewTextColor,
        ),
        const SizedBox(height: 8),
        Text(
          "Report Preview Will Appear Here",
          style: TextStyle(color: ReportsTab._previewTextColor, fontSize: 16),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          "Select a date range and generate report to view data",
          style: TextStyle(
            color: ReportsTab._previewTextColor.withOpacity(0.7),
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
