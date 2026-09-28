package com.example.finance_tracker.inbound

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

object InboundMessageStore {
    private const val PREFS = "inbound_message_store"
    private const val KEY_QUEUE = "queue"
    private const val MAX = 250

    private fun prefs(ctx: Context): SharedPreferences =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    @Synchronized
    fun enqueue(ctx: Context, obj: JSONObject) {
        val p = prefs(ctx)
        val raw = p.getString(KEY_QUEUE, "[]") ?: "[]"
        val arr = JSONArray(raw)

        arr.put(obj)

        val trimmed = JSONArray()
        val start = if (arr.length() > MAX) arr.length() - MAX else 0
        for (i in start until arr.length()) {
            trimmed.put(arr.get(i))
        }

        p.edit().putString(KEY_QUEUE, trimmed.toString()).apply()
    }

    @Synchronized
    fun drain(ctx: Context): JSONArray {
        val p = prefs(ctx)
        val raw = p.getString(KEY_QUEUE, "[]") ?: "[]"
        return JSONArray(raw)
    }

    @Synchronized
    fun clear(ctx: Context) {
        prefs(ctx).edit().putString(KEY_QUEUE, "[]").apply()
    }
}
