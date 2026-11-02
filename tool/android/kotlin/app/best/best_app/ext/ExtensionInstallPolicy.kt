package app.best.best_app.ext

import java.net.URI

/** Pure validation, also exercised by the release JVM gate. */
internal object ExtensionInstallPolicy {
    fun validateIdentity(
        expectedPackage: String, expectedVersion: Long,
        actualPackage: String, actualVersion: Long,
        newSigners: Set<String>, oldVersion: Long? = null,
        oldSigners: Set<String>? = null,
    ) {
        require(Regex("eu\\.kanade\\.tachiyomi\\.(animeextension|extension)\\.[A-Za-z0-9_.]+")
            .matches(expectedPackage)) { "Not an extension package." }
        require(actualPackage == expectedPackage) { "The APK package does not match its repository entry." }
        require(expectedVersion > 0 && actualVersion == expectedVersion) { "The APK version does not match its repository entry." }
        require(newSigners.isNotEmpty()) { "The APK has no verified signing certificate." }
        if (oldVersion != null) {
            require(actualVersion >= oldVersion) { "Extension downgrades are not allowed." }
            require(!oldSigners.isNullOrEmpty() && oldSigners == newSigners) {
                "The extension publisher signature changed. The existing APK was kept."
            }
        }
    }

    fun allowDownload(url: String, redirected: Boolean = false): Boolean {
        val uri = runCatching { URI(url) }.getOrNull() ?: return false
        if (uri.scheme != "https" || uri.userInfo != null || uri.port !in listOf(-1, 443)) return false
        val path = uri.path ?: return false
        if (path.split('/').any { it == "." || it == ".." }) return false
        return when (uri.host) {
            "github.com" -> path.startsWith("/keiyoushi/extensions/releases/download/") ||
                path.startsWith("/yuzono/anime-repo/releases/download/")
            "raw.githubusercontent.com" -> path.startsWith("/yuzono/anime-repo/repo/apk/")
            "release-assets.githubusercontent.com", "objects.githubusercontent.com" -> redirected
            else -> false
        }
    }
}
