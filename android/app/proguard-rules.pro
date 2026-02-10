# Add project specific ProGuard rules here.

# FFmpegKit ProGuard Rules - https://github.com/arthenica/ffmpeg-kit
# Prevent R8 from stripping native libraries and preserve JNI functionality

# Keep ffmpeg-kit native libraries from being stripped or modified
-keep class com.antonkarpenko.ffmpegkit.** { *; }
-keep class com.arthenica.ffmpegkit.** { *; }

# Keep native methods
-keepclassmembers class com.antonkarpenko.ffmpegkit.** {
    native <methods>;
}
-keepclassmembers class com.arthenica.ffmpegkit.** {
    native <methods>;
}

# Prevent R8 from removing native libraries
-keep class libffmpegkit { *; }
-keep class libffmpegkit_abidetect { *; }
-keep class libffmpegkit_full { *; }
-keep class libffmpegkit_full_gpl { *; }
-keep class libffmpegkit_lts { *; }
-keep class libffmpegkit_full_gpl_lts { *; }

# Prevent R8 from stripping .so files
-keep class * implements android.content.pm.PackageManagerInstaller$MigrationCallback { *; }
-keepclassmembers class * implements android.content.pm.PackageManagerInstaller$MigrationCallback { *; }

# Keep native library loading methods
-keepclassmembers class * {
    native <methods>;
}

# General Android rules
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
-keep public class * extends java.lang.Error

# Kotlin metadata
-keep class kotlin.Metadata { *; }

# For applications that target Android API level 23 (Android M) or lower,
# you may need to add the following to avoid the crash when loading native libraries:
-dontwarn java.lang.invoke.*
-dontwarn java.lang.management.*
-dontwarn java.io.File.*

# Prevent native method registration failures
-keepclassmembers,allowobfuscation class * {
    @com.arthenica.ffmpegkit.Level <fields>;
    @com.arthenica.ffmpegkit.Level <methods>;
}
