package com.example.finance_tracker.inbound

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import org.json.JSONObject

class AppNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            val n = sbn.notification
            val extras = n.extras

            val title = extras.getCharSequence("android.title")?.toString()?.trim()
            val text = extras.getCharSequence("android.text")?.toString()?.trim()
            val bigText = extras.getCharSequence("android.bigText")?.toString()?.trim()

            val combined = listOfNotNull(title, bigText ?: text)
                .joinToString("\n")
                .trim()

            if (combined.isEmpty()) return

            val timestamp = sbn.postTime
            val sender = sbn.packageName
            val channel = "notification"
            val id = InboundMessageUtil.stableId(timestamp, sender, channel, combined)

            val obj = JSONObject()
                .put("id", id)
                .put("timestampMillis", timestamp)
                .put("sender", sender)
                .put("channel", channel)
                .put("text", combined)

            InboundMessageBus.publish(applicationContext, obj)
        } catch (_: Throwable) {
            // ignore
        }
    }
}
