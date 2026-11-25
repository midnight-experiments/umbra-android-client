# umbra-android-client

The Android shell of the IPIR+SP client: a Gradle library project over `libps_client.so` and the UniFFI Kotlin
bindings built by [`universal-gpu-reinspire-client`](../universal-gpu-reinspire-client) (`dist/android/`).

| Path | What |
|---|---|
| `build.gradle.kts` | library `ps.client` (AGP 8.7.3, Kotlin 2.0.21, compileSdk 35, minSdk 26, JDK 17); depends on JNA, which UniFFI's Kotlin bindings use |
| `src/main/jniLibs/`, `src/main/kotlin/uniffi/` | build outputs copied in by `scripts/test.sh` (not committed) |
| `src/androidTest/kotlin/ps/client/RoundTripTest.kt` | the round trip on a device or emulator, against the test server |
| `gradlew` | Gradle wrapper (8.10.2) |

```kotlin
import uniffi.ps_client.PsClient
val client = PsClient(rows.toUInt(), cols.toUInt(), seed, snapshot, masks)
val request = client.request(42u)                    // send request.bytes()
val row = client.decode(request, answer)            // u16 little-endian cells
```

## Build and test

Needs the Rust repository next to this one (or `RUST_CLIENT=<path>`), JDK 17, the Android SDK with
`platforms;android-35`, `build-tools;35.0.0`, `platform-tools`, the NDK `27.2.12479018`, `cargo-ndk`, and a device or
emulator. This was set up with:

```sh
brew install openjdk@17 && brew install --cask android-commandlinetools
yes | sdkmanager --licenses
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0" "ndk;27.2.12479018" "emulator" \
  "system-images;android-35;google_apis;arm64-v8a"
cargo install cargo-ndk
avdmanager create avd -n ps-api35 -k "system-images;android-35;google_apis;arm64-v8a"
```

Then:

```sh
AVD=ps-api35 scripts/test.sh      # AVD starts that emulator headless if no device is connected
```

It builds the `.so` files, the Kotlin bindings and the test server in the Rust repository, copies them here, starts
`ps-server` on port 8787 (`PORT`) with three tables (2,048 × 2,048, 8,192 × 4,096, 32,768 × 2,048), and runs
`connectedDebugAndroidTest`. The emulator reaches the host at `10.0.2.2`, and the test's `server` argument points
there. For each table the test loads the masks, makes 7 requests, has the server answer them, decodes, and asserts
that the decoded row equals the table's row byte for byte. The reports are in `results/reports.jsonl`.
`ANDROID_HOME`, `ANDROID_NDK_HOME` and `JAVA_HOME` default to the Homebrew paths above.

## Measured (API 35 arm64-v8a emulator on an Apple M4 Max: near native, so not a phone's speed)

Query build 6–26 ms, decode 0.8–1.4 ms (mostly JNA copying the byte arrays), masks load 3–21 ms (the first includes
loading the library). `libps_client.so` is 567 KB (arm64-v8a) and 620 KB (x86_64). A request is 40–228 KB, an
answer 5.7–11 KB.
