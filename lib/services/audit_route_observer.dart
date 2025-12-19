import 'package:flutter/widgets.dart';
import 'audit_service.dart';

class AuditRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  static const Set<String> _whitelist = {
    'Dashboard',
    'PosSale',
    'Profile',
    'RegisterCashier',
    'Settings',
    'CashierDetail',
    'AuditTrail',
  };

  void _log(Route<dynamic>? route, String action) {
    if (route is! PageRoute) return;
    final name = route.settings.name;
    if (name == null || name == '/' || !_whitelist.contains(name))
      return; // skip unnamed, root, or not whitelisted
    if (action != 'push') return; // log only pushes to reduce noise
    AuditService.instance.log(
      event: 'screen_view',
      data: {'route_action': action, 'route_name': name},
    );
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    _log(route, 'push');
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    _log(previousRoute, 'pop');
  }
}
