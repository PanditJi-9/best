import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// A release key lives only in CI secrets, is written to android/key.properties
// by tool/configure_signing.sh, and never enters the repository. Without it the
// build stays debug-signed so a contributor can still produce an APK.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "app.best.best_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.best.best_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    sourceSets.getByName("test").java.srcDir(
        rootProject.projectDir.resolve("../../../tool/android/tests"),
    )

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8 must not touch this APK.
            //
            // A Mihon/Komikku extension is a separate dex file that links against
            // class and method names compiled into it: `eu.kanade.tachiyomi.*`,
            // `rx.*`, `okhttp3.*`, `org.jsoup.*`, `uy.kohesive.injekt.*`, the
            // Kotlin stdlib. Renaming, merging or inlining any of them — or
            // dropping the generic `Signature` attributes Injekt reads with
            // `getGenericSuperclass()` — turns every installed extension into a
            // `NoClassDefFoundError` at run time. The Flutter Gradle plugin turns
            // minification on for release builds, so it has to be turned off here.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

/**
 * The extension runtime.
 *
 * Best hosts Mihon/Komikku extension APKs itself: the Kotlin sources under
 * `tool/android/kotlin/` are the real implementation of the `source-api`
 * contract those APKs were compiled against, and these libraries are what the
 * extensions reach for at run time (OkHttp for requests, Jsoup for parsing,
 * RxJava 1 for the streaming API, Injekt for the service locator). None of them
 * contains a scraper: the extension is the program.
 */
dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    // Current MangaDex/AnimeXin bundles call the Kotlin Duration overloads in
    // OkHttp 5 (e.g. CacheControl.Builder.maxStale-LRDsOJo), absent in 4.x.
    implementation("com.squareup.okhttp3:okhttp:5.3.2")
    // Current Keiyoushi sources build a CompressionInterceptor over Gzip,
    // Deflate, Brotli and Zstd. These modules ship the codec classes the
    // extension links against; without them every catalogue request fails with
    // NoClassDefFoundError: okhttp3/brotli/Brotli.
    implementation("com.squareup.okhttp3:okhttp-brotli:5.3.2")
    implementation("com.squareup.okhttp3:okhttp-zstd:5.3.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
    // AniZone/AnimePahe/AnimeXin serialize protobuf payloads; MangaFire links
    // against androidx.webkit's WebView compat boundary; Anime4Up and other
    // extractor-based anime sources run JavaScript through QuickJS. All three
    // are part of the Aniyomi host surface an extension may reference.
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-protobuf:1.9.0")
    implementation("androidx.webkit:webkit:1.12.1")
    implementation("app.cash.quickjs:quickjs-android:0.9.2")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json-okio:1.9.0")
    implementation("org.jsoup:jsoup:1.18.3")
    implementation("io.reactivex:rxjava:1.3.8")
    implementation("io.reactivex:rxandroid:1.2.1")
    implementation("uy.kohesive.injekt:injekt-core:1.16.1")
    implementation("androidx.preference:preference:1.2.1")
    testImplementation("junit:junit:4.13.2")
}
