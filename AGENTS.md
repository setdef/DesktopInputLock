<!--
  SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  SPDX-License-Identifier: CC-BY-SA-4.0
-->

# AGENTS.md

## Project

DesktopInputLock (the `desktop_input_lock` gem, https://github.com/setdef/DesktopInputLock) keeps tests that take the keyboard and mouse out of each other's way. It holds one exclusive `flock` on `/tmp/desktop-input.lock` that every such test shares, across processes and projects. A speaking span also tells the person at a Mac, with a Notification Center banner and then `say`, to step away, and calls them back once no span has run for three seconds, using a marker at `/tmp/desktop-input.away`. It is extracted from the copies in Lota (`rove_2d/tasks/desktop_input.rb`), Tokra (`tokra/test/integration/support/keyboard_notice.rb`), and Deckbuilder (`deckbuilder/gui/conf.rb`), and Fledge will use it too. The plan of record is `doc/contributors/plan/001.md`.

Pre-1.0. Its users are the maintainer's own projects, so record every change they can observe in CHANGELOG.md.

## Design precedence

1. **The protocol.** Other projects already implement it, and processes on one computer agree only if every copy does the same thing. Its files (`/tmp/desktop-input.lock`, `/tmp/desktop-input.away` and its `<pid> <unix time>` contents, both mode 0666), timings (`SETTLE` 3 s), words (`STEP_AWAY`, `COME_BACK`, `WAITING`), and environment (`CI`, `DESKTOP_INPUT_QUIET`) never change here. A change to the protocol is a new protocol version, agreed with every project that implements it first.
2. **The person at the computer.** Never move or block their mouse, never take focus to tell them something (a banner, never a dialog), and never leave them sent away: every step away gets a call back.
3. **Ruby the language.** Stdlib only at run time. `flock`, `Process`, and `Monitor` say what they do; read their documentation and Ruby's source rather than guessing.
4. **Ruby culture.** Idioms yield to 1, 2, and 3.

## How to work

- Research before designing: read the plan and the projects' copies first. Never guess at a reference's contents; cite the file and lines you relied on.
- Root-cause every fix. If you cannot explain why a change fixed the symptom, it is not a fix.
- Write tests first. A test must fail if the code it covers is deleted or mutated. The lock is tested with real processes and a real `flock`, over a lock and marker of each test's own, with `say` and `osascript` replaced by scripts that write down what they were given. Never mock the lock. Never add retries or sleeps to mask a race: processes hand over through files they write and through `SIGSTOP` and `SIGCONT`. Fast, reliable tests come before anything else.
- Coordinate with the projects that use the lock. Their sessions may be running now; find them with ListAgents and ask before you change something they depend on. Never edit another project's repository: send its session a migration note instead.
- Design in the spirit of Kent Beck (small steps, Implementation Patterns), Freeman & Pryce (tests drive interfaces), Sandi Metz (duplication over the wrong abstraction), Rebecca Wirfs-Brock (responsibility-driven roles), Martin Fowler (refactor in behavior-preserving steps), and Matz (programmer happiness). Write prose in the style of `doc/contributors/documentation_style.md`.

## Ruby, RBS, and docs

- `Data.define` for value objects (`class Foo < Data.define(...)`), `class` for entities.
- Every Ruby method has an RBS signature in `sig/` mirroring `lib/`. No `untyped`, no comments in `.rbs`. For `Data.define` classes, declare `self.new` instead of `initialize` (Steep mis-checks `initialize` there); plain classes declare `initialize` as usual.
- RDoc (never YARD) in `.rb` files only. Wrap SPDX headers in `#--` / `#++`, and wrap examples in `MIT-0` SPDX snippets.
- Architectural decisions get an ADR; plans live in `doc/contributors/plan/`.

## Commands

- Run Ruby with `bundle exec ruby`. Run tests with `bundle exec rake test`. Never `ruby -Ilib:test`.
- `bundle exec rake` is the gate: RuboCop and REUSE fixes, tests, RuboCop, RubyCritic, RDoc coverage, REUSE, actionlint and shellcheck, RBS checks (no `untyped`, `rbs validate`, signature parity), Steep, and the package check. It must pass with zero errors and zero warnings. Run `bundle exec rake rubocop:autocorrect_all` first to save time.
- Approved exceptions live in `rbs_exceptions.rb`; adding one needs a justification that it is impossible otherwise.
- Rake tasks use `git ls-files`: new or deleted files must be staged before they count.
- Always `PAGER=cat` for git.

## Provenance

The maintainer uses three words for how work comes to exist. *Written* means typed by hand, with nothing generated. *Wrought* means an agent generated it while the maintainer iterated with it and reviewed every change before committing it. *Requested* means an agent built it with little or no review.

- **In DesktopInputLock, everything is requested.** Because no one reviews this work line by line, the gates and the real-process tests review it. Never weaken a gate to make requested work pass.
- **Engineering decisions are the agents'.** The maintainer reads this project as a Director of Engineering would: what it unblocks, and whether it is good. Interface names, options, paths, modes, and test design are engineering calls. Make them, explain them in the plan or an ADR, and coordinate them with the projects that depend on them.
- **Decisions** that belong to the maintainer go to the maintainer as questions: licenses, publishing to RubyGems.org, and a change to the protocol that changes what the person at the computer sees or hears. Do not wait for an answer, and do not decide silently: pick a sensible default that is easy to reverse, build on it, and record the question in `doc/contributors/questions.md` with its context, the default chosen, and how to reverse it, in terms of what it means for the projects and the people using them. When the maintainer answers, record the answer in an ADR or the plan and remove the question.
- **Generated code** is marked as generated in its header and is never edited by hand; change the generator instead.

Every commit carries a `Provenance: requested` trailer.

## Committing

- Trunk-based development: commit to `trunk`. Branches are rare and short-lived, and are thrown away or cherry-picked onto `trunk`, never merged.
- One commit per working session, after the gate passes. Include any plan, ADR, or question the session produced.
- Push `trunk` to `origin` (github.com/setdef/DesktopInputLock) only when the maintainer has allowed it for the session, and only once the gate passes. Never force-push, and never push in any other repository.
- Conventional Commits, plain text, wrapped at 72. The body explains why this approach over alternatives, in prose (no lists, no markdown, no file inventories). Types: `lib`/`sig` feat/fix/refactor/perf; `bin`/`tasks`/CI chore; `doc/` docs; `test/` test. End with the `Provenance: requested` trailer, then the AI footer shown by `git log -n1`.

## Releasing

Publishing to RubyGems.org is a human-only activity: no agent runs `gem push`, ever. `rake release` refuses, and the gemspec requires MFA, so a push asks a person for their one-time password. A person builds and pushes the gem by hand.

Before 1.0.0, an orchestration agent or a solo agent (never a sub-agent) may tag a version and publish it as a GitHub Release, once the gate and CI pass for the commit on `trunk`:

- `0.0.X.pre.Y` (tag `v0.0.X.pre.Y`) while the gem is not yet ready for other libraries and gems to try.
- `0.X.Y`, by Semantic Versioning, once it is.

Each release moves CHANGELOG.md's `[Unreleased]` entries under the new version, sets `VERSION`, and names the release after its tag. Version 1.0.0 is the maintainer's call.

## Changelog

Keep a Changelog + SemVer. Only changes the projects that use the gem can observe: the public interface, behavior, the protocol, breaking changes, deprecations, dependency changes. Not tests, docs, internal refactors, or tooling. Terse one-line entries under `## [Unreleased]`, which means "since the last tag": a change undone before the next tag removes its entry instead of adding a "Fixed" line. Never edit released sections.

## Definition of done

1. Every item in the plan is done, or explicitly deferred with a reason.
2. The protocol's files, timings, words, and environment are unchanged.
3. `bundle exec rake` passes from a clean build (`rm -rf tmp`), zero errors, zero warnings.
4. RDoc, RBS, `doc/`, README, and CHANGELOG updated where behavior changed.
5. Every maintainer decision the work touched is in `doc/contributors/questions.md` or already answered.
6. Each project that uses the gem has been sent a migration note for any change it must make.
7. A commit message is written (and the commit made, per Committing).
