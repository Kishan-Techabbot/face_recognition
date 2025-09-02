import 'package:camera/camera.dart';
import 'package:face_recognition/screens/face_detector/widget/detecter_view.dart';
import 'package:face_recognition/screens/helper/face_detection_helper.dart';

import 'package:face_recognition/utils/face_detector_painter.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectorScreen extends StatefulWidget {
  const FaceDetectorScreen({super.key});

  @override
  State<FaceDetectorScreen> createState() => _FaceDetectorScreenState();
}

class _FaceDetectorScreenState extends State<FaceDetectorScreen> {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: false,
      enableLandmarks: false,
      enableClassification: false,
      minFaceSize: 0.1, // Detect smaller faces (default: 0.1)
      enableTracking: false, // Disable tracking for better detection
      performanceMode: FaceDetectorMode.accurate, // More accurate detection
    ),
  );
  final FaceRecognitionHelper _recognitionHelper =
      FaceRecognitionHelper.instance;

  bool _isBusy = false;
  bool _canProcess = true;
  CustomPaint? _customPaint;
  String? _text;
  CameraLensDirection _cameraLensDirection = CameraLensDirection.front;
  final Map<int, String> _recognizedNames = {}; // Face index -> Name mapping
  List<Face> _currentFaces = [];

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> _initializeModel() async {
    try {
      await _recognitionHelper.loadModel();
      if (mounted) {
        setState(() {
          _text = "Model loaded. Ready to recognize faces!";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _text = "Error loading model: $e";
        });
      }
    }
  }

  @override
  void dispose() {
    _canProcess = false;
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DetectorView(
      title: 'Face Recognition',
      customPaint: _customPaint,
      text: _text,
      onImage: _processImage,
      initialCameraLensDirection: _cameraLensDirection,
      onCameraLensDirectionChanged: (value) => _cameraLensDirection = value,
    );
  }

  Future<void> _processImage(InputImage inputImage) async {
    if (!_canProcess || _isBusy) return;
    _isBusy = true;

    try {
      final faces = await _faceDetector.processImage(inputImage);
      _currentFaces = faces;
      _recognizedNames.clear();

      print("=== FACE DETECTION DEBUG ===");
      for (int i = 0; i < faces.length; i++) {
        print("Face $i bounding box: ${faces[i].boundingBox}");
        print(
          "Face $i head angles: Y=${faces[i].headEulerAngleY}, Z=${faces[i].headEulerAngleZ}",
        );
      }
      print("=== END FACE DEBUG ===");

      print("📷 Image size: ${inputImage.metadata?.size}");
      print("📷 Image rotation: ${inputImage.metadata?.rotation}");
      print("🔍 Total faces detected: ${faces.length}");

      if (faces.isNotEmpty) {
        String statusText = "Detected ${faces.length} face(s)\n";

        // Process each face for recognition
        print("🔍 DETECTED FACES: ${faces.length}");
        for (int i = 0; i < faces.length; i++) {
          try {
            final currentBoundingBox = faces[i].boundingBox;
            print("PROCESSING Face $i with box: $currentBoundingBox");

            // Check if this bounding box is different from previous ones
            for (int j = 0; j < i; j++) {
              if (faces[j].boundingBox == currentBoundingBox) {
                print("WARNING: Face $i has same bounding box as Face $j!");
              }
            }

            final embedding = await _recognitionHelper.getEmbedding(
              inputImage,
              currentBoundingBox,
            );

            if (embedding != null) {
              final recognizedName = await _recognitionHelper.recognizeUser(
                embedding,
              );
              _recognizedNames[i] = recognizedName ?? "Unknown";

              if (recognizedName != null && recognizedName != "Unknown") {
                statusText += "✅ $recognizedName\n";
              } else {
                statusText += "❓ Unknown person\n";
              }
            } else {
              _recognizedNames[i] = "Unknown";
              statusText += "⚠️ Processing failed\n";
            }
          } catch (e) {
            print("❌ Error processing face $i: $e");
            _recognizedNames[i] = "Unknown";
            statusText += "❌ Error processing face\n";
          }
        }

        print("🗺️ FINAL _recognizedNames mapping: $_recognizedNames");

        _text = statusText.trim();
      } else {
        _text = "No faces detected";
        _recognizedNames.clear();
      }

      // Update custom paint with face bounding boxes and names
      if (inputImage.metadata?.size != null &&
          inputImage.metadata?.rotation != null) {
        _customPaint = CustomPaint(
          painter: FaceDetectorPainter(
            _currentFaces,
            inputImage.metadata!.size,
            inputImage.metadata!.rotation,
            _cameraLensDirection,
            recognizedNames: _recognizedNames,
          ),
        );
      }
    } catch (e) {
      _text = "Error processing image: $e";
      print("FaceDetectorScreen Error: $e");
    }

    _isBusy = false;
    if (mounted) setState(() {});
  }
}
