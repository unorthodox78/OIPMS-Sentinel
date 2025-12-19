import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

class InventoryItem {
  final String type; // 'Ice Block' or 'Ice Cube'
  final int inStock;
  final int inProduction;

  InventoryItem({
    required this.type,
    required this.inStock,
    required this.inProduction,
  });
}

class InventoryRepository {
  final String baseUrl;
  final Map<String, String>? headers;
  final String namespace;
  final String setName;
  final String path;
  final String updatePath;

  InventoryRepository({
    String? baseUrl,
    this.headers,
    this.namespace = 'oipms',
    this.setName = 'inventory',
    this.path = '/api/inventory',
    this.updatePath = '/api/inventory/update',
  }) : baseUrl = baseUrl ?? 'http://139.162.46.103:8080';

  Future<List<InventoryItem>> fetchInventory() async {
    final uri = Uri.parse(
      '$baseUrl$path',
    ).replace(queryParameters: {'ns': namespace, 'set': setName});
    final res = await http.get(uri, headers: headers);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Inventory fetch failed: ${res.statusCode}');
    }
    final body = json.decode(res.body);
    return _parseInventory(body);
  }

  Stream<List<InventoryItem>> streamInventory({
    Duration initialBackoff = const Duration(seconds: 2),
    Duration maxBackoff = const Duration(seconds: 30),
  }) {
    final controller = StreamController<List<InventoryItem>>();

    bool cancelled = false;
    http.Client? client;
    StreamSubscription<String>? sub;

    void connect(Duration prevDelay) async {
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
          '$baseUrl/api/inventory/stream',
        ).replace(queryParameters: {'ns': namespace});
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
                final items = _parseInventory(data);
                if (!controller.isClosed) controller.add(items);
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

  Future<bool> updateInventory({
    required String type,
    int? inStock,
    int? inProduction,
  }) async {
    final uri = Uri.parse('$baseUrl$updatePath');
    final payload = <String, dynamic>{
      'ns': namespace,
      'set': setName,
      'type': type,
      if (inStock != null) 'inStock': inStock,
      if (inProduction != null) 'inProduction': inProduction,
    };
    final hdrs = {
      'Content-Type': 'application/json',
      if (headers != null) ...headers!,
    };
    final res = await http.post(uri, headers: hdrs, body: json.encode(payload));
    return res.statusCode >= 200 && res.statusCode < 300;
  }

  List<InventoryItem> _normalizeList(List<dynamic> list) {
    final items = <InventoryItem>[];
    for (final e in list) {
      if (e is Map<String, dynamic>) {
        final typeRaw = (e['type'] ?? e['name'] ?? '').toString();
        final type = typeRaw.toLowerCase().contains('cube')
            ? 'Ice Cube'
            : 'Ice Block';
        final inStock = _asInt(e['inStock'] ?? e['stock'] ?? e['quantity']);
        final inProd = _asInt(
          e['inProduction'] ?? e['in_prod'] ?? e['production'],
        );
        items.add(
          InventoryItem(type: type, inStock: inStock, inProduction: inProd),
        );
      }
    }
    return _ensureTwo(items);
  }

  List<InventoryItem> _parseInventory(dynamic jsonBody) {
    if (jsonBody is List) {
      return _normalizeList(jsonBody);
    }
    if (jsonBody is Map<String, dynamic>) {
      // Try keyed objects
      final items = <InventoryItem>[];
      final block = jsonBody['iceBlock'] ?? jsonBody['block'];
      final cube = jsonBody['iceCube'] ?? jsonBody['cube'];
      if (block is Map<String, dynamic>) {
        items.add(
          InventoryItem(
            type: 'Ice Block',
            inStock: _asInt(
              block['inStock'] ?? block['stock'] ?? block['quantity'],
            ),
            inProduction: _asInt(
              block['inProduction'] ?? block['in_prod'] ?? block['production'],
            ),
          ),
        );
      }
      if (cube is Map<String, dynamic>) {
        items.add(
          InventoryItem(
            type: 'Ice Cube',
            inStock: _asInt(
              cube['inStock'] ?? cube['stock'] ?? cube['quantity'],
            ),
            inProduction: _asInt(
              cube['inProduction'] ?? cube['in_prod'] ?? cube['production'],
            ),
          ),
        );
      }
      if (items.isNotEmpty) return _ensureTwo(items);
      // Fallback: try values list
      return _normalizeList(jsonBody.values.toList());
    }
    throw Exception('Unsupported inventory JSON');
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  List<InventoryItem> _ensureTwo(List<InventoryItem> items) {
    if (items.length >= 2) return items.take(2).toList();
    if (items.isEmpty) {
      return [
        InventoryItem(type: 'Ice Block', inStock: 0, inProduction: 0),
        InventoryItem(type: 'Ice Cube', inStock: 0, inProduction: 0),
      ];
    }
    final first = items.first;
    final secondType = first.type == 'Ice Block' ? 'Ice Cube' : 'Ice Block';
    return [
      first,
      InventoryItem(type: secondType, inStock: 0, inProduction: 0),
    ];
  }
}
