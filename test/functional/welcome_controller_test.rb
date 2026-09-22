# frozen_string_literal: true

require File.expand_path '../../test_helper', __FILE__

# Renders the macro in the welcome text, which has no current project
class WelcomeControllerTest < RedmineRefIssues::ControllerTest
  fixtures :users, :email_addresses, :roles,
           :enumerations,
           :projects, :projects_trackers, :enabled_modules,
           :members, :member_roles,
           :trackers,
           :issue_statuses, :issues,
           :queries

  def setup
    @request.session[:user_id] = 2
  end

  def test_ref_issues_with_global_query_by_name_without_project
    with_settings welcome_text: '{{ref_issues(-q=Open issues by priority and tracker)}}' do
      get :index
    end

    assert_response :success
    assert_select 'div.flash.error', count: 0
    assert_ref_issues_macro
  end

  def test_ref_issues_with_current_project_id_without_project
    with_settings welcome_text: '{{ref_issues(-f:project_id = [current_project_id])}}' do
      get :index
    end

    assert_response :success
    assert_select 'div.flash.error', text: /can not use reference '\[current_project_id\]' outside of a project/
    assert_ref_issues_macro count: 0
  end
end
