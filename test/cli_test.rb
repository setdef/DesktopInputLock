# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"
require "desktop_input_lock/cli"

# The command line in process, through real streams and a lock of each
# test's own, with real child commands.
class CLITest < Minitest::Test
  include DesktopHelper
  parallelize_me!

  EXE = File.expand_path("../exe/desktop_input_lock", __dir__)

  def cli(root, out: StringIO.new, err: StringIO.new)
    DesktopInputLock::CLI.new(help_path: EXE, out:, err:, input: input(root))
  end

  def test_help_is_the_executables_header
    in_desktop do |root|
      out = StringIO.new

      assert_equal 0, cli(root, out:).call(["--help"])
      assert_equal "desktop_input_lock - Run a command holding the desktop input lock\n", out.string.lines[1]
      assert_includes out.string, "EXIT STATUS"
      refute_includes out.string, "requested"
    end
  end

  def test_a_bare_command_prints_help_and_fails
    in_desktop do |root|
      err = StringIO.new

      assert_equal 1, cli(root, err:).call([])
      assert_includes err.string, "SYNOPSIS"
    end
  end

  def test_version
    in_desktop do |root|
      out = StringIO.new

      assert_equal 0, cli(root, out:).call(["-V"])
      assert_equal "desktop_input_lock #{DesktopInputLock::VERSION}\n", out.string
    end
  end

  def test_mistakes_are_messages_and_status_one
    in_desktop do |root|
      err = StringIO.new

      assert_equal 1, cli(root, err:).call(["frobnicate"])
      assert_equal 1, cli(root, err:).call(["--frobnicate"])
      assert_equal 1, cli(root, err:).call(["hold", "--loud", "--", "true"])
      assert_equal 1, cli(root, err:).call(["hold", "--"])
      assert_equal 1, cli(root, err:).call(["hold"])
      assert_equal <<~ERR, err.string
        desktop_input_lock: 'frobnicate' is not a command. See 'desktop_input_lock --help'.
        desktop_input_lock: unknown option '--frobnicate'. See 'desktop_input_lock --help'.
        desktop_input_lock hold: unknown option '--loud'. See 'desktop_input_lock --help'.
        desktop_input_lock hold: no COMMAND to run. See 'desktop_input_lock --help'.
        desktop_input_lock hold: no COMMAND to run. See 'desktop_input_lock --help'.
      ERR
    end
  end

  def test_hold_returns_the_commands_status_with_or_without_the_double_dash
    in_desktop do |root|
      assert_equal 0, cli(root).call(%w[hold -- true])
      assert_equal 3, cli(root).call(["hold", "sh", "-c", "exit 3"])
    end
  end

  # The command's own options are its own, after the double dash.
  def test_options_after_the_double_dash_are_the_commands
    in_desktop do |root|
      assert_equal 0, cli(root).call(["hold", "--", "sh", "-c", "test \"$1\" = --speak", "sh", "--speak"])
    end
  end

  def test_a_command_that_is_not_there_is_127
    in_desktop do |root|
      err = StringIO.new

      assert_equal 127, cli(root, err:).call(%w[hold -- no-such-command-anywhere])
      assert_equal "desktop_input_lock: no-such-command-anywhere: command not found\n", err.string
    end
  end

  def test_a_command_that_cannot_run_is_126
    in_desktop do |root|
      File.write(File.join(root, "plain"), "")
      File.chmod(0o644, File.join(root, "plain"))

      assert_equal 126, cli(root, err: StringIO.new).call(["hold", "--", File.join(root, "plain")])
    end
  end

  # The lock is held while the command runs, and only then.
  def test_the_lock_is_held_while_the_command_runs
    in_desktop do |root|
      command = ["sh", "-c", "touch '#{root}/running'; while [ ! -e '#{root}/free' ]; do sleep 0.01; done"]
      holder = Thread.new { cli(root).call(["hold", "--", *command]) }
      wait_for(File.join(root, "running"))

      assert_equal "#{DesktopInputLock::WAITING}\nwaited\n", try_from_another_process(root)

      File.write(File.join(root, "free"), "")

      assert_equal 0, holder.value
      assert_equal "got it\n", try_from_another_process(root)
    end
  end

  # Silent by default; with --speak, the person is asked to step away and
  # called back as the command's process exits.
  def test_it_speaks_only_when_asked
    in_desktop do |root|
      code = "require 'desktop_input_lock/cli'\n" \
        "exit DesktopInputLock::CLI.new(help_path: #{EXE.dump}, input:).call(ARGV.drop(1))"
      reap(spawn(RbConfig.ruby, "-I", LIB, "-e", "#{PRELUDE}\n#{code}", root, "hold", "--", "true"))

      assert_empty said(root)

      reap(spawn(RbConfig.ruby, "-I", LIB, "-e", "#{PRELUDE}\n#{code}", root, "hold", "--speak", "--", "true"))

      assert_equal told(DesktopInputLock::STEP_AWAY, DesktopInputLock::COME_BACK), said(root)
    end
  end
end
