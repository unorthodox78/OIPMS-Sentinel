import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/camera_publisher_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Use native google-services.json for the camera flavor
  await Firebase.initializeApp();
  runApp(const OipCameraApp());
}

class OipCameraApp extends StatelessWidget {
  const OipCameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OIP Camera',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const CameraPublisherScreen(),
    );
  }
}
