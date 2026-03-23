#!/usr/bin/env bash

set -euo pipefail

INIT_DEST_DIR=""
INIT_PACKAGE_NAME=""
INIT_APP_NAME=""
INIT_TEMPLATE="compose-empty"
INIT_MIN_SDK="24"
INIT_COMPILE_SDK=""
INIT_TARGET_SDK=""
INIT_AGP_VERSION="9.1.0"
INIT_KOTLIN_VERSION="2.3.10"
INIT_GRADLE_VERSION="9.3.1"
INIT_COMPOSE_BOM="2026.02.01"
INIT_CORE_KTX_VERSION="1.17.0"
INIT_ACTIVITY_COMPOSE_VERSION="1.12.4"
INIT_LIFECYCLE_VERSION="2.10.0"
INIT_ANDROIDX_JUNIT_VERSION="1.3.0"
INIT_ESPRESSO_VERSION="3.7.0"
INIT_FORCE="0"

init_usage() {
  cat <<'EOF'
Usage:
  ./android init <directory> [options]

Options:
  --package NAME        application id / namespace, e.g. com.example.app
  --app-name NAME       display name shown on device
  --template NAME       template name (default: compose-empty)
  --min-sdk N           minimum sdk (default: 24)
  --compile-sdk N       compile sdk (default: highest installed platform)
  --target-sdk N        target sdk (default: compile sdk)
  --agp VERSION         Android Gradle Plugin version (default: 9.1.0)
  --kotlin VERSION      Compose compiler plugin version (default: 2.3.10)
  --gradle VERSION      Gradle wrapper version (default: 9.3.1)
  --compose-bom VER     Compose BOM version (default: 2026.02.01)
  --force               allow writing into an existing non-empty directory
  -h, --help            Show this help

Notes:
  The generated project is intentionally close to a current Android Studio
  Empty Activity setup: Kotlin DSL, version catalog, Gradle wrapper, one app
  module, and a Jetpack Compose entry screen.
EOF
}

parse_init_args() {
  while (($#)); do
    case "$1" in
      --package)
        INIT_PACKAGE_NAME="${2:-}"
        shift 2
        ;;
      --app-name)
        INIT_APP_NAME="${2:-}"
        shift 2
        ;;
      --template)
        INIT_TEMPLATE="${2:-}"
        shift 2
        ;;
      --min-sdk)
        INIT_MIN_SDK="${2:-}"
        shift 2
        ;;
      --compile-sdk)
        INIT_COMPILE_SDK="${2:-}"
        shift 2
        ;;
      --target-sdk)
        INIT_TARGET_SDK="${2:-}"
        shift 2
        ;;
      --agp)
        INIT_AGP_VERSION="${2:-}"
        shift 2
        ;;
      --kotlin)
        INIT_KOTLIN_VERSION="${2:-}"
        shift 2
        ;;
      --gradle)
        INIT_GRADLE_VERSION="${2:-}"
        shift 2
        ;;
      --compose-bom)
        INIT_COMPOSE_BOM="${2:-}"
        shift 2
        ;;
      --force)
        INIT_FORCE="1"
        shift
        ;;
      -h|--help)
        init_usage
        exit 0
        ;;
      *)
        if [[ -z "$INIT_DEST_DIR" ]]; then
          INIT_DEST_DIR="$1"
          shift
        else
          die "Unknown init argument: $1"
        fi
        ;;
    esac
  done
}

slugify_segment() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_]/_/g; s/^[^a-z]*/app/; s/_\+/_/g; s/^_//; s/_$//')"
  printf '%s\n' "${value:-app}"
}

default_package_name() {
  local leaf
  leaf="$(slugify_segment "$(basename "$INIT_DEST_DIR")")"
  printf 'com.example.%s\n' "$leaf"
}

humanize_app_name() {
  local raw
  raw="$(basename "$INIT_DEST_DIR" | sed 's/[-_]\+/ /g')"
  printf '%s\n' "$raw" | awk '{ for (i = 1; i <= NF; i++) { $i = toupper(substr($i,1,1)) tolower(substr($i,2)); } print }'
}

pascal_case() {
  local input out
  input="$(printf '%s' "$1" | sed 's/[^[:alnum:]]\+/ /g')"
  out="$(printf '%s\n' "$input" | awk '{ for (i = 1; i <= NF; i++) { $i = toupper(substr($i,1,1)) tolower(substr($i,2)); } printf "%s", $0 }' | tr -d ' ')"
  printf '%s\n' "${out:-App}"
}

package_to_path() {
  printf '%s\n' "${1//./\/}"
}

validate_package_name() {
  [[ "$INIT_PACKAGE_NAME" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]] || die "Invalid package name: $INIT_PACKAGE_NAME"
}

validate_numeric() {
  [[ "$2" =~ ^[0-9]+$ ]] || die "$1 must be numeric."
}

resolve_init_defaults() {
  [[ -n "$INIT_DEST_DIR" ]] || die "init requires a destination directory."

  case "$INIT_DEST_DIR" in
    /*)
      ;;
    *)
      INIT_DEST_DIR="$PWD/$INIT_DEST_DIR"
      ;;
  esac

  if [[ -z "$INIT_PACKAGE_NAME" ]]; then
    INIT_PACKAGE_NAME="$(default_package_name)"
  fi
  validate_package_name

  if [[ -z "$INIT_APP_NAME" ]]; then
    INIT_APP_NAME="$(humanize_app_name)"
  fi

  if [[ -z "$INIT_COMPILE_SDK" ]]; then
    INIT_COMPILE_SDK="$(detect_latest_compile_sdk || true)"
    INIT_COMPILE_SDK="${INIT_COMPILE_SDK:-36}"
  fi

  if [[ -z "$INIT_TARGET_SDK" ]]; then
    INIT_TARGET_SDK="$INIT_COMPILE_SDK"
  fi

  validate_numeric "min sdk" "$INIT_MIN_SDK"
  validate_numeric "compile sdk" "$INIT_COMPILE_SDK"
  validate_numeric "target sdk" "$INIT_TARGET_SDK"

  case "$INIT_TEMPLATE" in
    compose-empty)
      ;;
    *)
      die "Unsupported template: $INIT_TEMPLATE"
      ;;
  esac
}

ensure_init_target_dir() {
  if [[ -e "$INIT_DEST_DIR" ]]; then
    if [[ ! -d "$INIT_DEST_DIR" ]]; then
      die "Target exists and is not a directory: $INIT_DEST_DIR"
    fi

    if [[ "$INIT_FORCE" != "1" ]] && find "$INIT_DEST_DIR" -mindepth 1 -print -quit | grep -q .; then
      die "Target directory is not empty: $INIT_DEST_DIR (pass --force to allow)."
    fi
  fi

  mkdir -p "$INIT_DEST_DIR"
}

ensure_wrapper_assets() {
  local gradlew_src wrapper_jar_src wrapper_bat_src
  gradlew_src="$SCRIPT_DIR/assets/gradle/gradlew"
  wrapper_bat_src="$SCRIPT_DIR/assets/gradle/gradlew.bat"
  wrapper_jar_src="$SCRIPT_DIR/assets/gradle/wrapper/gradle-wrapper.jar"

  [[ -f "$gradlew_src" ]] || die "Missing bundled asset: $gradlew_src"
  [[ -f "$wrapper_bat_src" ]] || die "Missing bundled asset: $wrapper_bat_src"
  [[ -f "$wrapper_jar_src" ]] || die "Missing bundled asset: $wrapper_jar_src"
}

write_root_gitignore() {
  cat >"$INIT_DEST_DIR/.gitignore" <<'EOF'
*.iml
.gradle
/local.properties
/.idea/caches
/.idea/libraries
/.idea/modules.xml
/.idea/workspace.xml
/.idea/navEditor.xml
/.idea/assetWizardSettings.xml
/.kotlin
.DS_Store
/build
/captures
.externalNativeBuild
.cxx
EOF
}

write_gradle_properties() {
  cat >"$INIT_DEST_DIR/gradle.properties" <<'EOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
EOF
}

write_settings_gradle() {
  cat >"$INIT_DEST_DIR/settings.gradle.kts" <<EOF
import org.gradle.api.initialization.resolve.RepositoriesMode

pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "$(basename "$INIT_DEST_DIR")"
include(":app")
EOF
}

write_root_build_gradle() {
  cat >"$INIT_DEST_DIR/build.gradle.kts" <<'EOF'
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.compose.compiler) apply false
}
EOF
}

write_version_catalog() {
  mkdir -p "$INIT_DEST_DIR/gradle"
  cat >"$INIT_DEST_DIR/gradle/libs.versions.toml" <<EOF
[versions]
agp = "$INIT_AGP_VERSION"
kotlin = "$INIT_KOTLIN_VERSION"
coreKtx = "$INIT_CORE_KTX_VERSION"
junit = "4.13.2"
junitExt = "$INIT_ANDROIDX_JUNIT_VERSION"
espressoCore = "$INIT_ESPRESSO_VERSION"
lifecycleRuntimeKtx = "$INIT_LIFECYCLE_VERSION"
activityCompose = "$INIT_ACTIVITY_COMPOSE_VERSION"
composeBom = "$INIT_COMPOSE_BOM"

[libraries]
androidx-core-ktx = { group = "androidx.core", name = "core-ktx", version.ref = "coreKtx" }
androidx-lifecycle-runtime-ktx = { group = "androidx.lifecycle", name = "lifecycle-runtime-ktx", version.ref = "lifecycleRuntimeKtx" }
androidx-activity-compose = { group = "androidx.activity", name = "activity-compose", version.ref = "activityCompose" }
androidx-compose-bom = { group = "androidx.compose", name = "compose-bom", version.ref = "composeBom" }
androidx-ui = { group = "androidx.compose.ui", name = "ui" }
androidx-ui-graphics = { group = "androidx.compose.ui", name = "ui-graphics" }
androidx-ui-tooling = { group = "androidx.compose.ui", name = "ui-tooling" }
androidx-ui-tooling-preview = { group = "androidx.compose.ui", name = "ui-tooling-preview" }
androidx-ui-test-manifest = { group = "androidx.compose.ui", name = "ui-test-manifest" }
androidx-ui-test-junit4 = { group = "androidx.compose.ui", name = "ui-test-junit4" }
androidx-material3 = { group = "androidx.compose.material3", name = "material3" }
junit = { group = "junit", name = "junit", version.ref = "junit" }
androidx-junit = { group = "androidx.test.ext", name = "junit", version.ref = "junitExt" }
androidx-espresso-core = { group = "androidx.test.espresso", name = "espresso-core", version.ref = "espressoCore" }

[plugins]
android-application = { id = "com.android.application", version.ref = "agp" }
compose-compiler = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
EOF
}

write_wrapper_files() {
  mkdir -p "$INIT_DEST_DIR/gradle/wrapper"
  install -m 755 "$SCRIPT_DIR/assets/gradle/gradlew" "$INIT_DEST_DIR/gradlew"
  install -m 644 "$SCRIPT_DIR/assets/gradle/gradlew.bat" "$INIT_DEST_DIR/gradlew.bat"
  install -m 644 "$SCRIPT_DIR/assets/gradle/wrapper/gradle-wrapper.jar" "$INIT_DEST_DIR/gradle/wrapper/gradle-wrapper.jar"

  cat >"$INIT_DEST_DIR/gradle/wrapper/gradle-wrapper.properties" <<EOF
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-$INIT_GRADLE_VERSION-bin.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF
}

write_local_properties() {
  local sdk_root
  sdk_root="$(detect_android_sdk_root || true)"
  [[ -n "$sdk_root" ]] || return 0

  cat >"$INIT_DEST_DIR/local.properties" <<EOF
sdk.dir=$sdk_root
EOF
}

write_compose_app_module() {
  local package_path theme_name
  package_path="$(package_to_path "$INIT_PACKAGE_NAME")"
  theme_name="$(pascal_case "$INIT_APP_NAME")Theme"

  mkdir -p \
    "$INIT_DEST_DIR/app/src/main/java/$package_path/ui/theme" \
    "$INIT_DEST_DIR/app/src/main/res/values" \
    "$INIT_DEST_DIR/app/src/main/res/xml" \
    "$INIT_DEST_DIR/app/src/androidTest/java/$package_path" \
    "$INIT_DEST_DIR/app/src/test/java/$package_path"

  cat >"$INIT_DEST_DIR/app/build.gradle.kts" <<EOF
plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.compose.compiler)
}

android {
    namespace = "$INIT_PACKAGE_NAME"
    compileSdk = $INIT_COMPILE_SDK

    defaultConfig {
        applicationId = "$INIT_PACKAGE_NAME"
        minSdk = $INIT_MIN_SDK
        targetSdk = $INIT_TARGET_SDK
        versionCode = 1
        versionName = "1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)

    testImplementation(libs.junit)

    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.ui.test.junit4)

    debugImplementation(libs.androidx.ui.tooling)
    debugImplementation(libs.androidx.ui.test.manifest)
}
EOF

  cat >"$INIT_DEST_DIR/app/proguard-rules.pro" <<'EOF'
# Add project specific ProGuard rules here.
EOF

  cat >"$INIT_DEST_DIR/app/src/main/AndroidManifest.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <application
        android:allowBackup="true"
        android:dataExtractionRules="@xml/data_extraction_rules"
        android:fullBackupContent="@xml/backup_rules"
        android:label="@string/app_name"
        android:supportsRtl="true">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />

                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>

</manifest>
EOF

  cat >"$INIT_DEST_DIR/app/src/main/res/values/strings.xml" <<EOF
<resources>
    <string name="app_name">$INIT_APP_NAME</string>
</resources>
EOF

  cat >"$INIT_DEST_DIR/app/src/main/res/xml/backup_rules.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<full-backup-content>
    <include domain="sharedpref" path="." />
</full-backup-content>
EOF

  cat >"$INIT_DEST_DIR/app/src/main/res/xml/data_extraction_rules.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
    <cloud-backup />
    <device-transfer />
</data-extraction-rules>
EOF

  cat >"$INIT_DEST_DIR/app/src/main/java/$package_path/MainActivity.kt" <<EOF
package $INIT_PACKAGE_NAME

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import $INIT_PACKAGE_NAME.ui.theme.$theme_name

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            $theme_name {
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    Greeting(
                        name = "Android",
                        modifier = Modifier.padding(innerPadding),
                    )
                }
            }
        }
    }
}

@Composable
fun Greeting(name: String, modifier: Modifier = Modifier) {
    Text(
        text = "Hello \$name!",
        modifier = modifier,
    )
}

@Preview(showBackground = true)
@Composable
fun GreetingPreview() {
    $theme_name {
        Greeting("Android")
    }
}
EOF

  cat >"$INIT_DEST_DIR/app/src/main/java/$package_path/ui/theme/Color.kt" <<'EOF'
package __PACKAGE__.ui.theme

import androidx.compose.ui.graphics.Color

val Purple80 = Color(0xFFD0BCFF)
val PurpleGrey80 = Color(0xFFCCC2DC)
val Pink80 = Color(0xFFEFB8C8)

val Purple40 = Color(0xFF6650A4)
val PurpleGrey40 = Color(0xFF625B71)
val Pink40 = Color(0xFF7D5260)
EOF
  sed -i "s/__PACKAGE__/$INIT_PACKAGE_NAME/g" "$INIT_DEST_DIR/app/src/main/java/$package_path/ui/theme/Color.kt"

  cat >"$INIT_DEST_DIR/app/src/main/java/$package_path/ui/theme/Theme.kt" <<EOF
package $INIT_PACKAGE_NAME.ui.theme

import android.app.Activity
import android.os.Build
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.dynamicDarkColorScheme
import androidx.compose.material3.dynamicLightColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext

private val DarkColorScheme = darkColorScheme(
    primary = Purple80,
    secondary = PurpleGrey80,
    tertiary = Pink80,
)

private val LightColorScheme = lightColorScheme(
    primary = Purple40,
    secondary = PurpleGrey40,
    tertiary = Pink40,
)

@Composable
fun $theme_name(
    darkTheme: Boolean = isSystemInDarkTheme(),
    dynamicColor: Boolean = true,
    content: @Composable () -> Unit,
) {
    val colorScheme = when {
        dynamicColor && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
            val context = LocalContext.current
            if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
        }

        darkTheme -> DarkColorScheme
        else -> LightColorScheme
    }

    MaterialTheme(
        colorScheme = colorScheme,
        typography = Typography,
        content = content,
    )
}
EOF

  cat >"$INIT_DEST_DIR/app/src/main/java/$package_path/ui/theme/Type.kt" <<EOF
package $INIT_PACKAGE_NAME.ui.theme

import androidx.compose.material3.Typography

val Typography = Typography()
EOF

  cat >"$INIT_DEST_DIR/app/src/androidTest/java/$package_path/ExampleInstrumentedTest.kt" <<EOF
package $INIT_PACKAGE_NAME

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ExampleInstrumentedTest {
    @Test
    fun useAppContext() {
        val appContext = InstrumentationRegistry.getInstrumentation().targetContext
        assertEquals("$INIT_PACKAGE_NAME", appContext.packageName)
    }
}
EOF

  cat >"$INIT_DEST_DIR/app/src/test/java/$package_path/ExampleUnitTest.kt" <<'EOF'
package __PACKAGE__

import org.junit.Assert.assertEquals
import org.junit.Test

class ExampleUnitTest {
    @Test
    fun addition_isCorrect() {
        assertEquals(4, 2 + 2)
    }
}
EOF
  sed -i "s/__PACKAGE__/$INIT_PACKAGE_NAME/g" "$INIT_DEST_DIR/app/src/test/java/$package_path/ExampleUnitTest.kt"
}

cmd_init() {
  parse_init_args "${COMMAND_ARGS[@]}"
  resolve_init_defaults
  ensure_init_target_dir
  ensure_wrapper_assets

  write_root_gitignore
  write_gradle_properties
  write_settings_gradle
  write_root_build_gradle
  write_version_catalog
  write_wrapper_files
  write_local_properties
  write_compose_app_module

  printf 'Initialized Android project:\n'
  printf '  dir=%s\n' "$INIT_DEST_DIR"
  printf '  package=%s\n' "$INIT_PACKAGE_NAME"
  printf '  app_name=%s\n' "$INIT_APP_NAME"
  printf '  template=%s\n' "$INIT_TEMPLATE"
  printf '  compile_sdk=%s\n' "$INIT_COMPILE_SDK"
  printf '  target_sdk=%s\n' "$INIT_TARGET_SDK"
  printf '  min_sdk=%s\n' "$INIT_MIN_SDK"
  printf '  agp=%s\n' "$INIT_AGP_VERSION"
  printf '  kotlin=%s\n' "$INIT_KOTLIN_VERSION"
  printf '  gradle=%s\n' "$INIT_GRADLE_VERSION"
}
