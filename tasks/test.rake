# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require "minitest/test_task"

# Clear the default test task created by Minitest::TestTask if it exists
Rake::Task["test"].clear if Rake::Task.task_defined?("test")

# Every test runs with Ruby's warnings on, so a warning shows in the
# gate's output instead of in a user's terminal.
Minitest::TestTask.create(:test) do |t|
  t.test_globs = %w[test/**/*_test.rb]
  t.warning = true
end
