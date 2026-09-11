# frozen_string_literal: true

gem 'redmine_plugin_kit'

# Linters are not required to run the plugin and would conflict with the gem
# versions of other plugins in a shared Redmine installation. Enable them for
# local development or in the CI by creating an .enable_linters file in this
# directory (do not use in production!).
if File.file? File.expand_path './.enable_linters', __dir__
  group :development, :test do
    gem 'brakeman', require: false
    gem 'rubocop', require: false
    gem 'rubocop-minitest', require: false
    gem 'rubocop-performance', require: false
    gem 'rubocop-rails', require: false
  end
end
