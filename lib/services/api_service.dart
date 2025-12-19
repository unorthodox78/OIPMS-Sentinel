import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'audit_service.dart';

Future<String?> _idToken() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  return await user.getIdToken();
}

Future<Map<String, dynamic>> fetchDashboardMetrics() async {
  final token = await _idToken();
  final headers = <String, String>{
    if (token != null) 'Authorization': 'Bearer $token',
  };
  final uri = Uri.parse('http://139.162.46.103:8080/dashboard-metrics');
  final started = DateTime.now();
  http.Response? resp;
  try {
    resp = await http.get(uri, headers: headers);
    return json.decode(resp.body);
  } finally {
    final durationMs = DateTime.now().difference(started).inMilliseconds;
    await AuditService.instance.log(
      event: 'api_call',
      data: {
        'method': 'GET',
        'url': uri.toString(),
        'status': resp?.statusCode,
        'latency_ms': durationMs,
      },
    );
  }
}

Future<Map<String, dynamic>> requestPasswordOtp(String email) async {
  final token = await _idToken();
  final headers = <String, String>{
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
  final uri = Uri.parse('http://139.162.46.103:8080/auth/request-password-otp');
  final started = DateTime.now();
  http.Response? resp;
  try {
    resp = await http.post(
      uri,
      headers: headers,
      body: json.encode({'email': email}),
    );
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return json.decode(resp.body);
    }
    try {
      final body = json.decode(resp.body);
      final msg =
          (body['message'] ??
                  body['error'] ??
                  'Request invalid. Please try again.')
              .toString();
      return {
        'success': false,
        'status': resp.statusCode,
        'message': msg,
        'raw': resp.body,
      };
    } catch (_) {
      return {
        'success': false,
        'status': resp.statusCode,
        'message': 'Request invalid. Please try again.',
        'raw': resp.body,
      };
    }
  } finally {
    final durationMs = DateTime.now().difference(started).inMilliseconds;
    await AuditService.instance.log(
      event: 'api_call',
      data: {
        'method': 'POST',
        'url': uri.toString(),
        'status': resp?.statusCode,
        'latency_ms': durationMs,
      },
    );
  }
}

Future<Map<String, dynamic>> resetPasswordWithOtp({
  required String email,
  required String otp,
  required String newPassword,
}) async {
  final token = await _idToken();
  final headers = <String, String>{
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
  final uri = Uri.parse(
    'http://139.162.46.103:8080/auth/reset-password-with-otp',
  );
  final started = DateTime.now();
  http.Response? resp;
  try {
    final r = await http.post(
      uri,
      headers: headers,
      body: json.encode({
        'email': email,
        'otp': otp,
        'newPassword': newPassword,
      }),
    );
    resp = r;
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return json.decode(r.body);
    }
    try {
      final body = json.decode(r.body);
      final msg =
          (body['message'] ??
                  body['error'] ??
                  'Request invalid. Please try again.')
              .toString();
      return {
        'success': false,
        'status': r.statusCode,
        'message': msg,
        'raw': r.body,
      };
    } catch (_) {
      return {
        'success': false,
        'status': r.statusCode,
        'message': 'Request invalid. Please try again.',
        'raw': r.body,
      };
    }
  } finally {
    final durationMs = DateTime.now().difference(started).inMilliseconds;
    await AuditService.instance.log(
      event: 'api_call',
      data: {
        'method': 'POST',
        'url': uri.toString(),
        'status': resp?.statusCode,
        'latency_ms': durationMs,
      },
    );
  }
}

// Login step-up 2FA: request a login OTP via email
Future<Map<String, dynamic>> requestLoginOtp(String email) async {
  final token = await _idToken();
  final headers = <String, String>{
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
  final uri = Uri.parse('http://139.162.46.103:8080/auth/request-login-otp');
  final started = DateTime.now();
  http.Response? resp;
  try {
    resp = await http.post(
      uri,
      headers: headers,
      body: json.encode({'email': email}),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      try {
        final body = json.decode(resp.body);
        final msg =
            (body['message'] ??
                    body['error'] ??
                    'Request invalid. Please try again.')
                .toString();
        return {
          'success': false,
          'status': resp.statusCode,
          'message': msg,
          'raw': resp.body,
        };
      } catch (_) {
        return {
          'success': false,
          'status': resp.statusCode,
          'message': 'Request invalid. Please try again.',
          'raw': resp.body,
        };
      }
    }
    try {
      return json.decode(resp.body);
    } catch (_) {
      return {
        'success': false,
        'status': resp.statusCode,
        'message': 'Non-JSON response from server',
        'raw': resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body,
      };
    }
  } finally {
    final durationMs = DateTime.now().difference(started).inMilliseconds;
    await AuditService.instance.log(
      event: 'api_call',
      data: {
        'method': 'POST',
        'url': uri.toString(),
        'status': resp?.statusCode,
        'latency_ms': durationMs,
      },
    );
  }
}

// Verify login OTP
Future<Map<String, dynamic>> verifyLoginOtp({
  required String email,
  required String otp,
}) async {
  final token = await _idToken();
  final headers = <String, String>{
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
  final uri = Uri.parse('http://139.162.46.103:8080/auth/verify-login-otp');
  final started = DateTime.now();
  http.Response? resp;
  try {
    resp = await http.post(
      uri,
      headers: headers,
      body: json.encode({'email': email, 'otp': otp}),
    );
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      try {
        final body = json.decode(resp.body);
        final msg =
            (body['message'] ?? body['error'] ?? 'Invalid or expired OTP')
                .toString();
        return {
          'success': false,
          'status': resp.statusCode,
          'message': msg,
          'raw': resp.body,
        };
      } catch (_) {
        return {
          'success': false,
          'status': resp.statusCode,
          'message': 'Invalid or expired OTP',
          'raw': resp.body,
        };
      }
    }
    try {
      return json.decode(resp.body);
    } catch (_) {
      return {
        'success': false,
        'status': resp.statusCode,
        'message': 'Non-JSON response from server',
        'raw': resp.body.length > 200 ? resp.body.substring(0, 200) : resp.body,
      };
    }
  } finally {
    final durationMs = DateTime.now().difference(started).inMilliseconds;
    await AuditService.instance.log(
      event: 'api_call',
      data: {
        'method': 'POST',
        'url': uri.toString(),
        'status': resp?.statusCode,
        'latency_ms': durationMs,
      },
    );
  }
}
