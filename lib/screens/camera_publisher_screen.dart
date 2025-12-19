import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:camera/camera.dart' as cam;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show WriteBuffer;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/camera_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/webrtc_signaling.dart';

class CameraPublisherScreen extends StatefulWidget {
  const CameraPublisherScreen({super.key});

  @override
  State<CameraPublisherScreen> createState() => _CameraPublisherScreenState();
}

class _CameraPublisherScreenState extends State<CameraPublisherScreen> {
  late final RTCVideoRenderer _localRenderer;
  late final RTCVideoRenderer _remoteRenderer;
  WebRTCSignaling? _signaling;
  String? _roomId;
  bool _busy = false;

  // ML Kit + camera(image stream for detection only)
  cam.CameraController? _camController;
  ObjectDetector? _detector;
  bool _detecting = false;
  Size? _imgSize;
  List<DetectedObject> _objects = const [];
  Timer? _throttle;
  static const _prefsPubRoomKey = 'publisher_room_id';

  // Battery + backend publishing
  final Battery _battery = Battery();
  Timer? _batteryTimer;
  CameraRepository? _cameraRepo;
  String? _deviceId;
  // Target viewer config doc (entrance/exit)
  String _cameraTarget = 'entrance'; // 'entrance' | 'exit'
  String get _targetDoc =>
      _cameraTarget == 'exit' ? 'camera_room_exit' : 'camera_room_entrance';
  static const _prefsTargetKey = 'camera_target';

  @override
  void initState() {
    super.initState();
    _localRenderer = RTCVideoRenderer();
    _remoteRenderer = RTCVideoRenderer();
    _init();
  }

  Future<void> _setupCameraStatusPublisher() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _deviceId = prefs.getString('camera_device_id');
      if (_deviceId == null || _deviceId!.isEmpty) {
        // Prefer room id if present; else generate simple id
        final rid = prefs.getString(_prefsPubRoomKey);
        _deviceId = (rid != null && rid.isNotEmpty)
            ? 'cam:$rid'
            : 'cam:${DateTime.now().millisecondsSinceEpoch}';
        await prefs.setString('camera_device_id', _deviceId!);
      }

      String? token;
      try {
        token = await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {}
      _cameraRepo = CameraRepository(
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
      );
      await _cameraRepo!.ensureTableMetadata();

      // Start periodic battery publish
      _batteryTimer?.cancel();
      _batteryTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
        try {
          final level = await _battery.batteryLevel; // 0..100
          final id = _deviceId ?? 'cam:unknown';
          await _cameraRepo!.upsertStatus(deviceId: id, battery: level);
        } catch (_) {}
      });
    } catch (_) {}
  }

  Future<void> _init() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    // Load preferred target (entrance/exit)
    try {
      final prefs = await SharedPreferences.getInstance();
      final t = prefs.getString(_prefsTargetKey);
      if (t == 'entrance' || t == 'exit') {
        _cameraTarget = t!;
      }
    } catch (_) {}

    final permissions = await [
      Permission.camera,
      Permission.microphone,
    ].request();
    if (!permissions.values.every((s) => s.isGranted)) {
      setState(() {});
      return;
    }

    _signaling = WebRTCSignaling(
      localRenderer: _localRenderer,
      remoteRenderer: _remoteRenderer,
      persistRoom: true,
    );

    // Prepare ML Kit
    _detector = ObjectDetector(
      options: ObjectDetectorOptions(
        mode: DetectionMode.stream,
        multipleObjects: true,
        classifyObjects: true,
      ),
    );

    // Start a separate camera for ML detection (low res)
    final cameras = await cam.availableCameras();
    final back = cameras.firstWhere(
      (c) => c.lensDirection == cam.CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    _camController = cam.CameraController(
      back,
      cam.ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: cam.ImageFormatGroup.yuv420,
    );
    await _camController!.initialize();
    await _camController!.startImageStream(_onImage);

    setState(() {});
    // Auto-start or resume previous room using saved ID
    await _autoStartFromSavedRoom();

    // Prepare camera status publisher to Aerospike (battery%)
    await _setupCameraStatusPublisher();
  }

  Future<void> _autoStartFromSavedRoom() async {
    if (_signaling == null) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsPubRoomKey);
    setState(() => _busy = true);
    try {
      // Ensure any prior PC is closed without deleting the room
      await _signaling!.hangUp();
      final id = await _signaling!.createOrReuseRoom(roomId: saved);
      if (!mounted) return;
      setState(() => _roomId = id);
      await prefs.setString(_prefsPubRoomKey, id);
      try {
        await FirebaseFirestore.instance
            .collection('config')
            .doc(_targetDoc)
            .set({'roomId': id}, SetOptions(merge: true));
      } catch (_) {}
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onImage(cam.CameraImage img) async {
    if (_detecting || _detector == null) return;
    // throttle to ~6 fps
    if (_throttle?.isActive == true) return;
    _throttle = Timer(const Duration(milliseconds: 160), () {});

    _detecting = true;
    try {
      final rotation =
          InputImageRotationValue.fromRawValue(
            _camController?.description.sensorOrientation ?? 0,
          ) ??
          InputImageRotation.rotation0deg;
      final format =
          InputImageFormatValue.fromRawValue(img.format.raw) ??
          InputImageFormat.yuv420;

      final WriteBuffer allBytes = WriteBuffer();
      for (final plane in img.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final imageSize = Size(img.width.toDouble(), img.height.toDouble());

      final metadata = InputImageMetadata(
        size: imageSize,
        rotation: rotation,
        format: format,
        bytesPerRow: img.planes.first.bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: metadata);

      final results = await _detector!.processImage(inputImage);
      if (!mounted) return;
      setState(() {
        _objects = results;
        _imgSize = imageSize;
      });

      // Send normalized detections over data channel
      if (_signaling != null && _objects.isNotEmpty && _imgSize != null) {
        final w = _imgSize!.width;
        final h = _imgSize!.height;
        final payload = _objects.map((DetectedObject o) {
          String? label;
          double? score;
          if (o.labels.isNotEmpty) {
            label = o.labels.first.text;
            score = o.labels.first.confidence;
          }
          return {
            'l': o.boundingBox.left / w,
            't': o.boundingBox.top / h,
            'r': o.boundingBox.right / w,
            'b': o.boundingBox.bottom / h,
            'label': label,
            'score': score,
          };
        }).toList();
        _signaling!.sendDetections(payload);
      }
    } catch (_) {
    } finally {
      _detecting = false;
    }
  }

  @override
  void dispose() {
    _batteryTimer?.cancel();
    _throttle?.cancel();
    _camController?.dispose();
    _detector?.close();
    _signaling?.hangUp();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    if (_signaling == null) return;
    setState(() => _busy = true);
    try {
      // Close current connection (do not delete room due to persistRoom=true)
      await _signaling!.hangUp();
      // Create a brand-new room ID and save it, so viewers must join the new ID
      final id = await _signaling!.createOrReuseRoom();
      setState(() => _roomId = id);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsPubRoomKey, id);
      try {
        await FirebaseFirestore.instance
            .collection('config')
            .doc(_targetDoc)
            .set({'roomId': id}, SetOptions(merge: true));
      } catch (_) {}
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OIP Camera Publisher')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: RTCVideoView(
                      _localRenderer,
                      mirror: false,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                  if (_imgSize != null)
                    CustomPaint(
                      painter: _DetectionsPainter(
                        objects: _objects,
                        imageSize: _imgSize!,
                      ),
                      child: const SizedBox.expand(),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Camera Target:', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _cameraTarget,
                  items: const [
                    DropdownMenuItem(
                      value: 'entrance',
                      child: Text('Entrance'),
                    ),
                    DropdownMenuItem(value: 'exit', child: Text('Exit')),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() => _cameraTarget = v);
                    try {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString(_prefsTargetKey, v);
                    } catch (_) {}
                    // Republish current room to the selected target doc
                    if (_roomId != null && _roomId!.isNotEmpty) {
                      try {
                        await FirebaseFirestore.instance
                            .collection('config')
                            .doc(_targetDoc)
                            .set({'roomId': _roomId}, SetOptions(merge: true));
                      } catch (_) {}
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_roomId != null) ...[
              SelectableText(
                'Room ID: ${_roomId!}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Share this code with the dashboard device to view the stream.',
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _busy ? null : _createRoom,
              icon: const Icon(Icons.video_call),
              label: Text(_roomId == null ? 'Create Room' : 'Recreate Room'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetectionsPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final Size imageSize;

  _DetectionsPainter({required this.objects, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    for (final o in objects) {
      final rect = Rect.fromLTRB(
        o.boundingBox.left * scaleX,
        o.boundingBox.top * scaleY,
        o.boundingBox.right * scaleX,
        o.boundingBox.bottom * scaleY,
      );
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionsPainter oldDelegate) {
    return oldDelegate.objects != objects || oldDelegate.imageSize != imageSize;
  }
}
