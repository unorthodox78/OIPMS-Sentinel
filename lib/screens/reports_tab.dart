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
    return ScrollConfiguration(
      behavior: const MaterialScrollBehavior().copyWith(
        overscroll: false,
      ),
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
              _buildButtonSection(),
              const SizedBox(height: _sectionSpacing),
              _buildPreviewSection(),
              const SizedBox(height: _sectionSpacing), // Extra bottom padding
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Text(
      "Reports & Analytics",
      style: (Theme.of(context).textTheme.headlineSmall ??
          const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))
          .copyWith(color: _primaryTextColor800),
    );
  }

  Widget _buildDescription(BuildContext context) {
    return Text(
      "Generate detailed reports for sales, payroll, and production to help with decision-making.",
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: _secondaryTextColor,
      ),
    );
  }

  Widget _buildButtonSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isNarrow = constraints.maxWidth < _breakpointWidth;

        if (isNarrow) {
          return _buildVerticalButtons();
        } else {
          return _buildHorizontalButtons();
        }
      },
    );
  }

  Widget _buildVerticalButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReportButton(
          label: "Select Date Range",
          icon: Icons.date_range,
          color: _primaryTextColor700,
          onPressed: _selectDateRange,
        ),
        const SizedBox(height: _smallSpacing),
        _ReportButton(
          label: "Generate Report",
          icon: Icons.analytics_outlined,
          color: _primaryTextColor900,
          onPressed: _generateReport,
        ),
      ],
    );
  }

  Widget _buildHorizontalButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: _ReportButton(
            label: "Select Date Range",
            icon: Icons.date_range,
            color: _primaryTextColor700,
            onPressed: _selectDateRange,
          ),
        ),
        const SizedBox(width: _smallSpacing),
        Flexible(
          child: _ReportButton(
            label: "Generate Report",
            icon: Icons.analytics_outlined,
            color: _primaryTextColor900,
            onPressed: _generateReport,
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
      child: const Center(
        child: _PreviewPlaceholder(),
      ),
    );
  }

  void _selectDateRange() {
    // TODO: Implement date range picker
    // Show date range picker dialog
    _showSnackBar('Date range selection coming soon!');
  }

  void _generateReport() {
    // TODO: Implement report generation
    // Generate and display report
    _showSnackBar('Report generation coming soon!');
  }

  void _showSnackBar(String message) {
    // We need to use a Builder to get the context for ScaffoldMessenger
    // This would typically be handled in the widget build method
    // For now, we'll leave the TODOs as is
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
      child: Padding(
        padding: ReportsTab._cardPadding,
        child: child,
      ),
    );
  }
}

/// Dedicated widget for report action buttons
class _ReportButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _ReportButton({
    required this.label,
    required this.icon,
    required this.color,
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
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ReportsTab._buttonBorderRadius),
        ),
        elevation: 2,
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
          style: TextStyle(
            color: ReportsTab._previewTextColor,
            fontSize: 16,
          ),
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