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
  static const int _dbVersion = 2;
  Database? _db;
  final String usersTable = 'users';
  final String embeddingsTable = 'user_embeddings';

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
          await _createTables(db);
          print("✅ Database tables created successfully");
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _upgradeToV2(db);
            print("✅ Database upgraded to version 2");
          }
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

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE $usersTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE $embeddingsTable (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        embedding BLOB NOT NULL,
        yaw REAL DEFAULT 0.0,
        pitch REAL DEFAULT 0.0,
        roll REAL DEFAULT 0.0,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES $usersTable (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('CREATE INDEX idx_user_id ON $embeddingsTable(user_id)');
    await db.execute('CREATE INDEX idx_user_name ON $usersTable(name)');
  }

  Future<void> _upgradeToV2(Database db) async {
    final oldUsers = await db.query('users');
    await _createTables(db);
    
    for (var user in oldUsers) {
      final name = user['name'] as String;
      final oldEmbedding = user['embedding'] as Uint8List?;
      
      if (oldEmbedding != null) {
        final userId = await db.insert('users', {
          'name': name,
          'created_at': user['created_at'],
          'updated_at': user['created_at'],
        });
        
        await db.insert('user_embeddings', {
          'user_id': userId,
          'embedding': oldEmbedding,
          'yaw': 0.0,
          'pitch': 0.0,
          'roll': 0.0,
          'created_at': user['created_at'],
        });
        
        print("📦 Migrated user: $name");
      }
    }
  }

  Future<int> _ensureUser(String name) async {
    final db = await database;
    
    final existing = await db.query(
      usersTable,
      where: 'LOWER(name) = ?',
      whereArgs: [name.toLowerCase().trim()],
      limit: 1,
    );
    
    if (existing.isNotEmpty) {
      return existing.first['id'] as int;
    }
    
    return await db.insert(usersTable, {
      'name': name.trim(),
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> insertUserEmbedding(
    String name, 
    List<double> embedding,
    double yaw,
    double pitch,
    double roll,
  ) async {
    try {
      final db = await database;
      final userId = await _ensureUser(name);
      
      final byteData = ByteData(embedding.length * 4);
      for (int i = 0; i < embedding.length; i++) {
        byteData.setFloat32(i * 4, embedding[i], Endian.little);
      }
      final embeddingBlob = byteData.buffer.asUint8List();

      final embeddingId = await db.insert(embeddingsTable, {
        'user_id': userId,
        'embedding': embeddingBlob,
        'yaw': yaw,
        'pitch': pitch,
        'roll': roll,
        'created_at': DateTime.now().toIso8601String(),
      });

      await db.update(
        usersTable,
        {'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [userId],
      );

      print("✅ Embedding stored with ID: $embeddingId for user: $name");
      return embeddingId;
    } catch (e) {
      print("❌ Error inserting user embedding: $e");
      rethrow;
    }
  }

  Future<int> insertUser(String name, List<double> embedding) async {
    return await insertUserEmbedding(name, embedding, 0.0, 0.0, 0.0);
  }

  Future<List<Map<String, Object?>>> getUserEmbeddings(String name) async {
    try {
      final db = await database;
      final results = await db.rawQuery('''
        SELECT e.*, u.name
        FROM $embeddingsTable e
        JOIN $usersTable u ON e.user_id = u.id
        WHERE LOWER(u.name) = ?
        ORDER BY e.created_at DESC
      ''', [name.toLowerCase().trim()]);
      return results;
    } catch (e) {
      print("❌ Error getting user embeddings: $e");
      return [];
    }
  }

  Future<List<Map<String, Object?>>> getAllEmbeddings() async {
    try {
      final db = await database;
      final results = await db.rawQuery('''
        SELECT e.*, u.name
        FROM $embeddingsTable e
        JOIN $usersTable u ON e.user_id = u.id
        ORDER BY u.name, e.created_at DESC
      ''');
      return results;
    } catch (e) {
      print("❌ Error getting all embeddings: $e");
      return [];
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
      final user = await getUserByName(name);
      if (user == null) return 0;
      
      final userId = user['id'] as int;
      await db.delete(embeddingsTable, where: 'user_id = ?', whereArgs: [userId]);
      final result = await db.delete(usersTable, where: 'id = ?', whereArgs: [userId]);
      
      print("✅ Deleted user: $name with all embeddings");
      return result;
    } catch (e) {
      print("❌ Error deleting user: $e");
      return 0;
    }
  }

  Future<void> deleteAllUsers() async {
    try {
      final db = await database;
      await db.delete(embeddingsTable);
      await db.delete(usersTable);
      print("✅ All users and embeddings deleted");
    } catch (e) {
      print("❌ Error deleting all users: $e");
      rethrow;
    }
  }

  Future<int> getUserCount() async {
    try {
      final db = await database;
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM $usersTable');
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      print("❌ Error getting user count: $e");
      return 0;
    }
  }

  Future<int> getEmbeddingCount() async {
    try {
      final db = await database;
      final result = await db.rawQuery('SELECT COUNT(*) as count FROM $embeddingsTable');
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      print("❌ Error getting embedding count: $e");
      return 0;
    }
  }

  Future<Map<String, int>> getStatistics() async {
    try {
      final userCount = await getUserCount();
      final embeddingCount = await getEmbeddingCount();
      
      return {
        'total_users': userCount,
        'total_embeddings': embeddingCount,
        'avg_embeddings_per_user': userCount > 0 ? (embeddingCount / userCount).round() : 0,
      };
    } catch (e) {
      print("❌ Error getting statistics: $e");
      return {'total_users': 0, 'total_embeddings': 0, 'avg_embeddings_per_user': 0};
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