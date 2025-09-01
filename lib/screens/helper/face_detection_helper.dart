import 'package:face_recognition/db/database_services.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
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

  /// Load TFLite model and DB
  Future<void> loadModel() async {
    if (_isModelLoaded) return;

    try {
      _interpreter ??= await Interpreter.fromAsset(
        'assets/models/mobilefacenet.tflite',
      );
      // Initialize DB
      await FaceDatabaseService.instance.database;
      _isModelLoaded = true;
      print("✅ Model loaded and DB initialized");
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
      print('Face Data: ${embedding.length}');
      return _normalize(embedding);
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

  /// Save embedding using singleton DB (with duplicate prevention)
  Future<String> saveUserEmbedding(String name, List<double> embedding) async {
    try {
      // Check if user already exists
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

  /// Find if a similar face already exists
  Future<String?> _findSimilarFace(List<double> embedding) async {
    try {
      final users = await FaceDatabaseService.instance.getAllUsers();
      const double similarityThreshold = 0.5; // Lower = more strict

      for (var user in users) {
        final storedBytes = user['embedding'] as Uint8List;
        final storedEmbedding = storedBytes.buffer.asFloat32List();
        final distance = _euclideanDistance(embedding, storedEmbedding);

        if (distance < similarityThreshold) {
          return user['name'] as String;
        }
      }
      return null;
    } catch (e) {
      print("❌ Error finding similar face: $e");
      return null;
    }
  }

  /// Recognize face
  Future<String?> recognizeUser(List<double> embedding) async {
    try {
      final users = await FaceDatabaseService.instance.getAllUsers();
      if (users.isEmpty) return "Unknown";

      double minDist = double.infinity;
      String? matchedUser;
      const double recognitionThreshold = .5;

      for (var user in users) {
        final storedBytes = user['embedding'] as Uint8List;
        final storedEmbedding = storedBytes.buffer.asFloat32List();
        print("=====================================Stored : $storedEmbedding");
        print("=====================================Current: $embedding");
        final dist = _euclideanDistance(embedding, storedEmbedding);

        if (dist < minDist) {
          minDist = dist;
          matchedUser = user['name'] as String;
        }
      }

      return minDist < recognitionThreshold ? matchedUser : "Unknown";
    } catch (e) {
      print("❌ Error recognizing user: $e");
      return "Unknown";
    }
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
      final db = await FaceDatabaseService.instance.database;
      final result = await db.delete(
        FaceDatabaseService.instance.usersTable,
        where: 'name = ?',
        whereArgs: [name],
      );
      return result > 0;
    } catch (e) {
      print("❌ Error deleting user: $e");
      return false;
    }
  }

  /// ---------------- Helpers ----------------

  List<double> _normalize(List<double> vector) {
    double sum = 0;
    for (var v in vector) {
      sum += v * v;
    }
    sum = math.sqrt(sum);
    if (sum == 0) return vector; // Prevent division by zero
    return vector.map((e) => e / sum).toList();
  }

  /// Helper: Euclidean distance
  double _euclideanDistance(List<double> e1, List<double> e2) {
    if (e1.length != e2.length) return double.infinity;

    double sum = 0;
    for (int i = 0; i < e1.length; i++) {
      sum += (e1[i] - e2[i]) * (e1[i] - e2[i]);
    }
    return math.sqrt(sum);
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

    if (metadata.format == InputImageFormat.nv21) {
      baseImage = img.Image.fromBytes(
        metadata.size.width.toInt(),
        metadata.size.height.toInt(),
        bytes,
        format: img.Format.rgb,
      );
    } else if (metadata.format == InputImageFormat.bgra8888) {
      baseImage = img.Image.fromBytes(
        metadata.size.width.toInt(),
        metadata.size.height.toInt(),
        bytes,
        format: img.Format.rgba,
      );
    } else {
      return [];
    }

    final faceCrop = img.copyCrop(
      baseImage,
      faceRect.left.toInt(),
      faceRect.top.toInt(),
      faceRect.width.toInt(),
      faceRect.height.toInt(),
    );

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

  /// NV21 -> RGB conversion (for Android)
  // img.Image _nv21ToImage(Uint8List nv21, int width, int height) {
  //   final image = img.Image(width, height);
  //   for (int y = 0; y < height; y++) {
  //     for (int x = 0; x < width; x++) {
  //       final yIndex = y * width + x;
  //       if (yIndex < nv21.length) {
  //         final Y = nv21[yIndex] & 0xff;
  //         image.setPixelRgba(x, y, Y, Y, Y);
  //       }
  //     }
  //   }
  //   return image;
  // }

  /// Dispose resources
  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isModelLoaded = false;
  }
}
