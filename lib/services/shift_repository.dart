import 'dart:convert';
import 'package:http/http.dart' as http;

class ShiftRepository {
  final String baseUrl;
  final Map<String, String>? headers;
  final String namespace;
  final String setName;

  ShiftRepository({
    String? baseUrl,
    this.headers,
    this.namespace = 'oipms',
    this.setName = 'shifts',
  }) : baseUrl = baseUrl ?? 'http://139.162.46.103:8080';

  Future<bool> ensureTableMetadata() async {
    final uri = Uri.parse('$baseUrl/api/tables');
    final hdrs = {
      'Content-Type': 'application/json',
      if (headers != null) ...headers!,
    };
    final body = json.encode({
      'tableName': setName,
      'database': 'aerospike',
      'schema': {
        'shiftName': 'string',
        'time': 'string',
        'count': 'string',
        'expected': 'number',
        'actual': 'number',
        'presentStaff': 'array',
        'color': 'number',
        'gradient': 'array',
        'updatedAt': 'string',
      },
    });
    final res = await http.post(uri, headers: hdrs, body: body);
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  Future<bool> upsertShift({
    required Map<String, dynamic> record,
    required String primaryKey,
  }) async {
    final uri = Uri.parse('$baseUrl/api/tables/$setName/records');
    final payload = {
      'database': 'aerospike',
      'record': record,
      'primaryKey': primaryKey,
    };
    final hdrs = {
      'Content-Type': 'application/json',
      if (headers != null) ...headers!,
    };
    final res = await http.post(uri, headers: hdrs, body: json.encode(payload));
    return res.statusCode >= 200 && res.statusCode < 300;
  }
}
