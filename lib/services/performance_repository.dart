import 'dart:convert';
import 'package:http/http.dart' as http;

class PerformanceRepository {
  final String baseUrl;
  final Map<String, String>? headers;
  final String namespace;
  final String setSnapshot; // performance_metrics (overwrite)
  final String setTimeseries; // performance_timeseries (append)

  PerformanceRepository({
    String? baseUrl,
    this.headers,
    this.namespace = 'oipms',
    this.setSnapshot = 'performance_metrics',
    this.setTimeseries = 'performance_timeseries',
  }) : baseUrl = baseUrl ?? 'http://139.162.46.103:8080';

  Future<bool> ensureTableMetadata() async {
    // Ensure snapshot table
    bool ok = true;
    try {
      final uri1 = Uri.parse('$baseUrl/api/tables');
      final body1 = json.encode({
        'tableName': setSnapshot,
        'database': 'aerospike',
        'schema': {
          'metric_key': 'string',
          'metric': 'string',
          'value': 'number',
          'site': 'string',
          'deviceId': 'string',
          'context': 'object',
          'updatedAt': 'string',
        },
      });
      final res1 = await http.post(
        uri1,
        headers: {
          'Content-Type': 'application/json',
          if (headers != null) ...headers!,
        },
        body: body1,
      );
      ok = ok && res1.statusCode >= 200 && res1.statusCode < 300;
    } catch (_) {
      ok = false;
    }

    // Ensure timeseries table
    try {
      final uri2 = Uri.parse('$baseUrl/api/tables');
      final body2 = json.encode({
        'tableName': setTimeseries,
        'database': 'aerospike',
        'schema': {
          'metric': 'string',
          'value': 'number',
          'site': 'string',
          'deviceId': 'string',
          'context': 'object',
          'timestamp': 'string',
        },
      });
      final res2 = await http.post(
        uri2,
        headers: {
          'Content-Type': 'application/json',
          if (headers != null) ...headers!,
        },
        body: body2,
      );
      ok = ok && res2.statusCode >= 200 && res2.statusCode < 300;
    } catch (_) {
      ok = false;
    }
    return ok;
  }

  Future<bool> upsertMetric({
    required String metricKey,
    required String metric,
    required num value,
    String? site,
    String? deviceId,
    Map<String, dynamic>? context,
    DateTime? updatedAt,
  }) async {
    final uri = Uri.parse('$baseUrl/api/tables/$setSnapshot/records');
    final record = <String, dynamic>{
      'metric_key': metricKey,
      'metric': metric,
      'value': value,
      if (site != null) 'site': site,
      if (deviceId != null) 'deviceId': deviceId,
      if (context != null) 'context': context,
      'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
    final payload = {
      'database': 'aerospike',
      'primaryKey': metricKey,
      'record': record,
    };
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (headers != null) ...headers!,
      },
      body: json.encode(payload),
    );
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  Future<bool> appendMetricPoint({
    required String metric,
    required num value,
    String? site,
    String? deviceId,
    Map<String, dynamic>? context,
    DateTime? timestamp,
  }) async {
    final uri = Uri.parse('$baseUrl/api/tables/$setTimeseries/records');
    final ts = (timestamp ?? DateTime.now()).toIso8601String();
    final pk = '${metric}_$ts';
    final record = <String, dynamic>{
      'metric': metric,
      'value': value,
      if (site != null) 'site': site,
      if (deviceId != null) 'deviceId': deviceId,
      if (context != null) 'context': context,
      'timestamp': ts,
    };
    final payload = {
      'database': 'aerospike',
      'primaryKey': pk,
      'record': record,
    };
    final res = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        if (headers != null) ...headers!,
      },
      body: json.encode(payload),
    );
    return res.statusCode >= 200 && res.statusCode < 300;
  }
}
