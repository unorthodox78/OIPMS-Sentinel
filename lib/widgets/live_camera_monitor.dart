import 'dart:async';
import 'package:flutter/foundation.dart' show WriteBuffer;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

class LiveCameraMonitor extends StatefulWidget {
  const LiveCameraMonitor({super.key});

  @override
  State<LiveCameraMonitor> createState() => _LiveCameraMonitorState();
}

class _LiveCameraMonitorState extends State<LiveCameraMonitor> {
  CameraController? _controller;
  CameraDescription? _cameraDesc;
  ObjectDetector? _detector;
  bool _initialized = false;
  bool _processing = false;
  bool _permissionGranted = false;
  List<DetectedObject> _objects = const [];
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      setState(() {
        _permissionGranted = false;
      });
      return;
    }
    _permissionGranted = true;

    final cams = await availableCameras();
    if (cams.isEmpty) return;
    _cameraDesc = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cams.first,
    );

    _controller = CameraController(
      _cameraDesc!,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();

    final options = ObjectDetectorOptions(
      classifyObjects: true,
      multipleObjects: true,
      mode: DetectionMode.stream,
    );
    _detector = ObjectDetector(options: options);

    await _controller!.startImageStream(_onFrame);
    if (mounted) setState(() => _initialized = true);
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_processing || _detector == null) return;
    _processing = true;
    try {
      final rotation =
          InputImageRotationValue.fromRawValue(
            _cameraDesc?.sensorOrientation ?? 0,
          ) ??
          InputImageRotation.rotation0deg;
      final format =
          InputImageFormatValue.fromRawValue(image.format.raw) ??
          InputImageFormat.yuv420;

      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(
        image.width.toDouble(),
        image.height.toDouble(),
      );

      final metadata = InputImageMetadata(
        size: imageSize,
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: metadata);

      final results = await _detector!.processImage(inputImage);
      if (mounted) {
        setState(() {
          _objects = results;
          _imageSize = imageSize;
        });
      }
    } catch (_) {
    } finally {
      _processing = false;
    }
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _detector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_permissionGranted) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.camera_alt_outlined, size: 36),
            const SizedBox(height: 8),
            const Text('Camera permission required'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () async {
                await openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
    }
    if (!_initialized || _controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final preview = CameraPreview(_controller!);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.previewSize!.height,
                height: _controller!.value.previewSize!.width,
                child: preview,
              ),
            ),
            if (_imageSize != null)
              CustomPaint(
                painter: _ObjectPainter(
                  objects: _objects,
                  imageSize: _imageSize!,
                  lensDirection: _cameraDesc!.lensDirection,
                ),
                child: const SizedBox.expand(),
              ),
          ],
        );
      },
    );
  }
}

class _ObjectPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final Size imageSize;
  final CameraLensDirection lensDirection;

  _ObjectPainter({
    required this.objects,
    required this.imageSize,
    required this.lensDirection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint boxPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final double scaleX = size.width / imageSize.width;
    final double scaleY = size.height / imageSize.height;

    for (final o in objects) {
      Rect r = Rect.fromLTRB(
        o.boundingBox.left * scaleX,
        o.boundingBox.top * scaleY,
        o.boundingBox.right * scaleX,
        o.boundingBox.bottom * scaleY,
      );
      if (lensDirection == CameraLensDirection.front) {
        r = Rect.fromLTWH(size.width - r.right, r.top, r.width, r.height);
      }
      canvas.drawRect(r, boxPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ObjectPainter oldDelegate) {
    return oldDelegate.objects != objects ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.lensDirection != lensDirection;
  }
}
