# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "bundler/gem_tasks"

require "rdoc/task"
RDoc::Task.new do |rdoc|
  rdoc.rdoc_dir = ENV["RDOC_OUTPUT"] || "tmp/rdoc"
  rdoc.main = "README.rdoc"
  rdoc.rdoc_files.include("lib/**/*.rb", "examples/**/*.rb", "README.rdoc")
  rdoc.rdoc_files.exclude("**/*.rbs")
end

# Import all tasks from the tasks/ directory
Dir.glob("tasks/*.rake").each { |r| import r }

task default: %w[lint:fix test lint steep package:check]
