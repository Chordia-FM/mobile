# ExoPlayer/Media3 resolves some components reflectively; R8 cannot see those edges.
-keep class com.google.android.exoplayer2.** { *; }
-keep class androidx.media3.** { *; }
-dontwarn com.google.android.exoplayer2.**
-dontwarn androidx.media3.**

# audio_service's service and receiver are named from the manifest, never from Kotlin.
-keep class com.ryanheise.audioservice.** { *; }
