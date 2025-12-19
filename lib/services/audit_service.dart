import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

class AuditService {
  AuditService._();
  static final AuditService instance = AuditService._();

  final _col = FirebaseFirestore.instance.collection('audit_logs_admin');

  Future<void> log({required String event, Map<String, dynamic>? data}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final device = await _deviceInfo();
      final now = Timestamp.now();
      // Allowed event set and API exclusion (applies to admin & cashier)
      const allowedEvents = {'screen_view', 'login', 'logout', 'tab_selected'};
      // Normalize variants like 'login_google_success' -> 'login', 'logout_user' -> 'logout'
      String ev = event;
      if (event.toLowerCase().startsWith('login')) ev = 'login';
      if (event.toLowerCase().startsWith('logout')) ev = 'logout';
      final bool isApiEvent = ev.startsWith('api_');

      // Prepare a mutable copy of data for admin
      final Map<String, dynamic> adminData = Map<String, dynamic>.from(
        data ?? {},
      );
      // Ensure route_name for tab selections
      if (ev == 'tab_selected' &&
          (adminData['route_name'] == null ||
              (adminData['route_name'] as String?)?.isEmpty == true)) {
        adminData['route_name'] =
            (adminData['tab'] as String?) ??
            (adminData['tab_name'] as String?) ??
            (adminData['label'] as String?) ??
            'Tab';
      }
      // Include username hint in admin logs (not required by UI but useful)
      if (user?.uid != null) {
        try {
          final uDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user!.uid)
              .get();
          final raw = uDoc.data()?['username'];
          String? uname;
          if (raw is String) {
            uname = raw.trim();
          } else if (raw is List && raw.isNotEmpty && raw.first is String) {
            uname = (raw.first as String).trim();
          }
          adminData['username'] = uname ?? user?.displayName;
        } catch (_) {}
      }
      // Write admin log only for allowed events and non-API events
      if (allowedEvents.contains(ev) && !isApiEvent) {
        await _col.add({
          'event': ev,
          'timestamp': now,
          'uid': user?.uid,
          'email': user?.email,
          'data': adminData,
          'device': device,
        });
      }

      // Cashier-only flattened log for the audit table
      String route = (data?['route_name'] as String?) ?? '';
      final role = (data?['role'] as String?) ?? '';
      // Allow caller to provide explicit uid/email for login/logout flows
      final uidFromData = (data?['uid'] as String?)?.trim();
      final emailFromData = (data?['email'] as String?)?.trim();

      // Only certain events should appear in cashier table
      const allowedCashierEvents = {
        'screen_view',
        'login',
        'logout',
        'tab_selected',
      };
      if (!allowedCashierEvents.contains(ev) || isApiEvent) {
        return; // skip cashier table for disallowed events
      }

      // Ensure route has a value for tab selections
      if (ev == 'tab_selected' && (route.isEmpty)) {
        route =
            (data?['tab'] as String?) ??
            (data?['tab_name'] as String?) ??
            (data?['label'] as String?) ??
            'Tab';
      }

      // Determine if this is a cashier-context event
      bool isCashierContext = route == 'PosSale' || role == 'cashier';
      if (!isCashierContext) {
        final uidProbe = uidFromData ?? user?.uid;
        if (uidProbe != null && uidProbe.isNotEmpty) {
          try {
            final roleDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(uidProbe)
                .get();
            final roleVal = (roleDoc.data()?['role'] as String?) ?? '';
            if (roleVal.toLowerCase() == 'cashier') isCashierContext = true;
          } catch (_) {}
        }
      }

      if (isCashierContext) {
        String? finalUid = user?.uid ?? uidFromData;
        String? finalEmail = user?.email ?? emailFromData;
        String? username;
        try {
          // 1) Try users/{uid}.username using best-known uid
          final uidProbe = finalUid ?? uidFromData;
          if (uidProbe != null && uidProbe.isNotEmpty) {
            final uDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(uidProbe)
                .get();
            final raw = uDoc.data()?['username'];
            if (raw is String) {
              username = raw.trim();
            } else if (raw is List && raw.isNotEmpty) {
              final first = raw.first;
              if (first is String) username = first.trim();
            }
          }
          // 2) Fallback to displayName
          if (username == null || username.isEmpty) {
            username = user?.displayName;
          }
          // 3) Fallback to email or its local-part from best-known email
          final emailProbe = finalEmail;
          if ((username == null || username.isEmpty) &&
              emailProbe != null &&
              emailProbe.isNotEmpty) {
            final at = emailProbe.indexOf('@');
            username = at > 0 ? emailProbe.substring(0, at) : emailProbe;
          }
          // 4) Final fallback
          username ??= 'unknown';
        } catch (_) {
          username ??= 'unknown';
        }

        await FirebaseFirestore.instance.collection('audit_logs_cashier').add({
          'event': ev,
          'timestamp': now,
          'uid': finalUid,
          'email': finalEmail,
          'username': username,
          'route_name': route,
          'device_platform': device['platform'],
          'device_model': device['model'] ?? device['computerName'],
          'device_manufacturer':
              device['manufacturer'] ?? device['productName'],
          'device_product': device['productName'] ?? device['browser'],
        });
      }
    } catch (_) {
      // Swallow logging errors to avoid breaking UX
    }
  }

  Future<Map<String, dynamic>> _deviceInfo() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (kIsWeb) {
        final info = await plugin.webBrowserInfo;
        return {
          'platform': 'web',
          'browser': info.browserName.toString(),
          'userAgent': info.userAgent,
        };
      }

      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final info = await plugin.androidInfo;
          return {
            'platform': 'android',
            'model': info.model,
            'manufacturer': info.manufacturer,
            'version': info.version.sdkInt,
          };
        case TargetPlatform.iOS:
          final info = await plugin.iosInfo;
          return {
            'platform': 'ios',
            'model': info.utsname.machine,
            'systemName': info.systemName,
            'version': info.systemVersion,
          };
        case TargetPlatform.windows:
          final info = await plugin.windowsInfo;
          return {
            'platform': 'windows',
            'computerName': info.computerName,
            'productName': info.productName,
            'buildNumber': info.buildNumber,
          };
        case TargetPlatform.macOS:
          final info = await plugin.macOsInfo;
          return {
            'platform': 'macos',
            'model': info.model,
            'osRelease': info.osRelease,
            'arch': info.arch,
          };
        case TargetPlatform.linux:
          final info = await plugin.linuxInfo;
          return {
            'platform': 'linux',
            'name': info.name,
            'version': info.version,
            'variant': info.variant,
          };
        case TargetPlatform.fuchsia:
          return {'platform': 'fuchsia'};
      }
    } catch (_) {
      return {'platform': 'unknown'};
    }
  }
}
