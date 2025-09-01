import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class FaceDatabaseService {
  static final FaceDatabaseService instance = FaceDatabaseService._();
  factory FaceDatabaseService() => instance;
  FaceDatabaseService._();

  static const String _dbName = 'face_recognition.db';
  static const int _dbVersion = 1;
  Database? _db;
  final String usersTable = 'users';

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final path = join(directory.path, _dbName);

      return await openDatabase(
        path,
        version: _dbVersion,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $usersTable (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              embedding BLOB NOT NULL,
              created_at TEXT DEFAULT CURRENT_TIMESTAMP
            )
          ''');
          print("✅ Database table created successfully");
        },
        onOpen: (db) {
          print("✅ Database opened successfully");
        },
      );
    } catch (e) {
      print("❌ Error initializing database: $e");
      rethrow;
    }
  }

  Future<int> insertUser(String name, List<double> embedding) async {
    print("EMBWHILESTORING: $embedding");
    try {
      final db = await database;
      final embeddingBlob = Float32List.fromList(
        embedding,
      ).buffer.asUint8List();

      return await db.insert(usersTable, {
        'name': name.trim(),
        'embedding': embeddingBlob,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      print("❌ Error inserting user: $e");
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> getAllUsers() async {
    try {
      final db = await database;
      return await db.query(usersTable, orderBy: 'created_at DESC');
    } catch (e) {
      print("❌ Error getting all users: $e");
      return [];
    }
  }

  Future<Map<String, Object?>?> getUserByName(String name) async {
    try {
      final db = await database;
      final results = await db.query(
        usersTable,
        where: 'LOWER(name) = ?',
        whereArgs: [name.toLowerCase().trim()],
        limit: 1,
      );
      return results.isNotEmpty ? results.first : null;
    } catch (e) {
      print("❌ Error getting user by name: $e");
      return null;
    }
  }

  Future<int> deleteUser(String name) async {
    try {
      final db = await database;
      return await db.delete(
        usersTable,
        where: 'LOWER(name) = ?',
        whereArgs: [name.toLowerCase().trim()],
      );
    } catch (e) {
      print("❌ Error deleting user: $e");
      return 0;
    }
  }

  Future<void> deleteAllUsers() async {
    try {
      final db = await database;
      await db.delete(usersTable);
      print("✅ All users deleted");
    } catch (e) {
      print("❌ Error deleting all users: $e");
      rethrow;
    }
  }

  Future<int> getUserCount() async {
    try {
      final db = await database;
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $usersTable',
      );
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      print("❌ Error getting user count: $e");
      return 0;
    }
  }

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
      print("✅ Database closed");
    }
  }

  Future<void> deleteDatabaseFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final path = join(directory.path, _dbName);

      await close();

      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        print("✅ Database file deleted");
      }
    } catch (e) {
      print("❌ Error deleting database file: $e");
      rethrow;
    }
  }
}
