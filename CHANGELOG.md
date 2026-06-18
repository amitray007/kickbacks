# Changelog

Notable changes per release. Loosely follows [Keep a Changelog](https://keepachangelog.com); versions are git tags.

## [0.3.1](https://github.com/amitray007/kickbacks/compare/v0.3.0...v0.3.1) (2026-06-18)


### Bug Fixes

* **cask:** use symbol form for depends_on macos ([#15](https://github.com/amitray007/kickbacks/issues/15)) ([a1ba91a](https://github.com/amitray007/kickbacks/commit/a1ba91a036c638f8104b5b6351580099bbe9a5f5))

## [0.3.0](https://github.com/amitray007/kickbacks/compare/v0.2.0...v0.3.0) (2026-06-17)


### Features

* **demo:** add setting to hide the Demo mode label ([9f08cfc](https://github.com/amitray007/kickbacks/commit/9f08cfc478179fd14a37d42467c26a279886775b))
* **dist:** add Kickbacks.dmg + Homebrew cask for drag-to-Applications install ([6457d73](https://github.com/amitray007/kickbacks/commit/6457d737e86435dbeafc013f3c86d76091f81277))
* **dist:** add Kickbacks.dmg + Homebrew cask for drag-to-Applications install ([b08f7d7](https://github.com/amitray007/kickbacks/commit/b08f7d789676d1d64f7564fdb06b7f34198c8ff5))
* **dist:** Kickbacks.dmg + Homebrew cask ([6457d73](https://github.com/amitray007/kickbacks/commit/6457d737e86435dbeafc013f3c86d76091f81277))
* show the live ad from the extension's local cache, with API fallback ([#6](https://github.com/amitray007/kickbacks/issues/6)) ([4df32c3](https://github.com/amitray007/kickbacks/commit/4df32c3755d1a65963df715be248b07585b2ce88))


### Bug Fixes

* **brew:** install prebuilt arm64 binaries (no source build) ([b1240f5](https://github.com/amitray007/kickbacks/commit/b1240f550c36aa99cbb0b2f977bac03ba61050c0))
* **brew:** install prebuilt arm64 binaries instead of building from source ([b1240f5](https://github.com/amitray007/kickbacks/commit/b1240f550c36aa99cbb0b2f977bac03ba61050c0))
* **brew:** install prebuilt arm64 binaries instead of building from source ([dd672cc](https://github.com/amitray007/kickbacks/commit/dd672cc39c35a11de6e34f19858ec3c045a63885))
* **demo:** real ads in demo mode + hide Demo mode label option ([eafa94f](https://github.com/amitray007/kickbacks/commit/eafa94f7d7bc504644127ec058d5e788a81bfd1f))
* **demo:** show real ads in demo mode, fall back to demo ads only when none exist ([eafa94f](https://github.com/amitray007/kickbacks/commit/eafa94f7d7bc504644127ec058d5e788a81bfd1f))
* **demo:** show real ads in demo mode; fall back to demo ads only when none exist ([d9dbe02](https://github.com/amitray007/kickbacks/commit/d9dbe021914023ca76b63a4d149739bfc45ea1df))
* **update:** .app bundle path wins in classify() when cask + formula both installed ([388704c](https://github.com/amitray007/kickbacks/commit/388704c1b616917217f8e976a8c7620122db4d2d))
* **update:** check .app bundle path before CLI sibling in classify() ([388704c](https://github.com/amitray007/kickbacks/commit/388704c1b616917217f8e976a8c7620122db4d2d))
* **update:** check .app bundle path before CLI sibling in classify() ([b57e1b3](https://github.com/amitray007/kickbacks/commit/b57e1b360e449b7f866f7c9e67b7ce1c962c725a))

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
