import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuroflow/app/providers.dart';
import 'package:neuroflow/domain/task.dart';
import 'package:neuroflow/domain/date_key.dart';
import 'package:neuroflow/domain/reentry_note.dart';
import 'package:neuroflow/presentation/lexi_conversation_screen.dart';
import 'package:neuroflow/presentation/settings_screen.dart';
import 'package:neuroflow/presentation/theme.dart';
import 'package:neuroflow/presentation/today/lexi_avatar.dart';
import 'package:neuroflow/executive/planner.dart';
import 'package:neuroflow/executive/timeline_logic.dart';
import 'package:neuroflow/presentation/widgets/capture_sheet.dart';
import 'package:neuroflow/presentation/widgets/due_routines_card.dart';
import 'package:neuroflow/presentation/widgets/mood_check_in.dart';

class TodayScreen extends ConsumerStatefulWidget {
  final DateTime? now;
  const TodayScreen({super.key, this.now});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}
