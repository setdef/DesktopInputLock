# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# exe/desktop_input_lock as a shell script runs it: a process of its own,
# on a lock of the test's own through DESKTOP_INPUT_LOCK, with its own
# exit status and signals.
class ExeTest < Minitest::Test
  include DesktopHelper
  parallelize_me!

  EXE = File.expand_path("../exe/desktop_input_lock", __dir__)

  def env(root) = { "DESKTOP_INPUT_LOCK" => File.join(root, "lock"), "CI" => "true" }

  def spawn_exe(root, *argv) = spawn(env(root), RbConfig.ruby, "-W", "-I", LIB, EXE, *argv, err: File::NULL)

  def test_it_runs_and_reports_like_the_command
    in_desktop do |root|
      out, err, status = Open3.capture3(env(root), RbConfig.ruby, "-W", "-I", LIB, EXE, "hold", "--", "sh", "-c",
        "echo out; echo err >&2; exit 4")

      assert_equal 4, status.exitstatus
      assert_equal "out\n", out
      assert_equal "err\n", err
    end
  end

  def test_help_and_version
    in_desktop do |root|
      out, err, status = Open3.capture3(env(root), RbConfig.ruby, "-W", "-I", LIB, EXE, "--version")

      assert_predicate status, :success?, err
      assert_equal "desktop_input_lock #{DesktopInputLock::VERSION}\n", out
    end
  end

  # TERM sent to the command is passed on to its child, which ends as it
  # chooses, and its status is the command's.
  def test_a_signal_is_passed_on_to_the_command
    in_desktop do |root|
      pid = spawn_exe(root, "hold", "--", "sh", "-c",
        "trap 'echo got >> \"#{root}/signals\"; exit 3' TERM; touch '#{root}/running'; while :; do sleep 0.01; done")
      wait_for(File.join(root, "running"))
      Process.kill(:TERM, pid)

      assert_equal 3, reap(pid).exitstatus
      assert_equal "got\n", File.read(File.join(root, "signals"))
    end
  end

  # A command a signal ends exits, as a shell reports it, 128 plus the
  # signal's number.
  def test_a_command_ended_by_a_signal_is_128_plus_its_number
    in_desktop do |root|
      pid = spawn_exe(root, "hold", "--", "sh", "-c", "kill -KILL $$")

      assert_equal 128 + Signal.list.fetch("KILL"), reap(pid).exitstatus
    end
  end

  # The lock the command holds is the one DESKTOP_INPUT_LOCK names.
  def test_it_holds_the_sessions_lock
    in_desktop do |root|
      pid = spawn_exe(root, "hold", "--", "sh", "-c",
        "touch '#{root}/running'; while [ ! -e '#{root}/free' ]; do sleep 0.01; done")
      begin
        wait_for(File.join(root, "running"))

        assert_equal "#{DesktopInputLock::WAITING}\nwaited\n", try_from_another_process(root)
      ensure
        File.write(File.join(root, "free"), "")
      end

      assert_predicate reap(pid), :success?
    end
  end
end
