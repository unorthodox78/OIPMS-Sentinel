import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class CameraRepository {
  final String baseUrl;
  final Map<String, String>? headers;
  final String namespace;
  final String setName;

  CameraRepository({
    String? baseUrl,
    this.headers,
    this.namespace = 'oipms',
    this.setName = 'camera_status',
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
        'deviceId': 'string',
        'battery': 'number',
        'updatedAt': 'string',
      },
    });
    final res = await http.post(uri, headers: hdrs, body: body);
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  Future<bool> upsertStatus({
    required String deviceId,
    required int battery,
    DateTime? updatedAt,
  }) async {
    final uri = Uri.parse('$baseUrl/api/tables/$setName/records');
    final pk = deviceId; // one row per device
    final record = <String, dynamic>{
      'deviceId': deviceId,
      'battery': battery,
      'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
    final payload = {
      'database': 'aerospike',
      'primaryKey': pk,
      'record': record,
    };
    final hdrs = {
      'Content-Type': 'application/json',
      if (headers != null) ...headers!,
    };
    final res = await http.post(uri, headers: hdrs, body: json.encode(payload));
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  Future<List<Map<String, dynamic>>> fetchAllStatus() async {
    final uri = Uri.parse(
      '$baseUrl/api/tables/$setName/records?database=aerospike',
    );
    final hdrs = {
      'Content-Type': 'application/json',
      if (headers != null) ...headers!,
    };
    final res = await http.get(uri, headers: hdrs);
    if (res.statusCode < 200 || res.statusCode >= 300) return const [];
    final data = json.decode(res.body);
    final records = (data['records'] as List?) ?? const [];
    return records
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<int?> fetchLatestBatteryPercent() async {
    final list = await fetchAllStatus();
    if (list.isEmpty) return null;
    // Pick newest by updatedAt if present
    list.sort(
      (a, b) => (b['updatedAt'] ?? '').toString().compareTo(
        (a['updatedAt'] ?? '').toString(),
      ),
    );
    final top = list.first;
    final b = top['battery'];
    if (b is num) return b.toInt();
    return int.tryParse(b?.toString() ?? '');
  }
}
