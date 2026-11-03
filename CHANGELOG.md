<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
