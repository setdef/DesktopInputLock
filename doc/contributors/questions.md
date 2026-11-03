<!--
SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>

SPDX-License-Identifier: CC-BY-SA-4.0
-->

# Questions for the Maintainer

Decisions that belong to the maintainer (AGENTS.md, Provenance) wait here. None of them blocks work: each names the default the work proceeds on, chosen to be easy to reverse, and how to reverse it. When a question is answered, record the answer in an ADR or a plan, and remove it from this list.

## 1. Who tags a version?

**Context.** Fledge wants to pin the gem by version and checksum, and the other projects will want a fixed version too. A git tag (`vX.Y.Z`) gives them one without RubyGems.org, which only a person publishes to. A tag is a release, and a release is publishing outside the repository.

**Default.** Only the maintainer tags. Until a tag exists, projects pin a commit with Bundler's `git:` and `ref:`.

**To reverse.** Say in AGENTS.md (Releasing) when an agent may tag, such as once the gate and CI pass for a commit on `trunk`.

## 2. Where does the lock live on Windows?

**Context.** On macOS and Linux every process agrees on `/tmp/desktop-input.lock` and `/tmp/desktop-input.away`. Windows has no `/tmp`, and `%TEMP%` and `Dir.tmpdir` differ per user, so two users' tests would never meet. No project locks on Windows yet, so this gem sets the path every later copy follows (Plan 001, Linux and Windows).

**Default.** `%ProgramData%\desktop-input.lock` and `%ProgramData%\desktop-input.away` (usually `C:\ProgramData`), which every user can create files in. Until that work lands, the gem does nothing on Windows unless the caller passes paths.

**To reverse.** Change the Windows paths in one place in `lib/` and Plan 001, before any project depends on them.

## 3. What names a session's own lock?

**Context.** Lota's hidden macOS test session runs tests in a second user's session, whose focus and pointer can't disturb the person's, so it wants a lock of its own (Plan 001, One session's own lock). The variable is public interface, and every project's runner would set it.

**Default.** One variable, `DESKTOP_INPUT_LOCK`, naming the lock file. The marker is the same path with `.lock` replaced by `.away`, or `.away` appended. Unset, the protocol's `/tmp` files are used.

**To reverse.** Rename the variable, or add `DESKTOP_INPUT_MARKER` for a marker set apart, in `DesktopInputLock`'s defaults and the command, before any project's runner sets it.

## 4. Does the lock need a shared mode?

**Context.** Lota considered letting windows that never take focus or the pointer hold the lock shared, so they could run beside each other while focus-takers stayed exclusive, and Fledge listed `--shared` for its command. Lota's reliability work found other lanes' windows harmless and chose not to add it.

**Default.** No shared mode: no `shared:` keyword and no `--shared`. Every span is exclusive, as every copy of the protocol is today.

**To reverse.** Add `shared:` to `hold` and `acquire` and `--shared` to the command, with one descriptor per process, a counted mode, and an error rather than a deadlock when a process holding the lock shared asks for it exclusive (Plan 001).
