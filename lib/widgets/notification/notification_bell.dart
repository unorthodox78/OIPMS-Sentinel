import 'package:flutter/material.dart';

class RightTrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, size.height / 2);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class NotificationBell extends StatefulWidget {
  final GlobalKey bellKey;
  final int notificationCount;
  final VoidCallback onOpened;

  const NotificationBell({
    super.key,
    required this.bellKey,
    required this.notificationCount,
    required this.onOpened,
  });

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  OverlayEntry? _overlayEntry;

  void _toggleOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
      return;
    }

    final RenderBox renderBox =
        widget.bellKey.currentContext!.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: offset.dy, // align top with bell icon
        left: offset.dx - 220, // position box to the left
        child: Material(
          color: Colors.transparent,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Notification container
              Container(
                width: 220,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Notifications",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Divider(),
                    _notificationItem(
                      Icons.warning,
                      "Inventory discrepancy detected",
                      "40-block gap in Shift 2",
                    ),
                    _notificationItem(
                      Icons.access_time,
                      "Overtime warning",
                      "Employee #203 near OT limit",
                    ),
                    _notificationItem(
                      Icons.device_unknown,
                      "AI Tracker Offline",
                      "Tablet disconnected since 8:10 PM",
                    ),
                  ],
                ),
              ),

              // Triangle arrow pointing to bell (vertically centered)
              Positioned(
                top: size.height / 2 - 6, // center arrow to bell
                right: -12, // outside container
                child: CustomPaint(
                  size: const Size(12, 12),
                  painter: RightTrianglePainter(),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    widget.onOpened();
  }

  Widget _notificationItem(IconData icon, String title, String subtitle) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.blueGrey),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(
          key: widget.bellKey,
          width: 60, // Increased container size
          height: 60,
          child: IconButton(
            icon: Image.asset(
              'assets/bell.png',
              width: 40, // Increased bell size
              height: 40,
              // Removed color property to show original PNG colors
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.notifications_none,
                  color: Colors.black87,
                  size: 40, // Increased fallback icon size
                );
              },
            ),
            iconSize: 40, // Increased iconSize
            onPressed: _toggleOverlay,
          ),
        ),
        if (widget.notificationCount > 0)
          Positioned(
            right: 8, // Adjusted position for bigger icon
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(5), // Slightly bigger padding
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${widget.notificationCount}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12, // Slightly bigger font
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
