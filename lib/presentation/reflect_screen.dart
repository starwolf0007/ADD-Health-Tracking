// lib/presentation/reflect_screen.dart
import 'package:flutter/material.dart';
import 'theme.dart';

class ReflectScreen extends StatelessWidget {
  const ReflectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reflect')),
      body: const Center(
        child: Text('Reflection coming in Phase 2', style: AppTextStyles.bodyMedium),
      ),
    );
  }
}
