import 'dart:developer';
import 'dart:typed_data';

import 'package:face_recognition/db/database_services.dart';
import 'package:flutter/services.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'dart:math' as math;

class FaceRecognitionHelper {
  static final FaceRecognitionHelper instance = FaceRecognitionHelper._();
  factory FaceRecognitionHelper() => instance;
  FaceRecognitionHelper._();

  Interpreter? _interpreter;
  static const int inputSize = 112;
  static const int embeddingSize = 192;
  bool _isModelLoaded = false;

  static const double recognitionThreshold = 0.7;
  static const double similarityThreshold = 0.6;

  /// Load TFLite model and DB
  Future<void> loadModel() async {
    if (_isModelLoaded) return;

    try {
      _interpreter ??= await Interpreter.fromAsset(
        'assets/models/mobilefacenet (1).tflite',
      );
      await FaceDatabaseService.instance.database;
      _isModelLoaded = true;
      print("✅ Model loaded and DB initialized");
      print("📊 Recognition threshold: $recognitionThreshold");
      print("📊 Similarity threshold: $similarityThreshold");
    } catch (e) {
      print("❌ Error loading model: $e");
      rethrow;
    }
  }

  /// Extract embedding from face
  Future<List<double>?> getEmbedding(InputImage image, Rect faceRect) async {
    if (_interpreter == null) {
      print("❌ Model not loaded");
      return null;
    }

    try {
      final bytes = await _imageToByteList(image, faceRect);
      if (bytes.isEmpty) {
        print("❌ Failed to process image");
        return null;
      }

      var input = bytes.reshape([1, inputSize, inputSize, 3]);
      var output = List.filled(
        1 * embeddingSize,
        0.0,
      ).reshape([1, embeddingSize]);

      _interpreter!.run(input, output);
      final embedding = List<double>.from(output[0]);

      // Enhanced logging
      final normalized = _normalize(embedding);
      log('🧮 RAW EMBEDDING (first 5): ${embedding.take(5).toList()}');
      log('🔄 NORMALIZED EMBEDDING (first 5): ${normalized.take(5).toList()}');
      log('📏 Embedding length: ${normalized.length}');

      return normalized;
    } catch (e) {
      print("❌ Error extracting embedding: $e");
      return null;
    }
  }

  /// Check if user already exists (duplicate prevention)
  Future<bool> userExists(String name) async {
    try {
      final users = await FaceDatabaseService.instance.getAllUsers();
      return users.any(
        (user) => (user['name'] as String).toLowerCase() == name.toLowerCase(),
      );
    } catch (e) {
      print("❌ Error checking user existence: $e");
      return false;
    }
  }

  /// Save embedding with enhanced duplicate detection
  Future<String> saveUserEmbedding(String name, List<double> embedding) async {
    try {
      // Check if user already exists by name
      if (await userExists(name)) {
        return "User '$name' already exists!";
      }

      // Check if this face embedding is similar to any existing face
      final existingSimilar = await _findSimilarFace(embedding);
      if (existingSimilar != null) {
        return "This face is already enrolled as '$existingSimilar'!";
      }

      await FaceDatabaseService.instance.insertUser(name, embedding);
      return "Face enrolled successfully for '$name'!";
    } catch (e) {
      print("❌ Error saving user embedding: $e");
      return "Error saving face: $e";
    }
  }

  /// Enhanced similarity detection with better logging
  Future<String?> _findSimilarFace(List<double> embedding) async {
    try {
      final users = await FaceDatabaseService.instance.getAllUsers();
      log(
        "🔍 DUPLICATE CHECK: Comparing against ${users.length} existing users",
      );

      for (var user in users) {
        final storedBytes = user['embedding'] as Uint8List;
        final storedEmbedding = _bytesToDoubleList(storedBytes);
        final userName = user['name'] as String;

        log("👤 Checking against user: $userName");
        log("📊 Stored (first 3): ${storedEmbedding.take(3).toList()}");
        log("📊 Current (first 3): ${embedding.take(3).toList()}");

        final distance = _euclideanDistance(embedding, storedEmbedding);
        log(
          "📏 DUPLICATE CHECK DISTANCE: $distance (threshold: $similarityThreshold)",
        );

        if (distance < similarityThreshold) {
          log(
            "⚠️  DUPLICATE DETECTED: Distance $distance < $similarityThreshold",
          );
          return userName;
        }
      }

      log("✅ NO DUPLICATES FOUND");
      return null;
    } catch (e) {
      print("❌ Error finding similar face: $e");
      return null;
    }
  }

  /// Enhanced face recognition with detailed logging
  Future<String?> recognizeUser(List<double> embedding) async {
    try {
      final users = await FaceDatabaseService.instance.getAllUsers();
      if (users.isEmpty) {
        log("📝 No users in database");
        return "Unknown";
      }

      // double minDist = double.infinity;
      // String? matchedUser;
      const double marginThreshold = 0.2;
      double bestDist = double.infinity;
      double secondBestDist = double.infinity;
      String? bestUser;

      log("🎯 RECOGNITION: Testing against ${users.length} users");
      log("📊 Input embedding (first 3): ${embedding.take(3).toList()}");

      for (var user in users) {
        final storedBytes = user['embedding'] as Uint8List;
        final storedEmbedding = _bytesToDoubleList(storedBytes);
        final userName = user['name'] as String;

        log("👤 Testing user: $userName");
        log("📊 Stored (first 3): ${storedEmbedding.take(3).toList()}");

        final dist = _euclideanDistance(embedding, storedEmbedding);
        log("📏 DISTANCE to $userName: $dist");

        if (dist < bestDist) {
          // update best/second-best
          secondBestDist = bestDist;
          bestDist = dist;
          bestUser = user['name'] as String?;
          log("[log] 🏆 NEW BEST MATCH: $bestUser (distance: $bestDist)");
        } else if (dist < secondBestDist) {
          secondBestDist = dist;
        }
      }

      final margin = secondBestDist - bestDist;

      log("[log] 🎯 FINAL RECOGNITION RESULT:");
      log("[log]    👤 Best match: $bestUser");
      log("[log]    📏 Best distance: $bestDist");
      log("[log]    📏 Second-best distance: $secondBestDist");
      log("[log]    ➖ Margin: $margin");
      log("[log]    🎚️ Threshold: $recognitionThreshold");

      if (bestDist < recognitionThreshold && margin > marginThreshold) {
        log("[log]    ✅ Match: true");
        return bestUser;
      } else {
        log("    ❌ Match: false → UNKNOWN");
        return "Unknown";
      }
    } catch (e) {
      print("❌ Error recognizing user: $e");
      return "Unknown";
    }
  }

  /// Proper conversion from Uint8List to Listdouble
  List<double> _bytesToDoubleList(Uint8List bytes) {
    final byteData = ByteData.sublistView(bytes);
    final List<double> result = [];

    for (int i = 0; i < bytes.length; i += 4) {
      if (i + 3 < bytes.length) {
        final floatValue = byteData.getFloat32(i, Endian.little);
        result.add(floatValue);
      }
    }

    return result;
  }

  /// Get all enrolled users
  Future<List<String>> getAllEnrolledUsers() async {
    try {
      final users = await FaceDatabaseService.instance.getAllUsers();
      return users.map((user) => user['name'] as String).toList();
    } catch (e) {
      print("❌ Error getting users: $e");
      return [];
    }
  }

  /// Delete a user
  Future<bool> deleteUser(String name) async {
    try {
      final result = await FaceDatabaseService.instance.deleteUser(name);
      return result > 0;
    } catch (e) {
      print("❌ Error deleting user: $e");
      return false;
    }
  }

  /// Enhanced normalization with validation
  List<double> _normalize(List<double> vector) {
    double sum = 0;
    for (var v in vector) {
      sum += v * v;
    }
    sum = math.sqrt(sum);

    if (sum == 0 || sum.isNaN || sum.isInfinite) {
      log("⚠️  WARNING: Invalid normalization sum: $sum");
      return vector;
    }

    final normalized = vector.map((e) => e / sum).toList();

    // Validation
    double checkSum = 0;
    for (var v in normalized) {
      checkSum += v * v;
    }
    final magnitude = math.sqrt(checkSum);
    log("✅ Normalized vector magnitude: $magnitude (should be ~1.0)");

    return normalized;
  }

  /// Enhanced Euclidean distance calculation
  double _euclideanDistance(List<double> e1, List<double> e2) {
    if (e1.length != e2.length) {
      log("❌ LENGTH MISMATCH: e1=${e1.length}, e2=${e2.length}");
      return double.infinity;
    }

    double sum = 0;
    for (int i = 0; i < e1.length; i++) {
      final diff = e1[i] - e2[i];
      sum += diff * diff;
    }

    final distance = math.sqrt(sum);

    // Validation
    if (distance.isNaN || distance.isInfinite) {
      log("⚠️  WARNING: Invalid distance calculated: $distance");
      return double.infinity;
    }

    return distance;
  }

  /// Converts InputImage + face rect into 112x112 normalized float array
  Future<List<List<List<double>>>> _imageToByteList(
    InputImage image,
    Rect faceRect,
  ) async {
    if (image.bytes == null || image.metadata == null) return [];

    final metadata = image.metadata!;
    final bytes = image.bytes!;
    img.Image baseImage;

    log(
      "Format: ${metadata.format}, Rotation: ${metadata.rotation}, Size: ${metadata.size}",
    );

    img.Image yuv420ToImage(Uint8List nv21Bytes, int width, int height) {
      final imgOut = img.Image(width, height); // RGBA buffer
      final frameSize = width * height;
      for (int y = 0; y < height; y++) {
        int uvp = frameSize + (y >> 1) * width;
        int u = 0, v = 0;
        for (int x = 0; x < width; x++) {
          final yp = y * width + x;
          final Y = nv21Bytes[yp] & 0xFF;
          if ((x & 1) == 0) {
            v = nv21Bytes[uvp++] & 0xFF;
            u = nv21Bytes[uvp++] & 0xFF;
          }
          int C = Y - 16;
          int D = u - 128;
          int E = v - 128;
          int R = (298 * C + 409 * E + 128) >> 8;
          int G = (298 * C - 100 * D - 208 * E + 128) >> 8;
          int B = (298 * C + 516 * D + 128) >> 8;
          if (R < 0) {
            R = 0;
          } else if (R > 255) {
            R = 255;
          }

          if (G < 0) {
            G = 0;
          } else if (G > 255) {
            G = 255;
          }

          if (B < 0) {
            B = 0;
          } else if (B > 255) {
            B = 255;
          }
          imgOut.setPixelRgba(x, y, R, G, B, 255);
        }
      }
      return imgOut;
    }

    if (metadata.format == InputImageFormat.nv21) {
      baseImage = yuv420ToImage(
        bytes,
        metadata.size.width.toInt(),
        metadata.size.height.toInt(),
      );
    } else if (metadata.format == InputImageFormat.bgra8888) {
      baseImage = img.Image.fromBytes(
        metadata.size.width.toInt(),
        metadata.size.height.toInt(),
        bytes,
        format: img.Format.bgra, // BGRA → not RGBA
      );
    } else {
      return [];
    }

    int rotationToDegrees(InputImageRotation r) {
      switch (r) {
        case InputImageRotation.rotation90deg:
          return 90;
        case InputImageRotation.rotation180deg:
          return 180;
        case InputImageRotation.rotation270deg:
          return 270;
        case InputImageRotation.rotation0deg:
          return 0;
      }
    }

    final rotationDegrees = rotationToDegrees(metadata.rotation);
    if (rotationDegrees != 0) {
      baseImage = img.copyRotate(baseImage, rotationDegrees);
    }

    final double cx = faceRect.center.dx;
    final double cy = faceRect.center.dy;
    final double side = (math.max(faceRect.width, faceRect.height) * 1.3).clamp(
      64.0,
      math.min(baseImage.width, baseImage.height).toDouble(),
    );

    int left = (cx - side / 2).floor();
    int top = (cy - side / 2).floor();
    int s = side.floor();

    left = left.clamp(0, baseImage.width - 1);
    top = top.clamp(0, baseImage.height - 1);
    s = math.min(s, math.min(baseImage.width - left, baseImage.height - top));

    final faceCrop = img.copyCrop(baseImage, left, top, s, s);
    final resized = img.copyResize(
      faceCrop,
      width: inputSize,
      height: inputSize,
    );

    // final faceCrop = img.copyCrop(
    //   baseImage,
    //   faceRect.left.toInt(),
    //   faceRect.top.toInt(),
    //   faceRect.width.toInt(),
    //   faceRect.height.toInt(),
    // );

    // final resized = img.copyResize(
    //   faceCrop,
    //   width: inputSize,
    //   height: inputSize,
    // );

    return List.generate(inputSize, (y) {
      return List.generate(inputSize, (x) {
        final pixel = resized.getPixel(x, y);
        return [
          (img.getRed(pixel) - 128) / 128.0,
          (img.getGreen(pixel) - 128) / 128.0,
          (img.getBlue(pixel) - 128) / 128.0,
        ];
      });
    });
  }

  /// Dispose resources
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isModelLoaded = false;
  }
}
