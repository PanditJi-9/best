package app.best.best_app.ext

import android.content.Context
import androidx.preference.EditTextPreference
import androidx.preference.ListPreference
import androidx.preference.MultiSelectListPreference
import androidx.preference.Preference
import androidx.preference.PreferenceGroup
import androidx.preference.PreferenceManager
import androidx.preference.PreferenceScreen
import androidx.preference.TwoStatePreference
import eu.kanade.tachiyomi.animesource.ConfigurableAnimeSource
import eu.kanade.tachiyomi.source.ConfigurableSource
import org.json.JSONArray
import org.json.JSONObject

/**
 * The settings screen an extension declares with `androidx.preference`.
 *
 * Community sources put real choices there — mirror/domain, image quality,
 * login, content filters — and many of them have no working default once their
 * first domain is blocked. The host builds the same screen the extension would
 * show under Mihon, against the extension's own preference file
 * (`source_<id>`, the one its generated code reads), so a value written here is
 * the value the source sees on its next request.
 */
internal object SourcePreferences {

    /** The preference file extensions read for their own source id. */
    private fun fileName(sourceId: Long) = "source_$sourceId"

    private fun manager(context: Context, sourceId: Long): PreferenceManager =
        PreferenceManager(context).apply {
            sharedPreferencesName = fileName(sourceId)
        }

    private fun screen(context: Context, sourceId: Long, source: Any): PreferenceScreen? {
        val screen = manager(context, sourceId).createPreferenceScreen(context)
        return runCatching {
            when (source) {
                is ConfigurableSource -> source.setupPreferenceScreen(screen)
                is ConfigurableAnimeSource -> source.setupPreferenceScreen(screen)
                else -> return null
            }
            screen
        }.getOrNull()
    }

    /** Every visible setting as plain JSON, in the order the extension added it. */
    fun describe(context: Context, sourceId: Long, source: Any): JSONArray {
        val screen = screen(context, sourceId, source) ?: return JSONArray()
        val out = JSONArray()
        collect(screen, out)
        return out
    }

    private fun collect(group: PreferenceGroup, out: JSONArray) {
        for (index in 0 until group.preferenceCount) {
            val preference = group.getPreference(index) ?: continue
            if (!preference.isVisible) continue
            when (preference) {
                // A category or nested screen is only a container.
                is PreferenceGroup -> collect(preference, out)
                is ListPreference -> out.put(
                    base(preference, "list").apply {
                        put("value", preference.value.orEmpty())
                        put("entries", strings(preference.entries))
                        put("entryValues", strings(preference.entryValues))
                    }
                )
                is MultiSelectListPreference -> out.put(
                    base(preference, "multi").apply {
                        put("values", JSONArray(preference.values.orEmpty().sorted()))
                        put("entries", strings(preference.entries))
                        put("entryValues", strings(preference.entryValues))
                    }
                )
                is EditTextPreference -> out.put(
                    base(preference, "text").apply {
                        put("value", preference.text.orEmpty())
                    }
                )
                is TwoStatePreference -> out.put(
                    base(preference, "switch").apply {
                        put("value", preference.isChecked)
                    }
                )
                // A plain preference is usually a button or an intent; the app
                // has no matching action, so it is left out instead of shown
                // as a control that does nothing.
            }
        }
    }

    private fun base(preference: Preference, type: String): JSONObject = JSONObject().apply {
        put("key", preference.key.orEmpty())
        put("type", type)
        put("title", preference.title?.toString().orEmpty())
        put("summary", preference.summary?.toString().orEmpty())
    }

    private fun strings(values: Array<out CharSequence>?): JSONArray =
        JSONArray(values?.map { it?.toString().orEmpty() }.orEmpty())

    private fun find(group: PreferenceGroup, key: String): Preference? {
        for (index in 0 until group.preferenceCount) {
            val preference = group.getPreference(index) ?: continue
            if (preference is PreferenceGroup) {
                find(preference, key)?.let { return it }
            } else if (preference.key == key) {
                return preference
            }
        }
        return null
    }

    /**
     * Writes one value through the extension's own preference object, so its
     * persistence rules and listeners run exactly as they would in the app the
     * extension was written for.
     */
    fun apply(
        context: Context,
        sourceId: Long,
        source: Any,
        key: String,
        value: String,
    ): Boolean {
        if (key.isBlank()) return false
        val screen = screen(context, sourceId, source) ?: return false
        val preference = find(screen, key) ?: return false
        return runCatching {
            when (preference) {
                is ListPreference -> preference.value = value
                is MultiSelectListPreference ->
                    preference.values = value.split(SEPARATOR).filter { it.isNotEmpty() }.toSet()
                is EditTextPreference -> preference.text = value
                is TwoStatePreference -> preference.isChecked = value == "true"
                else -> return false
            }
            true
        }.getOrDefault(false)
    }

    /** Multi-select values travel as one string, the same way the bridge does. */
    const val SEPARATOR = "\u001f"
}
