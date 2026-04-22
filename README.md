# klean

<p align="center">
  <img src="docs/assets/klean-app-icon-master.png" alt="klean app icon" width="128" />
</p>

<p align="center">
  <strong>Native macOS storage cleanup for developer machines.</strong>
</p>

<p align="center">
  <sub>Scan storage hotspots, surface safe cleanup routines, and reclaim space from Xcode, Flutter, SwiftPM, Docker, and other local build tooling.</sub>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2015-1f2937?style=flat-square" alt="macOS 15" />
  <img src="https://img.shields.io/badge/built%20with-SwiftUI-2f7cf6?style=flat-square" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/focus-developer%20cleanups-3c8f4f?style=flat-square" alt="Developer cleanups" />
</p>

![klean dashboard](docs/assets/klean-dashboard-public.png)

## What It Is

`klean` is a native macOS dashboard that combines two jobs:

- explain where storage is going on your Mac
- give you high-confidence cleanup routines for reclaimable space

The goal is not to guess at hidden macOS internals. The goal is to make the useful, safe, and actionable parts obvious.

## Why It Is Useful

Developer machines accumulate a lot of storage waste that is technically rebuildable but easy to forget:

- Xcode `DerivedData`
- old Xcode archives
- SwiftPM caches
- Flutter and Dart package caches
- CoreSimulator caches
- Docker build cache
- regular user caches and trash

`klean` puts those into one UI, with reclaimable size, risk labeling, and direct actions.

## Current Product Direction

The app is moving from a pure storage browser toward a local maintenance dashboard for dev-heavy Macs.

Today it already covers:

- storage overview with transparent `System/Rest`
- hotspot scanning for common heavy folders
- safe cleanup actions for selected locations
- dedicated developer cleanup routines in the dashboard
- cached startup with progressive refresh during scans

## Core Features

| Area | What You Get |
| --- | --- |
| Storage Overview | Used, free, scanned, and unexplained storage shown without pretending opaque system data is fully understood |
| Hotspot Scan | Fast scan across common heavy directories like Downloads, Documents, Pictures, Caches, Xcode, and Simulator data |
| Developer Cleanups | Ready-to-run routines for common rebuildable artifacts from local development workflows |
| Safety Model | Risk labels such as `Sicher`, `Pruefen`, and `Vorsicht`, plus explicit estimated reclaimable space |
| Direct Actions | Reveal in Finder, move to Trash, or run a known cleanup routine from the UI |
| Cached Startup | The last successful snapshot appears immediately while a fresh scan streams in |

## Developer Cleanup Routines

The current dashboard can surface routines like:

- `Xcode DerivedData`
- `Xcode Archives`
- `SwiftPM Cache`
- `Flutter Pub Cache`
- `CoreSimulator Caches`
- `Docker Build Cache`

The intent is that these routines are allowlist-based and understandable, not generic “delete random large files” actions.

## Design Principles

- Native macOS app, not an Electron wrapper
- Local-first scanning and cleanup
- Clear separation between safe cleanup and areas that still need review
- No fake precision where macOS itself is opaque
- Dashboard-first UX instead of raw filesystem browsing

## Build

### Requirements

- Xcode 16 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Generate And Run

```bash
xcodegen generate
open klean.xcodeproj
```

### Build From Terminal

```bash
xcodebuild -project klean.xcodeproj -scheme klean -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

## Privacy And Permissions

- All scanning happens locally on your Mac
- No storage data is uploaded anywhere by the app
- Full Disk Access may be needed for deeper visibility into protected folders
- Some storage remains inherently opaque on macOS, and `klean` keeps that visible instead of hiding it

## Project Structure

```text
klean/
  Models/
  Services/
  ViewModels/
  Views/
project.yml
```

## Notes

- The app UI is currently mostly German
- The repository and code comments stay in English for public sharing
