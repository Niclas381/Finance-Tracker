package com.example.finance_tracker.inbound

import android.content.Context
import android.content.Intent
import org.json.JSONObject

object InboundMessageBus {
    const val ACTION_NEW_MESSAGE = "com.example.finance_tracker.ACTION_NEW_INBOUND_MESSAGE"
    const val EXTRA_PAYLOAD = "payload"

    fun publish(ctx: Context, payload: JSONObject) {
        InboundMessageStore.enqueue(ctx, payload)

        val intent = Intent(ACTION_NEW_MESSAGE)
        intent.putExtra(EXTRA_PAYLOAD, payload.toString())
        ctx.sendBroadcast(intent)
    }
}
