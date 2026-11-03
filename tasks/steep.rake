# frozen_string_literal: true

#--
# SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
# SPDX-License-Identifier: AGPL-3.0-or-later
#++

require_relative "lint"

namespace :steep do
  desc "Run Steep type checker"
  task :check do
    sh "bundle exec steep check"
  end

  desc "Forbid 'untyped' in RBS files except approved exceptions"
  task :no_untyped do
    Lint.load(File.expand_path("../rbs_exceptions.rb", __dir__)).enforce!(
      glob: "sig/**/*.rbs",
      pattern: /\buntyped\b/,
      reject_pattern: /^\s*#/,
      violation_name: "'untyped' in RBS files"
    )
  end
end

namespace :rbs do
  desc "Validate the signatures in sig/ against RBS's core library"
  task :validate do
    sh "bundle exec rbs -I sig -r monitor validate"
  end

  desc "Check every signature has an implementation and every public method a signature"
  task :parity do
    ruby File.expand_path("rbs_parity.rb", __dir__), *%w[--sig sig --lib lib --allow rbs_exceptions.rb]
  end
end

desc "Run Steep type checker (with no_untyped check)"
task steep: %w[steep:check steep:no_untyped]

namespace :lint do
  desc "Run RBS linting (no unapproved untyped, valid signatures, signature and implementation parity)"
  task rbs: %w[steep:no_untyped rbs:validate rbs:parity]
end
