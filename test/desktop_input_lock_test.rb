# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# The desktop input lock and what it says, in real processes, over a lock
# and marker of each test's own. Ported from Lota's
# test/tasks/desktop_input_test.rb at 4a3ce54, with the cases of Tokra's
# test/integration/keyboard_notice_test.rb that Lota's lacked.
class DesktopInputLockTest < Minitest::Test
  include DesktopHelper
  parallelize_me!

  # The second process's span waits for the first's and starts as soon as
  # it ends, so the person is asked to step away once and to come back
  # once, after both.
  def test_two_processes_say_each_once
    in_desktop do |root|
      first = spawn_script(root, "input.hold { File.write(File.join(dir, 'first'), ''); hand_over_to('second') }; " \
        "sleep #{SETTLE * 2}")
      wait_for(File.join(root, "first"))
      run_script(root, "input.hold { sleep 0.5 }", err: "second")
      reap(first)

      assert_equal told(DesktopInputLock::STEP_AWAY, DesktopInputLock::COME_BACK), said(root)
      refute_path_exists File.join(root, "away")
    end
  end

  # A process that settles while another, silent, holds the lock says
  # nothing, since someone is still working, and asks the person back
  # once the lock is free, without waiting to exit.
  def test_a_silent_span_holding_the_lock_only_delays_the_call_back
    in_desktop do |root|
      speaker = spawn_script(root, "input.hold { File.write(File.join(dir, 'spoke'), ''); hand_over_to('silent') }; " \
        "sleep 0.1 until File.exist?(File.join(dir, 'free'))")
      begin
        wait_for(File.join(root, "spoke"))
        run_script(root, "input.hold(speak: false) { sleep #{SETTLE * 3} }", err: "silent")

        assert_equal told(DesktopInputLock::STEP_AWAY), said(root)
        wait_until { said(root).size == 4 }

        assert_equal told(DesktopInputLock::STEP_AWAY, DesktopInputLock::COME_BACK), said(root)
      ensure
        File.write(File.join(root, "free"), "")
        reap(speaker)
      end

      assert_equal told(DesktopInputLock::STEP_AWAY, DesktopInputLock::COME_BACK), said(root)
    end
  end

  # A watcher that finds the marker gone, because another process called
  # the person back, stops trying, and its process says nothing more as
  # it exits.
  def test_a_watcher_stops_trying_once_the_marker_is_gone
    in_desktop do |root|
      speaker = spawn_script(root, "input.hold { File.write(File.join(dir, 'spoke'), ''); hand_over_to('other') }; " \
        "sleep 0.1 until File.exist?(File.join(dir, 'free'))")
      begin
        wait_for(File.join(root, "spoke"))
        run_script(root, "input.hold(speak: false) { File.delete(File.join(dir, 'away')) }", err: "other")
        sleep SETTLE * 2

        assert_equal told(DesktopInputLock::STEP_AWAY), said(root)
      ensure
        File.write(File.join(root, "free"), "")
        reap(speaker)
      end

      assert_equal told(DesktopInputLock::STEP_AWAY), said(root)
    end
  end

  # A process that exits as soon as it lets go leaves the lock to one
  # already waiting for it, held up here so that the exiting one would
  # get there first, and so leaves the call back to that one.
  def test_a_process_exiting_as_it_lets_go_leaves_the_call_back_to_one_waiting
    in_desktop do |root|
      first = spawn_script(root, "input.hold { File.write(File.join(dir, 'first'), ''); hand_over_to('second') }; " \
        "File.write(File.join(dir, 'released'), '')")
      wait_for(File.join(root, "first"))
      second = spawn_script(root, "input.hold { sleep #{SETTLE * 3} }", err: "second")
      begin
        wait_until { File.exist?(File.join(root, "second")) && File.read(File.join(root, "second")).include?(DesktopInputLock::WAITING) }
        Process.kill(:STOP, second)
        wait_for(File.join(root, "released"))
        sleep SETTLE / 3
      ensure
        Process.kill(:CONT, second)
      end
      reap(first)
      reap(second)

      assert_equal told(DesktopInputLock::STEP_AWAY, DesktopInputLock::COME_BACK), said(root)
    end
  end

  # A process whose spans settled long before it exits has already called
  # the person back, so it exits without waiting out SETTLE again.
  def test_an_exit_after_it_settles_calls_back_without_waiting
    in_desktop do |root|
      code = "input.hold { }; sleep 0.01 until File.exist?(File.join(dir, 'said')) && " \
        "File.readlines(File.join(dir, 'said')).size == 4; " \
        "File.write(File.join(dir, 'exiting'), Process.clock_gettime(Process::CLOCK_MONOTONIC).to_s)"
      run_script(root, code)
      exited = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      assert_equal told(DesktopInputLock::STEP_AWAY, DesktopInputLock::COME_BACK), said(root)
      assert_operator exited - Float(File.read(File.join(root, "exiting"))), :<, SETTLE
    end
  end

  # A process that exits while its watcher is calling the person back
  # waits until the words are said, rather than cutting them off after
  # the banner. Here say takes a second over the call back, and the
  # process exits as soon as say starts.
  def test_a_process_exiting_while_it_calls_back_waits_until_it_is_said
    in_desktop do |root|
      script(root, "say", "case \"$1\" in *'come back'*) touch \"#{root}/telling\"; sleep 1;; esac\n" \
        "printf 'say: %s\\n' \"$1\" >> \"#{root}/said\"")
      run_script(root, "input.hold { }; sleep 0.01 until File.exist?(File.join(dir, 'telling'))")

      assert_equal told(DesktopInputLock::STEP_AWAY, DesktopInputLock::COME_BACK), said(root)
    end
  end

  # A say that never finishes would hold the watcher's call back, and so
  # the process's exit, which waits for it, for good. Each thing said gets
  # at most its limit before it is stopped, so the process exits; the
  # banner was shown first, and the words were not said.
  def test_a_say_that_hangs_is_stopped_so_the_process_still_exits
    in_desktop do |root|
      script(root, "say", "case \"$1\" in *'come back'*) touch \"#{root}/telling\"; exec sleep 60;; esac\n" \
        "printf 'say: %s\\n' \"$1\" >> \"#{root}/said\"")
      code = "input = DesktopInputLock.new(lock: File.join(dir, 'lock'), marker: File.join(dir, 'away'), " \
        "say: File.join(dir, 'say'), osascript: File.join(dir, 'osascript'), settle: #{SETTLE}, env: {}, " \
        "host_os: 'darwin', tell_limit: 0.5)\n" \
        "input.hold { }; sleep 0.01 until File.exist?(File.join(dir, 'telling'))"
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      run_script(root, code)

      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 5
      assert_equal [*told(DesktopInputLock::STEP_AWAY), told(DesktopInputLock::COME_BACK).first], said(root)
      refute_path_exists File.join(root, "away")
    end
  end

  # The lock and the marker are ones every user can open and rewrite,
  # whatever the umask of the process that made them.
  def test_the_files_it_makes_are_every_users_whatever_the_umask
    in_desktop do |root|
      run_script(root, "input.hold { File.write(File.join(dir, 'mode'), File.stat(File.join(dir, 'away')).mode & 0o777) }",
        umask: 0o022)

      assert_equal 0o666, File.stat(File.join(root, "lock")).mode & 0o777
      assert_equal 0o666, Integer(File.read(File.join(root, "mode")))
    end
  end

  # A process that settles while another holds the lock leaves it to that
  # one to ask the person back.
  def test_a_process_that_settles_while_another_works_says_nothing
    in_desktop do |root|
      first = spawn_script(root, "input.hold { File.write(File.join(dir, 'first'), ''); hand_over_to('second') }; " \
        "sleep #{SETTLE * 3}")
      wait_for(File.join(root, "first"))
      run_script(root, "input.hold { sleep #{SETTLE * 6} }", err: "second")

      assert_equal told(DesktopInputLock::STEP_AWAY, DesktopInputLock::COME_BACK), said(root)
      reap(first)

      assert_equal told(DesktopInputLock::STEP_AWAY, DesktopInputLock::COME_BACK), said(root)
    end
  end

  # A marker whose process is gone was left by one that died before asking
  # the person back, so the person is asked again, and the marker is this
  # process's.
  def test_a_marker_left_by_a_dead_process_is_replaced
    in_desktop do |root|
      dead = spawn("true")
      Process.wait(dead)
      File.write(File.join(root, "away"), "#{dead} 0")
      run_script(root, "input.hold { File.write(File.join(dir, 'held'), File.read(File.join(dir, 'away'))) }")

      assert_equal told(DesktopInputLock::STEP_AWAY, DesktopInputLock::COME_BACK), said(root)
      refute_equal dead, Integer(File.read(File.join(root, "held")).split.first)
    end
  end

  # A marker naming no process at all is as stale as one whose process is
  # gone.
  def test_a_marker_naming_no_process_is_replaced
    in_desktop do |root|
      File.write(File.join(root, "away"), "0 0")
      run_script(root, "input.hold { }")

      assert_equal told(DesktopInputLock::STEP_AWAY, DesktopInputLock::COME_BACK), said(root)
    end
  end

  # A marker whose process lives means the person was asked already.
  def test_a_marker_of_a_live_process_keeps_it_quiet
    in_desktop do |root|
      File.write(File.join(root, "away"), "#{Process.pid} 0")
      run_script(root, "input.hold { }")

      assert_equal told(DesktopInputLock::COME_BACK), said(root)
    end
  end

  # A marker naming another user's live process, which this one may not
  # signal, still means the person was asked already. Process 1 is the
  # system's, and a test never runs as root.
  def test_a_marker_of_a_process_it_may_not_signal_keeps_it_quiet
    skip "running as root, which may signal every process" if Process.uid.zero?

    in_desktop do |root|
      File.write(File.join(root, "away"), "1 0")
      run_script(root, "input.hold { }")

      assert_equal told(DesktopInputLock::COME_BACK), said(root)
    end
  end

  # Spans nest, and the process lets go of the lock only when the last
  # ends, without waiting on the lock it already holds.
  def test_spans_nest_and_the_last_lets_go
    in_desktop do |root|
      outer = input(root).acquire(speak: false)
      Timeout.timeout(1) { outer.hold(speak: false) { nil } }

      assert_equal "#{DesktopInputLock::WAITING}\nwaited\n", try_from_another_process(root)

      outer.release

      assert_equal "got it\n", try_from_another_process(root)
    end
  end

  # Spans on several threads of one process share its one lock.
  def test_spans_on_two_threads_share_the_lock
    in_desktop do |root|
      held = input(root)
      inside = Queue.new
      done = Queue.new
      thread = Thread.new { held.hold(speak: false) { inside << true; done.pop } }
      inside.pop
      Timeout.timeout(1) { held.hold(speak: false) { nil } }

      assert_equal "#{DesktopInputLock::WAITING}\nwaited\n", try_from_another_process(root)
    ensure
      done&.push(true)
      thread&.join
    end
  end

  # A silent span writes no marker, removes none, says nothing, and
  # starts no watcher, which its process's threads show.
  def test_a_silent_span_says_nothing_and_leaves_the_marker_alone
    in_desktop do |root|
      code = "threads = Thread.list.size; input.hold(speak: false) { }; " \
        "File.write(File.join(dir, 'threads'), Thread.list.size - threads)"
      run_script(root, code)

      refute_path_exists File.join(root, "away")
      File.write(File.join(root, "away"), "1 0")
      run_script(root, code)

      assert_equal "1 0", File.read(File.join(root, "away"))
      assert_empty said(root)
      assert_equal "0", File.read(File.join(root, "threads"))
    end
  end

  def test_hold_returns_the_blocks_value
    in_desktop do |root|
      assert_equal 42, input(root).hold(speak: false) { 42 }
    end
  end

  def test_it_speaks_only_on_macos_outside_ci_unless_quieted
    in_desktop do |root|
      assert_predicate input(root), :speaks?
      refute_predicate input(root, env: { "CI" => "true" }), :speaks?
      refute_predicate input(root, env: { "DESKTOP_INPUT_QUIET" => "" }), :speaks?
      refute_predicate input(root, host_os: "linux-gnu"), :speaks?
      refute_predicate input(root, host_os: "mingw32"), :speaks?
    end
  end

  # Without say, the person still sees the banners.
  def test_without_say_it_only_shows
    in_desktop do |root|
      File.delete(File.join(root, "say"))
      run_script(root, "input.hold { }")

      assert_equal told(DesktopInputLock::STEP_AWAY, DesktopInputLock::COME_BACK).grep(/\Aosascript/), said(root)
    end
  end

  # A Mac with neither the banner nor the voice cannot tell the person
  # anything, so its speaking span is a silent one and leaves no marker,
  # which would keep every other process from telling them.
  def test_without_say_or_osascript_a_speaking_span_is_a_silent_one
    in_desktop do |root|
      File.delete(File.join(root, "say"))
      File.delete(File.join(root, "osascript"))

      refute_predicate input(root), :speaks?

      run_script(root, "input.hold { File.write(File.join(dir, 'ran'), '') }")

      assert_path_exists File.join(root, "ran")
      refute_path_exists File.join(root, "away")
    end
  end

  # A banner that cannot be shown, as where notifications are denied,
  # fails nothing, and the words are still said.
  def test_a_banner_that_fails_fails_nothing
    in_desktop do |root|
      script(root, "osascript", "exit 1")
      run_script(root, "input.hold { File.write(File.join(dir, 'ran'), '') }")

      assert_path_exists File.join(root, "ran")
      assert_equal told(DesktopInputLock::STEP_AWAY, DesktopInputLock::COME_BACK).grep(/\Asay/), said(root)
    end
  end

  # What osascript prints, such as its complaint when notifications are
  # denied, never reaches the tests' own output.
  def test_what_the_banner_prints_stays_out_of_the_output
    in_desktop do |root|
      script(root, "osascript", "echo shown; echo refused >&2")
      out, err, status = Open3.capture3(RbConfig.ruby, "-I", LIB, "-e", "#{PRELUDE}\ninput.hold { }", root)

      assert_predicate status, :success?
      assert_empty out
      assert_empty err
    end
  end

  # Where it would not speak, a speaking span is a silent one.
  def test_a_quiet_span_says_nothing
    in_desktop do |root|
      input(root, env: { "DESKTOP_INPUT_QUIET" => "1" }).hold { nil }

      assert_empty said(root)
      refute_path_exists File.join(root, "away")
    end
  end

  # Another process waits while this one holds the lock, saying so once,
  # and goes on when this one lets go.
  def test_a_process_waits_for_the_process_holding_the_lock
    in_desktop do |root|
      held = input(root).acquire(speak: false)

      assert_equal "#{DesktopInputLock::WAITING}\nwaited\n", try_from_another_process(root)

      held.release

      assert_equal "got it\n", try_from_another_process(root)
    end
  end

  def test_hold_gives_the_lock_back_when_the_block_raises
    in_desktop do |root|
      assert_raises(RuntimeError) { input(root).hold(speak: false) { raise "boom" } }

      Timeout.timeout(1) { input(root).hold(speak: false) { nil } }
    end
  end

  # With no lock, as on Windows unless given one, a span runs its block
  # and touches nothing.
  def test_with_no_lock_a_span_only_runs_its_block
    in_desktop do |root|
      none = input(root, lock: nil, marker: nil)

      assert_equal :ran, none.hold { :ran }
      assert_equal :gone, none.call_back
      refute_path_exists File.join(root, "lock")
      refute_path_exists File.join(root, "away")
    end
  end

  # The lock and marker are the ones every project following the protocol
  # shares, with its timing and words.
  def test_the_protocol_is_the_one_every_project_shares
    assert_equal "/tmp/desktop-input.lock", DesktopInputLock::LOCK
    assert_equal "/tmp/desktop-input.away", DesktopInputLock::MARKER
    assert_equal 3, DesktopInputLock::SETTLE
    assert_equal "Tests need the keyboard and mouse for a moment. Please step away.", DesktopInputLock::STEP_AWAY
    assert_equal "The tests are done with the keyboard and mouse. You can come back now.", DesktopInputLock::COME_BACK
    assert_equal "waiting for the desktop input lock", DesktopInputLock::WAITING
  end
end
