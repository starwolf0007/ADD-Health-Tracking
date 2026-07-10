import 'package:flutter/material.dart';

import 'package:neuroflow/presentation/theme.dart';
import 'package:neuroflow/presentation/today/lexi_avatar.dart';

class LexiConversationScreen extends StatelessWidget {
  const LexiConversationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lexi')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpace.xxl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LexiAvatar(
                visualState: LexiVisualState.idle,
                assetPath: 'assets/lexi/placeholder.png',
                size: 72,
              ),
              SizedBox(height: AppSpace.lg),
              Text('Lexi is available when you want a little clarity.',
                  style: AppTextStyles.titleMedium,
                  textAlign: TextAlign.center),
              SizedBox(height: AppSpace.sm),
              Text(
                'Conversation is not connected in this slice. Your plan still works without AI.',
                style: AppTextStyles.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
