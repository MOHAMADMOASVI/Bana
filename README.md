# Project Launcher

A lightweight native macOS app (SwiftUI, macOS 13+) that finds local projects in a folder and runs their dev servers, with live logs, LAN links and QR codes.

| Detected by | Type | Default command |
|---|---|---|
| `artisan` | Laravel | `php artisan serve --host=0.0.0.0 --port={port} --no-reload --tries=1` |
| `composer.json` / `index.php` / `public/index.php` | PHP | `php -S 0.0.0.0:{port}` (+ `-t public` when `public/index.php` exists) |
| `requirements.txt` / `main.py` | Python | `uvicorn main:app --host 0.0.0.0 --port {port}` (uses `.venv/bin` / `venv/bin` first) |
| `package.json` | Node.js | `npm run dev` (+ host/port flags for Vite, Astro, Nuxt, Next) |
| `docker-compose.yml` / `compose.yaml` | Docker | `docker compose up` (URL from the first published port) |

Scanning goes 5 levels deep, skips `node_modules`, `vendor` and similar, and stops at the first folder that is a project. You can override the port, the command (`{port}` placeholder, no shell) and the type for each project. Settings are saved in `~/Library/Containers/com.mosavi.ProjectLauncher/Data/Library/Application Support/ProjectLauncher/settings.json`.

## Build

```bash
xcodegen generate            # only after editing project.yml
open ProjectLauncher.xcodeproj
```

Command line: `xcodebuild -scheme ProjectLauncher -derivedDataPath build test`.
The icon comes from `swift Scripts/make-icon.swift ProjectLauncher/Resources/Assets.xcassets/AppIcon.appiconset`.

## Sandbox

Off (`ProjectLauncher.entitlements`): servers need the whole home folder (`~/.nvm`, `~/.pyenv`, `~/.composer`, `/tmp`). The code still works sandboxed — it then points `TMPDIR` and PHP's opcache lock into the container — if you turn it back on with `network.server`, `network.client`, `files.user-selected.read-write` and `files.bookmarks.app-scope`.

Quitting the app sends SIGTERM to every running server's whole process tree (SIGKILL after a grace period; Docker gets longer).

`TEST_RUNNER_LAUNCHER_REAL_ROOT=~/Projects xcodebuild … test -only-testing:ProjectLauncherTests/RealProjectsTests` starts every detected project for real and writes a report to `$TMPDIR/launcher-report.txt`.
