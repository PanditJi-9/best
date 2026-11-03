package eu.kanade.tachiyomi.network

/**
 * The standard "not a successful HTTP response" error.
 *
 * Extensions built for current extensions-lib throw and catch this class by
 * name (Toonily and MangaPark do), so its binary identity matters: same package,
 * same single-Int constructor, same `IllegalStateException` parent.
 */
@Suppress("unused")
class HttpException(val code: Int) : IllegalStateException("HTTP error $code")
