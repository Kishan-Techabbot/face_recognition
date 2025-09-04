import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

class CameraView extends StatefulWidget {
  const CameraView({
    super.key,
    required this.customPaint,
    required this.onImage,
    this.onCameraFeedReady,
    this.onDetectorViewModeChanged,
    this.onCameraLensDirectionChanged,
    this.initialCameraLensDirection = CameraLensDirection.back,
  });

  final CustomPaint? customPaint;
  final Function(InputImage inputImage) onImage;
  final VoidCallback? onCameraFeedReady;
  final VoidCallback? onDetectorViewModeChanged;
  final Function(CameraLensDirection direction)? onCameraLensDirectionChanged;
  final CameraLensDirection initialCameraLensDirection;

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  static List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = -1;
  // double _currentZoomLevel = 1.0;
  // double _minAvailableZoom = 1.0;
  // double _maxAvailableZoom = 1.0;
  // double _minAvailableExposureOffset = 0.0;
  // double _maxAvailableExposureOffset = 0.0;
  // double _currentExposureOffset = 0.0;
  bool _changingCameraLens = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  void _initialize() async {
    if (_cameras.isEmpty) {
      _cameras = await availableCameras();
    }
    for (var i = 0; i < _cameras.length; i++) {
      if (_cameras[i].lensDirection == widget.initialCameraLensDirection) {
        _cameraIndex = i;
        break;
      }
    }
    if (_cameraIndex != -1) {
      _startLiveFeed();
    }
  }

  @override
  void dispose() {
    _stopLiveFeed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: _liveFeedBody());
  }

  Widget _liveFeedBody() {
    if (_cameras.isEmpty ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return Container();
    }
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Center(
            child: _changingCameraLens
                ? Center(child: const Text('Changing camera lens'))
                : CameraPreview(_controller!, child: widget.customPaint),
          ),
          // _backButton(),
          _switchLiveCameraToggle(),
          // _detectionViewModeToggle(),
          // _zoomControl(),
          // _exposureControl(),
        ],
      ),
    );
  }

  // Widget _backButton() => Positioned(
  //   top: 40,
  //   left: 8,
  //   child: SizedBox(
  //     height: 50.0,
  //     width: 50.0,
  //     child: FloatingActionButton(
  //       heroTag: Object(),
  //       onPressed: () => Navigator.of(context).pop(),
  //       backgroundColor: Colors.black54,
  //       child: Icon(Icons.arrow_back_ios_outlined, size: 20),
  //     ),
  //   ),
  // );

  // Widget _detectionViewModeToggle() => Positioned(
  //   bottom: 8,
  //   left: 8,
  //   child: SizedBox(
  //     height: 50.0,
  //     width: 50.0,
  //     child: FloatingActionButton(
  //       heroTag: Object(),
  //       onPressed: widget.onDetectorViewModeChanged,
  //       backgroundColor: Colors.black54,
  //       child: Icon(Icons.photo_library_outlined, size: 25),
  //     ),
  //   ),
  // );

  Widget _switchLiveCameraToggle() => Positioned(
    bottom: 8,
    right: 8,
    child: SizedBox(
      height: 50.0,
      width: 50.0,
      child: FloatingActionButton(
        heroTag: Object(),
        onPressed: _switchLiveCamera,
        backgroundColor: Colors.black54,
        child: Icon(
          Platform.isIOS
              ? Icons.flip_camera_ios_outlined
              : Icons.flip_camera_android_outlined,
          size: 25,
        ),
      ),
    ),
  );

  // Widget _zoomControl() => Positioned(
  //   bottom: 16,
  //   left: 0,
  //   right: 0,
  //   child: Align(
  //     alignment: Alignment.bottomCenter,
  //     child: SizedBox(
  //       width: 250,
  //       child: Row(
  //         mainAxisAlignment: MainAxisAlignment.center,
  //         crossAxisAlignment: CrossAxisAlignment.center,
  //         children: [
  //           Expanded(
  //             child: Slider(
  //               value: _currentZoomLevel,
  //               min: _minAvailableZoom,
  //               max: _maxAvailableZoom,
  //               activeColor: Colors.white,
  //               inactiveColor: Colors.white30,
  //               onChanged: (value) async {
  //                 setState(() {
  //                   _currentZoomLevel = value;
  //                 });
  //                 await _controller?.setZoomLevel(value);
  //               },
  //             ),
  //           ),
  //           Container(
  //             width: 50,
  //             decoration: BoxDecoration(
  //               color: Colors.black54,
  //               borderRadius: BorderRadius.circular(10.0),
  //             ),
  //             child: Padding(
  //               padding: const EdgeInsets.all(8.0),
  //               child: Center(
  //                 child: Text(
  //                   '${_currentZoomLevel.toStringAsFixed(1)}x',
  //                   style: TextStyle(color: Colors.white),
  //                 ),
  //               ),
  //             ),
  //           ),
  //         ],
  //       ),
  //     ),
  //   ),
  // );

  // Widget _exposureControl() => Positioned(
  //   top: 40,
  //   right: 8,
  //   child: ConstrainedBox(
  //     constraints: BoxConstraints(maxHeight: 250),
  //     child: Column(
  //       children: [
  //         Container(
  //           width: 55,
  //           decoration: BoxDecoration(
  //             color: Colors.black54,
  //             borderRadius: BorderRadius.circular(10.0),
  //           ),
  //           child: Padding(
  //             padding: const EdgeInsets.all(8.0),
  //             child: Center(
  //               child: Text(
  //                 '${_currentExposureOffset.toStringAsFixed(1)}x',
  //                 style: TextStyle(color: Colors.white),
  //               ),
  //             ),
  //           ),
  //         ),
  //         Expanded(
  //           child: RotatedBox(
  //             quarterTurns: 3,
  //             child: SizedBox(
  //               height: 30,
  //               child: Slider(
  //                 value: _currentExposureOffset,
  //                 min: _minAvailableExposureOffset,
  //                 max: _maxAvailableExposureOffset,
  //                 activeColor: Colors.white,
  //                 inactiveColor: Colors.white30,
  //                 onChanged: (value) async {
  //                   setState(() {
  //                     _currentExposureOffset = value;
  //                   });
  //                   await _controller?.setExposureOffset(value);
  //                 },
  //               ),
  //             ),
  //           ),
  //         ),
  //       ],
  //     ),
  //   ),
  // );

  Future _startLiveFeed() async {
    final camera = _cameras[_cameraIndex];
    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    await _controller?.initialize();
    if (!mounted) return;

    // _currentZoomLevel = await _controller!.getMinZoomLevel();
    // _minAvailableZoom = _currentZoomLevel;
    // _maxAvailableZoom = await _controller!.getMaxZoomLevel();
    // _currentExposureOffset = 0.0;
    // _minAvailableExposureOffset = await _controller!.getMinExposureOffset();
    // _maxAvailableExposureOffset = await _controller!.getMaxExposureOffset();

    if (mounted) {
      setState(() {});
    }

    await _controller?.startImageStream((image) {
      if (!mounted) return; // prevent crash after back
      _processCameraImage(image);
    });

    if (widget.onCameraFeedReady != null) widget.onCameraFeedReady!();
    if (widget.onCameraLensDirectionChanged != null) {
      widget.onCameraLensDirectionChanged!(camera.lensDirection);
    }
  }

  Future _stopLiveFeed() async {
    if (_controller != null) {
      try {
        if (_controller!.value.isStreamingImages) {
          await _controller!.stopImageStream();
        }
      } catch (_) {}
      await _controller!.dispose();
      _controller = null;
    }
  }

  Future _switchLiveCamera() async {
    setState(() => _changingCameraLens = true);
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;

    await _stopLiveFeed();
    await _startLiveFeed();
    setState(() => _changingCameraLens = false);
  }

  void _processCameraImage(CameraImage image) {
    if (!mounted) return;
    final inputImage = _inputImageFromCameraImage(image);
    if (inputImage == null) return;
    widget.onImage(inputImage);
  }

  final _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;

    final camera = _cameras[_cameraIndex];
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation =
          _orientations[_controller!.value.deviceOrientation];
      if (rotationCompensation == null) return null;
      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }
      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }

    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }
}
