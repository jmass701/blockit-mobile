# Building BlockIT Mobile in Termux (on-device, no PC/Android Studio needed)

This project can be built directly on your phone since it targets arm64-v8a
only — no emulator, no separate computer. Flutter itself doesn't officially
support running inside Termux, but there are community toolchains that make
it work by swapping in Termux's own `aapt2` (Android's resource compiler),
since Google's official build-tools only ship `aapt2` for x86_64 Linux, not
ARM64. This doc has NOT been run end-to-end here (no Android device
available in the environment that built this project) — if a step doesn't
match what you see, tell me the exact error and I'll adjust.

Requirements: an arm64-v8a Android phone, Termux from F-Droid (not the
Play Store version, which is outdated and unmaintained), and roughly 8GB
of free storage for the toolchain.

## 1. Install a Flutter toolchain built for Termux

Two community projects handle the hard part (Flutter SDK + Android SDK +
JDK + the aapt2 swap) as a single install script. Try the first; if it
fails or is out of date, fall back to the second.

**Option A — termux-flutter-wsl** (actively describes supporting existing
projects, which is what we need here):
```
pkg update && pkg upgrade -y
pkg install -y curl
curl -L https://raw.githubusercontent.com/ImL1s/termux-flutter-wsl/master/install_flutter_complete.sh -o install_flutter_complete.sh
bash install_flutter_complete.sh
```

**Option B — flutter_in_termux** (uses a proot-distro Debian environment):
```
curl -s https://raw.githubusercontent.com/Hax4us/flutter_in_termux/master/install.sh | bash -s
proot-distro login flutter
```
(Everything after this point runs inside `proot-distro login flutter`
if you used Option B.)

## 2. Copy this project in

Get this `blockit_mobile` folder onto the phone (e.g. download the zip
into Termux's storage — run `termux-setup-storage` once first to allow
access to your Downloads folder — then `unzip` it), and `cd` into it.

## 3. Point Gradle at Termux's own aapt2

The project already restricts native builds to `arm64-v8a` in
`android/app/build.gradle`. You still need to tell Gradle to use Termux's
`aapt2` binary instead of the x86_64 one it would otherwise try to
download. Do this as a Termux-wide setting (not inside the project, so it
never affects a future build from a real PC) by creating/editing
`~/.gradle/gradle.properties`:
```
mkdir -p ~/.gradle
echo "android.aapt2FromMavenOverride=$PREFIX/bin/aapt2" >> ~/.gradle/gradle.properties
```
(`$PREFIX` is Termux's own path variable, expands to something like
`/data/data/com.termux/files/usr`.)

## 4. Get dependencies and build

```
flutter pub get
flutter build apk --release --target-platform android-arm64
```

The first build is slow (Gradle has to download the Android Gradle
Plugin, Kotlin compiler, etc. over your connection) — expect it to take a
while the first time, faster after that. If the very first attempt fails
partway through with an aapt2-related error, that's a known hiccup with
these toolchains (the guides describe re-running the build a second time
after Gradle has cached the plugin) — just run the `flutter build apk`
command again.

The finished APK lands at:
```
build/app/outputs/flutter-apk/app-release.apk
```

## 5. Install it

```
pkg install android-tools   # gives you adb, if you want to install via cable/wireless debugging
```
or just open the APK file directly in a file manager on the phone and
tap to install (you'll need to allow "install from this source" once).

## If this doesn't work

Send me the exact command and the exact error text. The two toolchain
projects above (and the underlying aapt2-swap trick) are actively
maintained community workarounds, not an official Flutter target, so
version drift between them and this project's `pubspec.yaml` /
`build.gradle` is the most likely failure point — that's very fixable
once I can see what actually broke.
