package kr.pe.ssun.textflow.text_flow

import android.content.Context
import android.telephony.SmsManager
import org.json.JSONArray
import org.json.JSONObject

private const val filterStoreName = "textflow_filter_store"
private const val keyFiltersJson = "filters_json"

data class ForwardingFilterConfig(
	val title: String,
	val enabled: Boolean,
	val allowSms: Boolean,
	val allowMms: Boolean,
	val forwardAll: Boolean,
	val ignoreCase: Boolean,
	val useWildcard: Boolean,
	val senderConditions: List<String>,
	val messageConditions: List<String>,
	val destinations: List<String>,
)

object FilterConfigStorage {
	fun saveFilters(context: Context, filters: List<*>) {
		val jsonArray = JSONArray()
		filters.forEach { raw ->
			if (raw !is Map<*, *>) {
				return@forEach
			}

			val json = JSONObject().apply {
				put("title", raw["title"] as? String ?: "")
				put("enabled", raw["enabled"] as? Boolean ?: true)
				put("allowSms", raw["allowSms"] as? Boolean ?: true)
				put("allowMms", raw["allowMms"] as? Boolean ?: true)
				put("forwardAll", raw["forwardAll"] as? Boolean ?: true)
				put("ignoreCase", raw["ignoreCase"] as? Boolean ?: true)
				put("useWildcard", raw["useWildcard"] as? Boolean ?: false)
				put("senderConditions", JSONArray((raw["senderConditions"] as? List<*>) ?: emptyList<Any?>()))
				put("messageConditions", JSONArray((raw["messageConditions"] as? List<*>) ?: emptyList<Any?>()))
				put("destinations", JSONArray((raw["destinations"] as? List<*>) ?: emptyList<Any?>()))
			}

			jsonArray.put(json)
		}

		context.getSharedPreferences(filterStoreName, Context.MODE_PRIVATE)
			.edit()
			.putString(keyFiltersJson, jsonArray.toString())
			.apply()
	}

	fun loadFilters(context: Context): List<ForwardingFilterConfig> {
		val rawJson = context.getSharedPreferences(filterStoreName, Context.MODE_PRIVATE)
			.getString(keyFiltersJson, null)
			?: return emptyList()

		val jsonArray = runCatching { JSONArray(rawJson) }.getOrNull() ?: return emptyList()
		val filters = mutableListOf<ForwardingFilterConfig>()

		for (index in 0 until jsonArray.length()) {
			val item = jsonArray.optJSONObject(index) ?: continue
			filters.add(
				ForwardingFilterConfig(
					title = item.optString("title", ""),
					enabled = item.optBoolean("enabled", true),
					allowSms = item.optBoolean("allowSms", true),
					allowMms = item.optBoolean("allowMms", true),
					forwardAll = item.optBoolean("forwardAll", true),
					ignoreCase = item.optBoolean("ignoreCase", true),
					useWildcard = item.optBoolean("useWildcard", false),
					senderConditions = item.optStringList("senderConditions"),
					messageConditions = item.optStringList("messageConditions"),
					destinations = item.optStringList("destinations"),
				)
			)
		}

		return filters
	}
}

object SmsForwardingEngine {
	fun forwardIfMatched(context: Context, event: Map<String, Any?>) {
		val messageType = (event["messageType"] as? String)?.lowercase() ?: "sms"
		val address = (event["address"] as? String).orEmpty()
		val body = (event["body"] as? String).orEmpty()

		val filters = FilterConfigStorage.loadFilters(context)
		if (filters.isEmpty()) {
			return
		}

		filters
			.asSequence()
			.filter { it.enabled }
			.filter { matchesType(it, messageType) }
			.filter { matchesConditions(it, address, body) }
			.forEach { filter ->
				val phoneDestinations = filter.destinations
					.asSequence()
					.map { normalizePhone(it) }
					.filter { it.isNotEmpty() }
					.distinct()
					.toList()

				if (phoneDestinations.isEmpty()) {
					return@forEach
				}

				val forwardedText = buildForwardedMessage(filter.title, messageType, address, body)
				phoneDestinations.forEach { destination ->
					sendSms(destination, forwardedText)
				}
			}
	}

	private fun matchesType(filter: ForwardingFilterConfig, messageType: String): Boolean {
		return when (messageType) {
			"mms" -> filter.allowMms
			else -> filter.allowSms
		}
	}

	private fun matchesConditions(filter: ForwardingFilterConfig, address: String, body: String): Boolean {
		if (filter.forwardAll) {
			return true
		}

		val senderMatched = filter.senderConditions.any { condition ->
			matchesCondition(address, condition, filter.ignoreCase, filter.useWildcard)
		}
		if (senderMatched) {
			return true
		}

		return filter.messageConditions.any { condition ->
			matchesCondition(body, condition, filter.ignoreCase, filter.useWildcard)
		}
	}

	private fun matchesCondition(
		target: String,
		condition: String,
		ignoreCase: Boolean,
		useWildcard: Boolean,
	): Boolean {
		val normalizedTarget = if (ignoreCase) target.lowercase() else target
		val normalizedCondition = if (ignoreCase) condition.lowercase() else condition
		if (normalizedCondition.isBlank()) {
			return false
		}

		if (!useWildcard) {
			return normalizedTarget.contains(normalizedCondition)
		}

		val regexPattern = Regex.escape(normalizedCondition).replace("\\*", ".*")
		return Regex(regexPattern).containsMatchIn(normalizedTarget)
	}

	private fun normalizePhone(rawDestination: String): String {
		val compact = rawDestination.trim().replace(" ", "").replace("-", "")
		if (compact.length < 7) {
			return ""
		}

		return if (compact.matches(Regex("^\\+?[0-9]{7,15}$"))) compact else ""
	}

	private fun buildForwardedMessage(title: String, messageType: String, from: String, body: String): String {
		val typeLabel = if (messageType == "mms") "MMS" else "SMS"
		return "[TextFlow/$title] $typeLabel from $from\n$body"
	}

	private fun sendSms(destination: String, body: String) {
		runCatching {
			SmsManager.getDefault().sendTextMessage(destination, null, body, null, null)
		}
	}
}

private fun JSONObject.optStringList(key: String): List<String> {
	val array = optJSONArray(key) ?: return emptyList()
	val result = mutableListOf<String>()
	for (index in 0 until array.length()) {
		val value = array.optString(index, "").trim()
		if (value.isNotEmpty()) {
			result.add(value)
		}
	}
	return result
}