# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "test_helper"

# How the lock speaks on a Linux desktop and on Windows, in real
# processes over each test's own lock, with stand-ins for notify-send,
# spd-say, espeak-ng, and PowerShell that write down what they were
# given. The operating system is named to the lock, so these run on any
# POSIX system.
class PlatformsTest < Minitest::Test
  include DesktopHelper
  parallelize_me!

  # A child's DesktopInputLock over the desktop at its first argument, as
  # on +host_os+ with +env+.
  def child(host_os, env)
    "input = DesktopInputLock.new(lock: File.join(dir, 'lock'), marker: File.join(dir, 'away'), " \
      "say: File.join(dir, 'say'), osascript: File.join(dir, 'osascript'), " \
      "notify_send: File.join(dir, 'notify-send'), spd_say: File.join(dir, 'spd-say'), " \
      "espeak_ng: File.join(dir, 'espeak-ng'), powershell: File.join(dir, 'powershell'), " \
      "settle: #{SETTLE}, env: #{env.inspect}, host_os: #{host_os.dump})\n"
  end

  # Writes the Linux stand-ins, each recording its name and arguments.
  def linux(root, *names)
    names.each { |name| script(root, name, "printf '#{name}' >> \"#{root}/said\"; printf ' %s' \"$@\" >> \"#{root}/said\"; echo >> \"#{root}/said\"") }
  end

  DESKTOP = { "DISPLAY" => ":0" }.freeze

  def told_on_linux(voice, *words)
    words.flat_map do |text|
      ["notify-send Tests #{text}", (voice == "spd-say") ? "spd-say --wait #{text}" : "#{voice} #{text}"]
    end
  end

  def test_a_linux_desktop_shows_a_notification_then_speaks
    in_desktop do |root|
      linux(root, "notify-send", "spd-say", "espeak-ng")
      run_script(root, "#{child('linux-gnu', DESKTOP)}input.hold { }")

      assert_equal told_on_linux("spd-say", DesktopInputLock::STEP_AWAY, DesktopInputLock::COME_BACK), said(root)
      refute_path_exists File.join(root, "away")
    end
  end

  def test_a_linux_desktop_without_speech_dispatcher_speaks_with_espeak_ng
    in_desktop do |root|
      linux(root, "notify-send", "espeak-ng")
      run_script(root, "#{child('linux-gnu', { 'WAYLAND_DISPLAY' => 'wayland-0' })}input.hold { }")

      assert_equal told_on_linux("espeak-ng", DesktopInputLock::STEP_AWAY, DesktopInputLock::COME_BACK), said(root)
    end
  end

  def test_a_linux_desktop_with_only_notifications_still_shows_them
    in_desktop do |root|
      linux(root, "notify-send")
      run_script(root, "#{child('linux-gnu', DESKTOP)}input.hold { }")

      assert_equal told_on_linux("spd-say", DesktopInputLock::STEP_AWAY, DesktopInputLock::COME_BACK).grep(/\Anotify/),
        said(root)
    end
  end

  # Linux with no display is a server or CI, with no one to tell, and
  # Linux with nothing to speak with cannot tell anyone, so a speaking
  # span there is a silent one and leaves no marker.
  def test_linux_without_a_desktop_or_a_voice_is_silent
    in_desktop do |root|
      linux(root, "notify-send", "spd-say")

      refute_predicate input(root, host_os: "linux-gnu"), :speaks?
      refute_predicate input(root, host_os: "linux-gnu", env: { "DISPLAY" => "" }), :speaks?
      refute_predicate input(root, host_os: "linux-gnu", env: { **DESKTOP, "CI" => "true" }), :speaks?
      assert_predicate input(root, host_os: "linux-gnu", env: DESKTOP), :speaks?

      %w[notify-send spd-say].each { |name| File.delete(File.join(root, name)) }

      refute_predicate input(root, host_os: "linux-gnu", env: DESKTOP), :speaks?
      run_script(root, "#{child('linux-gnu', DESKTOP)}input.hold { File.write(File.join(dir, 'ran'), '') }")

      assert_path_exists File.join(root, "ran")
      refute_path_exists File.join(root, "away")
      assert_empty said(root)
    end
  end

  # Windows shows a toast, then speaks, each a PowerShell given the words
  # in its environment, never in the script it runs.
  def test_windows_shows_a_toast_then_speaks_through_powershell
    in_desktop do |root|
      script(root, "powershell", "printf '%s %s: %s\\n' \"$3\" \"$DESKTOP_INPUT_TELL\" \"$DESKTOP_INPUT_WORDS\" >> \"#{root}/said\"; " \
        "case \"$4\" in *DESKTOP_INPUT_WORDS*) ;; *) echo 'words not from the environment' >> \"#{root}/said\";; esac")
      run_script(root, "#{child('mingw32', {})}input.hold { }")

      expected = [DesktopInputLock::STEP_AWAY, DesktopInputLock::COME_BACK]
        .flat_map { |text| ["-Command banner: #{text}", "-Command voice: #{text}"] }

      assert_equal expected, said(root)
      refute_path_exists File.join(root, "away")
    end
  end

  def test_windows_without_powershell_is_silent
    in_desktop do |root|
      refute_predicate input(root, host_os: "mingw32"), :speaks?
      script(root, "powershell", "true")

      assert_predicate input(root, host_os: "mingw32"), :speaks?
      refute_predicate input(root, host_os: "mingw32", env: { "DESKTOP_INPUT_QUIET" => "1" }), :speaks?
    end
  end

  # A marker another user's process left where this one may not delete
  # it, as in /tmp, whose sticky bit keeps each user's files their own,
  # is left to that user's processes: this one says nothing more, and
  # neither its watcher nor its exit fails. Here a folder this process
  # may not write stands in for the other user's file.
  def test_a_marker_it_may_not_delete_is_left_to_its_owner
    skip "running as root, which may delete any file" if Process.uid.zero?

    in_desktop do |root|
      shared = File.join(root, "shared")
      Dir.mkdir(shared)
      File.write(File.join(shared, "away"), "#{Process.pid} 0")
      File.write(File.join(shared, "lock"), "")
      File.chmod(0o555, shared)
      begin
        code = "input = DesktopInputLock.new(lock: File.join(dir, 'shared', 'lock'), " \
          "marker: File.join(dir, 'shared', 'away'), say: File.join(dir, 'say'), " \
          "osascript: File.join(dir, 'osascript'), settle: #{SETTLE}, env: {}, host_os: 'darwin')\n" \
          "input.hold { }; sleep #{SETTLE * 2}"
        _, err, status = Open3.capture3(RbConfig.ruby, "-I", LIB, "-e", "#{PRELUDE}\n#{code}", root)

        assert_predicate status, :success?, err
        assert_empty err
        assert_empty said(root)
        assert_path_exists File.join(shared, "away")
      ensure
        File.chmod(0o755, shared)
      end
    end
  end
end
