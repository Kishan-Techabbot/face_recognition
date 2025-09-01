import 'package:face_recognition/screens/face_detector/enroll_face.dart';
import 'package:face_recognition/screens/face_detector/face_detector_screen.dart';
import 'package:face_recognition/screens/helper/face_detection_helper.dart';
import 'package:flutter/material.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final TextEditingController _nameController = TextEditingController();
  final FaceRecognitionHelper _recognitionHelper =
      FaceRecognitionHelper.instance;
  List<String> _enrolledUsers = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadEnrolledUsers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadEnrolledUsers() async {
    setState(() => _isLoading = true);
    try {
      final users = await _recognitionHelper.getAllEnrolledUsers();
      if (mounted) {
        setState(() {
          _enrolledUsers = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Error loading users: $e")));
      }
    }
  }

  Future<void> _deleteUser(String userName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete User'),
        content: Text('Are you sure you want to delete "$userName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _recognitionHelper.deleteUser(userName);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$userName deleted successfully')),
          );
          _loadEnrolledUsers();
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to delete $userName')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Face Recognition Dashboard"),
        actions: [
          IconButton(onPressed: _loadEnrolledUsers, icon: Icon(Icons.refresh)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Main Action Buttons
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const FaceDetectorScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.face, size: 28),
                        label: const Text("Start Face Recognition"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                          textStyle: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: "Enter Name for Enrollment",
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final userName = _nameController.text.trim();
                          if (userName.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Please enter a name"),
                              ),
                            );
                            return;
                          }
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  EnrollFaceScreen(userName: userName),
                            ),
                          ).then((_) {
                            _nameController.clear();
                            _loadEnrolledUsers(); // Refresh user list
                          });
                        },
                        icon: const Icon(Icons.add),
                        label: const Text("Enroll New Face"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Enrolled Users Section
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.people,
                            color: Theme.of(context).primaryColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Enrolled Users (${_enrolledUsers.length})",
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                      const Divider(),
                      Expanded(
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : _enrolledUsers.isEmpty
                            ? const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.person_off,
                                      size: 64,
                                      color: Colors.grey,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      "No users enrolled yet",
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      "Start by enrolling a face above",
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: _enrolledUsers.length,
                                itemBuilder: (context, index) {
                                  final user = _enrolledUsers[index];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      child: Text(
                                        user.isNotEmpty
                                            ? user[0].toUpperCase()
                                            : '?',
                                      ),
                                    ),
                                    title: Text(user),
                                    subtitle: Text("Face enrolled"),
                                    trailing: IconButton(
                                      onPressed: () => _deleteUser(user),
                                      icon: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
