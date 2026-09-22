# frozen_string_literal: true

require File.expand_path '../../test_helper', __FILE__

# The parser without a current project, as for the macro in the welcome text or other global texts
class RefIssuesParserTest < ActiveSupport::TestCase
  fixtures :users, :email_addresses, :roles,
           :projects, :enabled_modules,
           :members, :member_roles,
           :trackers, :issue_statuses,
           :queries

  def setup
    User.current = users :users_002
  end

  def test_query_by_name_without_project_uses_global_query
    parser = RedmineRefIssues::Parser.new nil, [+'-q=Open issues by priority and tracker'], nil
    query = parser.query nil

    assert_equal 'Open issues by priority and tracker', query.name
    assert_nil query.project_id
  end

  def test_current_project_id_without_project_raises
    error = assert_raises RuntimeError do
      RedmineRefIssues::Parser.new nil, [+'-f:project_id = [current_project_id]'], nil
    end

    assert_equal "- can not use reference '[current_project_id]' outside of a project.", error.message
  end
end
