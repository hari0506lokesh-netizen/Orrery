# Orrery for iPhone

This folder is a complete Xcode project for Orrery as a native iPhone app. It has its own icon on your home screen, no Safari bar, and it works offline. The whole Orrery app ships inside it.

What the native app adds over the web version:

- **Opens straight from your lock automations.** Links like `orrery://gate/instagram` open the app itself, not Safari.
- **Real haptics** when you check off a task, finish the day or turn back at a gate.
- **Your data is kept twice:** once in the app's web storage and once in a native copy, so iOS clearing web data can't lose it.
- **Native export and restore.** Export goes through the iPhone share sheet (save it to Files). Restore takes a backup file.

## Why there's no one-tap download link

Apple only lets an iPhone install an app that has been signed with an Apple account. Signing happens on a Mac with Xcode, or with a signing tool such as Sideloadly. A link that installs straight onto your phone only exists through Apple's paid Developer Program (TestFlight or the App Store). Pick one of the routes below.

## Route A: you have a Mac (simplest)

1. Install **Xcode** (version 16 or newer) from the Mac App Store.
2. Unzip this folder and double-click `Orrery.xcodeproj`.
3. In Xcode, open **Settings → Accounts** and add your Apple ID. A free one works.
4. Click the blue **Orrery** project in the left sidebar, choose the **Orrery** target, then open **Signing & Capabilities**. Set **Team** to your name (Personal Team).
   - If Xcode says the bundle identifier isn't available, change `app.orrery.daily` to something unique, such as `app.orrery.daily.yourname`.
5. Connect your iPhone with a cable and tap **Trust** on the phone.
6. On the iPhone, turn on **Settings → Privacy & Security → Developer Mode**. The phone restarts.
7. In Xcode, choose your iPhone at the top of the window, then press the **Run** (▶) button.
8. The first time, the iPhone may block the app. Go to **Settings → General → VPN & Device Management**, tap your Apple ID and choose **Trust**. Then open Orrery.

**With a free Apple ID:** the app stops opening after 7 days. Connect the phone and press Run again. Your data stays.

**With the paid Apple Developer Program (US$99 a year):** installs last a year, and you can send yourself a TestFlight link instead of using a cable.

## Route B: no Mac (Windows, or a Mac without Xcode)

A GitHub-hosted Mac builds the app, then **Sideloadly** signs it with your Apple ID and installs it.

1. Create a GitHub repository and upload everything in this folder, including the hidden `.github` folder.
2. In the repository, open **Actions → Build unsigned IPA → Run workflow**.
   - This is free for public repositories. Private repositories use up your included minutes faster on Mac machines.
3. When the run finishes, download the **Orrery-unsigned-ipa** artifact and unzip it to get `Orrery-unsigned.ipa`.
4. Install Sideloadly from sideloadly.io, plug in your iPhone, drag the `.ipa` in, sign in with your Apple ID and press **Start**.
5. On the iPhone, turn on Developer Mode and trust your Apple ID, as in Route A steps 6 and 8.

The same 7-day limit applies with a free Apple ID: re-run Sideloadly to refresh.

## Moving your current data into the app

1. In the web version of Orrery, open **History → Export my data**, and save the file to Files.
2. In the iPhone app, open **History → Restore from a backup** and pick that file.

## Reconnecting the locks

Your two shortcuts (Orrery Gate and Orrery Pass) stay the same. Each automation needs the new link:

1. In the app, open **Locks**, tap an app, and tap **Copy automation link**. You get a link like `orrery://gate/instagram`.
2. In Shortcuts, open that app's automation and paste the link into its **Text** action, replacing the old claude.ai link.

## Good to know

- **Fonts:** the two typefaces load from Google Fonts the first time the app is online. Until then, and if they're never fetched, the app uses the iPhone's system fonts.
- **Locks still go through Shortcuts.** Blocking apps at system level, the way Screen Time does, needs Apple's Family Controls permission. That requires the paid program and Apple's approval to distribute, so it's a possible future step, not part of this build.
- **Updating Orrery later:** replace `Orrery/index.html` with a newer version and run again.

## What's in the folder

| Path | What it is |
|---|---|
| `Orrery.xcodeproj` | The Xcode project. |
| `Orrery/OrreryApp.swift` | The native shell. It covers the web view, offline page serving, deep links, haptics, storage copy and the share sheet. |
| `Orrery/index.html` | The Orrery app itself. |
| `Orrery/Assets.xcassets` | App icon and launch colour. |
| `Orrery-Info.plist` | Registers the `orrery://` link scheme and the black launch screen. |
| `project.yml` | Fallback project spec. Use it only if the `.xcodeproj` won't open: run `brew install xcodegen`, then `xcodegen` in this folder. |
| `.github/workflows/build-unsigned-ipa.yml` | The cloud build used in Route B. |
