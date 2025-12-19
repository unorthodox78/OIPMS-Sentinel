import 'dart:async';
import 'dart:convert';
import 'dart:io';

class InventoryItemLive {
  final String type;
  final int inStock;
  final int inProduction;
  InventoryItemLive({
    required this.type,
    required this.inStock,
    required this.inProduction,
  });
}

class InventoryLiveStream {
  final String?
  wsUrl; // e.g. ws://139.162.46.103:8080/ws/inventory?ns=oipms&set=inventory
  final String?
  sseUrl; // e.g. http://139.162.46.103:8080/api/inventory/stream?ns=oipms&set=inventory
  final Map<String, String>? headers;

  WebSocket? _ws;
  HttpClient? _httpClient;
  HttpClientRequest? _sseReq;
  HttpClientResponse? _sseResp;
  StreamSubscription? _wsSub;
  StreamSubscription<List<int>>? _sseSub;

  final _controller = StreamController<List<InventoryItemLive>>.broadcast();
  Stream<List<InventoryItemLive>> get stream => _controller.stream;

  bool get isConnected => (_ws != null) || (_sseResp != null);

  InventoryLiveStream({this.wsUrl, this.sseUrl, this.headers});

  Future<void> connect() async {
    // Try WebSocket first if provided
    if (wsUrl != null) {
      try {
        _ws = await WebSocket.connect(
          wsUrl!,
          compression: CompressionOptions.compressionOff,
          headers: headers,
        );
        _wsSub = _ws!.listen(
          _onWsMessage,
          onDone: _onClosed,
          onError: (_) => _onClosed(),
        );
        return;
      } catch (_) {
        await _closeWs();
      }
    }
    // Fallback to SSE if provided
    if (sseUrl != null) {
      try {
        _httpClient = HttpClient();
        _sseReq = await _httpClient!.getUrl(Uri.parse(sseUrl!));
        if (headers != null) {
          headers!.forEach((k, v) => _sseReq!.headers.set(k, v));
        }
        _sseResp = await _sseReq!.close();
        _sseSub = _sseResp!.listen(
          _onSseChunk,
          onDone: _onClosed,
          onError: (_) => _onClosed(),
        );
        return;
      } catch (_) {
        await _closeSse();
      }
    }
  }

  void _onClosed() {
    // Connection closed by remote. Keep controller alive; higher layer may reconnect.
    _ws = null;
    _sseResp = null;
  }

  void _onWsMessage(dynamic data) {
    try {
      final decoded = (data is String)
          ? json.decode(data)
          : json.decode(utf8.decode(data as List<int>));
      final items = _parseInventory(decoded);
      if (!_controller.isClosed) _controller.add(items);
    } catch (_) {}
  }

  // Very small SSE parser: look for lines starting with "data:"
  void _onSseChunk(List<int> bytes) {
    final text = utf8.decode(bytes);
    for (final line in const LineSplitter().convert(text)) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('data:')) {
        final jsonPart = trimmed.substring(5).trim();
        try {
          final decoded = json.decode(jsonPart);
          final items = _parseInventory(decoded);
          if (!_controller.isClosed) _controller.add(items);
        } catch (_) {}
      }
    }
  }

  List<InventoryItemLive> _parseInventory(dynamic jsonBody) {
    List<InventoryItemLive> list = [];
    if (jsonBody is List) {
      for (final e in jsonBody) {
        if (e is Map<String, dynamic>) {
          final typeRaw = (e['type'] ?? e['name'] ?? '').toString();
          final type = typeRaw.toLowerCase().contains('cube')
              ? 'Ice Cube'
              : 'Ice Block';
          final inStock = _asInt(e['inStock'] ?? e['stock'] ?? e['quantity']);
          final inProd = _asInt(
            e['inProduction'] ?? e['in_prod'] ?? e['production'],
          );
          list.add(
            InventoryItemLive(
              type: type,
              inStock: inStock,
              inProduction: inProd,
            ),
          );
        }
      }
    } else if (jsonBody is Map<String, dynamic>) {
      final block = jsonBody['iceBlock'] ?? jsonBody['block'];
      final cube = jsonBody['iceCube'] ?? jsonBody['cube'];
      if (block is Map<String, dynamic>) {
        list.add(
          InventoryItemLive(
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
        list.add(
          InventoryItemLive(
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
    }
    if (list.isEmpty) {
      return [
        InventoryItemLive(type: 'Ice Block', inStock: 0, inProduction: 0),
        InventoryItemLive(type: 'Ice Cube', inStock: 0, inProduction: 0),
      ];
    }
    if (list.length == 1) {
      final first = list.first;
      list.add(
        InventoryItemLive(
          type: first.type == 'Ice Block' ? 'Ice Cube' : 'Ice Block',
          inStock: 0,
          inProduction: 0,
        ),
      );
    }
    return list.take(2).toList();
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  Future<void> _closeWs() async {
    await _wsSub?.cancel();
    await _ws?.close();
    _wsSub = null;
    _ws = null;
  }

  Future<void> _closeSse() async {
    await _sseSub?.cancel();
    _sseSub = null;
    _sseResp = null;
    await _sseReq?.close();
    _sseReq = null;
    _httpClient?.close(force: true);
    _httpClient = null;
  }

  Future<void> dispose() async {
    await _closeWs();
    await _closeSse();
    await _controller.close();
  }
}
