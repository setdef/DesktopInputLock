# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# Which files a process locks: the protocol's, a session's own, or, on
# Windows, those in ProgramData.
class PathsTest < Minitest::Test
  include DesktopHelper
  parallelize_me!

  def test_the_protocols_files_by_default
    assert_equal [DesktopInputLock::LOCK, DesktopInputLock::MARKER], DesktopInputLock.paths({}, "darwin25")
    assert_equal [DesktopInputLock::LOCK, DesktopInputLock::MARKER], DesktopInputLock.paths({}, "linux-gnu")
  end

  def test_a_sessions_own_lock_with_its_marker_beside_it
    assert_equal ["/tmp/desktop-input-hidden.lock", "/tmp/desktop-input-hidden.away"],
      DesktopInputLock.paths({ "DESKTOP_INPUT_LOCK" => "/tmp/desktop-input-hidden.lock" }, "darwin25")
    assert_equal ["/tmp/mine", "/tmp/mine.away"], DesktopInputLock.paths({ "DESKTOP_INPUT_LOCK" => "/tmp/mine" }, "darwin25")
  end

  def test_an_empty_variable_names_no_lock_of_its_own
    assert_equal [DesktopInputLock::LOCK, DesktopInputLock::MARKER],
      DesktopInputLock.paths({ "DESKTOP_INPUT_LOCK" => "" }, "darwin25")
  end

  # Windows has no /tmp, so every user's processes meet in ProgramData,
  # the folder every user shares.
  def test_windows_locks_in_program_data
    assert_equal ["D:/Data/desktop-input.lock", "D:/Data/desktop-input.away"],
      DesktopInputLock.paths({ "ProgramData" => "D:/Data" }, "mingw32")
    assert_equal ["C:/ProgramData/desktop-input.lock", "C:/ProgramData/desktop-input.away"],
      DesktopInputLock.paths({}, "mingw32")
    assert_equal ['C:\\locks\\desk.lock', 'C:\\locks\\desk.away'],
      DesktopInputLock.paths({ "DESKTOP_INPUT_LOCK" => 'C:\\locks\\desk.lock' }, "mingw32")
  end

  # A fresh process started with DESKTOP_INPUT_LOCK locks that file
  # through DesktopInputLock.hold, so another process taking it waits,
  # and leaves the protocol's own lock alone.
  def test_a_process_started_with_the_variable_locks_its_file
    in_desktop do |root|
      lock = File.join(root, "session.lock")
      code = "DesktopInputLock.hold(speak: false) { File.write(File.join(dir, 'held'), ''); " \
        "sleep 0.01 until File.exist?(File.join(dir, 'free')) }"
      holder = spawn({ "DESKTOP_INPUT_LOCK" => lock }, RbConfig.ruby, "-I", LIB, "-e", "#{PRELUDE}\n#{code}", root)
      begin
        wait_for(File.join(root, "held"))

        assert_equal "#{DesktopInputLock::WAITING}\nwaited\n", try_from_another_process(root, lock:)
        assert_equal "got it\n", try_from_another_process(root)
      ensure
        File.write(File.join(root, "free"), "")
        reap(holder)
      end
    end
  end
end
