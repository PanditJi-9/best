package eu.kanade.tachiyomi.animesource.model

import okhttp3.Headers

/**
 * One anime as an extension describes it.
 *
 * The property names are part of the ABI: an extension compiled against the
 * Aniyomi `source-api` writes `setThumbnail_url`, `setStatus`, `getUrl` by
 * exact JVM name, so they cannot be renamed for tidiness.
 */
@Suppress("PropertyName", "unused")
open class SAnime {
    var url: String = ""
    var title: String = ""
    var artist: String? = null
    var author: String? = null
    var description: String? = null
    var genre: String? = null
    var status: Int = 0
    var thumbnail_url: String? = null
    var initialized: Boolean = false

    companion object {
        fun create(): SAnime = SAnime()
    }
}

/** One episode of an anime. `episode_number` is a float, as in the real API. */
@Suppress("PropertyName", "unused")
open class SEpisode {
    var url: String = ""
    var name: String = ""
    var date_upload: Long = 0L
    var episode_number: Float = -1f
    var scanlator: String? = null
    var filler: Boolean = false
    var summary: String? = null
    var thumbnail_url: String? = null

    companion object {
        fun create(): SEpisode = SEpisode()
    }
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
