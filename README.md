# Project Launcher

A lightweight native macOS app (SwiftUI, macOS 13+) that finds local projects in a folder and runs their dev servers, with live logs, LAN links and QR codes.

| Detected by | Type | Default command |
|---|---|---|
| `composer.json` / `index.php` | PHP | `php -S 0.0.0.0:{port}` (+ `-t public` when `public/index.php` exists) |
| `requirements.txt` / `main.py` | Python | `uvicorn main:app --host 0.0.0.0 --port {port}` (uses `.venv/bin` / `venv/bin` first) |
| `package.json` | Node.js | `npm run dev` (+ host/port flags for Vite, Astro, Nuxt, Next) |
| `docker-compose.yml` / `compose.yaml` | Docker | `docker compose up` (URL from the first published port) |

Scanning goes 3 levels deep, skips `node_modules`, `vendor` and similar, and stops at the first folder that is a project. You can override the port, the command (`{port}` placeholder, no shell) and the type for each project. Settings are saved in `~/Library/Containers/com.mosavi.ProjectLauncher/Data/Library/Application Support/ProjectLauncher/settings.json`.

## Build

```bash
xcodegen generate            # only after editing project.yml
open ProjectLauncher.xcodeproj
```

Command line: `xcodebuild -scheme ProjectLauncher -derivedDataPath build test`.
The icon comes from `swift Scripts/make-icon.swift ProjectLauncher/Resources/Assets.xcassets/AppIcon.appiconset`.

## Sandbox

`ProjectLauncher.entitlements` turns on App Sandbox with `network.server`, `network.client`, `files.user-selected.read-write` and `files.bookmarks.app-scope`. The root folder is remembered as a security-scoped bookmark. Child processes inherit the sandbox. This means:

* Tools under `/opt/homebrew`, `/usr/local` and `/Library/Frameworks/Python.framework` run fine. The test suite runs real `php -S` and `npm run dev` servers inside the sandbox.
* `/tmp` is not writable, so `TMPDIR` points to the container, and PHP gets `-d opcache.lockfile_path=…`.
* Anything in your **home folder outside the chosen root** can't be read. That includes `~/.nvm`, `~/.pyenv`, `~/.composer` and global configs. If you rely on those, set `com.apple.security.app-sandbox` to `false`. This is a local developer tool and does not need the Mac App Store, and every other feature works the same.

Quitting the app sends SIGTERM to every running server's whole process tree (SIGKILL after a grace period; Docker gets longer).
