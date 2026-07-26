// lib/presentation/notes_screen.dart
import 'package:flutter/material.dart';
import 'package:neuroflow/presentation/theme.dart';

class NotesScreen extends StatelessWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notes')),
      body: const Center(
        child: Text('Notes coming in Phase 2', style: AppTextStyles.bodyMedium),
      ),
    );
  }
}
