# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "monitor"
require "rbconfig"
require_relative "desktop_input_lock/version"

# Keeps tests that take the keyboard and mouse out of each other's way.
#
# A computer has one pointer, and one window at a time has the keyboard's
# focus. A test that opens a real menu, brings a window to the front, or
# moves the pointer passes only if nothing else takes them in the
# meantime. Run two projects' tests at once on one computer, or one
# project's checks in parallel, and each lands its input in the other's
# windows. The failures look random, and vanish when you run the test
# alone.
#
# This class holds one lock that every such test shares, across processes
# and across projects. A speaking span also tells the person at a Mac,
# first with a Notification Center banner and then aloud, to step away,
# and calls them back once no span has run for SETTLE seconds. A silent
# span only takes the lock.
#
# Use it around a test that takes focus, opens a menu, or moves the
# pointer, or for a whole run that does, with #hold for a block or
# #acquire and #release for a test's setup and teardown.
#
# === The protocol
#
# Other projects implement the same protocol, so its files, timings, and
# words never change:
#
# - The lock is an exclusive +flock+ on LOCK, held only around each span,
#   so the system frees it if the process dies. Taking it blocks, after
#   printing WAITING.
# - A speaking span, on taking the lock, finds no marker at MARKER, or one
#   naming a process that has ended, writes its own process id and the
#   time there (<tt>"<pid> <unix time>"</tt>), and says STEP_AWAY. A
#   marker naming a live process means someone has already warned.
# - Once SETTLE seconds pass with none of its spans running, a process
#   that held a speaking span tries the lock without waiting. If it gets
#   it and the marker is there, it removes the marker and says COME_BACK.
#   If the lock is busy, it tries again at each poll until it calls back
#   or finds the marker gone.
# - On exit it first waits out the rest of SETTLE from its last release,
#   so a process blocked waiting for the lock takes it first, then tries
#   once more.
# - Both files are made mode 0666 whatever the umask, so every user's
#   processes can open the lock and rewrite the marker.
# - A silent span takes the same lock, but never speaks, never writes or
#   removes the marker, and starts no watcher.
#
# The lock is taken everywhere, on CI too, and even when quiet. Windows
# has no /tmp, so there the files are WINDOWS_LOCK and WINDOWS_MARKER in
# <tt>%ProgramData%</tt>, the folder every user shares.
#
# A speaking span speaks only outside CI, unless +DESKTOP_INPUT_QUIET+ is
# set, and only where it has something to speak with; elsewhere it is a
# silent one. Each thing it says it first shows as a banner, which takes
# no focus, for a person whose sound is off, then says aloud:
#
# - On macOS, a Notification Center banner through +osascript+, then
#   +say+.
# - On a Linux desktop (+DISPLAY+ or +WAYLAND_DISPLAY+ set), a
#   notification through +notify-send+, then +spd-say+, or +espeak-ng+
#   where it has no +spd-say+.
# - On Windows, a toast notification and then the system's own voice,
#   both through PowerShell.
#
# Neither the banner nor the voice fails a span, and each is stopped
# after TELL_LIMIT seconds, so one that hangs cannot hang the process's
# exit.
#
# Two edges stay open, since closing either would change the protocol: a
# retrying watcher can find the lock free in the gap between another
# process's spans and call the person back early, and a process of one
# user cannot delete a marker another user's process left in /tmp, whose
# sticky bit keeps each user's files their own, so it leaves the call
# back to that user's processes.
#
# Spans nest, and spans on several threads of one process share the one
# lock held while any runs, since a second +flock+ from the same process,
# on a descriptor of its own, would wait on the first forever.
#
# === One session's own lock
#
# Set +DESKTOP_INPUT_LOCK+ to a path, and every process that starts with
# it locks that file instead of LOCK, with its marker beside it, ending
# in <tt>.away</tt> in place of <tt>.lock</tt>. Do this for a session
# whose keyboard focus and pointer are its own, such as a second user
# logged in in the background, so its tests stop waiting on those of the
# person's session. Point it only at a path every process of that session
# can reach, and only where nothing outside the session can take the same
# focus or pointer.
#
# === Examples
#
#--
# SPDX-SnippetBegin
# SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: MIT-0
#++
#   require "desktop_input_lock"
#
#   # A test that opens a real menu, which takes the keyboard: the person
#   # at a Mac is asked to step away, and called back afterward.
#   DesktopInputLock.hold { menu.popup(window) }
#
#   # A test that moves the pointer, quickly and out of sight.
#   DesktopInputLock.hold(speak: false) { move_pointer_and_read_it_back }
#
#   # A test whose setup and teardown are separate methods.
#   def setup
#     @desktop_input = DesktopInputLock.acquire(speak: false)
#   end
#
#   def teardown
#     @desktop_input.release
#   end
#--
# SPDX-SnippetEnd
#++
class DesktopInputLock
  # The file every process locks: literally /tmp, not Dir.tmpdir, which
  # differs between processes on macOS.
  LOCK = "/tmp/desktop-input.lock"
  # The file that says the person was told to step away, holding
  # <tt>"<pid> <unix time>"</tt> of the process that told them.
  MARKER = "/tmp/desktop-input.away"
  # macOS's speech synthesizer.
  SAY = "/usr/bin/say"
  # What shows a Notification Center banner.
  OSASCRIPT = "/usr/bin/osascript"
  # The name of the file locked on Windows, in <tt>%ProgramData%</tt>.
  WINDOWS_LOCK = "desktop-input.lock"
  # The name of the marker on Windows, in <tt>%ProgramData%</tt>.
  WINDOWS_MARKER = "desktop-input.away"
  # What shows a notification on a Linux desktop, found on +PATH+.
  NOTIFY_SEND = "notify-send"
  # Speech Dispatcher's voice on a Linux desktop, found on +PATH+.
  SPD_SAY = "spd-say"
  # The voice a Linux desktop without Speech Dispatcher may have, found on
  # +PATH+.
  ESPEAK_NG = "espeak-ng"
  # The PowerShell that shows a toast and speaks on Windows, under
  # <tt>%SystemRoot%</tt>: Windows PowerShell, which every Windows has.
  POWERSHELL = "System32/WindowsPowerShell/v1.0/powershell.exe"
  # What Windows PowerShell runs to show <tt>$env:DESKTOP_INPUT_WORDS</tt>
  # in a toast, under PowerShell's own name, since a toast needs an app
  # to come from.
  WINDOWS_BANNER = [
    "$type = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]",
    "$toast = $type::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)",
    "$texts = $toast.GetElementsByTagName('text')",
    "$null = $texts.Item(0).AppendChild($toast.CreateTextNode('Tests'))",
    "$null = $texts.Item(1).AppendChild($toast.CreateTextNode($env:DESKTOP_INPUT_WORDS))",
    '$app = \'{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe\'',
    "$type::CreateToastNotifier($app).Show([Windows.UI.Notifications.ToastNotification]::new($toast))",
  ].join("\n")
  # What Windows PowerShell runs to say <tt>$env:DESKTOP_INPUT_WORDS</tt>
  # with the system's own voice, waiting until it is said.
  WINDOWS_VOICE = [
    "Add-Type -AssemblyName System.Speech",
    "(New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak($env:DESKTOP_INPUT_WORDS)",
  ].join("\n")
  # Seconds with no span running before the person is called back.
  SETTLE = 3
  # What the first speaking span says.
  STEP_AWAY = "Tests need the keyboard and mouse for a moment. Please step away."
  # What is said once no one needs them.
  COME_BACK = "The tests are done with the keyboard and mouse. You can come back now."
  # What a span that has to wait for the lock prints first.
  WAITING = "waiting for the desktop input lock"
  # Seconds the banner, and then the voice, may take before it is stopped:
  # far longer than either sentence takes to say.
  TELL_LIMIT = 30
  # The variable that points one session at a lock of its own.
  SESSION_LOCK = "DESKTOP_INPUT_LOCK"

  # The lock and marker a process uses, given its environment and
  # operating system: the file +DESKTOP_INPUT_LOCK+ names and its marker,
  # or else LOCK and MARKER, or, on Windows, WINDOWS_LOCK and
  # WINDOWS_MARKER in <tt>%ProgramData%</tt>.
  #
  # [env] The environment, which may name a session's own lock.
  # [host_os] The operating system.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   DesktopInputLock.paths({}, "darwin25")
  #   # => ["/tmp/desktop-input.lock", "/tmp/desktop-input.away"]
  #   DesktopInputLock.paths({ "DESKTOP_INPUT_LOCK" => "/tmp/hidden.lock" }, "darwin25")
  #   # => ["/tmp/hidden.lock", "/tmp/hidden.away"]
  #   DesktopInputLock.paths({ "ProgramData" => "C:/ProgramData" }, "mingw32")
  #   # => ["C:/ProgramData/desktop-input.lock", "C:/ProgramData/desktop-input.away"]
  #--
  # SPDX-SnippetEnd
  #++
  def self.paths(env, host_os)
    lock = env[SESSION_LOCK]
    return [lock, "#{lock.delete_suffix('.lock')}.away"] if lock && !lock.empty?
    return [LOCK, MARKER] unless windows?(host_os)

    shared = env["ProgramData"] || "C:/ProgramData"
    [File.join(shared, WINDOWS_LOCK), File.join(shared, WINDOWS_MARKER)]
  end

  # Whether +host_os+ names Windows.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   DesktopInputLock.windows?("mingw32") # => true
  #--
  # SPDX-SnippetEnd
  #++
  def self.windows?(host_os)
    host_os.match?(/mswin|mingw|cygwin/)
  end

  # The full path of the command +name+ on +PATH+, or +nil+ where it is
  # not there.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   DesktopInputLock.find("notify-send") # => "/usr/bin/notify-send", on most Linux desktops
  #--
  # SPDX-SnippetEnd
  #++
  def self.find(name)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }
      .find { |path| File.file?(path) && File.executable?(path) }
  end

  # Creates a lock of its own, for a test of the lock or a process that
  # keeps its own files. Most callers use the class methods, which share
  # DEFAULT.
  #
  # [lock] The file locked, or +nil+ to lock nothing.
  # [marker] The file that says the person was told to step away.
  # [say] macOS's speech synthesizer, given the words to say.
  # [osascript] What runs the AppleScript that shows macOS's banner.
  # [settle] Seconds with no span running before COME_BACK.
  # [env] The environment that can quiet it (+CI+, +DESKTOP_INPUT_QUIET+),
  #       and that says whether Linux has a desktop (+DISPLAY+,
  #       +WAYLAND_DISPLAY+).
  # [host_os] The operating system, which decides how it speaks.
  # [log] Where WAITING is printed.
  # [tell_limit] Seconds the banner, and then the voice, may take.
  # [notify_send] What shows a Linux desktop's notification, or +nil+.
  # [spd_say] Speech Dispatcher's voice on Linux, or +nil+.
  # [espeak_ng] The Linux voice used where there is no +spd_say+, or +nil+.
  # [powershell] The Windows PowerShell that shows a toast and speaks.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   input = DesktopInputLock.new(lock: "/tmp/mine.lock", marker: "/tmp/mine.away", settle: 0.3)
  #   input.hold(speak: false) { move_pointer }
  #--
  # SPDX-SnippetEnd
  #++
  def initialize(lock: LOCK, marker: MARKER, say: SAY, osascript: OSASCRIPT, settle: SETTLE, env: ENV,
    host_os: RbConfig::CONFIG["host_os"], log: $stderr, tell_limit: TELL_LIMIT,
    notify_send: DesktopInputLock.find(NOTIFY_SEND), spd_say: DesktopInputLock.find(SPD_SAY),
    espeak_ng: DesktopInputLock.find(ESPEAK_NG), powershell: File.join(ENV["SystemRoot"] || "C:/Windows", POWERSHELL)
  )
    @lock = lock
    @marker = marker
    @say = say
    @osascript = osascript
    @notify_send = notify_send
    @spd_say = spd_say
    @espeak_ng = espeak_ng
    @powershell = powershell
    @settle = settle
    @env = env
    @host_os = host_os
    @log = log
    @tell_limit = tell_limit
    @state = Monitor.new
    @depth = 0
    @file = nil
    @pending = false
    @last_done = nil
    @watcher = nil
  end

  # Runs the block holding the lock, as a speaking span unless +speak+ is
  # false, and lets go, even if the block raises. Returns the block's
  # value.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   DesktopInputLock.new.hold { menu.popup(window) }
  #--
  # SPDX-SnippetEnd
  #++
  def hold(speak: true)
    acquire(speak:)
    begin
      yield
    ensure
      release
    end
  end

  # Takes the lock, to be given back by #release, for a test whose setup
  # and teardown are separate methods. Returns this DesktopInputLock,
  # which keeps the lock open until #release, or until the process ends,
  # whether or not you keep a reference to it.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   held = DesktopInputLock.new.acquire(speak: false)
  #   move_pointer
  #   held.release
  #--
  # SPDX-SnippetEnd
  #++
  def acquire(speak: true)
    speak &&= speaks?
    @state.synchronize do
      take if @depth.zero?
      @depth += 1
      announce if speak
    end
    self
  end

  # Gives back what #acquire took, letting go of the lock once no span of
  # this process holds it.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   DesktopInputLock.new.acquire(speak: false).release
  #--
  # SPDX-SnippetEnd
  #++
  def release
    @state.synchronize do
      @depth -= 1
      @last_done = now
      next unless @depth.zero?

      @file&.close
      @file = nil
    end
  end

  # Whether a speaking span speaks here: outside CI, unless
  # +DESKTOP_INPUT_QUIET+ is set, with a lock to hold, and with something
  # to speak with: +osascript+ or +say+ on macOS, a desktop and
  # +notify-send+, +spd-say+, or +espeak-ng+ on Linux, PowerShell on
  # Windows.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   DesktopInputLock.new(env: { "CI" => "true" }).speaks? # => false
  #--
  # SPDX-SnippetEnd
  #++
  def speaks?
    return false unless @lock && @env["CI"].nil? && @env["DESKTOP_INPUT_QUIET"].nil?

    case system_kind
    when :macos then executable?(@osascript) || executable?(@say)
    when :linux then desktop? && [@notify_send, @spd_say, @espeak_ng].any? { |command| executable?(command) }
    when :windows then executable?(@powershell)
    else false
    end
  end

  # Calls the person back, once SETTLE seconds have passed since the last
  # span of this process ended, if a speaking span has run since the last
  # call. While the lock is busy and the marker is there, it tries again
  # at the next call. The watcher polls it.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   input = DesktopInputLock.new
  #   input.hold { menu.popup(window) }
  #   sleep DesktopInputLock::SETTLE
  #   input.tick # calls the person back
  #--
  # SPDX-SnippetEnd
  #++
  def tick
    @state.synchronize do
      next unless @pending && @depth.zero?
      next if now - (@last_done || now) < @settle

      @pending = come_back == :busy
    end
  end

  # Calls the person back if no one holds the lock and the marker says
  # they were sent away. Never waits for the lock. Returns +:called+,
  # +:busy+ when someone holds the lock and the marker is there, or
  # +:gone+ when the marker is not.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   DesktopInputLock.new.call_back # => :gone, when no one was sent away
  #--
  # SPDX-SnippetEnd
  #++
  def call_back
    @state.synchronize { come_back }
  end

  # What a process that held a speaking span does as it exits: stops the
  # watcher, waits out what is left of SETTLE since it last let go of the
  # lock, so a process already waiting for the lock takes it first, and
  # then calls back.
  #
  # It stops the watcher only between ticks, since a tick holds the state
  # throughout a call back, and killing the watcher mid-call would leave
  # the marker removed and the words shown but never said.
  #
  # === Example
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   input = DesktopInputLock.new
  #   input.hold { menu.popup(window) }
  #   input.finish # => :called, about SETTLE seconds later
  #--
  # SPDX-SnippetEnd
  #++
  def finish
    @state.synchronize { @watcher&.kill }
    @watcher&.join
    @watcher = nil
    last_done = @state.synchronize { @last_done }
    left = last_done && (@settle - (now - last_done))
    sleep left if left&.positive?
    call_back
  end

  private def take
    lock = @lock or return
    file = open_lock(lock)
    begin
      unless file.flock(File::LOCK_EX | File::LOCK_NB)
        @log.puts WAITING
        file.flock(File::LOCK_EX)
      end
      @file = file
    ensure
      file.close unless @file
    end
  end

  private def announce
    step_away unless warned_by_a_live_process?
    @pending = true
    @watcher ||= start_watcher
  end

  private def open_lock(path)
    file = File.open(path, File::RDONLY | File::CREAT, 0o666)
    share(path)
    file
  end

  private def step_away
    marker = @marker or return
    File.write(marker, "#{Process.pid} #{Time.now.to_i}")
    share(marker)
    tell(STEP_AWAY)
  end

  # Makes +path+ readable and writable by every user, whatever the umask.
  # A file another user created stays as they made it.
  private def share(path)
    File.chmod(0o666, path)
  rescue Errno::EPERM
    nil
  end

  private def warned_by_a_live_process?
    marker = @marker or return false
    pid = Integer(File.read(marker).split.first, exception: false)
    !pid.nil? && pid.positive? && alive?(pid)
  rescue Errno::ENOENT
    false
  end

  private def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  rescue Errno::EPERM
    true
  end

  private def start_watcher
    at_exit { finish }
    Thread.new do
      loop do
        sleep [@settle / 4.0, 0.25].min
        tick
      end
    end
  end

  # Holding no lock of its own, looks at the lock on a fresh descriptor.
  private def come_back
    lock = @lock
    marker = @marker
    return :gone unless lock && marker

    file = open_lock(lock)
    begin
      come_back_holding(file, marker)
    ensure
      file.close
    end
  end

  # What #come_back finds with +file+, the lock on a descriptor of its own.
  private def come_back_holding(file, marker)
    return File.exist?(marker) ? :busy : :gone unless file.flock(File::LOCK_EX | File::LOCK_NB)
    return :gone unless File.exist?(marker)

    return :gone unless remove(marker)

    tell(COME_BACK)
    :called
  end

  # Removes the marker, or, when another user's process left it where
  # this one may not delete it, leaves it, and the call back, to that
  # user's processes. Returns whether it is gone.
  private def remove(marker)
    File.delete(marker)
    true
  rescue Errno::EACCES, Errno::EPERM
    false
  end

  # Shows +words+ in a banner, then says them, waiting until they are said.
  # Every command's output is dropped, so a refused notification prints
  # nothing into the tests' output.
  private def tell(words)
    case system_kind
    when :macos then tell_macos(words)
    when :linux then tell_linux(words)
    when :windows then tell_windows(words)
    end
  end

  private def tell_macos(words)
    run([@osascript, "-e", "display notification #{words.dump} with title \"Tests\""]) if executable?(@osascript)
    run([@say, words]) if executable?(@say)
  end

  private def tell_linux(words)
    notify_send = @notify_send
    spd_say = @spd_say
    espeak_ng = @espeak_ng
    run([notify_send, "Tests", words]) if notify_send && executable?(notify_send)
    if spd_say && executable?(spd_say)
      run([spd_say, "--wait", words])
    elsif espeak_ng && executable?(espeak_ng)
      run([espeak_ng, words])
    end
  end

  # PowerShell reads the words from its environment, so nothing in them
  # can change the script it runs.
  private def tell_windows(words)
    return unless executable?(@powershell)

    { "banner" => WINDOWS_BANNER, "voice" => WINDOWS_VOICE }.each do |part, script|
      run([@powershell, "-NoProfile", "-NonInteractive", "-Command", script],
        env: { "DESKTOP_INPUT_WORDS" => words, "DESKTOP_INPUT_TELL" => part })
    end
  end

  private def system_kind
    if @host_os.include?("darwin") then :macos
    elsif @host_os.include?("linux") then :linux
    elsif DesktopInputLock.windows?(@host_os) then :windows
    end
  end

  private def desktop?
    [@env["DISPLAY"], @env["WAYLAND_DISPLAY"]].any? { |display| display && !display.empty? }
  end

  private def executable?(command)
    !command.nil? && File.file?(command) && File.executable?(command)
  end

  # Runs +command+, with +env+ added to its environment, and waits for
  # it, as system does, for at most @tell_limit seconds, then stops it. A
  # command that cannot start is skipped, as system(exception: false)
  # skips it.
  private def run(command, env: {})
    pid = spawn(env, *command, out: File::NULL, err: File::NULL)
    deadline = now + @tell_limit
    until Process.wait(pid, Process::WNOHANG)
      next sleep(0.05) if now < deadline

      Process.kill(:KILL, pid)
      Process.wait(pid)
      break
    end
  rescue SystemCallError
    nil
  end

  private def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # The process's own, on the files paths gives for the environment it
  # started with, which every span in it shares.
  DEFAULT = begin
    lock, marker = paths(ENV, RbConfig::CONFIG["host_os"])
    new(lock:, marker:)
  end

  class << self
    # DEFAULT's #hold.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   DesktopInputLock.hold(speak: false) { move_pointer }
    #--
    # SPDX-SnippetEnd
    #++
    def hold(speak: true, &)
      DEFAULT.hold(speak:, &)
    end

    # DEFAULT's #acquire.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   DESKTOP_INPUT = DesktopInputLock.acquire(speak: false) # held until the process ends
    #--
    # SPDX-SnippetEnd
    #++
    def acquire(speak: true)
      DEFAULT.acquire(speak:)
    end
  end
end
