<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-11-03

### Added

- A speaking span speaks on a Linux desktop: a notification through `notify-send`, then `spd-say`, or `espeak-ng` where there is no `spd-say`. `DesktopInputLock.new` takes `notify_send:`, `spd_say:`, and `espeak_ng:`.
- A speaking span speaks on Windows: a toast, then the system's voice, both through Windows PowerShell. `DesktopInputLock.new` takes `powershell:`.
- `DesktopInputLock.windows?` and `DesktopInputLock.find`.

### Changed

- On Windows the lock is `%ProgramData%\desktop-input.lock`, with its marker beside it, rather than nothing unless named.

### Fixed

- A marker another user's process left where this one may not delete it no longer raises in the watcher or at exit; it is left to that user's processes.

## [0.1.0] - 2026-11-02

### Added

- `DesktopInputLock.hold` and `.acquire`, with `#release`, `#speaks?`, `#call_back`, `#tick`, and `#finish`: the desktop input lock and its spoken notices, extracted from Lota's `tasks/desktop_input.rb`, with its protocol unchanged.
- `desktop_input_lock hold [--speak] [--] COMMAND`, which runs a command holding the lock, passing on its exit status and signals.
- `DESKTOP_INPUT_LOCK`, which points a session at a lock of its own.
- `DesktopInputLock.paths`, the lock and marker a process uses for its environment.

### Changed

- A speaking span on a Mac with neither `osascript` nor `say` runs as a silent one and writes no marker, as the protocol says, rather than leaving a marker that kept every other process silent.
- Whatever `osascript` prints stays out of the tests' output.
- On Windows the lock does nothing unless `DESKTOP_INPUT_LOCK` or `lock:` names a file.
