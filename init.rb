# frozen_string_literal: true

loader = RedminePluginKit::Loader.new plugin_id: 'redmine_ref_issues'

Redmine::Plugin.register :redmine_ref_issues do
  name 'ref_issues macro'
  author 'AlphaNodes GmbH'
  description 'Wiki macro ref_issues to list issues.'
  version RedmineRefIssues::VERSION
  url 'https://github.com/alphanodes/redmine_ref_issues'
  author_url 'https://alphanodes.com/'

  requires_redmine version_or_higher: '6.1'
end

RedminePluginKit::Loader.persisting { loader.load_model_hooks! }
RedminePluginKit::Loader.to_prepare { RedmineRefIssues.setup! } if Rails.version < '6.0'
