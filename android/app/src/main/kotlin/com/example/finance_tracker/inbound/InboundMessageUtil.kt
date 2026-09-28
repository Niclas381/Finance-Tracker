package com.example.finance_tracker.inbound

import java.security.MessageDigest

object InboundMessageUtil {
    fun stableId(timestampMillis: Long, sender: String?, channel: String, text: String): String {
        val base = "${timestampMillis}|${sender ?: ""}|$channel|$text"
        val md = MessageDigest.getInstance("SHA-1")
        val bytes = md.digest(base.toByteArray(Charsets.UTF_8))
        return bytes.joinToString("") { "%02x".format(it) }
    }
}
