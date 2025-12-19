import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:math' as math;

class SalesRepository {
  final String baseUrl;
  final Map<String, String>? headers;
  final String namespace;
  final String setName;

  SalesRepository({
    String? baseUrl,
    this.headers,
    this.namespace = 'oipms',
    this.setName = 'sales_history',
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
        'type': 'string',
        'qty': 'number',
        'unitPrice': 'number',
        'amount': 'number',
        'cashierId': 'string',
        'timestamp': 'string',
      },
    });
    final res = await http.post(uri, headers: hdrs, body: body);
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  Future<bool> upsertSale({
    String? id,
    required String type,
    required int qty,
    required double unitPrice,
    required double amount,
    String? cashierId,
    DateTime? timestamp,
  }) async {
    final uri = Uri.parse('$baseUrl/api/tables/$setName/records');
    final pk = id ?? 'sale_${DateTime.now().millisecondsSinceEpoch}';
    final record = {
      'type': type,
      'qty': qty,
      'unitPrice': unitPrice,
      'amount': amount,
      if (cashierId != null) 'cashierId': cashierId,
      'timestamp': (timestamp ?? DateTime.now()).toIso8601String(),
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

  Future<List<Map<String, dynamic>>> fetchAllSales() async {
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

  Stream<List<Map<String, dynamic>>> streamSalesHistory({
    Duration initialBackoff = const Duration(seconds: 2),
    Duration maxBackoff = const Duration(seconds: 30),
  }) {
    final controller = StreamController<List<Map<String, dynamic>>>();

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
        final uri = Uri.parse(
          '$baseUrl/api/sales_history/stream?ns=$namespace',
        );
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
                final list = (data is List)
                    ? data
                          .whereType<Map>()
                          .map((e) => Map<String, dynamic>.from(e))
                          .toList()
                    : const <Map<String, dynamic>>[];
                if (!controller.isClosed) controller.add(list);
              } catch (_) {}
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

    // start
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
