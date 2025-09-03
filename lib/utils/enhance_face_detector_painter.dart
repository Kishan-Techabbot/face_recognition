import 'package:camera/camera.dart';
import 'package:face_recognition/utils/coordinates_translator.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';

class EnhancedFaceDetectorPainter extends CustomPainter {
  EnhancedFaceDetectorPainter(
    this.faces,
    this.imageSize,
    this.rotation,
    this.cameraLensDirection, {
    this.recognizedNames = const {},
    this.recognitionDetails = const {},
  });

  final List<Face> faces;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;
  final Map<int, String> recognizedNames;
  final Map<int, Map<String, dynamic>> recognitionDetails;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint recognizedBoxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.green;

    final Paint unknownBoxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.red;

    for (int i = 0; i < faces.length; i++) {
      final Face face = faces[i];
      final String recognizedName = recognizedNames[i] ?? "Unknown";
      final bool isRecognized = recognizedName != "Unknown";
      final details = recognitionDetails[i];

      final Paint currentBoxPaint = isRecognized
          ? recognizedBoxPaint
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

      canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), currentBoxPaint);

      if (recognizedName.isNotEmpty) {
        String labelText = recognizedName;
        if (details != null) {
          final yaw = details['yaw'] as double;
          final pitch = details['pitch'] as double;
          labelText +=
              "\n${_formatAngleShort(yaw)}, ${_formatPitchShort(pitch)}";
        }

        _drawEnhancedNameLabel(
          canvas,
          labelText,
          left,
          top,
          right - left,
          isRecognized,
        );
      }
    }
  }

  void _drawEnhancedNameLabel(
    Canvas canvas,
    String text,
    double left,
    double top,
    double boxWidth,
    bool isRecognized,
  ) {
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: 14,
      fontWeight: FontWeight.bold,
    );

    final textPainter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();

    final labelWidth = textPainter.width + 16;
    final labelHeight = textPainter.height + 8;
    final labelLeft = left + (boxWidth - labelWidth) / 2;
    final labelTop = top - labelHeight - 4;

    final Paint labelPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = isRecognized
          ? Colors.green.withValues(alpha: 0.8)
          : Colors.red.withValues(alpha: 0.8);

    final RRect labelRect = RRect.fromLTRBR(
      labelLeft,
      labelTop,
      labelLeft + labelWidth,
      labelTop + labelHeight,
      const Radius.circular(4),
    );

    canvas.drawRRect(labelRect, labelPaint);

    textPainter.paint(
      canvas,
      Offset(
        labelLeft + (labelWidth - textPainter.width) / 2,
        labelTop + (labelHeight - textPainter.height) / 2,
      ),
    );
  }

  String _formatAngleShort(double yaw) {
    if (yaw > 15) return "L";
    if (yaw < -15) return "R";
    return "S";
  }

  String _formatPitchShort(double pitch) {
    if (pitch < -15) return "↑";
    if (pitch > 15) return "↓";
    return "→";
  }

  @override
  bool shouldRepaint(EnhancedFaceDetectorPainter oldDelegate) {
    return oldDelegate.imageSize != imageSize ||
        oldDelegate.faces != faces ||
        oldDelegate.recognizedNames != recognizedNames ||
        oldDelegate.recognitionDetails != recognitionDetails;
  }
}
