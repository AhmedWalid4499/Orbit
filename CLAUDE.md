# Orbit

Native macOS life organizer (SwiftUI + SwiftData), built with SwiftPM: `scripts/build-app.sh` produces a signed `build/Orbit.app`.

## Shipping changes

The owner installs updates through the in-app updater, which reads GitHub Releases on `AhmedWalid4499/Orbit`. After any change they should get:

1. Bump the version (semver) and publish: `scripts/release.sh <version> "<short user-facing notes>"`.
   This commits, tags `v<version>`, pushes, builds, and uploads `Orbit-<version>.zip` as a release asset.
2. Never publish a build that isn't signed with the Apple Development certificate: the updater refuses builds from a different team, and an unsigned build would reset Keychain and privacy permissions.

## Windows app

`windows/` is the Windows version (Electron + React + TypeScript). It reads and writes the same Supabase `orbit_records` rows as the Mac app's `CloudSync.swift`, so field names in `windows/src/renderer/src/lib/models.ts` must match the Mac encoders, and dates must be ISO strings without milliseconds. `scripts/release.sh` also builds the Windows installer (`scripts/build-windows.sh`, needs Rosetta on Apple silicon) and uploads `Orbit-Setup.exe`, its blockmap and `latest.yml` (read by the Windows updater) to the same release. Preview the window with sample data: build with `npx electron-vite build` in `windows/`, run `node windows/scripts-preview.cjs`, open `/?demo`.

## Notes

- Secrets live in one Keychain item (`Keychain` in `Services/Claude.swift`); never put keys in files.
- `ORBIT_SNAPSHOT_DIR=... ORBIT_SNAPSHOT_DEMO=1 build/Orbit.app/Contents/MacOS/Orbit` renders every tab to PNG with in-memory demo data and makes no network calls.
