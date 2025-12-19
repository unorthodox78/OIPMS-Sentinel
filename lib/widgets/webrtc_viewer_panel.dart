import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/webrtc_signaling.dart';

class WebRTCViewerPanel extends StatefulWidget {
  final String? configDoc; // Firestore doc id under collection 'config'
  final ValueChanged<String>? onJoined; // callback with roomId when joined
  const WebRTCViewerPanel({super.key, this.configDoc, this.onJoined});

  @override
  State<WebRTCViewerPanel> createState() => _WebRTCViewerPanelState();
}

class _WebRTCViewerPanelState extends State<WebRTCViewerPanel>
    with WidgetsBindingObserver {
  final _roomController = TextEditingController();
  final _remoteRenderer = RTCVideoRenderer();
  final _localRenderer = RTCVideoRenderer();
  WebRTCSignaling? _signaling;
  bool _busy = false;
  List<Map<String, dynamic>> _detections = const [];
  bool _showControls = false;
  bool _joined = false;
  String? _currentRoomId;
  static const _prefsRoomKey = 'last_viewer_room_id';

  String get _scopedPrefsKey => widget.configDoc == null
      ? _prefsRoomKey
      : '${_prefsRoomKey}_${widget.configDoc}';
  bool _reconnectAttempted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    await _remoteRenderer.initialize();
    await _localRenderer.initialize();
    setState(() {});
    await _loadSavedAndAutoJoin();
  }

  Future<void> _loadSavedAndAutoJoin() async {
    // 1) Prefer last successful local roomId first (works even if logged out)
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_scopedPrefsKey);
      if (!_joined && saved != null && saved.isNotEmpty) {
        _roomController.text = saved;
        await _join(roomId: saved, fromAuto: true);
        return;
      }
    } catch (_) {}

    // 2) Try Firestore shared config
    try {
      final docId = widget.configDoc ?? 'camera_room';
      final doc = await FirebaseFirestore.instance
          .collection('config')
          .doc(docId)
          .get();
      final id = (doc.data() ?? const {})['roomId']?.toString();
      if (!_joined && id != null && id.isNotEmpty) {
        _roomController.text = id;
        await _join(roomId: id, fromAuto: true);
        return;
      }
    } catch (_) {}

    // 3) If still not joined, schedule a short retry (helps on tab switches)
    if (mounted && !_joined && !_busy) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && !_joined && !_busy) {
          _loadSavedAndAutoJoin();
        }
      });
    }
  }

  Future<void> _join({String? roomId, bool fromAuto = false}) async {
    if (_busy) return;
    final id = (roomId ?? _roomController.text.trim());
    if (id.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _signaling?.hangUp();
      _signaling = WebRTCSignaling(
        localRenderer: _localRenderer,
        remoteRenderer: _remoteRenderer,
        onDetections: (d) {
          if (!mounted) return;
          setState(() => _detections = d);
        },
      );
      await _signaling!.joinRoom(id);
      if (!mounted) return;
      setState(() {
        _joined = true;
        _currentRoomId = id;
        _showControls = false;
      });
      // Reset reconnect gate on every successful join
      _reconnectAttempted = false;
      try {
        widget.onJoined?.call(id);
      } catch (_) {}
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_scopedPrefsKey, id);
      _schedulePostJoinValidation();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to join room: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _signaling?.hangUp();
      _detections = const [];
      _joined = false;
      _currentRoomId = null;
      _reconnectAttempted = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_scopedPrefsKey);
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _showControls = true;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _signaling?.hangUp();
    _remoteRenderer.dispose();
    _localRenderer.dispose();
    _roomController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Attempt auto-join when coming back to foreground
      // Allow a fresh reconnect cycle after resume
      _reconnectAttempted = false;
      if (!_joined && !_busy) {
        // Schedule microtask to avoid setState during lifecycle callback issues
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_joined && !_busy) {
            _loadSavedAndAutoJoin();
          }
        });
      } else if (_joined) {
        // Validate renderer still has video; if not, attempt one-time rejoin
        _schedulePostJoinValidation();
      }
    }
  }

  void _schedulePostJoinValidation() {
    // If no video arrives shortly after join/resume, perform a one-time rejoin
    if (!mounted) return;
    Future.delayed(const Duration(seconds: 2), () async {
      if (!mounted || !_joined) return;
      final hasVideo =
          !((_remoteRenderer.srcObject?.getVideoTracks().isEmpty) ?? true);
      if (!hasVideo && !_reconnectAttempted && !_busy) {
        _reconnectAttempted = true;
        final room = _currentRoomId;
        try {
          await _signaling?.hangUp();
        } catch (_) {}
        if (room != null && room.isNotEmpty) {
          await _join(roomId: room, fromAuto: true);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() => _showControls = !_showControls);
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RTCVideoView(
              _remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
            CustomPaint(
              painter: _DetectionsOverlay(_detections),
              child: const SizedBox.expand(),
            ),
            if (_showControls)
              Positioned(left: 8, right: 8, top: 8, child: _buildControlsBar()),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsBar() {
    return Material(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: _joined
            ? Row(
                children: [
                  Expanded(
                    child: Text(
                      _currentRoomId == null
                          ? 'Connected'
                          : 'Room: ${_currentRoomId!}',
                      style: const TextStyle(color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _busy ? null : _leave,
                    child: const Text('Leave'),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _roomController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Enter Room ID',
                        hintStyle: TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (v) {
                        if (!_busy) {
                          _join(roomId: v.trim());
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () => _join(roomId: _roomController.text.trim()),
                    child: const Text('Join'),
                  ),
                ],
              ),
      ),
    );
  }
}

class _DetectionsOverlay extends CustomPainter {
  final List<Map<String, dynamic>> detections;
  _DetectionsOverlay(this.detections);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final tp = TextPainter(textDirection: TextDirection.ltr, maxLines: 1);
    for (final d in detections) {
      final l = (d['l'] as num?)?.toDouble() ?? 0;
      final t = (d['t'] as num?)?.toDouble() ?? 0;
      final r = (d['r'] as num?)?.toDouble() ?? 0;
      final b = (d['b'] as num?)?.toDouble() ?? 0;
      final rect = Rect.fromLTRB(
        l * size.width,
        t * size.height,
        r * size.width,
        b * size.height,
      );
      canvas.drawRect(rect, p);
      final label = d['label']?.toString();
      if (label != null && label.isNotEmpty) {
        tp.text = TextSpan(
          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          text: label,
        );
        tp.layout();
        tp.paint(canvas, Offset(rect.left + 2, rect.top + 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionsOverlay oldDelegate) {
    return oldDelegate.detections != detections;
  }
}
