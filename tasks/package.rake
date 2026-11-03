# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "fileutils"
require "open3"
require "rbconfig"

# Only a person publishes to RubyGems.org (AGENTS.md, Releasing).
# Bundler's gem tasks define release, which pushes the branch and a tag
# to git and the gem to RubyGems.org in one step an agent could run;
# this removes all three and leaves a refusal. A person publishes with
# gem build and gem push, which ask for their one-time password.
%w[release release:guard_clean release:source_control_push release:rubygem_push].each do |name|
  Rake::Task[name].clear if Rake::Task.task_defined?(name)
end
desc "Refuse: only a person publishes to RubyGems.org, by hand (AGENTS.md)"
task :release do
  abort "❌ rake release never publishes. A person runs gem build and gem push by hand (AGENTS.md, Releasing)."
end

namespace :package do
  # The gem, built from what git tracks, installed with no network into
  # an empty GEM_HOME, and loaded from there with no Bundler and none of
  # the caller's Ruby environment, so nothing in the checkout can stand
  # in for a file the gem forgot to pack.
  desc "Build the gem, install it into an empty GEM_HOME, and load and run it from there"
  task :check do
    root = File.expand_path("..", __dir__)
    work = File.join(root, "tmp", "package")
    FileUtils.rm_rf(work)
    FileUtils.mkdir_p(work)

    spec = Gem::Specification.load(File.join(root, "desktop_input_lock.gemspec"))
    stray = spec.files.grep(%r{\A(?:test|tasks|doc|examples|vendor|\.github)/})
    abort "❌ The gem packs development files: #{stray.join(', ')}" if stray.any?

    Bundler.with_unbundled_env do
      gem = File.join(work, "desktop_input_lock.gem")
      sh "gem", "build", File.join(root, "desktop_input_lock.gemspec"), "--output", gem, chdir: root
      home = File.join(work, "home")
      env = {
        "GEM_HOME" => home,
        "GEM_PATH" => home,
        "RUBYLIB" => nil,
        "RUBYOPT" => nil,
        "BUNDLE_GEMFILE" => nil,
      }
      sh env, "gem", "install", "--local", "--no-document", "--install-dir", home, gem

      script = 'require "desktop_input_lock"; print DesktopInputLock::VERSION'
      out, err, status = Open3.capture3(env, RbConfig.ruby, "-W", "-e", script, chdir: work)
      unless status.success? && out == spec.version.to_s && err.empty?
        abort "❌ The installed gem printed #{out.inspect} and #{err.inspect}, exit #{status.exitstatus}; " \
          "expected #{spec.version.to_s.inspect}"
      end

      # The command, on a lock of the check's own, runs what it is given
      # and passes its status through.
      exe = File.join(home, "bin", "desktop_input_lock")
      run_env = env.merge("DESKTOP_INPUT_LOCK" => File.join(work, "check.lock"), "CI" => "true")
      out, err, status = Open3.capture3(run_env, RbConfig.ruby, exe, "hold", "--", RbConfig.ruby, "-e", "exit 7",
        chdir: work)
      unless status.exitstatus == 7 && out.empty? && err.empty?
        abort "❌ The installed desktop_input_lock hold printed #{out.inspect} and #{err.inspect}, " \
          "exit #{status.exitstatus}; expected exit 7"
      end
    end

    puts "✅ The built gem installs into an empty GEM_HOME, loads, and runs desktop_input_lock from there"
  end
end
