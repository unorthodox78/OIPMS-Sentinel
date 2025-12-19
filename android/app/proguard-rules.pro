# Keep Facebook SDK (classes and members) and suppress warnings
-keep class com.facebook.** { *; }
-dontwarn com.facebook.**

# Keep the flutter_facebook_auth plugin package (safe)
-keep class app.meedu.** { *; }

# Keep Flutter plugins and embedding engine classes
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.engine.** { *; }

# (Optional) Keep Firebase Auth and Google Sign-In classes if minify is enabled
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class com.google.android.gms.auth.api.signin.** { *; }
-dontwarn com.google.android.gms.**

# Keep ML Kit and Google Play Services Vision classes
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
-keep class com.google.android.gms.** { *; }
