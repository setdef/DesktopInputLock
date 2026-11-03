# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

class VersionTest < Minitest::Test
  def gemspec
    Gem::Specification.load(File.expand_path("../desktop_input_lock.gemspec", __dir__))
  end

  def test_version_is_a_semantic_version
    assert_match(/\A\d+\.\d+\.\d+(?:\.pre\.\d+)?\z/, DesktopInputLock::VERSION)
  end

  def test_gemspec_publishes_the_library_version
    assert_equal DesktopInputLock::VERSION, gemspec.version.to_s
  end

  # Only a person publishes to RubyGems.org, and RubyGems asks them for
  # a one-time password when they do.
  def test_gemspec_requires_mfa_to_push
    assert_equal "true", gemspec.metadata.fetch("rubygems_mfa_required")
  end

  def test_gemspec_packs_the_library_and_its_signatures
    spec = gemspec

    assert_includes spec.files, "lib/desktop_input_lock.rb"
    assert_includes spec.files, "sig/desktop_input_lock.rbs"
    assert_includes spec.files, "LICENSES/AGPL-3.0-or-later.txt"
  end
end
