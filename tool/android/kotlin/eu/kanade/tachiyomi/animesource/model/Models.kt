package eu.kanade.tachiyomi.animesource.model

import okhttp3.Headers
import kotlinx.serialization.json.JsonObject
import java.io.Serializable

/**
 * One anime as an extension describes it.
 *
 * The property names are part of the ABI: an extension compiled against the
 * Aniyomi `source-api` writes `setThumbnail_url`, `setStatus`, `getUrl` by
 * exact JVM name, so they cannot be renamed for tidiness.
 */
@Suppress("PropertyName", "unused")
interface SAnime : Serializable {
    var url: String
    var title: String
    var artist: String?
    var author: String?
    var description: String?
    var genre: String?
    var status: Int
    var thumbnail_url: String?
    var background_url: String?
    var update_strategy: AnimeUpdateStrategy
    var fetch_type: FetchType
    var season_number: Double
    var initialized: Boolean
    var memo: JsonObject

    fun getGenres(): List<String>? = genre?.takeIf { it.isNotBlank() }
        ?.split(',')?.map { it.trim() }?.filter { it.isNotEmpty() }?.distinct()

    fun copy(): SAnime = create().also {
        it.url = url
        it.title = title
        it.artist = artist
        it.author = author
        it.description = description
        it.genre = genre
        it.status = status
        it.thumbnail_url = thumbnail_url
        it.background_url = background_url
        it.update_strategy = update_strategy
        it.fetch_type = fetch_type
        it.season_number = season_number
        it.initialized = initialized
        it.memo = memo
    }

    companion object {
        const val UNKNOWN = 0
        const val ONGOING = 1
        const val COMPLETED = 2
        const val LICENSED = 3
        const val PUBLISHING_FINISHED = 4
        const val CANCELLED = 5
        const val ON_HIATUS = 6
        const val UPCOMING = 7
        fun create(): SAnime = SAnimeImpl()
    }
}

class SAnimeImpl : SAnime {
    override var url: String = ""
    override var title: String = ""
    override var artist: String? = null
    override var author: String? = null
    override var description: String? = null
    override var genre: String? = null
    override var status: Int = SAnime.UNKNOWN
    override var thumbnail_url: String? = null
    override var background_url: String? = null
    override var update_strategy: AnimeUpdateStrategy = AnimeUpdateStrategy.ALWAYS_UPDATE
    override var fetch_type: FetchType = FetchType.Episodes
    override var season_number: Double = -1.0
    override var initialized: Boolean = false
    override var memo: JsonObject = JsonObject(emptyMap())
}

enum class AnimeUpdateStrategy { ALWAYS_UPDATE, ONLY_FETCH_ONCE }
enum class FetchType { Seasons, Episodes }

/** One episode of an anime. `episode_number` is a float, as in the real API. */
@Suppress("PropertyName", "unused")
interface SEpisode : Serializable {
    var url: String
    var name: String
    var date_upload: Long
    var episode_number: Float
    var scanlator: String?
    var fillermark: Boolean
    var summary: String?
    var preview_url: String?
    var memo: JsonObject

    fun copyFrom(other: SEpisode) {
        url = other.url
        name = other.name
        date_upload = other.date_upload
        episode_number = other.episode_number
        scanlator = other.scanlator
        fillermark = other.fillermark
        summary = other.summary
        preview_url = other.preview_url
        memo = other.memo
    }

    companion object {
        fun create(): SEpisode = SEpisodeImpl()
    }
}

class SEpisodeImpl : SEpisode {
    override var url: String = ""
    override var name: String = ""
    override var date_upload: Long = 0L
    override var episode_number: Float = -1f
    override var scanlator: String? = null
    override var fillermark: Boolean = false
    override var summary: String? = null
    override var preview_url: String? = null
    override var memo: JsonObject = JsonObject(emptyMap())
}

/** One page of a catalogue listing. */
class AnimesPage(val animes: List<SAnime>, val hasNextPage: Boolean)

/** A subtitle or audio track that travels with a [Video]. */
class Track(val url: String, val lang: String)

/** Where a timestamp marker sits inside an episode. */
enum class ChapterType {
    OPENING,
    ENDING,
    MIXED_OPENING,
    MIXED_ENDING,
}

/** An intro/outro marker, used by players that skip them. */
class TimeStamp(val start: Double, val end: Double, val name: String, val type: ChapterType)

/**
 * A playable stream.
 *
 * The 14-argument primary constructor is the one current Aniyomi extensions
 * link against; the 6-argument secondary constructor is the older shape that
 * v14 extensions still call. `videoTitle` is not part of the primary
 * constructor — the real API derives it — so it lives in the class body.
 */
@Suppress("unused")
data class Video(
    val videoUrl: String,
    val quality: String,
    val resolution: Int? = null,
    val bitrate: Int? = null,
    val headers: Headers? = null,
    val preferred: Boolean = false,
    val subtitleTracks: List<Track> = emptyList(),
    val audioTracks: List<Track> = emptyList(),
    val timestamps: List<TimeStamp> = emptyList(),
    val mpvArgs: List<Pair<String, String>> = emptyList(),
    val ffmpegVideoArgs: List<String> = emptyList(),
    val ffmpegStreamArgs: List<String> = emptyList(),
    val internalData: String = "",
    val initialized: Boolean = false,
) {
    var videoTitle: String = ""

    constructor(
        videoUrl: String,
        quality: String,
        videoTitle: String,
        headers: Headers? = null,
        subtitleTracks: List<Track> = emptyList(),
        audioTracks: List<Track> = emptyList(),
    ) : this(
        videoUrl = videoUrl,
        quality = quality,
        headers = headers,
        subtitleTracks = subtitleTracks,
        audioTracks = audioTracks,
    ) {
        this.videoTitle = videoTitle
    }

    /** What a picker shows: the quality if the extension gave one, else the url. */
    fun label(): String = videoTitle.ifBlank { quality.ifBlank { videoUrl } }
}

/** A mirror that has to be queried before it yields [videoList]. */
@Suppress("unused")
class Hoster(
    val hosterName: String,
    val hosterUrl: String,
    val videoList: List<Video> = emptyList(),
    val internalData: String = "",
    val initialized: Boolean = false,
) {
    companion object {
        /** Flattens a mixed list of hosters and videos into hosters. */
        fun toHosterList(list: List<Any?>): List<Hoster> = list.mapNotNull { entry ->
            when (entry) {
                is Hoster -> entry
                is Video -> Hoster(entry.quality, entry.videoUrl, listOf(entry))
                else -> null
            }
        }
    }
}

/**
 * The filter tree an anime source exposes.
 *
 * Kept separate from the manga `Filter` type on purpose: the two live in
 * different packages in the real API and an extension links against this one.
 */
@Suppress("unused")
open class AnimeFilter<T>(val name: String, var state: T) {

    open class Header(name: String) : AnimeFilter<Any>(name, 0)

    open class Separator(name: String = "") : AnimeFilter<Any>(name, 0)

    open class CheckBox(name: String, state: Boolean = false) : AnimeFilter<Boolean>(name, state)

    open class Select(name: String, val values: Array<Any>, state: Int = 0) : AnimeFilter<Int>(name, state) {
        val value: String get() = values.getOrNull(state)?.toString().orEmpty()
    }

    open class Text(name: String, state: String = "") : AnimeFilter<String>(name, state)

    open class Group(name: String, state: List<AnimeFilter<*>> = emptyList()) :
        AnimeFilter<List<AnimeFilter<*>>>(name, state)
}

/** The ordered list of filters a source hands to its search. */
class AnimeFilterList(vararg val list: AnimeFilter<*>) : ArrayList<AnimeFilter<*>>(list.asList())
