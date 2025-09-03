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

  InputImage? _lastInputImage;
  Face? _lastDetectedFace;
  bool _isFaceReady = false; // enable capture button

  bool _isBusy = false;
  bool _isEnrollmentComplete = false;
  String? _status;
  String? _resultMessage;
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
          : Stack(
              children: [
                DetectorView(
                  title: 'Enroll Face: ${widget.userName}',
                  customPaint: _customPaint,
                  text: _status,
                  onImage: _processImage,
                  initialCameraLensDirection: _cameraLensDirection,
                  onCameraLensDirectionChanged: (value) =>
                      _cameraLensDirection = value,
                ),
                if (!_isEnrollmentComplete)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: FloatingActionButton(
                        shape: CircleBorder(),
                        onPressed: _isFaceReady ? _enrollFace : null,
                        backgroundColor: _isFaceReady
                            ? Colors.white
                            : Colors.grey,
                      ),
                    ),
                  ),
              ],
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
              Icon(
                _resultMessage?.contains("successfully") == true
                    ? Icons.check_circle
                    : Icons.error,
                color: _resultMessage?.contains("successfully") == true
                    ? Colors.green
                    : Colors.red,
                size: 80,
              ),
              SizedBox(height: 24),
              Text(
                _resultMessage ?? "Enrollment completed.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text("Return to Dashboard"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _processImage(InputImage inputImage) async {
    if (_isBusy || _isEnrollmentComplete) return;
    _isBusy = true;

    try {
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        if (faces.length == 1 &&
            _isFaceQualityGood(faces.first, inputImage.metadata?.size)) {
          setState(() {
            _status = "Face ready! Tap the button to enroll.";
            _lastDetectedFace = faces.first;
            _lastInputImage = inputImage;
            _isFaceReady = true;
          });
        } else {
          setState(() {
            _status = "Please keep only one clear face in frame.";
            _isFaceReady = false;
          });
        }

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
          _status = "No face detected.";
          _isFaceReady = false;
          _lastDetectedFace = null;
          _lastInputImage = null;
          _customPaint = null;
        });
      }
    } catch (e) {
      setState(() => _status = "Error processing image: $e");
    }

    _isBusy = false;
  }

  Future<void> _enrollFace() async {
    if (_lastDetectedFace == null || _lastInputImage == null) return;

    setState(() => _status = "Processing enrollment...");

    final embedding = await _recognitionHelper.getEmbedding(
      _lastInputImage!,
      _lastDetectedFace!.boundingBox,
    );

    if (embedding != null) {
      final result = await _recognitionHelper.saveUserEmbedding(
        widget.userName,
        embedding,
      );

      setState(() {
        _resultMessage = result; // <-- store final message here
        _isEnrollmentComplete = result.contains("successfully");
      });
    } else {
      setState(() {
        _resultMessage = "Could not extract features. Try again.";
        _isEnrollmentComplete = true; // Still show success screen with error
      });
    }
  }

  bool _isFaceQualityGood(Face face, Size? imageSize) {
    if (imageSize == null) return false;
    final faceArea = face.boundingBox.width * face.boundingBox.height;
    final imageArea = imageSize.width * imageSize.height;

    final areaRatio = faceArea / imageArea;
    return areaRatio > 0.05 && areaRatio < 0.6; // not too small, not too big
  }
}
