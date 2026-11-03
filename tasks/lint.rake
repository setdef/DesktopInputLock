# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "rubocop/rake_task"
require "rubycritic/rake_task"
require "inch/rake"

RuboCop::RakeTask.new

# Run rubycritic in a shell to prevent it from exiting the rake process
task :rubycritic do
  sh "bundle exec rubycritic --no-browser exe lib sig"
end

Inch::Rake::Suggest.new("doc:suggest", "lib/**/*.rb", "sig/**/*.rbs") do |suggest|
  suggest.args << ""
end

namespace :reuse do
  desc "Run the REUSE Tool to confirm REUSE compliance"
  task :lint do
    sh "reuse lint"
  end

  desc "Add SPDX headers to files missing them (per AGENTS.md standards)"
  task :fix do
    copyright = "Kerrick Long <me@kerricklong.com>"

    # Code files: AGPL-3.0-or-later
    code_extensions = %w[rb rbs rake gemspec toml yml yaml json lock].freeze
    code_license = "AGPL-3.0-or-later"

    # Documentation files: CC-BY-SA-4.0
    doc_extensions = %w[md txt].freeze
    doc_license = "CC-BY-SA-4.0"

    # Find files missing headers (listed after "no copyright and licensing" message)
    puts "Checking for files missing REUSE headers..."
    output = `reuse lint 2>&1`
    in_missing_section = false
    missing_files = output.lines.filter_map do |line|
      in_missing_section = true if line.include?("no copyright and licensing")
      in_missing_section = false if line.start_with?("# ") && !line.include?("copyright")
      next unless in_missing_section

      line.match(/^\* (.+)/)&.[](1)
    end

    if missing_files.empty?
      puts "All files have REUSE headers!"
    else
      missing_files.each do |file|
        ext = File.extname(file).delete(".")
        license = if code_extensions.include?(ext)
          code_license
        elsif doc_extensions.include?(ext)
          doc_license
        else
          puts "  Skipping #{file} (unknown extension: .#{ext})"
          next
        end

        puts "  Annotating #{file} with #{license}"
        sh "reuse annotate --license #{license} --copyright '#{copyright}' --skip-existing '#{file}'", verbose: false
      end
    end
  end

  desc "Normalize Ruby files: frozen_string_literal at top, SPDX in #--/#++ block"
  task :normalize_ruby do
    ruby_extensions = %w[rb rake gemspec].freeze
    ruby_files = Dir.glob("**/*.{#{ruby_extensions.join(',')}}")
      .reject { |f| f.start_with?("vendor/", "tmp/", ".") }

    fixed_count = 0
    ruby_files.each do |file|
      content = File.read(file)
      original = content.dup

      # Skip if no SPDX header
      next unless content.match?(/# SPDX-/)

      # Extract components
      frozen = content.match?(/^# frozen_string_literal: true/)
      spdx_match = content.match(/(# SPDX-FileCopyrightText:[^\n]+\n(?:#[^\n]*\n)*# SPDX-License-Identifier:[^\n]+\n)/m)
      next unless spdx_match

      spdx_block = spdx_match[1]

      # Remove existing frozen_string_literal and SPDX block (and any #--/#+++)
      cleaned = content
        .sub(/^# frozen_string_literal: true\n+/, "")
        .sub(/^#--\s*\n/, "")
        .sub(spdx_block, "")
        .sub(/^#\+\+\s*\n/, "")
        .sub(/\A\n+/, "") # Remove leading blank lines

      # Rebuild file in correct order: frozen, blank, #--, SPDX, #++, rest
      new_content = ""
      new_content += "# frozen_string_literal: true\n\n" if frozen
      new_content += "#--\n#{spdx_block}#++\n\n"
      new_content += cleaned.sub(/\A\n+/, "") # Ensure no double blank lines

      if new_content != original
        File.write(file, new_content)
        puts "  Normalized #{file}"
        fixed_count += 1
      end
    end

    puts fixed_count.zero? ? "All Ruby files properly normalized!" : "Fixed #{fixed_count} files."
  end
end
task(:reuse) { Rake::Task["reuse:lint"].invoke }

namespace :lint do
  # rdoc:coverage exits the process when anything is undocumented, so it
  # runs in a child process that can fail the gate without ending rake.
  task :safe_rdoc_coverage do
    sh "bundle exec rake rdoc:coverage"
  end

  task docs: %w[safe_rdoc_coverage rubycritic reuse:lint]
  task code: %w[rubocop rubycritic]
  task licenses: %w[reuse:lint]
  task all: %w[docs code licenses rbs workflows shell]

  # actionlint runs shellcheck over each step's script only when it finds
  # it, and passes without a word when it does not, so a missing shellcheck
  # fails here instead.
  desc "Check the GitHub Actions workflows with actionlint, and their scripts with shellcheck"
  task :workflows do
    shellcheck = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, "shellcheck") }
      .find { |path| File.executable?(path) }
    abort "❌ lint:workflows needs shellcheck on PATH; mise install puts it there" unless shellcheck

    sh "actionlint", "-shellcheck=#{shellcheck}"
  end

  desc "Check the shell scripts git tracks with shellcheck"
  task :shell do
    scripts = `git ls-files -z bin`.split("\0").select { |path| File.read(path, 64).start_with?("#!/usr/bin/env bash") }
    sh "shellcheck", *scripts unless scripts.empty?
  end

  namespace :fix do
    desc "Auto-fix RuboCop offenses (most aggressive)"
    task :rubocop do
      sh "bundle exec rubocop --autocorrect-all"
    end

    desc "Add SPDX headers and normalize Ruby file structure"
    task reuse: %w[reuse:fix reuse:normalize_ruby]

    desc "Run all auto-fix tasks"
    task all: %w[lint:fix:rubocop lint:fix:reuse]
  end
end

desc "Run all lint auto-fix tasks"
task("lint:fix") { Rake::Task["lint:fix:all"].invoke }

# Aliases for convenience
task "rubocop:autocorrect_all" => "lint:fix:rubocop"

desc "Run all lint tasks"
task(:lint) { Rake::Task["lint:all"].invoke }
