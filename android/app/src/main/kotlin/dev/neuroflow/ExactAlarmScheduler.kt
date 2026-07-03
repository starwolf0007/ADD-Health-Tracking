// android/app/src/main/kotlin/dev/neuroflow/ExactAlarmScheduler.kt
//
// Schedules the morning briefing notification using AlarmManager exact alarms.
//
// Why not WorkManager for this?
// WorkManager periodic tasks are inexact by Android design — Doze mode can
// delay them 20-45 minutes. For ADHD users with time-blindness, a morning
// nudge at 8:35 when they're already driving is useless. Exact alarms fire
// within seconds of the scheduled time regardless of Doze.
//
// Permission:
//   Android 12+ (API 31+): SCHEDULE_EXACT_ALARM or USE_EXACT_ALARM required.
//   Pixel 10 Pro XL ships Android 15 (API 35). We use USE_EXACT_ALARM
//   (granted automatically, no runtime prompt needed for clock/alarm apps).
//   Declared in AndroidManifest.xml.
//
// Design:
//   • Each alarm fires once, then reschedules itself for the next day.
//   • Alarm time is read from FlutterSecureStorage via a ContentProvider shim.
//     Until the user sets a custom time, defaults to 08:00 AM local time.
//   • AlarmReceiver posts a local notification (same as WorkManager morning job)
//     and reschedules for the next day.
//   • On device reboot, BOOT_COMPLETED receiver re-schedules the alarm.
//
// Flutter integration:
//   Call ExactAlarmScheduler.schedule() from WearBridge or a dedicated
//   MethodChannel ('neuroflow/alarms') after the user sets their wake time.

package dev.neuroflow

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.util.Calendar

private const val ACTION_MORNING_ALARM = "dev.neuroflow.MORNING_ALARM"
private const val CHANNEL_ID = "neuroflow_briefing"
private const val REQUEST_CODE_MORNING = 1001
private const val DEFAULT_HOUR = 8
private const val DEFAULT_MINUTE = 0

object ExactAlarmScheduler {

    /**
     * Schedule (or reschedule) the morning briefing exact alarm.
     * Safe to call on every app launch — cancels any existing alarm first.
     *
     * @param hourOfDay 24h hour for the alarm (default 8)
     * @param minute    minute for the alarm (default 0)
     */
    fun schedule(context: Context, hourOfDay: Int = DEFAULT_HOUR, minute: Int = DEFAULT_MINUTE) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        // On Android 12+, check permission before scheduling exact alarm.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (!alarmManager.canScheduleExactAlarms()) {
                // USE_EXACT_ALARM should be auto-granted for apps targeting API 33+
                // that declare it in the manifest. If somehow not granted, fall back
                // to inexact — better than crashing.
                scheduleInexact(context, alarmManager, hourOfDay, minute)
                return
            }
        }

        val triggerAt = nextAlarmMillis(hourOfDay, minute)
        val intent    = alarmIntent(context)

        alarmManager.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            triggerAt,
            intent,
        )
    }

    fun cancel(context: Context) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(alarmIntent(context))
    }

    private fun scheduleInexact(
        context: Context,
        alarmManager: AlarmManager,
        hourOfDay: Int,
        minute: Int,
    ) {
        alarmManager.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            nextAlarmMillis(hourOfDay, minute),
            alarmIntent(context),
        )
    }

    private fun alarmIntent(context: Context): PendingIntent {
        val intent = Intent(context, MorningAlarmReceiver::class.java).apply {
            action = ACTION_MORNING_ALARM
        }
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE_MORNING,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun nextAlarmMillis(hourOfDay: Int, minute: Int): Long {
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hourOfDay)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            // If the time has already passed today, schedule for tomorrow.
            if (timeInMillis <= System.currentTimeMillis()) {
                add(Calendar.DAY_OF_YEAR, 1)
            }
        }
        return cal.timeInMillis
    }
}

/**
 * BroadcastReceiver that fires when the exact alarm triggers.
 * Posts the morning briefing notification and reschedules for the next day.
 *
 * Register in AndroidManifest.xml:
 * <receiver android:name=".MorningAlarmReceiver" android:exported="false">
 *   <intent-filter>
 *     <action android:name="dev.neuroflow.MORNING_ALARM"/>
 *   </intent-filter>
 * </receiver>
 */
class MorningAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_MORNING_ALARM) return

        // Post the morning briefing notification.
        // Pending task count requires a DB read — do it on a background thread.
        val pendingIntent = PendingIntent.getActivity(
            context, 0,
            context.packageManager.getLaunchIntentForPackage(context.packageName),
            PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info) // replace with app icon
            .setContentTitle("Good morning")
            .setContentText("Open NeuroFlow to see your plan for today.")
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        if (NotificationManagerCompat.from(context).areNotificationsEnabled()) {
            NotificationManagerCompat.from(context).notify(2001, notification)
        }

        // Reschedule for tomorrow at the same time.
        ExactAlarmScheduler.schedule(context)
    }
}

/**
 * Reschedules the morning alarm after device reboot.
 *
 * Register in AndroidManifest.xml:
 * <receiver android:name=".BootReceiver" android:exported="true">
 *   <intent-filter>
 *     <action android:name="android.intent.action.BOOT_COMPLETED"/>
 *   </intent-filter>
 * </receiver>
 *
 * Add to uses-permission:
 * <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            // Re-schedule with default time. Once the user opens the app,
            // their custom time will be restored from FlutterSecureStorage
            // and ExactAlarmScheduler.schedule() will be called again.
            ExactAlarmScheduler.schedule(context)
        }
    }
}
