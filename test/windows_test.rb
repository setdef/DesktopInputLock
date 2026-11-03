# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# The lock on a real Windows: where it lives, that two processes meet at
# it, and that the PowerShell it speaks with reads its scripts. Elsewhere
# these skip; test/platforms_test.rb covers how it speaks on Windows on
# every system.
class WindowsTest < Minitest::Test
  include DesktopHelper
  parallelize_me!

  def setup
    skip "only on Windows" unless Gem.win_platform?
  end

  def test_every_user_meets_in_program_data
    lock, marker = DesktopInputLock.paths(ENV.to_h.except("DESKTOP_INPUT_LOCK"), RbConfig::CONFIG["host_os"])

    assert_equal File.join(ENV.fetch("ProgramData"), "desktop-input.lock"), lock
    assert_equal File.join(ENV.fetch("ProgramData"), "desktop-input.away"), marker
  end

  # Each PowerShell script parses, so a toast or a voice fails, when it
  # does, only for want of a desktop to show it on or a voice to say it.
  def test_the_powershell_scripts_parse
    powershell = File.join(ENV.fetch("SystemRoot"), DesktopInputLock::POWERSHELL)
    [DesktopInputLock::WINDOWS_BANNER, DesktopInputLock::WINDOWS_VOICE].each do |script|
      out, status = Open3.capture2e({ "SCRIPT" => script }, powershell, "-NoProfile", "-NonInteractive", "-Command",
        "$null = [ScriptBlock]::Create($env:SCRIPT)")

      assert_predicate status, :success?, out
    end
  end

  def test_a_process_waits_for_another_holding_the_lock
    in_dir do |root|
      held = input(root, host_os: RbConfig::CONFIG["host_os"]).acquire(speak: false)

      assert_equal "#{DesktopInputLock::WAITING}\nwaited\n", try_from_another_process(root)

      held.release

      assert_equal "got it\n", try_from_another_process(root)
    end
  end
end
