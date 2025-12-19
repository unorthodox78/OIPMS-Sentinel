import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/notification/notification_bell.dart';

class AdminHeader extends StatefulWidget {
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

  @override
  State<AdminHeader> createState() => _AdminHeaderState();
}

class _AdminHeaderState extends State<AdminHeader> {
  static const double _avatarRadius = 20;
  static const double _spacing = 8;
  static const String _profileAssetPath = 'assets/profile.png';

  ImageProvider? _avatarProvider;
  String? _lastUrl;

  @override
  void initState() {
    super.initState();
    _primeAvatarFromAuth();
  }

  void _primeAvatarFromAuth() {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      // Prefer Facebook photo, then Google, then user.photoURL
      String? providerPhoto;
      for (final p in user.providerData) {
        if (p.providerId == 'facebook.com') {
          providerPhoto = p.photoURL ?? providerPhoto;
        }
      }
      if (providerPhoto == null) {
        for (final p in user.providerData) {
          if (p.providerId == 'google.com') {
            providerPhoto = p.photoURL ?? providerPhoto;
          }
        }
      }
      providerPhoto ??= user.photoURL;
      if (providerPhoto != null && providerPhoto.isNotEmpty) {
        _avatarProvider = NetworkImage(providerPhoto);
        _lastUrl = providerPhoto;
      } else {
        _avatarProvider ??= const AssetImage(_profileAssetPath);
      }
    } catch (_) {
      // Keep default avatar if anything goes wrong
      _avatarProvider ??= const AssetImage(_profileAssetPath);
    }
  }

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
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    return GestureDetector(
      onTap: _openDrawer,
      child: Row(
        children: [
          if (uid == null)
            _buildProfileAvatar()
          else
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data();
                final firestorePhotoAdmin =
                    data?['profilePhotoAdmin'] as String?;
                final firestorePhotoLegacy = data?['profilePhoto'] as String?;
                final adminFbFlag = data?['facebookBoundAdmin'] as bool?;
                final adminGFlag = data?['googleBoundAdmin'] as bool?;
                final flagsPresent = adminFbFlag != null || adminGFlag != null;

                bool isFacebookBound = false;
                bool isGoogleBound = false;
                String? providerPhoto;

                if (flagsPresent) {
                  isFacebookBound = adminFbFlag == true;
                  isGoogleBound = adminGFlag == true;
                  if (isFacebookBound) {
                    try {
                      final fb = user!.providerData.firstWhere(
                        (p) => p.providerId == 'facebook.com',
                      );
                      providerPhoto = fb.photoURL ?? providerPhoto;
                    } catch (_) {}
                  }
                  if (isGoogleBound && providerPhoto == null) {
                    try {
                      final g = user!.providerData.firstWhere(
                        (p) => p.providerId == 'google.com',
                      );
                      providerPhoto = g.photoURL ?? providerPhoto;
                    } catch (_) {}
                  }
                } else {
                  // Legacy fallback: infer from providerData like before
                  for (final p in user!.providerData) {
                    if (p.providerId == 'facebook.com') {
                      isFacebookBound = true;
                      providerPhoto = p.photoURL ?? providerPhoto;
                    }
                    if (p.providerId == 'google.com') {
                      isGoogleBound = true;
                      providerPhoto = providerPhoto ?? p.photoURL;
                    }
                  }
                }

                // None linked when neither provider is bound (works with or without flags present)
                final noneLinked = !(isFacebookBound || isGoogleBound);

                String? desiredUrl;
                if (!noneLinked || !flagsPresent) {
                  final firestorePhoto =
                      (firestorePhotoAdmin != null &&
                          firestorePhotoAdmin.isNotEmpty)
                      ? firestorePhotoAdmin
                      : firestorePhotoLegacy;
                  desiredUrl =
                      (firestorePhoto != null && firestorePhoto.isNotEmpty)
                      ? firestorePhoto
                      : providerPhoto;
                }

                if (desiredUrl != null && desiredUrl.isNotEmpty) {
                  if (_lastUrl != desiredUrl) _lastUrl = desiredUrl;
                  final next = NetworkImage(desiredUrl);
                  final current = _avatarProvider;
                  final currentUrl = (current is NetworkImage)
                      ? current.url
                      : null;
                  if (currentUrl != desiredUrl) {
                    // Apply immediately in this build frame; precache in background
                    _avatarProvider = next;
                    try {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        precacheImage(next, context);
                      });
                    } catch (_) {}
                  }
                } else {
                  // No URL resolved. If no social is bound, treat as deletion: evict and clear last URL
                  if (noneLinked) {
                    try {
                      if (_lastUrl != null && _lastUrl!.isNotEmpty) {
                        NetworkImage(_lastUrl!).evict();
                      }
                    } catch (_) {}
                    _lastUrl = null;
                  }
                  if (_avatarProvider == null) {
                    _avatarProvider = const AssetImage(_profileAssetPath);
                  } else if (noneLinked && _avatarProvider is NetworkImage) {
                    _avatarProvider = const AssetImage(_profileAssetPath);
                  }
                }

                return _buildProfileAvatar();
              },
            ),
          const SizedBox(width: _spacing),
          if (uid == null)
            ValueListenableBuilder<String>(
              valueListenable: widget.adminNameNotifier,
              builder: (context, name, _) => _buildNameText(name),
            )
          else
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data();
                final name =
                    (data?['name'] as String?) ??
                    widget.adminNameNotifier.value;
                return _buildNameText(name);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildProfileAvatar() {
    final bg = Colors.grey.shade300;
    return CircleAvatar(
      radius: _avatarRadius,
      backgroundColor: bg,
      child: ClipOval(
        child: Image(
          image: _avatarProvider ?? const AssetImage(_profileAssetPath),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          width: _avatarRadius * 2,
          height: _avatarRadius * 2,
        ),
      ),
    );
  }

  Widget _buildNameText(String name) {
    return Text(
      name,
      style: const TextStyle(
        color: Colors.black87,
        fontWeight: FontWeight.bold,
        fontSize: 16,
      ),
    );
  }

  Widget _buildNotificationSection() {
    return NotificationBell(
      bellKey: widget.bellKey,
      notificationCount: widget.notificationCount,
      onOpened: widget.onNotificationOpened,
    );
  }

  void _openDrawer() {
    widget.scaffoldKey.currentState?.openDrawer();
  }
}
