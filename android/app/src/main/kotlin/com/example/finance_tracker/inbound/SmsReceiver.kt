package com.example.finance_tracker.inbound

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import org.json.JSONObject

class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (Telephony.Sms.Intents.SMS_RECEIVED_ACTION != intent.action) return

        try {
            val msgs = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            if (msgs.isEmpty()) return

            val body = buildString {
                for (m in msgs) append(m.messageBody ?: "")
            }.trim()

            if (body.isEmpty()) return

            val sender = msgs[0].originatingAddress
            val timestamp = msgs[0].timestampMillis
            val channel = "sms"
            val id = InboundMessageUtil.stableId(timestamp, sender, channel, body)

            val obj = JSONObject()
                .put("id", id)
                .put("timestampMillis", timestamp)
                .put("sender", sender)
                .put("channel", channel)
                .put("text", body)

            InboundMessageBus.publish(context.applicationContext, obj)
        } catch (_: Throwable) {
            // ignore
        }
    }
}
