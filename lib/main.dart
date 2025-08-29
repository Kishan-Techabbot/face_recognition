import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 812), // iPhone X reference
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return GetMaterialApp(
          title: 'Face Recognition Prototype',
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            appBar: AppBar(title: const Text("Face Recognition Prototype")),
            body: Center(
              child: Text("Hyy", style: TextStyle(fontSize: 20.sp)),
            ),
          ),
        );
      },
    );
  }
}
