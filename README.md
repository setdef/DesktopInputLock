<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# DesktopInputLock

[![Certified Shovelware](https://justin.searls.co/img/shovelware.svg)](https://justin.searls.co/shovelware/)
[![CI](https://github.com/setdef/DesktopInputLock/actions/workflows/ci.yml/badge.svg?branch=trunk)](https://github.com/setdef/DesktopInputLock/actions)

DesktopInputLock keeps tests that take the keyboard and mouse out of each other's way.

A computer has one pointer, and one window at a time has the keyboard's focus. A test that opens a real menu, brings a window to the front, or moves the pointer passes only if nothing else takes them in the meantime. Run two projects' tests at once on one computer, or one project's checks in parallel, and each lands its clicks and keystrokes in the other's windows. The failures look random, and they go away when you run the test alone.

DesktopInputLock holds one lock that every such test shares, across processes and across projects. On a Mac it also tells you, with a Notification Center banner and aloud, when tests are about to take the keyboard and mouse, and calls you back once they're done.

## Using it

Add it to your Gemfile's development group:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
group :development do
  gem "desktop_input_lock", git: "https://github.com/setdef/DesktopInputLock.git", ref: "COMMIT"
end
```
<!-- SPDX-SnippetEnd -->

Wrap each test that takes the keyboard or the pointer in a span. A speaking span tells the person at a Mac to step away before it starts, and calls them back once no span has run for three seconds. A silent span only takes the lock, for something quick or out of sight:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```ruby
require "desktop_input_lock"

# Opens a real menu, which takes the keyboard until it closes.
DesktopInputLock.hold { menu.popup(window) }

# Moves the pointer and reads it back.
DesktopInputLock.hold(speak: false) { move_pointer_and_read_it_back }

# A test whose setup and teardown are separate methods.
class MouseTest < Minitest::Test
  def setup
    @desktop_input = DesktopInputLock.acquire(speak: false)
  end

  def teardown
    @desktop_input.release
  end
end
```
<!-- SPDX-SnippetEnd -->

`hold` returns its block's value and lets go even when the block raises. Spans nest, and spans on several threads of one process share its one lock. A lock you `acquire` and never `release` stays held until the process ends, whether or not you keep the returned object.

When another process holds the lock, a span prints `waiting for the desktop input lock` to standard error and waits its turn.

### From a shell script

macOS has no `flock(1)`, so the gem ships a command that holds the lock around another command:

<!-- SPDX-SnippetBegin -->
<!--
  SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: MIT-0
-->
```bash
desktop_input_lock hold -- bin/drive-simulator --device iPhone
desktop_input_lock hold --speak -- bundle exec rake test:gui
```
<!-- SPDX-SnippetEnd -->

It is silent unless you pass `--speak`. It exits with the command's status, or 128 plus the signal that ended it, and passes INT, TERM, and HUP on to the command. `desktop_input_lock --help` prints the rest.

### Where it locks and speaks

It locks `/tmp/desktop-input.lock` on macOS and Linux, on CI too, and even when quiet, since its purpose is that two runs never collide. On Windows it does nothing unless you name a lock.

It speaks only on macOS, outside CI, and unless `DESKTOP_INPUT_QUIET` is set. Each message shows first as a Notification Center banner, which takes no focus, for a person whose sound is off, then is said with `say`. A Mac with neither `osascript` nor `say` stays silent.

### Testing your own use of it

Give `DesktopInputLock.new` paths of your test's own (`lock:`, `marker:`) and stand-ins for `say:` and `osascript:` that write down what they were given, so your tests never touch the shared lock or speak aloud. A span speaks only where `speaks?` is true, which needs `host_os:` to name macOS and one of the two stand-ins to be executable. On Windows, `File.executable?` is false for an extensionless shell script, so a span there never speaks. Skip speaking tests unless `speaks?` is true, or a silent span will pass them without proving anything.

### A session of its own

Set `DESKTOP_INPUT_LOCK` to a path, such as `/tmp/desktop-input-hidden.lock`, and every process started with it locks that file instead, with its marker beside it (`/tmp/desktop-input-hidden.away`). Use it for a session whose keyboard focus and pointer are its own, such as a second user logged in in the background, so its tests stop waiting on yours. Point it only at a path every process of that session can reach, and only where nothing outside the session can take the same focus or pointer.

### The protocol

Lota, Tokra, Deckbuilder, and Fledge share this lock, and other copies of it exist, so its files, timing, and words never change: an exclusive `flock` on `/tmp/desktop-input.lock`; a marker at `/tmp/desktop-input.away` holding `<pid> <unix time>` of the process that asked the person to step away; three seconds with no span before the call back; both files mode 0666. `DesktopInputLock`'s RDoc spells it out, with the two edges it leaves open. [Plan 001](doc/contributors/plan/001.md) records the extraction and each project's migration.

## Development

```bash
git clone https://github.com/setdef/DesktopInputLock.git
cd DesktopInputLock
bin/setup
bundle exec rake
```

`bin/setup` installs the tools pinned in `mise.toml` (Ruby, the REUSE tool, actionlint, and shellcheck), installs the bundle, and installs the pre-commit hook. `bundle exec rake` is the gate: it fixes what RuboCop and the REUSE tool can fix, then runs the tests, RuboCop, RubyCritic, RDoc coverage, REUSE, actionlint and shellcheck, signature checks (no `untyped`, `rbs validate`, and parity between `sig/` and `lib/`), Steep, and the package check, which builds the gem, installs it into an empty `GEM_HOME`, and loads it from there. It passes with zero errors and zero warnings.

GitHub Actions runs `.github/workflows/ci.yml` on every push and pull request. The **Gate** job runs `bundle exec rake` on Linux and fails if the gate changed a file. The **Test** jobs run the tests on macOS 15 (Apple Silicon), Windows, and Linux.

Contributors, people and agents alike, start with [AGENTS.md](AGENTS.md) and the [documentation style guide](doc/contributors/documentation_style.md). Open questions for the maintainer live in [doc/contributors/questions.md](doc/contributors/questions.md).

## Copyright & License

DesktopInputLock is copyright 2026, Kerrick Long. The code is [AGPL-3.0-or-later](LICENSES/AGPL-3.0-or-later.txt), the documentation is [CC-BY-SA-4.0](LICENSES/CC-BY-SA-4.0.txt), and code examples in the documentation are [MIT-0](LICENSES/MIT-0.txt). The vendored RuboCop configuration is [MIT](LICENSES/MIT.txt), and `Gemfile.lock` and the pre-commit configuration are [CC0-1.0](LICENSES/CC0-1.0.txt).
