# Changelog

Notable changes per release. Loosely follows [Keep a Changelog](https://keepachangelog.com); versions are git tags.

## [0.2.0](https://github.com/amitray007/kickbacks/compare/v0.1.0...v0.2.0) (2026-06-16)


### Features

* **app:** favicon fallback for ads with no custom icon ([54d5a36](https://github.com/amitray007/kickbacks/commit/54d5a36c20e4ba686d83219bbaf037ee7c8dacd2))
* **app:** in-app updates (notify → brew upgrade → relaunch) ([0cd1a84](https://github.com/amitray007/kickbacks/commit/0cd1a8493b0449e41e48c892bb970a35d3aef94e))
* **app:** MenuVM update state, periodic check, brew upgrade + skip actions ([0089e41](https://github.com/amitray007/kickbacks/commit/0089e416f21ac1cc8af03ffce85d6ec50ed09cd4))
* **app:** move Share to the bottom bar beside Settings (out of the ⇄ menu) ([93f6292](https://github.com/amitray007/kickbacks/commit/93f629294401a60ced741cd425f170b0fcd93f08))
* **app:** Updater core — semver compare, release parse, install detection ([0bb3f2e](https://github.com/amitray007/kickbacks/commit/0bb3f2ea366358370166e57ad6ff83a1b482f9ce))
* **app:** Updater wrappers — kickbacks --version, GitHub fetch, install method ([ac7e689](https://github.com/amitray007/kickbacks/commit/ac7e689ad75501ceacd621c6a9a4a9f92d1535fa))
* **app:** UpdateRunner — detached brew upgrade with streamed log + relaunch ([067a8fe](https://github.com/amitray007/kickbacks/commit/067a8fe4c366dfec20fe4b7df19cd873261b9d05))
* **app:** UpdateView — changelog window with background progress + actions ([590a990](https://github.com/amitray007/kickbacks/commit/590a9908e229821bd9c41a2337d5203fb37f60ed))
* **app:** wire updates — window scene, panel banner, Settings section ([0fda4c8](https://github.com/amitray007/kickbacks/commit/0fda4c83918f25bd3d05c49e578490fb9c6a6bac))
* **release:** release-please automation, shared CLI+app versioning, README logo, CI hardening ([6de2066](https://github.com/amitray007/kickbacks/commit/6de2066c2f84751cac51d8440db8ce3400b6d402))


### Bug Fixes

* **app:** keep self main-actor-isolated in MenuVM version fetch ([50a565f](https://github.com/amitray007/kickbacks/commit/50a565fa53b35b5469686d381ebedfbe9cd2f7d9))
* harden ad URL/icon opening (scheme allow-list) + correct docs ([0a692ce](https://github.com/amitray007/kickbacks/commit/0a692cef401d90c927bc3acccd4a4946d5a30540))
* **release:** release-please root 'simple' package (keeps root CHANGELOG; bumps cli/package.json via extra-files) ([8786099](https://github.com/amitray007/kickbacks/commit/8786099d42edf35af3ced32d42f61c6c7409ff52))

## v0.1.0 — 2026-06-15

First public release.

- **CLI** (`kickbacks`) — earnings dashboard, `watch` live TUI, `earnings`/`status`, Google OAuth (read-only API client).
- **Menu-bar app** — today's earnings in the menu bar; dropdown with today/lifetime, hourly/daily caps, recent ads, and inline history; share cards (Today/Week/Lifetime); pinnable floating HUD; privacy + demo modes.
- **Local history** (SQLite) — this-week/this-month, best day, averages, pace projections.
- **launchd poller** — background sampling + cap and lifetime-milestone notifications.
- **Homebrew tap** — build-from-source formula (no code-signing/notarization required).
