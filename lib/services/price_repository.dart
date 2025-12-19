import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:math' as math;

class PriceRepository {
  final String baseUrl;
  final Map<String, String>? headers;
  final String namespace;
  final String setName;

  PriceRepository({
    String? baseUrl,
    this.headers,
    this.namespace = 'oipms',
    this.setName = 'prices',
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
      'schema': {'type': 'string', 'price': 'number', 'updatedAt': 'string'},
    });
    final res = await http.post(uri, headers: hdrs, body: body);
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  Future<bool> upsertPrice({
    required String type,
    required double price,
  }) async {
    final uri = Uri.parse('$baseUrl/api/tables/$setName/records');
    final payload = {
      'database': 'aerospike',
      'primaryKey': type,
      'record': {
        'type': type,
        'price': price,
        'updatedAt': DateTime.now().toIso8601String(),
      },
    };
    final hdrs = {
      'Content-Type': 'application/json',
      if (headers != null) ...headers!,
    };
    final res = await http.post(uri, headers: hdrs, body: json.encode(payload));
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  Future<Map<String, double>> fetchAllPrices() async {
    final uri = Uri.parse(
      '$baseUrl/api/tables/$setName/records?database=aerospike',
    );
    final hdrs = {
      'Content-Type': 'application/json',
      if (headers != null) ...headers!,
    };
    final res = await http.get(uri, headers: hdrs);
    if (res.statusCode < 200 || res.statusCode >= 300) return {};
    final data = json.decode(res.body);
    final records = (data['records'] as List?) ?? const [];
    final Map<String, double> out = {};
    for (final r in records) {
      if (r is Map) {
        final id = (r['id'] ?? r['type'] ?? '').toString();
        final p = r['price'];
        final price = p is num
            ? p.toDouble()
            : double.tryParse(p?.toString() ?? '');
        if (id.isNotEmpty && price != null) out[id] = price;
      }
    }
    return out;
  }

  // Server-Sent Events (SSE) stream for instant price updates with auto-retry
  Stream<Map<String, double>> streamPrices({
    Duration initialBackoff = const Duration(seconds: 2),
    Duration maxBackoff = const Duration(seconds: 30),
  }) {
    final controller = StreamController<Map<String, double>>();

    bool cancelled = false;
    http.Client? client;
    StreamSubscription<String>? sub;

    void connect(Duration prevDelay) async {
      // Exponential backoff with cap
      final nextDelay = Duration(
        milliseconds: math.min(
          maxBackoff.inMilliseconds,
          math.max(initialBackoff.inMilliseconds, prevDelay.inMilliseconds * 2),
        ),
      );

      try {
        client?.close();
        client = http.Client();
        final uri = Uri.parse('$baseUrl/api/prices/stream?ns=$namespace');
        final request = http.Request('GET', uri);
        request.headers.addAll({
          'Accept': 'text/event-stream',
          'Cache-Control': 'no-cache',
          if (headers != null) ...headers!,
        });
        final response = await client!.send(request);
        final lines = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());

        await sub?.cancel();
        sub = lines.listen(
          (line) {
            if (line.startsWith('data:')) {
              final payload = line.substring(5).trim();
              try {
                final data = json.decode(payload);
                final list = (data is List) ? data : const [];
                final out = <String, double>{};
                for (final r in list) {
                  if (r is Map) {
                    final id = (r['id'] ?? r['type'] ?? '').toString();
                    final p = r['price'];
                    final v = p is num
                        ? p.toDouble()
                        : double.tryParse(p?.toString() ?? '');
                    if (id.isNotEmpty && v != null) out[id] = v;
                  }
                }
                if (out.isNotEmpty && !controller.isClosed) controller.add(out);
              } catch (_) {
                // ignore malformed events
              }
            }
          },
          onError: (_) {
            if (cancelled) return;
            Future.delayed(nextDelay, () {
              if (!cancelled) connect(nextDelay);
            });
          },
          onDone: () {
            if (cancelled) return;
            Future.delayed(nextDelay, () {
              if (!cancelled) connect(nextDelay);
            });
          },
          cancelOnError: true,
        );
      } catch (_) {
        if (cancelled) return;
        Future.delayed(prevDelay, () {
          if (!cancelled) connect(prevDelay);
        });
      }
    }

    // Start initial connection with initialBackoff
    connect(initialBackoff);

    controller.onCancel = () async {
      cancelled = true;
      try {
        await sub?.cancel();
      } catch (_) {}
      try {
        client?.close();
      } catch (_) {}
    };

    return controller.stream;
  }
}
