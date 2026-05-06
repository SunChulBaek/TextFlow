package kr.pe.ssun.textflow.text_flow

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony

class SmsBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
            return
        }

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isEmpty()) {
            return
        }

        val address = messages.firstOrNull()?.originatingAddress ?: "알 수 없음"
        val body = messages.joinToString(separator = "") { smsMessage ->
            smsMessage.displayMessageBody ?: smsMessage.messageBody ?: ""
        }
        val receivedAt = messages.firstOrNull()?.timestampMillis ?: System.currentTimeMillis()
        val event = mapOf(
            "messageType" to "sms",
            "address" to address,
            "body" to body,
            "receivedAt" to receivedAt,
        )

        context?.let { SmsStorage.save(it, event) }

        SmsEventBridge.dispatch(event)
    }
}


