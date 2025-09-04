import 'package:camera/camera.dart';
import 'package:face_recognition/screens/face_detector/widget/detecter_view.dart';
import 'package:face_recognition/screens/helper/face_detection_helper.dart';
import 'package:face_recognition/utils/face_detector_painter.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

enum EnrollmentStep {
  straight,
  lookLeft,
  lookRight,
  lookUp,
  lookDown,
  completed,
}

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
      minFaceSize: 0.1,
      enableTracking: false,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );
  late final FaceRecognitionHelper _recognitionHelper;

  InputImage? _lastInputImage;
  Face? _lastDetectedFace;
  bool _isFaceReady = false;
  bool _isBusy = false;
  bool _isProcessing = false;
  String? _status;
  CustomPaint? _customPaint;
  CameraLensDirection _cameraLensDirection = CameraLensDirection.front;

  // Multi-angle enrollment state
  EnrollmentStep _currentStep = EnrollmentStep.straight;
  final List<String> _enrollmentResults = [];
  int _successfulEnrollments = 0;
  bool _isEnrollmentComplete = false;

  // Auto-capture settings
  static const int samplesPerStep = 4; // 3 steps × 4 = 12 (tweak as you like)
  static const int autoCaptureHoldMs = 350; // must stay "ready" for this long
  int _capturedThisStep = 0;
  DateTime? _readySince;
  DateTime _lastAutoShot = DateTime.fromMillisecondsSinceEpoch(0);
  static const int autoCaptureCooldownMs = 600;

  // Track which steps are already captured (for auto mode)
  final Set<EnrollmentStep> _capturedAngles = {};

  // Target total embeddings to collect (you asked for ~15-20; using 15 here)
  static const int targetTotalEmbeddings = 15;

  // Step configuration
  final Map<EnrollmentStep, Map<String, dynamic>> _stepConfig = {
    EnrollmentStep.straight: {
      'title': 'Look Straight',
      'instruction': 'Look directly at the camera with your face centered',
      'color': Colors.blue,
      'icon': Icons.face,
      'yawRange': [-15, 15],
      'pitchRange': [-15, 15],
    },
    EnrollmentStep.lookLeft: {
      'title': 'Turn Left',
      'instruction': 'Turn your head slightly to the left (your left)',
      'color': Colors.orange,
      'icon': Icons.keyboard_arrow_left,
      'yawRange': [15, 45],
      'pitchRange': [-15, 15],
    },
    EnrollmentStep.lookRight: {
      'title': 'Turn Right',
      'instruction': 'Turn your head slightly to the right (your right)',
      'color': Colors.green,
      'icon': Icons.keyboard_arrow_right,
      'yawRange': [-45, -15],
      'pitchRange': [-15, 15],
    },
    EnrollmentStep.lookUp: {
      'title': 'Look Up',
      'instruction': 'Tilt your head slightly upward',
      'color': Colors.purple,
      'icon': Icons.keyboard_arrow_up,
      'yawRange': [-15, 15],
      'pitchRange': [-45, -15],
    },
    EnrollmentStep.lookDown: {
      'title': 'Look Down',
      'instruction': 'Tilt your head slightly downward',
      'color': Colors.red,
      'icon': Icons.keyboard_arrow_down,
      'yawRange': [-15, 15],
      'pitchRange': [15, 45],
    },
  };

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
          _status = _getStepInstruction();
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

  String _getStepInstruction() {
    final config = _stepConfig[_currentStep]!;
    return "${config['title']}\n${config['instruction']}";
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
          ? _buildCompletionScreen()
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
                _buildProgressIndicator(),
                // if (!_isEnrollmentComplete) _buildCaptureButton(),
                // _buildStepIndicator(),
              ],
            ),
    );
  }

  Widget _buildProgressIndicator() {
    return Positioned(
      top: 100,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              'Step ${_currentStep.index + 1} of ${_stepConfig.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (_currentStep.index + 1) / _stepConfig.length,
              backgroundColor: Colors.grey[700],
              valueColor: AlwaysStoppedAnimation<Color>(
                _stepConfig[_currentStep]!['color'],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enrolled: $_successfulEnrollments',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // Widget _buildStepIndicator() {
  //   return Positioned(
  //     top: 200,
  //     left: 16,
  //     right: 16,
  //     child: Container(
  //       padding: const EdgeInsets.all(16),
  //       decoration: BoxDecoration(
  //         color: _stepConfig[_currentStep]!['color'].withOpacity(0.9),
  //         borderRadius: BorderRadius.circular(12),
  //       ),
  //       child: Row(
  //         mainAxisAlignment: MainAxisAlignment.center,
  //         children: [
  //           Icon(
  //             _stepConfig[_currentStep]!['icon'],
  //             color: Colors.white,
  //             size: 32,
  //           ),
  //           const SizedBox(width: 12),
  //           Expanded(
  //             child: Text(
  //               _stepConfig[_currentStep]!['title'],
  //               style: const TextStyle(
  //                 color: Colors.white,
  //                 fontSize: 18,
  //                 fontWeight: FontWeight.bold,
  //               ),
  //               textAlign: TextAlign.center,
  //             ),
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  // Widget _buildCaptureButton() {
  //   return Align(
  //     alignment: Alignment.bottomCenter,
  //     child: Container(
  //       margin: const EdgeInsets.all(24.0),
  //       child: Column(
  //         mainAxisSize: MainAxisSize.min,
  //         children: [
  //           if (_isProcessing)
  //             const CircularProgressIndicator(
  //               valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
  //             )
  //           else
  //             FloatingActionButton(
  //               heroTag: "capture_button",
  //               onPressed: _isFaceReady ? _enrollCurrentAngle : null,
  //               backgroundColor: _isFaceReady ? Colors.white : Colors.grey,
  //               child: Icon(
  //                 Icons.camera_alt,
  //                 color: _isFaceReady ? Colors.black : Colors.white,
  //               ),
  //             ),
  //           const SizedBox(height: 12),
  //           Container(
  //             padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  //             decoration: BoxDecoration(
  //               color: Colors.black87,
  //               borderRadius: BorderRadius.circular(20),
  //             ),
  //             child: Text(
  //               _isFaceReady ? 'Tap to capture' : 'Position your face',
  //               style: const TextStyle(color: Colors.white, fontSize: 14),
  //             ),
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  Widget _buildCompletionScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text("Enrollment Complete")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _successfulEnrollments > 0 ? Icons.check_circle : Icons.error,
                color: _successfulEnrollments > 0 ? Colors.green : Colors.red,
                size: 80,
              ),
              const SizedBox(height: 24),
              Text(
                _successfulEnrollments > 0
                    ? 'Successfully enrolled $_successfulEnrollments angles!'
                    : 'Enrollment failed',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              if (_enrollmentResults.isNotEmpty) ...[
                const Text(
                  'Results:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: SingleChildScrollView(
                    child: Column(
                      children: _enrollmentResults
                          .map(
                            (result) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                result,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: result.contains('success')
                                      ? Colors.green
                                      : Colors.orange,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // if (_successfulEnrollments > 0) ...[
                  //   ElevatedButton(
                  //     onPressed: _restartEnrollment,
                  //     child: const Text("Add More Angles"),
                  //   ),
                  // ],
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Done"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _processImage(InputImage inputImage) async {
    if (_isBusy || _isEnrollmentComplete || _isProcessing) return;
    _isBusy = true;

    try {
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty && faces.length == 1) {
        final face = faces.first;

        // Check face quality and position for current step
        final qualityOk = _isFaceQualityGood(face, inputImage.metadata?.size);
        final angleOk = _isCorrectAngleForStep(face);

        if (qualityOk && angleOk) {
          // mark last seen
          _lastDetectedFace = face;
          _lastInputImage = inputImage;

          // Start or continue the "hold still" timer
          _readySince ??= DateTime.now();
          final heldMs = DateTime.now().difference(_readySince!).inMilliseconds;
          final sinceLast = DateTime.now()
              .difference(_lastAutoShot)
              .inMilliseconds;

          // Update UI while waiting
          setState(() {
            _isFaceReady = true;
            _status = "${_getStepInstruction()}\nHold still... (${heldMs}ms)";
          });

          // Conditions to auto-capture:
          final bool canAutoCapture =
              !_isProcessing &&
              // not already captured this step (we still allow multiple samplesPerStep)
              _capturedThisStep < samplesPerStep &&
              // required hold
              heldMs >= autoCaptureHoldMs &&
              // cooldown since last shot
              sinceLast >= autoCaptureCooldownMs &&
              // overall target not yet reached
              _successfulEnrollments < targetTotalEmbeddings;

          if (canAutoCapture) {
            _lastAutoShot = DateTime.now();
            _capturedThisStep++;

            // call capture (it sets _isProcessing internally)
            await _captureAndSaveFace(face, inputImage);

            // if we've captured enough samples for this step, advance to next step
            if (_capturedThisStep >= samplesPerStep) {
              _capturedThisStep = 0;
              _readySince = null;
              _moveToNextStep();
            }

            // If overall target reached, finish enrollment
            if (_successfulEnrollments >= targetTotalEmbeddings) {
              setState(() {
                _isEnrollmentComplete = true;
                _status =
                    "Enrollment complete: collected $_successfulEnrollments samples";
              });
            }
          }
        } else {
          // Not ready / angle guidance
          setState(() {
            _isFaceReady = false;
            _readySince = null;
            _capturedThisStep = 0;
            _status =
                "${_getStepInstruction()}\n${qualityOk ? _getAngleGuidance(face) : 'Move closer / center your face'}";
          });
        }

        // Draw bounding box overlay
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
              "${_getStepInstruction()}\n${faces.length > 1 ? 'Multiple faces detected. Please ensure only one person is visible.' : 'No face detected.'}";
          _isFaceReady = false;
          _lastDetectedFace = null;
          _lastInputImage = null;
          _customPaint = null;
          _readySince = null;
          _capturedThisStep = 0;
        });
      }
    } catch (e) {
      setState(() => _status = "Error processing image: $e");
    }

    _isBusy = false;
  }

  bool _isCorrectAngleForStep(Face face) {
    final config = _stepConfig[_currentStep]!;
    final yawRange = config['yawRange'] as List<int>;
    final pitchRange = config['pitchRange'] as List<int>;

    final yaw = face.headEulerAngleY ?? 0.0;
    final pitch = face.headEulerAngleX ?? 0.0; // FIX: use X for pitch

    return yaw >= yawRange[0] &&
        yaw <= yawRange[1] &&
        pitch >= pitchRange[0] &&
        pitch <= pitchRange[1];
  }

  String _getAngleGuidance(Face face) {
    final yaw = face.headEulerAngleY ?? 0.0;
    final pitch = face.headEulerAngleX ?? 0.0; // FIX: use X for pitch

    final config = _stepConfig[_currentStep]!;
    final requiredYaw = config['yawRange'] as List<int>;
    final requiredPitch = config['pitchRange'] as List<int>;

    List<String> guidance = [];

    if (yaw < requiredYaw[0]) {
      guidance.add("Turn more to your left");
    } else if (yaw > requiredYaw[1]) {
      guidance.add("Turn more to your right");
    }

    if (pitch < requiredPitch[0]) {
      guidance.add("Look up more");
    } else if (pitch > requiredPitch[1]) {
      guidance.add("Look down more");
    }

    return guidance.isEmpty ? "Perfect angle!" : guidance.join(", ");
  }

  Future<void> _enrollCurrentAngle() async {
    if (_lastDetectedFace == null || _lastInputImage == null || _isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _status = "Processing enrollment...";
    });

    try {
      final embeddingData = await _recognitionHelper.getEmbeddingWithAngle(
        _lastInputImage!,
        _lastDetectedFace!,
      );

      if (embeddingData != null) {
        final result = await _recognitionHelper.saveUserEmbeddingMultiAngle(
          widget.userName,
          embeddingData,
        );

        _enrollmentResults.add(result);

        if (result.contains("successfully") || result.contains("added")) {
          _successfulEnrollments++;
          _moveToNextStep();
        } else {
          // Handle error but don't move to next step
          setState(() {
            _status = "$result\nTry again or skip to next angle.";
          });
        }
      } else {
        _enrollmentResults.add(
          "Failed to extract features for ${_stepConfig[_currentStep]!['title']}",
        );
        setState(() {
          _status = "Could not extract features. Try again.";
        });
      }
    } catch (e) {
      _enrollmentResults.add(
        "Error during ${_stepConfig[_currentStep]!['title']}: $e",
      );
      setState(() {
        _status = "Error occurred. Try again.";
      });
    }

    setState(() {
      _isProcessing = false;
    });
  }

  Future<void> _captureAndSaveFace(Face face, InputImage inputImage) async {
    // guard
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _status = "Processing capture...";
    });

    try {
      final embeddingData = await _recognitionHelper.getEmbeddingWithAngle(
        inputImage,
        face,
      );

      if (embeddingData == null) {
        _enrollmentResults.add(
          "Failed to extract features for ${_stepConfig[_currentStep]!['title']}",
        );
        setState(() => _status = "Could not extract features. Try again.");
        return;
      }

      final result = await _recognitionHelper.saveUserEmbeddingMultiAngle(
        widget.userName,
        embeddingData,
      );

      _enrollmentResults.add(result);

      // consider these messages as success (matches old conventions)
      if (result.contains("successfully") || result.contains("added")) {
        _successfulEnrollments++;
        _capturedAngles.add(_currentStep);
        setState(() {
          _status =
              "Captured $_successfulEnrollments/$targetTotalEmbeddings samples";
        });
      } else {
        // not fatal — show message and continue
        setState(() {
          _status = "$result\nTry a different pose or lighting.";
        });
      }
    } catch (e) {
      _enrollmentResults.add("Error during capture: $e");
      setState(() {
        _status = "Error occurred: $e";
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _moveToNextStep() {
    final currentIndex = _currentStep.index;
    if (currentIndex + 1 < _stepConfig.length) {
      setState(() {
        _currentStep = EnrollmentStep.values[currentIndex + 1];
        _status = _getStepInstruction();
        _isFaceReady = false;
        _lastDetectedFace = null;
        _lastInputImage = null;
      });
    } else {
      // All steps completed
      setState(() {
        _isEnrollmentComplete = true;
      });
    }
  }

  // void _restartEnrollment() {
  //   setState(() {
  //     _currentStep = EnrollmentStep.straight;
  //     _enrollmentResults.clear();
  //     _isEnrollmentComplete = false;
  //     _isProcessing = false;
  //     _status = _getStepInstruction();
  //   });
  // }

  bool _isFaceQualityGood(Face face, Size? imageSize) {
    if (imageSize == null) return false;

    final faceArea = face.boundingBox.width * face.boundingBox.height;
    final imageArea = imageSize.width * imageSize.height;
    final areaRatio = faceArea / imageArea;

    // Check size and basic quality
    return areaRatio > 0.05 && areaRatio < 0.6;
  }
}
