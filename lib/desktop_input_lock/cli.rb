# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "../desktop_input_lock"

class DesktopInputLock
  # Runs the +desktop_input_lock+ command line.
  #
  # Shell scripts drive simulators, apps, and test runners that take the
  # keyboard and mouse too, but macOS has no flock(1), and a lock a
  # script takes its own way means nothing to the tests of other
  # projects. The script needs the same lock they take, held while its
  # command runs, with the command's exit status and signals passed
  # through as if the lock were not there.
  #
  # This class runs <tt>desktop_input_lock hold -- COMMAND</tt>: it holds
  # DesktopInputLock, silently unless <tt>--speak</tt> is given, runs
  # COMMAND as a child, passes INT, TERM, and HUP on to it, and returns
  # its exit status. It reads its help from the comment header of the
  # executable, between a <tt>####</tt> line and a <tt>###</tt> line, so
  # the help in the source is the help it prints. It writes to the
  # streams you give it and returns an exit status instead of exiting, so
  # a test can run it with StringIO.
  #
  # Use it from the executable, or from a test with a DesktopInputLock of
  # the test's own.
  #
  # === Examples
  #
  #--
  # SPDX-SnippetBegin
  # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
  # SPDX-License-Identifier: MIT-0
  #++
  #   # exe/desktop_input_lock:
  #   exit DesktopInputLock::CLI.new(help_path: __FILE__).call(ARGV)
  #
  #   # A test, with a lock of its own:
  #   input = DesktopInputLock.new(lock: "/tmp/mine.lock", marker: "/tmp/mine.away")
  #   cli = DesktopInputLock::CLI.new(help_path: "exe/desktop_input_lock", input:)
  #   cli.call(["hold", "--", "true"])  # => 0
  #   cli.call(["hold", "--", "false"]) # => 1
  #--
  # SPDX-SnippetEnd
  #++
  class CLI
    # The signals passed on to COMMAND, where the system has them.
    FORWARDED = %w[INT TERM HUP].select { |name| Signal.list.key?(name) }.freeze

    # Creates a command line.
    #
    # [help_path] The executable whose comment header is the help text.
    # [out] Where help and the version go (default: <tt>$stdout</tt>).
    # [err] Where errors go (default: <tt>$stderr</tt>).
    # [input] The lock held (default: DesktopInputLock::DEFAULT).
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   DesktopInputLock::CLI.new(help_path: "exe/desktop_input_lock", out: StringIO.new)
    #--
    # SPDX-SnippetEnd
    #++
    def initialize(help_path:, out: $stdout, err: $stderr, input: DEFAULT)
      @help_path = help_path
      @out = out
      @err = err
      @input = input
    end

    # Runs +argv+ and returns the exit status: COMMAND's own for
    # +hold+, 0 for help and the version, 1 for bad arguments. Leaves
    # +argv+ unchanged.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   DesktopInputLock::CLI.new(help_path: "exe/desktop_input_lock").call(["--version"]) # => 0
    #--
    # SPDX-SnippetEnd
    #++
    def call(argv)
      name, *arguments = argv
      case name
      when nil then fail_with(help)
      when "--help", "-h" then succeed_with(help)
      when "--version", "-V" then succeed_with("desktop_input_lock #{VERSION}")
      when "hold" then hold(arguments)
      when /\A-/ then fail_with("desktop_input_lock: unknown option '#{name}'. See 'desktop_input_lock --help'.")
      else fail_with("desktop_input_lock: '#{name}' is not a command. See 'desktop_input_lock --help'.")
      end
    end

    # The help text: the executable's header between its <tt>####</tt>
    # and <tt>###</tt> lines, with each line's leading <tt>#</tt> and one
    # space removed. Raises ArgumentError when the file has no such
    # header.
    #
    # === Example
    #
    #--
    # SPDX-SnippetBegin
    # SPDX-SnippetCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
    # SPDX-License-Identifier: MIT-0
    #++
    #   DesktopInputLock::CLI.new(help_path: "exe/desktop_input_lock").help.lines[1]
    #   # => "desktop_input_lock - Run a command holding the desktop input lock\n"
    #--
    # SPDX-SnippetEnd
    #++
    def help
      lines = File.readlines(@help_path)
      start = lines.index { |line| line.chomp == "####" } or raise missing_header
      header = lines.drop(start + 1)
      length = header.index { |line| line.chomp == "###" } or raise missing_header

      header.first(length).map { |line| line.sub(/\A# ?/, "") }.join
    end

    private def missing_header
      ArgumentError.new("#{@help_path} has no help header between #### and ### lines")
    end

    private def hold(arguments)
      speak = false
      command = arguments.dup
      while (option = command.first)&.start_with?("-")
        command.shift
        break if option == "--"
        return fail_with("desktop_input_lock hold: unknown option '#{option}'. See 'desktop_input_lock --help'.") \
          unless option == "--speak"

        speak = true
      end
      return fail_with("desktop_input_lock hold: no COMMAND to run. See 'desktop_input_lock --help'.") if command.empty?

      @input.hold(speak:) { run_child(command) }
    end

    # Runs +command+ as a child, passing FORWARDED signals on to it, and
    # returns its exit status, or 128 plus the signal that ended it. A
    # signal that arrives before the child starts is passed on as soon as
    # it does.
    private def run_child(command)
      child = nil #: Integer?
      caught = [] #: Array[String]
      previous = FORWARDED.to_h do |signal|
        [signal, Signal.trap(signal) { (pid = child) ? pass_on(signal, pid) : caught << signal }]
      end
      begin
        pid = spawn(*command)
        child = pid
        caught.each { |signal| pass_on(signal, pid) }
        _, status = Process.wait2(pid)
        status.exitstatus || (128 + status.termsig.to_i)
      ensure
        previous.each { |signal, handler| Signal.trap(signal, handler) }
      end
    rescue Errno::ENOENT
      fail_with("desktop_input_lock: #{command.first}: command not found", status: 127)
    rescue SystemCallError => e
      fail_with("desktop_input_lock: #{command.first}: #{e.message}", status: 126)
    end

    private def pass_on(signal, pid)
      Process.kill(signal, pid)
    rescue Errno::ESRCH
      nil
    end

    private def succeed_with(text)
      @out.puts text
      0
    end

    private def fail_with(text, status: 1)
      @err.puts text
      status
    end
  end
end
