# frozen_string_literal: true

require File.expand_path '../../test_helper', __FILE__

class WikiControllerTest < RedmineRefIssues::ControllerTest
  fixtures :users, :email_addresses, :roles,
           :enumerations,
           :projects, :projects_trackers, :enabled_modules,
           :members, :member_roles,
           :trackers,
           :groups_users,
           :issue_statuses, :issues, :issue_categories,
           :custom_fields, :custom_values, :custom_fields_trackers, :custom_fields_projects,
           :wikis, :wiki_pages, :wiki_contents,
           :attachments, :queries

  def setup
    @project = projects :projects_001
    @wiki = @project.wiki
    @page_name = 'ref_issues_macro_test'
    @request.session[:user_id] = 2
  end

  def test_ref_issues_with_query_by_id
    prepare_macro_page '{{ref_issues(-i=1)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_ref_issues_macro
  end

  def test_ref_issues_escapes_unresolved_filter_value_in_error
    prepare_macro_page '{{ref_issues(-f:project = <script>alert(1)</script>)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_not_includes response.body, '<script>alert(1)</script>'
    assert_includes response.body, '&lt;script&gt;alert(1)&lt;/script&gt;'
  end

  def test_ref_issues_escapes_unknown_option_in_error
    prepare_macro_page '{{ref_issues(-x<img src=x onerror=alert(1)>)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_select 'div.flash.error', text: /unknown option/
    assert_select 'div.flash.error img', count: 0
  end

  def test_ref_issues_escapes_unknown_user_in_error
    prepare_macro_page '{{ref_issues(-f:treated <b>x</b> 2017-05-01|2017-06-01)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_select 'div.flash.error', text: /can not find user/
    assert_select 'div.flash.error b', count: 0
  end

  def test_ref_issues_with_query_by_name
    prepare_macro_page '{{ref_issues(-q=Open issues by priority and tracker)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_ref_issues_macro
  end

  def test_ref_issues_with_project_query_by_name
    prepare_macro_page '{{ref_issues(-q=Multiple custom fields query)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_select 'div.flash.error', count: 0
    assert_ref_issues_macro
  end

  def test_ref_issues_with_query_by_name_shared_by_role
    IssueQuery.create! name: 'Shared with managers',
                       project: @project,
                       user: users(:users_001),
                       visibility: Query::VISIBILITY_ROLES,
                       roles: [roles(:roles_001)],
                       filters: { 'status_id' => { operator: 'o', values: [''] } }
    prepare_macro_page '{{ref_issues(-q=Shared with managers)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_select 'div.flash.error', count: 0
    assert_ref_issues_macro
  end

  def test_ref_issues_with_unknown_restrict_project
    @request.session[:user_id] = 3
    prepare_macro_page '{{ref_issues(-p=unknown-project)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_select 'div.flash.error', text: /can not find project:unknown-project/
    assert_ref_issues_macro count: 0
  end

  def test_ref_issues_with_invisible_restrict_project
    @request.session[:user_id] = 3
    prepare_macro_page '{{ref_issues(-p=onlinestore)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_select 'div.flash.error', text: /can not find project:onlinestore/
    assert_ref_issues_macro count: 0
  end

  def test_ref_issues_parameter_error_shows_usage_without_backtrace
    prepare_macro_page '{{ref_issues(-f:subject ~ recipe, unknown_column)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_select 'div.flash.error', text: /unknown column:unknown_column.*usage:/m
    assert_select 'div.flash.error', text: /\.rb:/, count: 0
  end

  def test_ref_issues_unknown_attribute_lists_names_without_values
    prepare_macro_page '{{ref_issues(-f:issue_id = 1, -t=unknown_attribute)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_select 'div.flash.error', text: /unknown attribute:unknown_attribute.*subject/m
    assert_select 'div.flash.error', text: /#{issues(:issues_001).subject}/, count: 0
    # the message is built as HTML on purpose, its line break must not be escaped
    assert_select 'div.flash.error br'
  end

  def test_ref_issues_unexpected_error_shows_generic_message_without_backtrace
    cf = IssueCustomField.create! name: 'Multiple values',
                                  is_for_all: true,
                                  tracker_ids: [1, 2, 3],
                                  field_format: 'list',
                                  possible_values: %w[A B],
                                  multiple: true
    issue = issues :issues_001
    issue.custom_field_values = { cf.id.to_s => %w[A B] }

    assert_save issue

    # The sum of a multiple value custom field fails with an unexpected NoMethodError
    prepare_macro_page "{{ref_issues(-f:issue_id = 1, -sum=cf_#{cf.id})}}"

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_select 'div.flash.error', text: /unexpected error, details are in the log file/
    assert_select 'div.flash.error', text: /\.rb:|undefined method/, count: 0
  end

  def test_ref_issues_with_subject_search
    prepare_macro_page '{{ref_issues(-f:subject ~ recipe)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_ref_issues_macro
  end

  def test_ref_issues_with_negation_filter_and_columns
    prepare_macro_page '{{ref_issues(-f:author_id = 2, -f:status ! New, id)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_ref_issues_macro
  end

  def test_ref_issues_with_columns
    prepare_macro_page '{{ref_issues(-f:author_id = 2' \
                       ', project' \
                       ', tracker' \
                       ', parent' \
                       ', status' \
                       ', priority' \
                       ', subject' \
                       ', author' \
                       ', assigned_to' \
                       ', updated_on' \
                       ', category' \
                       ', fixed_version' \
                       ', start_date' \
                       ', due_date' \
                       ', estimated_hours' \
                       ', done_ratio' \
                       ', created_on' \
                       ', closed_on' \
                       ', relations' \
                       ', cf_1)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_ref_issues_macro
  end

  def test_ref_issues_with_project_filter
    prepare_macro_page '{{ref_issues(-f:project = eCookbook)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_ref_issues_macro
  end

  def test_ref_issues_with_tracker_filter
    prepare_macro_page '{{ref_issues(-f:tracker == Bug | Feature request)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_ref_issues_macro
  end

  def test_ref_issues_with_min_and_max_id
    prepare_macro_page '{{ref_issues(-f:issue_id >< 1|5)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_ref_issues_macro
  end

  def test_ref_issues_with_id_or
    prepare_macro_page '{{ref_issues(-f:issue_id == 1|3)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_ref_issues_macro
  end

  def test_ref_issues_with_category_filter
    prepare_macro_page '{{ref_issues(-f:category == Printing|Recipes, subject, category)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_ref_issues_macro
  end

  def test_ref_issues_with_treated
    prepare_macro_page '{{ref_issues(-f:treated jsmith 2017-05-01|[1days_ago])}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_ref_issues_macro
  end

  def test_ref_issues_with_treated_rejects_sql_in_date
    prepare_macro_page "{{ref_issues(-f:treated jsmith 2017-05-01'OR'1'='1|2017-06-01)}}"

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_select 'div.flash.error', text: /invalid date/
    assert_ref_issues_macro count: 0
  end

  def test_ref_issues_with_zero_option
    prepare_macro_page '{{ref_issues(-0,-f:subject = Cannot print recipes2)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_ref_issues_macro count: 0
  end

  def test_ref_issues_with_linked_id
    prepare_macro_page '{{ref_issues(-f:subject = Add ingredients categories, -l=id)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_select 'div.wiki.wiki-page a[href="/issues/2"]'
  end

  def test_ref_issues_with_description
    prepare_macro_page '{{ref_issues(-f:subject = Add ingredients categories, -t=description)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_select 'div.wiki.wiki-page',
                  text: /Ingredients of the recipe should be classified by categories/
  end

  def test_ref_issues_with_count
    prepare_macro_page '{{ref_issues(-f:subject ~ recipe, -c)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_select 'div.wiki.wiki-page',
                  text: /2/
  end

  def test_ref_issues_with_enum_filter
    cf = IssueCustomField.create! name: 'Key',
                                  is_for_all: true,
                                  is_filter: true,
                                  tracker_ids: [1, 2, 3],
                                  field_format: 'enumeration'

    cf.enumerations << (valueb = CustomFieldEnumeration.new name: 'Value B', position: 1)
    CustomValue.create! custom_field: cf, customized: Issue.find(1), value: valueb.id

    prepare_macro_page "{{ref_issues(-f:cf_#{cf.id} == Value B, id, cf_#{cf.id})}}"

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_ref_issues_macro
  end

  def test_ref_issues_with_sum
    prepare_macro_page '{{ref_issues(-f:subject ~ recipe, -sum:estimated_hours)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_select 'div.wiki.wiki-page',
                  text: /201/
  end

  def test_multiple_ref_issues_macros
    prepare_macro_page '{{ref_issues(-i=1)}} and {{ref_issues(-f:subject ~ recipe)}}'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_ref_issues_macro count: 2
  end

  def test_ref_issues_macro_without_issue_permission
    @request.session[:user_id] = 8

    Role.find_each { |r| r.remove_permission! :view_issues }
    User.current = User.find 8

    assert User.current.allowed_to?(:view_wiki_pages, @project)
    assert_not User.current.allowed_to? :view_issues, @project

    prepare_macro_page '-0,-f:subject = Cannot print recipes'

    get :show,
        params: { project_id: 1, id: @page_name }

    assert_response :success
    assert_ref_issues_macro count: 0
  end

  def test_ref_issues_sort_order_ascending
    prepare_macro_page '{{ref_issues(-f:project_id = 1, id)}}'

    get :show,
        params: { project_id: 1, id: @page_name, sort: 'id:asc' }

    assert_response :success

    # Extract issue IDs from response in order they appear
    issue_links = css_select 'table.list.issues tbody tr td.id a'
    issue_ids = issue_links.map { |link| link.text.to_i }

    # Verify we have issues
    assert issue_ids.any?, 'Should have found issue IDs in response'

    # Verify they are in ascending order
    assert_equal issue_ids.sort, issue_ids, 'Issues should be sorted by ID ascending'
  end

  def test_ref_issues_sort_order_descending
    prepare_macro_page '{{ref_issues(-f:project_id = 1, id)}}'

    get :show,
        params: { project_id: 1, id: @page_name, sort: 'id:desc' }

    assert_response :success

    # Extract issue IDs from response in order they appear
    issue_links = css_select 'table.list.issues tbody tr td.id a'
    issue_ids = issue_links.map { |link| link.text.to_i }

    # Verify we have issues
    assert issue_ids.any?, 'Should have found issue IDs in response'

    # Verify they are in descending order
    expected_order = issue_ids.sort
    expected_order.reverse!

    assert_equal expected_order, issue_ids, 'Issues should be sorted by ID descending'
  end
end
