import 'package:flutter/material.dart';
import '../widgets/notification/notification_bell.dart';

class AdminHeader extends StatelessWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  final GlobalKey bellKey;
  final int notificationCount;
  final VoidCallback onNotificationOpened;
  final ValueNotifier<String> adminNameNotifier;

  const AdminHeader({
    super.key,
    required this.scaffoldKey,
    required this.bellKey,
    required this.notificationCount,
    required this.onNotificationOpened,
    required this.adminNameNotifier,
  });

  static const double _avatarRadius = 20;
  static const double _spacing = 8;
  static const String _profileAssetPath = 'assets/profile.png';

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildProfileSection(context),
        const Spacer(),
        _buildNotificationSection(),
      ],
    );
  }

  Widget _buildProfileSection(BuildContext context) {
    return GestureDetector(
      onTap: _openDrawer,
      child: Row(
        children: [
          _buildProfileAvatar(),
          const SizedBox(width: _spacing),
          ValueListenableBuilder<String>(
            valueListenable: adminNameNotifier,
            builder: (context, name, _) {
              return Text(
                name,
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProfileAvatar() {
    return CircleAvatar(
      radius: _avatarRadius,
      backgroundColor: Colors.grey.shade300,
      child: _buildProfileImage(),
    );
  }

  Widget _buildProfileImage() {
    try {
      return Image.asset(
        _profileAssetPath,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildFallbackAvatar();
        },
      );
    } catch (e) {
      return _buildFallbackAvatar();
    }
  }

  Widget _buildFallbackAvatar() {
    return const Icon(
      Icons.person,
      color: Colors.white,
      size: _avatarRadius,
    );
  }

  Widget _buildNotificationSection() {
    return NotificationBell(
      bellKey: bellKey,
      notificationCount: notificationCount,
      onOpened: onNotificationOpened,
    );
  }

  void _openDrawer() {
    scaffoldKey.currentState?.openDrawer();
  }
}
