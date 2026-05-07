package kr.pe.ssun.textflow.text_flow

import android.content.BroadcastReceiver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Telephony

class MmsBroadcastReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        val safeContext = context ?: return
        val action = intent?.action ?: return
        val mimeType = intent.type

        val isMmsPush = action == Telephony.Sms.Intents.WAP_PUSH_RECEIVED_ACTION ||
            action == Telephony.Sms.Intents.WAP_PUSH_DELIVER_ACTION
        val isMmsMime = mimeType == null || mimeType.equals(MMS_MIME_TYPE, ignoreCase = true)
        if (!isMmsPush || !isMmsMime) {
            return
        }

        val event = runCatching { buildLatestMmsEvent(safeContext) }.getOrNull() ?: return
        SmsStorage.save(safeContext, event)
        SmsForwardingEngine.forwardIfMatched(safeContext, event)
        SmsEventBridge.dispatch(event)
    }

    private fun buildLatestMmsEvent(context: Context): Map<String, Any?>? {
        val resolver = context.contentResolver
        val inboxUri = Uri.parse("content://mms/inbox")
        val projection = arrayOf("_id", "date")

        resolver.query(inboxUri, projection, null, null, "date DESC")?.use { cursor ->
            if (!cursor.moveToFirst()) {
                return null
            }

            val id = cursor.getString(cursor.getColumnIndexOrThrow("_id"))
            val timestampSeconds = cursor.getLong(cursor.getColumnIndexOrThrow("date"))
            val receivedAt = if (timestampSeconds > 0L) {
                timestampSeconds * 1000L
            } else {
                System.currentTimeMillis()
            }

            val address = queryMmsAddress(context, id)
            val body = queryMmsTextBody(context, id)

            return mapOf(
                "messageType" to "mms",
                "address" to address,
                "body" to body,
                "receivedAt" to receivedAt,
            )
        }

        return null
    }

    private fun queryMmsAddress(context: Context, messageId: String): String {
        val uri = Uri.parse("content://mms/$messageId/addr")
        val projection = arrayOf("address", "type")
        val selection = "type=137"

        context.contentResolver.query(uri, projection, selection, null, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val address = cursor.getString(cursor.getColumnIndexOrThrow("address")) ?: continue
                if (address.isNotBlank() && address != "insert-address-token") {
                    return address
                }
            }
        }

        return "알 수 없음"
    }

    private fun queryMmsTextBody(context: Context, messageId: String): String {
        val uri = Uri.parse("content://mms/part")
        val projection = arrayOf("_id", "ct", "text")
        val selection = "mid=?"
        val selectionArgs = arrayOf(messageId)
        val textParts = mutableListOf<String>()

        context.contentResolver.query(uri, projection, selection, selectionArgs, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val contentType = cursor.getString(cursor.getColumnIndexOrThrow("ct")) ?: continue
                if (!contentType.startsWith("text/")) {
                    continue
                }

                val directText = cursor.getString(cursor.getColumnIndexOrThrow("text"))
                if (!directText.isNullOrBlank()) {
                    textParts.add(directText)
                    continue
                }

                val partId = cursor.getString(cursor.getColumnIndexOrThrow("_id"))
                val partIdLong = partId.toLongOrNull() ?: continue
                val partUri = ContentUris.withAppendedId(Uri.parse("content://mms/part"), partIdLong)
                context.contentResolver.openInputStream(partUri)?.bufferedReader()?.use { reader ->
                    val text = reader.readText()
                    if (text.isNotBlank()) {
                        textParts.add(text)
                    }
                }
            }
        }

        return textParts.joinToString(separator = "\n").ifBlank { "(MMS 본문 없음 또는 첨부 전용)" }
    }

    companion object {
        private const val MMS_MIME_TYPE = "application/vnd.wap.mms-message"
    }
}

