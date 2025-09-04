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

  // Multi-angle enrollment settings
  static const int maxEmbeddingsPerUser = 20;
  static const double angleVariationThreshold =
      12.0; // Minimum angle difference between embeddings
  static const double minEmbeddingSeparation =
      0.35; // require enough feature-space delta

  // Pose-aware recognition weighting (small nudge toward closer pose)
  static const double angleBiasWeight = 0.10; // 0..0.3 usually safe
  static const double angleSigma =
      25.0; // degrees, controls falloff for pose proximity

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
      print("🔄 Multi-angle: Max $maxEmbeddingsPerUser embeddings per user");
    } catch (e) {
      print("❌ Error loading model: $e");
      rethrow;
    }
  }

  /// Extract embedding from face with angle information
  Future<Map<String, dynamic>?> getEmbeddingWithAngle(
    InputImage image,
    Face face,
  ) async {
    if (_interpreter == null) {
      print("❌ Model not loaded");
      return null;
    }

    try {
      final bytes = await _imageToByteList(image, face.boundingBox);
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
      final normalized = _normalize(embedding);

      // Extract head pose angles (ML Kit axes)
      final pitch = face.headEulerAngleX ?? 0.0; // Up/down
      final yaw = face.headEulerAngleY ?? 0.0; // Left/right
      final roll = face.headEulerAngleZ ?? 0.0; // Tilt

      log('🧮 RAW EMBEDDING (first 5): ${embedding.take(5).toList()}');
      log('🔄 NORMALIZED EMBEDDING (first 5): ${normalized.take(5).toList()}');
      log('📏 Embedding length: ${normalized.length}');
      log('📐 Face angles - Yaw: $yaw, Pitch: $pitch, Roll: $roll');

      return {
        'embedding': normalized,
        'yaw': yaw,
        'pitch': pitch,
        'roll': roll,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
    } catch (e) {
      print("❌ Error extracting embedding: $e");
      return null;
    }
  }

  /// Legacy method for backward compatibility
  Future<List<double>?> getEmbedding(InputImage image, Rect faceRect) async {
    // Create a dummy Face object for the new method
    final face = _createDummyFace(faceRect);
    final result = await getEmbeddingWithAngle(image, face);
    return result?['embedding'];
  }

  /// Create dummy Face object when only bounding box is available
  Face _createDummyFace(Rect boundingBox) {
    // This is a workaround since Face constructor is not public
    // In practice, you should pass the actual Face object
    return Face(
      boundingBox: boundingBox,
      landmarks: {},
      contours: {},
      headEulerAngleX: 0.0,
      headEulerAngleY: 0.0,
      headEulerAngleZ: 0.0,
      leftEyeOpenProbability: null,
      rightEyeOpenProbability: null,
      smilingProbability: null,
      trackingId: null,
    );
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

  /// Save embedding with multi-angle support
  Future<String> saveUserEmbeddingMultiAngle(
    String name,
    Map<String, dynamic> embeddingData,
  ) async {
    try {
      final embedding = embeddingData['embedding'] as List<double>;
      final yaw = (embeddingData['yaw'] as double?) ?? 0.0;
      final pitch = (embeddingData['pitch'] as double?) ?? 0.0;
      final roll = (embeddingData['roll'] as double?) ?? 0.0;

      final existingUser = await FaceDatabaseService.instance.getUserByName(
        name,
      );

      // If user exists, evaluate against their stored embeddings
      if (existingUser != null) {
        final existingEmbeddings = await FaceDatabaseService.instance
            .getUserEmbeddings(name);

        // Hard cap
        if (existingEmbeddings.length >= maxEmbeddingsPerUser) {
          return "Maximum embeddings ($maxEmbeddingsPerUser) already stored for '$name'.";
        }

        bool tooSimilarByPose = false;
        bool tooSimilarByEmbedding = false;

        for (var existing in existingEmbeddings) {
          final storedBytes = existing['embedding'] as Uint8List;
          final stored = bytesToDoubleList(storedBytes);

          final existingYaw = (existing['yaw'] as num?)?.toDouble() ?? 0.0;
          final existingPitch = (existing['pitch'] as num?)?.toDouble() ?? 0.0;

          // Pose delta
          final angleDiff = math.sqrt(
            math.pow(yaw - existingYaw, 2) + math.pow(pitch - existingPitch, 2),
          );
          if (angleDiff < angleVariationThreshold) {
            tooSimilarByPose = true;
          }

          // Feature-space delta
          final dist = euclideanDistance(embedding, stored);
          if (dist < minEmbeddingSeparation) {
            tooSimilarByEmbedding = true;
          }

          if (tooSimilarByPose || tooSimilarByEmbedding) break;
        }

        if (tooSimilarByPose && tooSimilarByEmbedding) {
          return "Similar pose & features already stored for '$name'. Try a more different angle.";
        }
        if (tooSimilarByPose) {
          return "A similar angle is already stored for '$name'. Turn a bit more.";
        }
        if (tooSimilarByEmbedding) {
          return "A very similar face sample already exists for '$name'. Try again.";
        }

        // Looks sufficiently new → save
        await FaceDatabaseService.instance.insertUserEmbedding(
          name,
          embedding,
          yaw,
          pitch,
          roll,
        );
        final total = existingEmbeddings.length + 1;
        return "New angle added for '$name'! ($total/$maxEmbeddingsPerUser stored)";
      }

      // New user: ensure not already enrolled as someone else
      final duplicateOf = await _findSimilarFaceMultiAngle(embedding);
      if (duplicateOf != null) {
        return "This face is already enrolled as '$duplicateOf'!";
      }

      await FaceDatabaseService.instance.insertUserEmbedding(
        name,
        embedding,
        yaw,
        pitch,
        roll,
      );
      return "Face enrolled successfully for '$name'! (1/$maxEmbeddingsPerUser stored)";
    } catch (e) {
      print("❌ Error saving user embedding: $e");
      return "Error saving face: $e";
    }
  }

  /// Legacy method for backward compatibility
  Future<String> saveUserEmbedding(String name, List<double> embedding) async {
    final embeddingData = {
      'embedding': embedding,
      'yaw': 0.0,
      'pitch': 0.0,
      'roll': 0.0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    return await saveUserEmbeddingMultiAngle(name, embeddingData);
  }

  /// Enhanced similarity detection with multiple embeddings
  Future<String?> _findSimilarFaceMultiAngle(List<double> embedding) async {
    try {
      final allEmbeddings = await FaceDatabaseService.instance
          .getAllEmbeddings();
      log(
        "🔍 DUPLICATE CHECK: Comparing against ${allEmbeddings.length} existing embeddings",
      );

      for (var embeddingRecord in allEmbeddings) {
        final storedBytes = embeddingRecord['embedding'] as Uint8List;
        final storedEmbedding = bytesToDoubleList(storedBytes);
        final userName = embeddingRecord['name'] as String;

        log("👤 Checking against user: $userName");

        final distance = euclideanDistance(embedding, storedEmbedding);
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

  /// Legacy similarity detection
  // Future<String?> _findSimilarFace(List<double> embedding) async {
  //   return await _findSimilarFaceMultiAngle(embedding);
  // }

  /// Enhanced face recognition with multiple embeddings per user
  Future<String?> recognizeUserMultiAngle(List<double> embedding) async {
    try {
      final users = await FaceDatabaseService.instance.getAllUsers();
      if (users.isEmpty) return "Unknown";

      double bestDist = double.infinity;
      String? bestUser;

      for (var user in users) {
        final userName = user['name'] as String;
        final userEmbeddings = await FaceDatabaseService.instance
            .getUserEmbeddings(userName);

        for (var embeddingRecord in userEmbeddings) {
          final storedBytes = embeddingRecord['embedding'] as Uint8List;
          final storedEmbedding = bytesToDoubleList(storedBytes);

          final dist = euclideanDistance(embedding, storedEmbedding);

          if (dist < bestDist) {
            bestDist = dist;
            bestUser = userName;
          }
        }
      }

      if (bestDist < recognitionThreshold) {
        return bestUser;
      } else {
        return "Unknown";
      }
    } catch (e) {
      print("❌ Error recognizing user: $e");
      return "Unknown";
    }
  }

  /// Legacy recognition method for backward compatibility
  Future<String?> recognizeUser(List<double> embedding) async {
    return await recognizeUserMultiAngle(embedding);
  }

  /// Get user embedding count
  Future<int> getUserEmbeddingCount(String name) async {
    try {
      final embeddings = await FaceDatabaseService.instance.getUserEmbeddings(
        name,
      );
      return embeddings.length;
    } catch (e) {
      print("❌ Error getting user embedding count: $e");
      return 0;
    }
  }

  /// Get detailed user info with embedding count
  Future<Map<String, dynamic>?> getUserInfo(String name) async {
    try {
      final user = await FaceDatabaseService.instance.getUserByName(name);
      if (user == null) return null;

      final embeddings = await FaceDatabaseService.instance.getUserEmbeddings(
        name,
      );

      return {
        'name': user['name'],
        'embedding_count': embeddings.length,
        'max_embeddings': maxEmbeddingsPerUser,
        'can_add_more': embeddings.length < maxEmbeddingsPerUser,
        'angles': embeddings
            .map(
              (e) => {
                'yaw': e['yaw'] ?? 0.0,
                'pitch': e['pitch'] ?? 0.0,
                'roll': e['roll'] ?? 0.0,
              },
            )
            .toList(),
      };
    } catch (e) {
      print("❌ Error getting user info: $e");
      return null;
    }
  }

  /// Proper conversion from Uint8List to Listdouble
  List<double> bytesToDoubleList(Uint8List bytes) {
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

  /// Get all enrolled users with embedding counts
  Future<List<Map<String, dynamic>>> getAllEnrolledUsersDetailed() async {
    try {
      final users = await FaceDatabaseService.instance.getAllUsers();
      List<Map<String, dynamic>> result = [];

      for (var user in users) {
        final userName = user['name'] as String;
        final info = await getUserInfo(userName);
        if (info != null) {
          result.add(info);
        }
      }

      return result;
    } catch (e) {
      print("❌ Error getting detailed users: $e");
      return [];
    }
  }

  /// Legacy method for backward compatibility
  Future<List<String>> getAllEnrolledUsers() async {
    try {
      final users = await FaceDatabaseService.instance.getAllUsers();
      return users.map((user) => user['name'] as String).toList();
    } catch (e) {
      print("❌ Error getting users: $e");
      return [];
    }
  }

  /// Delete a user and all their embeddings
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
  double euclideanDistance(List<double> e1, List<double> e2) {
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
