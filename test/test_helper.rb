# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

lib = File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "desktop_input_lock"

require "minitest/autorun"
require "fileutils"
require "open3"
require "rbconfig"
require "stringio"
require "timeout"
require "tmpdir"

# A desktop of each test's own: a lock and marker in a fresh directory,
# with say and osascript replaced by scripts that write down, in order,
# what they were given, so nothing is shown or said for real.
module DesktopHelper
  # The library, for the child Rubies the tests start.
  LIB = File.expand_path("../lib", __dir__)

  # What the tests settle in, in seconds: long enough for a process to
  # start, short enough for a fast suite.
  SETTLE = 0.3

  # What every child's script starts with: a DesktopInputLock over the
  # desktop given as its first argument, speaking as macOS outside CI
  # would.
  PRELUDE = <<~RUBY
    require "desktop_input_lock"
    dir = ARGV.fetch(0)
    input = DesktopInputLock.new(lock: File.join(dir, "lock"), marker: File.join(dir, "away"),
      say: File.join(dir, "say"), osascript: File.join(dir, "osascript"), settle: #{SETTLE}, env: {},
      host_os: "darwin", notify_send: File.join(dir, "notify-send"), spd_say: File.join(dir, "spd-say"),
      espeak_ng: File.join(dir, "espeak-ng"), powershell: File.join(dir, "powershell"))
    def waiting?(name)
      File.read(File.join(ARGV.fetch(0), name)).include?(DesktopInputLock::WAITING)
    rescue Errno::ENOENT
      false
    end
    def hand_over_to(name) = (sleep 0.01 until waiting?(name))
  RUBY

  # Yields a fresh, empty directory, its real path, since macOS links
  # /var to /private/var, for a test that needs a lock and nothing to
  # speak with, and so runs on every system.
  def in_dir
    Dir.mktmpdir("desktop-input-lock-test") { |dir| yield File.realpath(dir) }
  end

  # Yields a fresh directory (its real path, since macOS links /var to
  # /private/var) with recording say and osascript scripts in it. The
  # scripts, and the processes the tests stop and start, are POSIX, so on
  # Windows, where the lock takes no file until the Windows work of Plan
  # 001 lands, these tests skip.
  def in_desktop
    skip "needs a POSIX shell and signals; Windows comes later (Plan 001)" if Gem.win_platform?

    Dir.mktmpdir("desktop-input-lock-test") do |dir|
      root = File.realpath(dir)
      script(root, "say", "printf 'say: %s\\n' \"$1\" >> \"#{root}/said\"")
      script(root, "osascript", "printf 'osascript %s %s\\n' \"$1\" \"$2\" >> \"#{root}/said\"")
      yield root
    end
  end

  # Writes an executable shell script named +name+ under +root+.
  def script(root, name, body)
    path = File.join(root, name)
    File.write(path, "#!/bin/sh\n#{body}\n")
    File.chmod(0o755, path)
    path
  end

  # Starts a Ruby running +code+ after PRELUDE, its standard error, and
  # so whether it waits for the lock, in the file +err+ names.
  def spawn_script(root, code, err: nil, **)
    spawn(RbConfig.ruby, "-I", LIB, "-e", "#{PRELUDE}\n#{code}", root,
      err: err ? File.join(root, err) : File::NULL, **)
  end

  def run_script(root, code, err: nil, **) = reap(spawn_script(root, code, err:, **))

  # How long a test waits for something that should happen at once
  # before it fails. Only a broken lock reaches it, so it is generous:
  # a loaded machine can take seconds to start a process.
  GUARD = 30

  # Waits for the process +pid+ to end, killing it if it has not within
  # GUARD, so a test that fails leaves nothing running. Returns its
  # status.
  def reap(pid)
    Timeout.timeout(GUARD) { Process.wait2(pid).last }
  rescue Timeout::Error
    Process.kill(:KILL, pid)
    Process.wait(pid)
    raise
  end

  # What the person is shown and told of +words+ on macOS, in order: each
  # first as a banner, then aloud.
  def told(*words)
    words.flat_map { |text| ["osascript -e display notification #{text.dump} with title \"Tests\"", "say: #{text}"] }
  end

  def said(root) = File.exist?(File.join(root, "said")) ? File.readlines(File.join(root, "said"), chomp: true) : []

  # A DesktopInputLock in this process over the desktop at +root+.
  def input(root, **)
    DesktopInputLock.new(lock: File.join(root, "lock"), marker: File.join(root, "away"), **stand_ins(root),
      settle: SETTLE, env: {}, host_os: "darwin", log: StringIO.new, **)
  end

  # Every command the lock speaks with, at a path under +root+, so no
  # test finds the real ones on the machine it runs on.
  def stand_ins(root)
    %w[say osascript notify-send spd-say espeak-ng powershell]
      .to_h { |name| [name.tr("-", "_").to_sym, File.join(root, name)] }
  end

  def wait_for(path) = wait_until { File.exist?(path) }

  def wait_until(&) = Timeout.timeout(GUARD) { sleep 0.01 until yield }

  # What another process says of the lock at +lock+: <tt>"got it\n"</tt>
  # when it takes the lock, or, when it says it is waiting for it,
  # WAITING and <tt>"waited\n"</tt>, after which it is stopped. Whichever
  # it says first decides, so no time limit does.
  def try_from_another_process(root, lock: File.join(root, "lock"))
    script = "$stderr.sync = true; require 'desktop_input_lock'\n" \
      "input = DesktopInputLock.new(lock: #{lock.dump}, marker: File.join(ARGV[0], 'away'), settle: #{SETTLE})\n" \
      "input.hold(speak: false) { }; $stderr.puts 'got it'"
    Open3.popen2e(RbConfig.ruby, "-I", LIB, "-e", script, root) do |_, output, thread|
      line = Timeout.timeout(GUARD) { output.gets }
      next line if line == "got it\n"

      Process.kill(:KILL, thread.pid)
      "#{line}waited\n"
    end
  end
end
