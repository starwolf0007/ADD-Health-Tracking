package com.neuroflow.healthconnect

import android.app.Activity
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/**
 * Minimal Health Connect permission rationale surface.
 *
 * This activity intentionally describes the current read-only scope. Replace
 * the embedded copy with the published NeuroFlow privacy policy before release.
 */
class PermissionsRationaleActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val density = resources.displayMetrics.density
        fun dp(value: Int): Int = (value * density).toInt()

        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(dp(24), dp(32), dp(24), dp(24))

            addView(TextView(context).apply {
                text = "NeuroFlow Health Connect access"
                textSize = 24f
            })

            addView(TextView(context).apply {
                text = """
                    NeuroFlow requests read-only access to steps, heart rate,
                    resting heart rate, sleep, exercise sessions, and weight.

                    This information is used locally to help you understand your
                    routines, energy, sleep, and activity patterns. NeuroFlow does
                    not modify or delete data in Health Connect.

                    Access can be changed or revoked at any time in Health Connect.
                """.trimIndent()
                textSize = 17f
                setPadding(0, dp(24), 0, dp(24))
            })

            addView(Button(context).apply {
                text = "Close"
                setOnClickListener { finish() }
            }, ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ))
        }

        setContentView(ScrollView(this).apply { addView(content) })
    }
}
