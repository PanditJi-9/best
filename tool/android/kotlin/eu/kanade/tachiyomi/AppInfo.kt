package eu.kanade.tachiyomi

/**
 * Version of the host, which extensions read to decide whether a feature exists.
 * Reporting the real APK version keeps extensions on the code path they were
 * built for instead of an "unknown host" branch. The loader fills these in from
 * PackageManager at start-up.
 */
object AppInfo {
    internal var versionCode: Int = 1
    internal var versionName: String = "0.0.0"

    fun getVersionCode(): Int = versionCode

    fun getVersionName(): String = versionName
}
