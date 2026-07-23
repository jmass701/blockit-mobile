package com.blockit.mobile

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Button
import android.widget.TextView

/**
 * BlockedOverlayActivity — the full-screen "Blocked — request unlock in BlockIT"
 * screen shown by BlockAccessibilityService right after a locked app is caught
 * and the user is sent home. Purely informational; the "Open BlockIT" button
 * jumps to the app where they can fire an unlock request.
 */
class BlockedOverlayActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_blocked)

        val label = intent.getStringExtra(EXTRA_APP_LABEL)
        findViewById<TextView>(R.id.blockedAppLabel).text =
            if (label.isNullOrBlank()) "" else label

        findViewById<Button>(R.id.openBlockItButton).setOnClickListener {
            startActivity(
                Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            finish()
        }
    }

    companion object {
        const val EXTRA_APP_LABEL = "app_label"
    }
}
