// test/unit/enum_codec_test.dart
//
// Unit tests for the shared enum <-> name codec helper.
// Run with: dart test test/unit/enum_codec_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:neuroflow/domain/enum_codec.dart';
import 'package:neuroflow/domain/task.dart';

void main() {
  group('enumFromName', () {
    test('decodes a known name to its enum value', () {
      expect(
        enumFromName(TaskStatus.values, 'completed',
            fallback: TaskStatus.pending),
        TaskStatus.completed,
      );
    });

    test('round-trips every value via its name', () {
      for (final status in TaskStatus.values) {
        expect(
          enumFromName(TaskStatus.values, status.name,
              fallback: TaskStatus.pending),
          status,
        );
      }
    });

    test('returns the fallback for an unknown name', () {
      expect(
        enumFromName(EnergyLevel.values, 'nonsense',
            fallback: EnergyLevel.medium),
        EnergyLevel.medium,
      );
    });

    test('returns the fallback for an empty string', () {
      expect(
        enumFromName(EnergyLevel.values, '', fallback: EnergyLevel.low),
        EnergyLevel.low,
      );
    });
  });
}
