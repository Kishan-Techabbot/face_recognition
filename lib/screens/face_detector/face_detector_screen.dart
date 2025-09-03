import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:face_recognition/screens/face_detector/widget/detecter_view.dart';
import 'package:face_recognition/screens/helper/face_detection_helper.dart';
import 'package:face_recognition/db/database_services.dart';
import 'package:face_recognition/utils/enhance_face_detector_painter.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

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
      minFaceSize: 0.1,
      enableTracking: false,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );
  final FaceRecognitionHelper _recognitionHelper =
      FaceRecognitionHelper.instance;

  bool _isBusy = false;
  bool _canProcess = true;
  CustomPaint? _customPaint;
  String? _text;
  CameraLensDirection _cameraLensDirection = CameraLensDirection.front;
  final Map<int, String> _recognizedNames = {};
  List<Face> _currentFaces = [];
  final Map<int, Map<String, dynamic>> _recognitionDetails = {};

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> _initializeModel() async {
    try {
      await _recognitionHelper.loadModel();
      final stats = await FaceDatabaseService.instance.getStatistics();

      if (mounted) {
        setState(() {
          _text =
              "Model loaded! Ready to recognize faces!\n"
              "Database: ${stats['total_users']} users, ${stats['total_embeddings']} embeddings";
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
      _recognitionDetails.clear();

      if (faces.isNotEmpty) {
        String statusText = "Detected ${faces.length} face(s)\n";

        // Step 1: Get embeddings for all faces
        List<Map<String, dynamic>?> facesEmbeddings = [];
        for (var face in faces) {
          final embeddingData = await _recognitionHelper.getEmbeddingWithAngle(
            inputImage,
            face,
          );
          facesEmbeddings.add(embeddingData);
        }

        // Step 2: Prepare user distances per face
        final users = await FaceDatabaseService.instance.getAllUsers();
        Map<int, Map<String, double>> faceToUserDistances = {};

        for (int i = 0; i < faces.length; i++) {
          final embeddingData = facesEmbeddings[i];
          if (embeddingData == null) continue;

          final embedding = embeddingData['embedding'] as List<double>;
          faceToUserDistances[i] = {};

          for (var user in users) {
            final userName = user['name'] as String;
            final userEmbeddings = await FaceDatabaseService.instance
                .getUserEmbeddings(userName);

            double minDist = double.infinity;
            for (var embeddingRecord in userEmbeddings) {
              final storedEmbedding = _recognitionHelper.bytesToDoubleList(
                embeddingRecord['embedding'] as Uint8List,
              );
              final dist = _recognitionHelper.euclideanDistance(
                embedding,
                storedEmbedding,
              );
              if (dist < minDist) minDist = dist;
            }
            faceToUserDistances[i]![userName] = minDist;
          }
        }

        // Step 3: Assign best matches uniquely
        Set<String> assignedUsers = {};
        for (int i = 0; i < faces.length; i++) {
          final embeddingData = facesEmbeddings[i];
          if (embeddingData == null) {
            _recognizedNames[i] = "Unknown";
            _recognitionDetails[i] = {
              'name': "Unknown",
              'yaw': 0.0,
              'pitch': 0.0,
              'roll': 0.0,
              'confidence': 'Low',
            };
            statusText += "⚠️ Processing failed\n";
            continue;
          }

          final yaw = embeddingData['yaw'] as double;
          final pitch = embeddingData['pitch'] as double;
          final roll = embeddingData['roll'] as double;

          String? bestUser;
          double bestDist = double.infinity;

          faceToUserDistances[i]!.forEach((userName, dist) {
            if (dist < bestDist && !assignedUsers.contains(userName)) {
              bestDist = dist;
              bestUser = userName;
            }
          });

          if (bestDist < FaceRecognitionHelper.recognitionThreshold &&
              bestUser != null) {
            assignedUsers.add(bestUser!);
            _recognizedNames[i] = bestUser!;
            _recognitionDetails[i] = {
              'name': bestUser,
              'yaw': yaw,
              'pitch': pitch,
              'roll': roll,
              'confidence': 'High',
            };

            final userInfo = await _recognitionHelper.getUserInfo(bestUser!);
            final embeddingCount = userInfo?['embedding_count'] ?? 0;
            statusText += "✅ $bestUser ($embeddingCount poses)\n";
            statusText += "📐 ${_formatAngle(yaw)}, ${_formatPitch(pitch)}\n";
          } else {
            _recognizedNames[i] = "Unknown";
            _recognitionDetails[i] = {
              'name': "Unknown",
              'yaw': yaw,
              'pitch': pitch,
              'roll': roll,
              'confidence': 'Medium',
            };
            statusText += "❓ Unknown person\n";
            statusText += "📐 ${_formatAngle(yaw)}, ${_formatPitch(pitch)}\n";
          }
        }

        _text = statusText.trim();
      } else {
        _text = "No faces detected";
        _recognizedNames.clear();
        _recognitionDetails.clear();
      }

      if (inputImage.metadata?.size != null &&
          inputImage.metadata?.rotation != null) {
        _customPaint = CustomPaint(
          painter: EnhancedFaceDetectorPainter(
            _currentFaces,
            inputImage.metadata!.size,
            inputImage.metadata!.rotation,
            _cameraLensDirection,
            recognizedNames: _recognizedNames,
            recognitionDetails: _recognitionDetails,
          ),
        );
      }
    } catch (e) {
      _text = "Error processing image: $e";
    }

    _isBusy = false;
    if (mounted) setState(() {});
  }

  String _formatAngle(double yaw) {
    if (yaw > 15) return "Left turn";
    if (yaw < -15) return "Right turn";
    return "Straight";
  }

  String _formatPitch(double pitch) {
    if (pitch < -15) return "Looking up";
    if (pitch > 15) return "Looking down";
    return "Level";
  }
}
