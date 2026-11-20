/**
 * AlertService — Alert-Ready Timer Contract
 *
 * Requirements:
 * - Timer accounting is separate from alert delivery.
 * - The notification trigger is abstracted into a single service: AlertService.schedule(taskId, targetEndTime, title).
 * - No other code schedules alerts directly.
 * - The state persists targetEndTime, not just a start time and duration.
 * - An alert is not an eighth state, and reaching a deadline does not mark the task Finished.
 * - Pause and finish both cancel the pending alert.
 * - Note: Background alert delivery is tested separately at Gate 1A on the Razr Fold.
 */

export interface ScheduledAlert {
  taskId: string;
  targetEndTime: string; // ISO date string
  title: string;
  scheduledAt: string; // ISO date string
}

export class AlertService {
  private static pendingAlerts = new Map<string, ScheduledAlert>();

  /**
   * Abstracted notification trigger. Called with a target timestamp.
   * No other code schedules alerts directly.
   */
  static schedule(taskId: string, targetEndTime: string, title: string): void {
    if (!taskId || !targetEndTime) return;
    // Cancel any previous alert for this task before scheduling new one
    this.cancel(taskId);

    this.pendingAlerts.set(taskId, {
      taskId,
      targetEndTime,
      title,
      scheduledAt: new Date().toISOString(),
    });
  }

  /**
   * Pause and finish both cancel the pending alert.
   */
  static cancel(taskId: string): void {
    if (!taskId) return;
    this.pendingAlerts.delete(taskId);
  }

  static getPending(taskId: string): ScheduledAlert | undefined {
    return this.pendingAlerts.get(taskId);
  }

  static getAllPending(): ScheduledAlert[] {
    return Array.from(this.pendingAlerts.values());
  }

  static clearAll(): void {
    this.pendingAlerts.clear();
  }
}
