// Pure value enums shared by the health domain and Drift storage.
//
// Keep persisted enum ordering stable. Drift currently stores these through
// intEnum<T>(), so reordering existing values would be a schema change.

enum SensitivityClass { routine, sensitive, medical }

enum MeasurementStatus { valid, partial, unavailable, invalid, deleted }

enum RecordingMethod {
  deviceMeasured,
  userEntered,
  sourceEstimated,
  sourceDerived,
  importedUnknown,
}

enum QualityLabel { unknown, low, moderate, high }

enum RetentionPolicy { standard, limited, untilUserDeletes, medicalVaultPolicy }

enum IngestionStatus {
  pending,
  running,
  succeeded,
  partiallySucceeded,
  failed,
  cancelled,
}

enum IngestionTrigger {
  initialImport,
  foregroundRefresh,
  backgroundRefresh,
  permissionRestored,
  manualRetry,
  renormalization,
}

enum ContextIntensity { unknown, low, moderate, high }
