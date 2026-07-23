# Building the APK with GitHub Actions (recommended)

After two different community Termux/Flutter toolchains both hit broken
dependencies, this is the reliable path: GitHub's own cloud build servers
run the *real*, officially-supported Flutter/Android toolchain — no
Termux-specific workarounds needed at all. You do this once per set of
code changes (or whenever you want a fresh APK); it takes about 5 minutes
and costs nothing (GitHub Actions is free for public repos, and for
private repos on a personal account you get a generous free monthly
quota that a small project like this won't come close to using).

## 1. Create a GitHub account and a new repo (if you don't already have one)

On any device with a browser: go to https://github.com, sign up if
needed, then click "New repository". Name it e.g. `blockit-mobile`.
Leave it **empty** (don't add a README/.gitignore/license) — you'll push
the existing project into it. Public or private both work fine.

## 2. Push this project to that repo

You can do this from Termux (where the project already is / will be
unzipped) or from any computer. From Termux:

```
pkg install -y git
cd ~/blockit_mobile      # wherever you unzipped this project
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/<your-username>/blockit-mobile.git
git push -u origin main
```

GitHub will prompt for a username and password — but GitHub no longer
accepts your account password for git operations. Instead, create a
"Personal Access Token" (Settings → Developer settings → Personal
access tokens → Generate new token, give it `repo` scope) and paste that
token in as the password when prompted.

## 3. Let it build

As soon as you push, GitHub Actions automatically picks up the
`.github/workflows/build-apk.yml` file already included in this project
and starts building. Watch it at:

```
https://github.com/<your-username>/blockit-mobile/actions
```

Click the running workflow to watch live logs. It typically takes
3-6 minutes (downloading the Flutter SDK and Android toolchain fresh
each time, then compiling).

## 4. Download the APK

Once the workflow shows a green checkmark, open that run's page and
scroll to the "Artifacts" section at the bottom — you'll see
`blockit-mobile-release-apk`. Click it to download a zip containing
`app-release.apk`. Transfer that to your phone (or download directly
from your phone's browser if you're on the phone already) and tap it
to install (allow "install from this source" if prompted).

## Making changes later

Any time you edit the code and want a new APK: commit and push again
(`git add . && git commit -m "..." && git push`), and a new build kicks
off automatically. You can also trigger a rebuild without any code
changes from the Actions tab → select the workflow → "Run workflow".

## If a build fails

Click into the failed run and read the red step's log — GitHub Actions
gives full, readable error output (unlike the truncated Termux script
output we were fighting with). Paste that error back and I'll fix
whatever's wrong in the project itself.
