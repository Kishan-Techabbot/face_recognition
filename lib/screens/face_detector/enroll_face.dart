import 'package:camera/camera.dart';
import 'package:face_recognition/screens/face_detector/widget/detecter_view.dart';
import 'package:face_recognition/screens/helper/face_detection_helper.dart';
import 'package:face_recognition/utils/face_detector_painter.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class EnrollFaceScreen extends StatefulWidget {
  final String userName;
  const EnrollFaceScreen({super.key, required this.userName});

  @override
  State<EnrollFaceScreen> createState() => _EnrollFaceScreenState();
}

class _EnrollFaceScreenState extends State<EnrollFaceScreen> {
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
  late final FaceRecognitionHelper _recognitionHelper;

  bool _isBusy = false;
  bool _isEnrollmentComplete = false;
  String? _status;
  CustomPaint? _customPaint;
  CameraLensDirection _cameraLensDirection = CameraLensDirection.front;

  @override
  void initState() {
    super.initState();
    _recognitionHelper = FaceRecognitionHelper.instance;
    _initializeModel();
  }

  Future<void> _initializeModel() async {
    try {
      await _recognitionHelper.loadModel();
      if (mounted) {
        setState(() {
          _status = "Model loaded. Position your face in the camera to enroll.";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = "Error loading model: $e";
        });
      }
    }
  }

  @override
  void dispose() {
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isEnrollmentComplete
          ? _buildSuccessScreen()
          : DetectorView(
              title: 'Enroll Face: ${widget.userName}',
              customPaint: _customPaint,
              text: _status,
              onImage: _processImage,
              initialCameraLensDirection: _cameraLensDirection,
              onCameraLensDirectionChanged: (value) =>
                  _cameraLensDirection = value,
            ),
    );
  }

  Widget _buildSuccessScreen() {
    return Scaffold(
      appBar: AppBar(title: Text("Enrollment Complete")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 80),
              SizedBox(height: 24),
              Text(
                _status ?? "Enrollment completed successfully!",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text("Return to Dashboard"),
              ),
              SizedBox(height: 16),
              TextButton(
                onPressed: _resetEnrollment,
                child: Text("Enroll Another Face"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _resetEnrollment() {
    setState(() {
      _isEnrollmentComplete = false;
      _isBusy = false;
      _status = "Position your face in the camera to enroll.";
      _customPaint = null;
    });
  }

  Future<void> _processImage(InputImage inputImage) async {
    if (_isBusy || _isEnrollmentComplete) return;
    _isBusy = true;

    try {
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        if (faces.length > 1) {
          setState(() {
            _status =
                "Multiple faces detected. Please ensure only one face is visible.";
          });
          _isBusy = false;
          return;
        }

        final face = faces.first;

        // Check face quality (size, position)
        if (_isFaceQualityGood(face, inputImage.metadata?.size)) {
          setState(() {
            _status = "Good face detected! Processing enrollment...";
          });

          // Extract embedding
          final embedding = await _recognitionHelper.getEmbedding(
            inputImage,
            face.boundingBox,
          );

          print(
            "===============================\nEnroll: $embedding\n===========================",
          );

          if (embedding != null) {
            // Save with duplicate prevention
            final result = await _recognitionHelper.saveUserEmbedding(
              widget.userName,
              embedding,
            );

            if (mounted) {
              setState(() {
                _status = result;
                _isEnrollmentComplete = result.contains("successfully");
              });
            }
          } else {
            if (mounted) {
              setState(() {
                _status =
                    "Could not extract face features. Please try again with better lighting.";
              });
            }
          }
        } else {
          setState(() {
            _status =
                "Please position your face closer to the camera and ensure good lighting.";
          });
        }

        // Update face visualization
        if (inputImage.metadata?.size != null &&
            inputImage.metadata?.rotation != null) {
          _customPaint = CustomPaint(
            painter: FaceDetectorPainter(
              faces,
              inputImage.metadata!.size,
              inputImage.metadata!.rotation,
              _cameraLensDirection,
            ),
          );
        }
      } else {
        setState(() {
          _status =
              "No face detected. Please position your face in front of the camera.";
          _customPaint = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = "Error processing image: $e";
        });
      }
      print("EnrollFaceScreen Error: $e");
    }

    _isBusy = false;
  }

  bool _isFaceQualityGood(Face face, Size? imageSize) {
    if (imageSize == null) return false;

    // Check if face is large enough (at least 20% of image width)
    final faceWidth = face.boundingBox.width;
    final minWidth = imageSize.width * 0.15;

    if (faceWidth < minWidth) {
      return false;
    }

    // Check if face is reasonably centered
    final faceCenterX = face.boundingBox.left + face.boundingBox.width / 2;
    final imageCenterX = imageSize.width / 2;
    final maxOffset = imageSize.width * 0.3;

    if ((faceCenterX - imageCenterX).abs() > maxOffset) {
      return false;
    }

    return true;
  }
}
