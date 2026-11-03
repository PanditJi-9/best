package eu.kanade.tachiyomi.source.model

import android.net.Uri

/**
 * The real, working implementation of the Mihon/Komikku source model.
 *
 * Extension APKs are compiled against `extensions-lib`, where every one of these
 * members throws `Exception("Stub!")`. The extension never ships an
 * implementation of its own: it calls `SManga.create()` and the host is
 * expected to answer with a real object. Best therefore ships this file, which
 * is the runtime half of the contract — same package, same class names, same
 * members, real behaviour.
 *
 * Keep every member the stub declares. Adding a member is safe (extensions
 * compiled against an older lib simply never call it); removing or renaming one
 * breaks every extension at once.
 */
@Suppress("unused", "PropertyName")
interface SManga {

    var url: String

    var title: String

    var artist: String?

    var author: String?

    var description: String?

    var genre: String?

    var status: Int

    var thumbnail_url: String?

    var update_strategy: UpdateStrategy

    var initialized: Boolean

    companion object {
        const val UNKNOWN = 0
        const val ONGOING = 1
        const val COMPLETED = 2
        const val LICENSED = 3
        const val PUBLISHING_FINISHED = 4
        const val CANCELLED = 5
        const val ON_HIATUS = 6

        fun create(): SManga = SMangaImpl()
    }
}

class SMangaImpl : SManga {
    override var url: String = ""
    override var title: String = ""
    override var artist: String? = null
    override var author: String? = null
    override var description: String? = null
    override var genre: String? = null
    override var status: Int = SManga.UNKNOWN
    override var thumbnail_url: String? = null
    override var update_strategy: UpdateStrategy = UpdateStrategy.ALWAYS_UPDATE
    override var initialized: Boolean = false
}

@Suppress("unused", "PropertyName")
interface SChapter {

    var url: String

    var name: String

    var date_upload: Long

    var chapter_number: Float

    var scanlator: String?

    companion object {
        fun create(): SChapter = SChapterImpl()
    }
}

class SChapterImpl : SChapter {
    override var url: String = ""
    override var name: String = ""
    override var date_upload: Long = 0L
    override var chapter_number: Float = -1f
    override var scanlator: String? = null
}

@Suppress("unused")
class Page(
    val index: Int,
    val url: String = "",
    var imageUrl: String? = null,
    var uri: Uri? = null,
)

@Suppress("unused")
data class MangasPage(val mangas: List<SManga>, val hasNextPage: Boolean)

/** Current extensions-lib update result; class and constructor are ABI, not a data class. */
@Suppress("unused")
class SMangaUpdate(val manga: SManga, val chapters: List<SChapter>)

@Suppress("unused")
enum class UpdateStrategy {
    ALWAYS_UPDATE,
    ONLY_FETCH_ONCE,
}

@Suppress("unused")
sealed class Filter<T>(val name: String, var state: T) {
    open class Header(name: String) : Filter<Any>(name, 0)
    open class Separator(name: String = "") : Filter<Any>(name, 0)
    abstract class Select<V>(name: String, val values: Array<V>, state: Int = 0) : Filter<Int>(name, state)
    abstract class Text(name: String, state: String = "") : Filter<String>(name, state)
    abstract class CheckBox(name: String, state: Boolean = false) : Filter<Boolean>(name, state)
    abstract class TriState(name: String, state: Int = STATE_IGNORE) : Filter<Int>(name, state) {
        fun isIgnored() = state == STATE_IGNORE
        fun isIncluded() = state == STATE_INCLUDE
        fun isExcluded() = state == STATE_EXCLUDE

        companion object {
            const val STATE_IGNORE = 0
            const val STATE_INCLUDE = 1
            const val STATE_EXCLUDE = 2
        }
    }
    abstract class Group<V>(name: String, state: List<V>) : Filter<List<V>>(name, state)

    abstract class Sort(name: String, val values: Array<String>, state: Selection? = null) :
        Filter<Sort.Selection?>(name, state) {
        data class Selection(val index: Int, val ascending: Boolean)
    }
}

@Suppress("unused")
data class FilterList(val list: List<Filter<*>>) : List<Filter<*>> by list {

    constructor(vararg fs: Filter<*>) : this(if (fs.isNotEmpty()) fs.asList() else emptyList())
}
