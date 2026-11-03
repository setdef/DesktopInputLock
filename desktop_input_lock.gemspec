# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "lib/desktop_input_lock/version"

Gem::Specification.new do |spec|
  spec.name = "desktop_input_lock"
  spec.version = DesktopInputLock::VERSION
  spec.authors = ["Kerrick Long"]
  spec.email = ["me@kerricklong.com"]

  spec.summary = "Keep tests that take the keyboard and mouse out of each other's way."
  spec.description = File.read(File.expand_path("README.rdoc", __dir__))
  spec.homepage = "https://github.com/setdef/DesktopInputLock"
  spec.license = "AGPL-3.0-or-later"
  spec.required_ruby_version = ">= 4.0.1"
  spec.required_rubygems_version = ">= 3.3.11"

  # Only a person publishes to RubyGems.org, by hand (AGENTS.md,
  # Releasing); MFA keeps an agent's stray gem push from getting through.
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/trunk/CHANGELOG.md"

  # Listing paths keeps development files (plans, tasks, tests, tool
  # configuration) out without a deny list that every new file has to
  # remember.
  packaged = %w[
    exe
    lib
    sig
    README.rdoc
    CHANGELOG.md
    LICENSE
    LICENSES
  ]
  spec.files = IO.popen(["git", "ls-files", "-z", "--", *packaged], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true)
  end
  spec.bindir = "exe"
  spec.executables = ["desktop_input_lock"]
  spec.require_paths = ["lib"]
end
