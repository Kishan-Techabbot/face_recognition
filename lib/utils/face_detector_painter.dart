import 'dart:math';
import 'package:camera/camera.dart';
import 'package:face_recognition/utils/coordinates_translator.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

class FaceDetectorPainter extends CustomPainter {
  FaceDetectorPainter(
    this.faces,
    this.imageSize,
    this.rotation,
    this.cameraLensDirection, {
    this.recognizedNames = const {},
  });

  final List<Face> faces;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;
  final Map<int, String> recognizedNames; // Face index -> Name mapping

  @override
  void paint(Canvas canvas, Size size) {
    final Paint boundingBoxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.green;

    final Paint unknownBoxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.red;

    // final Paint landmarkPaint = Paint()
    //   ..style = PaintingStyle.fill
    //   ..strokeWidth = 1.0
    //   ..color = Colors.blue;

    for (int i = 0; i < faces.length; i++) {
      final Face face = faces[i];
      final String recognizedName = recognizedNames[i] ?? "Unknown";
      final bool isRecognized = recognizedName != "Unknown";

      // Choose paint based on recognition status
      final Paint currentBoxPaint = isRecognized
          ? boundingBoxPaint
          : unknownBoxPaint;

      final left = translateX(
        face.boundingBox.left,
        size,
        imageSize,
        rotation,
        cameraLensDirection,
      );
      final top = translateY(
        face.boundingBox.top,
        size,
        imageSize,
        rotation,
        cameraLensDirection,
      );
      final right = translateX(
        face.boundingBox.right,
        size,
        imageSize,
        rotation,
        cameraLensDirection,
      );
      final bottom = translateY(
        face.boundingBox.bottom,
        size,
        imageSize,
        rotation,
        cameraLensDirection,
      );

      // Draw bounding box
      canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), currentBoxPaint);

      // Draw name label if recognized
      if (recognizedName.isNotEmpty) {
        _drawNameLabel(
          canvas,
          recognizedName,
          left,
          top,
          right - left,
          isRecognized,
        );
      }

      // Draw facial landmarks (optional - you can remove this if not needed)
      // void paintLandmark(FaceLandmarkType type) {
      //   final landmark = face.landmarks[type];
      //   if (landmark?.position != null) {
      //     canvas.drawCircle(
      //       Offset(
      //         translateX(
      //           landmark!.position.x.toDouble(),
      //           size,
      //           imageSize,
      //           rotation,
      //           cameraLensDirection,
      //         ),
      //         translateY(
      //           landmark.position.y.toDouble(),
      //           size,
      //           imageSize,
      //           rotation,
      //           cameraLensDirection,
      //         ),
      //       ),
      //       2,
      //       landmarkPaint,
      //     );
      //   }
      // }

      // Uncomment to show landmarks
      // for (final type in FaceLandmarkType.values) {
      //   paintLandmark(type);
      // }
    }
  }

  void _drawNameLabel(
    Canvas canvas,
    String name,
    double left,
    double top,
    double boxWidth,
    bool isRecognized,
  ) {
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: 16,
      fontWeight: FontWeight.bold,
    );

    final textPainter = TextPainter(
      text: TextSpan(text: name, style: textStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    // Calculate label dimensions
    final labelWidth = max(textPainter.width + 16, 80.0);
    final labelHeight = textPainter.height + 8;

    // Position label above the bounding box
    final labelLeft = left + (boxWidth - labelWidth) / 2;
    final labelTop = top - labelHeight - 4;

    // Draw label background
    final Paint labelPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = isRecognized ? Colors.green : Colors.red;

    final RRect labelRect = RRect.fromLTRBR(
      labelLeft,
      labelTop,
      labelLeft + labelWidth,
      labelTop + labelHeight,
      const Radius.circular(4),
    );

    canvas.drawRRect(labelRect, labelPaint);

    // Draw text
    textPainter.paint(
      canvas,
      Offset(
        labelLeft + (labelWidth - textPainter.width) / 2,
        labelTop + (labelHeight - textPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(FaceDetectorPainter oldDelegate) {
    return oldDelegate.imageSize != imageSize ||
        oldDelegate.faces != faces ||
        oldDelegate.recognizedNames != recognizedNames;
  }
}
