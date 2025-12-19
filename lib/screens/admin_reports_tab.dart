import 'package:flutter/material.dart';

class AdminReportsTab extends StatelessWidget {
  const AdminReportsTab({super.key});

  // Design constants to match existing admin dashboard styling
  static const EdgeInsets _contentPadding = EdgeInsets.all(16);
  static const EdgeInsets _cardPadding = EdgeInsets.all(20);
  static const double _cardBorderRadius = 20;
  static const double _buttonBorderRadius = 12;
  static const double _previewBorderRadius = 16;
  static const double _sectionSpacing = 20;
  static const double _smallSpacing = 10;
  static const double _previewHeight = 200;
  static const double _breakpointWidth = 400;

  // Colors
  static const Color _primaryTextColor800 = Color(0xFF37474F); // blueGrey[800]
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
              children: const [
                _Header(),
                SizedBox(height: _smallSpacing),
                _Description(),
                SizedBox(height: _sectionSpacing),
                TabBar(
                  labelColor: Colors.redAccent,
                  unselectedLabelColor: _secondaryTextColor,
                  indicatorColor: Colors.redAccent,
                  tabs: [
                    Tab(text: 'Analytics'),
                    Tab(text: 'Management'),
                  ],
                ),
                SizedBox(height: _smallSpacing),
                SizedBox(
                  height: 420,
                  child: TabBarView(
                    children: [_AnalyticsContent(), _ManagementContent()],
                  ),
                ),
                SizedBox(height: _sectionSpacing),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    return Text(
      'Reports & Analytics',
      style:
          (Theme.of(context).textTheme.headlineSmall ??
                  const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))
              .copyWith(color: AdminReportsTab._primaryTextColor800),
    );
  }
}

class _Description extends StatelessWidget {
  const _Description();
  @override
  Widget build(BuildContext context) {
    return Text(
      'Generate and manage reports for production, inventory, sales, monitoring, shifts, and cashier activities.',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: AdminReportsTab._secondaryTextColor,
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final Widget child;
  const _ReportCard({required this.child});
  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AdminReportsTab._cardBorderRadius),
      ),
      child: Padding(padding: AdminReportsTab._cardPadding, child: child),
    );
  }
}

class _ReportButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onPressed;

  const _ReportButton({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            AdminReportsTab._buttonBorderRadius,
          ),
        ),
      ),
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        Icon(
          Icons.analytics_outlined,
          size: 48,
          color: AdminReportsTab._previewTextColor,
        ),
        SizedBox(height: 8),
        Text(
          'Report Preview Will Appear Here',
          style: TextStyle(
            color: AdminReportsTab._previewTextColor,
            fontSize: 16,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 4),
        Text(
          'Select a type and date range, then generate to view data',
          style: TextStyle(
            color: AdminReportsTab._previewTextColor,
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// Analytics
class _AnalyticsContent extends StatefulWidget {
  const _AnalyticsContent();
  @override
  State<_AnalyticsContent> createState() => _AnalyticsContentState();
}

class _AnalyticsContentState extends State<_AnalyticsContent> {
  DateTimeRange? _range;
  String _reportType = _types.first;

  static const List<String> _types = [
    'Production',
    'Inventory Add/Loss',
    'Ice Block Production',
    'Ice Cube Production',
    'Discrepancies',
    'Sales',
    'Returns and Voids',
    'Discounts',
    'Payment Breakdown',
    'Monitoring Records',
    'Shift Reports',
    'Cashier Reports',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow =
                constraints.maxWidth < AdminReportsTab._breakpointWidth;
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
              label: 'Select Date Range',
              icon: Icons.date_range,
              backgroundColor: Colors.white,
              foregroundColor: Colors.redAccent,
              onPressed: _pickRange,
            );
            final genBtn = _ReportButton(
              label: 'Generate Report',
              icon: Icons.analytics_outlined,
              backgroundColor: Colors.white,
              foregroundColor: Colors.redAccent,
              onPressed: _generate,
            );

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  dropdown,
                  const SizedBox(height: AdminReportsTab._smallSpacing),
                  dateBtn,
                  const SizedBox(height: AdminReportsTab._smallSpacing),
                  genBtn,
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: dropdown),
                const SizedBox(width: AdminReportsTab._smallSpacing),
                Expanded(child: dateBtn),
                const SizedBox(width: AdminReportsTab._smallSpacing),
                Expanded(child: genBtn),
              ],
            );
          },
        ),
        const SizedBox(height: AdminReportsTab._sectionSpacing),
        Container(
          height: AdminReportsTab._previewHeight,
          decoration: BoxDecoration(
            color: AdminReportsTab._previewBgColor,
            borderRadius: BorderRadius.circular(
              AdminReportsTab._previewBorderRadius,
            ),
            border: Border.all(color: AdminReportsTab._previewBorderColor),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.analytics_outlined,
                  size: 40,
                  color: AdminReportsTab._previewTextColor,
                ),
                const SizedBox(height: 8),
                Text(
                  _range == null
                      ? 'Select a date range'
                      : _formatRange(_range!),
                  style: const TextStyle(
                    color: AdminReportsTab._previewTextColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  'Type: ' + _reportType,
                  style: TextStyle(
                    color: AdminReportsTab._previewTextColor.withOpacity(0.8),
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
    _snack('Generating $_reportType report for ${_formatRange(_range!)}');
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

// Management
class _ManagementContent extends StatefulWidget {
  const _ManagementContent();
  @override
  State<_ManagementContent> createState() => _ManagementContentState();
}

class _ManagementContentState extends State<_ManagementContent> {
  final List<String> _saved = <String>[
    'Production - 2025-12-01',
    'Inventory Add/Loss - 2025-12-01',
    'Sales - 2025-12-01',
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
                backgroundColor: Colors.white,
                foregroundColor: Colors.redAccent,
                onPressed: () => _snack('Export CSV triggered'),
              ),
            ),
            const SizedBox(width: AdminReportsTab._smallSpacing),
            Expanded(
              child: _ReportButton(
                label: 'Export PDF',
                icon: Icons.picture_as_pdf,
                backgroundColor: Colors.white,
                foregroundColor: Colors.redAccent,
                onPressed: () => _snack('Export PDF triggered'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AdminReportsTab._sectionSpacing),
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
