import 'package:neuroflow/domain/health/health_transaction.dart';

import 'health_connect_steps_mapper.dart';
import 'health_connect_steps_parser.dart';
import 'health_connect_steps_transport.dart';

final class HealthConnectStepsReadResult {
  const HealthConnectStepsReadResult({
    required this.status,
    required this.transactions,
    required this.rejectionReasonCodes,
  });

  final HealthConnectReadStatus status;
  final List<HealthTransaction> transactions;
  final List<String> rejectionReasonCodes;
}

abstract final class HealthConnectStepsAdapter {
  static HealthConnectStepsReadResult fromWire(
    Object? value, {
    required DateTime capturedAtUtc,
  }) {
    if (value is! Map) return _failed();
    final status = HealthConnectStepsParser.parseStatus(value['status']);
    final rawRecords = value['records'];
    if (rawRecords is! List) return _failed();
    if (status != HealthConnectReadStatus.ok) {
      return rawRecords.isEmpty
          ? HealthConnectStepsReadResult(
              status: status,
              transactions: const [],
              rejectionReasonCodes: const [],
            )
          : _failed();
    }

    final transactions = <HealthTransaction>[];
    final rejections = <String>[];
    for (final rawRecord in rawRecords) {
      try {
        final record = HealthConnectStepsParser.parseRecord(rawRecord);
        transactions.add(
          HealthConnectStepsMapper.toTransaction(
            record,
            capturedAtUtc: capturedAtUtc,
          ),
        );
      } on HealthConnectTransportRejection catch (error) {
        rejections.add(error.reasonCode);
      } catch (_) {
        rejections.add('domain_mapping_failed');
      }
    }

    return HealthConnectStepsReadResult(
      status: status,
      transactions: List.unmodifiable(transactions),
      rejectionReasonCodes: List.unmodifiable(rejections),
    );
  }

  static HealthConnectStepsReadResult _failed() =>
      const HealthConnectStepsReadResult(
        status: HealthConnectReadStatus.failed,
        transactions: [],
        rejectionReasonCodes: [],
      );
}
