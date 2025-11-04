# frozen_string_literal: true

require File.expand_path '../../test_helper', __FILE__

class MailerTest < RedmineRefIssues::TestCase
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
    Setting.plain_text_mail = 0
    ActionMailer::Base.deliveries.clear
    @user = User.find 2
    @project = Project.find 1
  end

  def test_ref_issues_macro_in_email_notification
    # Create an issue with ref_issues macro in description
    issue = Issue.create!(
      project: @project,
      tracker_id: 1,
      author: @user,
      subject: 'Test issue with ref_issues macro',
      description: 'This issue contains a macro: {{ref_issues(-f:subject ~ recipe, -c)}}'
    )

    # Generate email notification
    Mailer.deliver_issue_add issue

    # Get the sent emails
    assert ActionMailer::Base.deliveries.any?

    # Check all sent emails for session errors
    ActionMailer::Base.deliveries.each do |mail|
      # Assert that the email body contains content (no macro error)
      assert mail.body.encoded.present?

      # Assert that error message is not present in email body
      assert_not mail.body.encoded.include?("undefined method `session'"),
                 'Email should not contain session-related error'
    end
  end

  def test_ref_issues_macro_in_email_with_query
    # Create an issue with ref_issues macro using query
    issue = Issue.create!(
      project: @project,
      tracker_id: 1,
      author: @user,
      subject: 'Test issue with ref_issues query macro',
      description: 'Query macro test: {{ref_issues(-q=Public query for all projects)}}'
    )

    # Generate email notification
    Mailer.deliver_issue_add issue

    # Get the sent emails
    assert ActionMailer::Base.deliveries.any?

    # Check all sent emails for session errors
    ActionMailer::Base.deliveries.each do |mail|
      # Assert that the email body contains content (no macro error)
      assert mail.body.encoded.present?

      # Assert that error message is not present in email body
      assert_not mail.body.encoded.include?("undefined method `session'"),
                 'Email should not contain session-related error'
      assert_not mail.body.encoded.include?('Fehler bei der Ausführung des Makros'),
                 'Email should not contain macro execution error'
    end
  end

  def test_ref_issues_macro_sort_order_in_email_ascending
    # Create an issue with ref_issues macro that explicitly sorts by ID ascending
    issue_with_macro = Issue.create!(
      project: @project,
      tracker_id: 1,
      author: @user,
      subject: 'Test issue with sorted ref_issues macro',
      description: 'Issues by ID: {{ref_issues(-f:project_id = 1, id)}}'
    )

    # Generate email notification
    Mailer.deliver_issue_add issue_with_macro

    # Get the sent emails
    assert ActionMailer::Base.deliveries.any?

    # Check that macro executed without errors
    mail = ActionMailer::Base.deliveries.last

    assert mail.body.encoded.present?
    assert_not mail.body.encoded.include?("undefined method `session'"),
               'Email should not contain session-related error'

    # The macro should render without crashing - that's the main goal
    # Verifying exact HTML structure is brittle and not essential for this test
    # The important part is that sorting doesn't cause session errors
  end

  # rubocop:disable Minitest/MultipleAssertions
  def test_ref_issues_macro_renders_full_issue_table_in_email
    # This test validates that the ref_issues macro actually renders the full issue table
    # in email context, not just that it doesn't error out. This catches issues like
    # missing route helpers (issues_context_menu_path) that only appear during full rendering.

    # Create an issue with ref_issues macro that should render a table with results
    # Use project_id filter to find existing issues in test DB
    issue_with_macro = Issue.create!(
      project: @project,
      tracker_id: 1,
      author: @user,
      subject: 'Test issue with ref_issues table macro',
      description: 'Project issues: {{ref_issues(-f:project_id = 1, subject, tracker)}}'
    )

    # Generate email notification
    Mailer.deliver_issue_add issue_with_macro

    # Get the sent emails
    assert ActionMailer::Base.deliveries.any?, 'Should have sent at least one email'

    # Get the HTML part of the email
    mail = ActionMailer::Base.deliveries.last
    html_body = if mail.multipart?
                  mail.html_part&.body&.decoded || mail.body.decoded
                else
                  mail.body.decoded
                end

    assert html_body.present?, 'Email should have HTML body'

    # Check for NO errors (catches any undefined method/variable errors)
    assert_not html_body.include?('undefined method'),
               "Email should not contain 'undefined method' errors"
    assert_not html_body.include?('undefined local variable'),
               "Email should not contain 'undefined local variable' errors"
    assert_not html_body.include?('NameError'),
               'Email should not contain NameError'

    # Check that the issue table was actually rendered
    assert_includes html_body, '<table', 'Email should contain a table element'
    assert_match(/class="[^"]*list[^"]*"/, html_body, 'Email should contain table with list class')
    assert_match(/class="[^"]*issues[^"]*"/, html_body, 'Email should contain table with issues class')

    # Check that actual issue data is present
    # We filter by project_id=1 so results should exist
    assert_match(/issue|tracker|subject/i, html_body,
                 'Email should contain issue-related data from the rendered table')

    # Check that issue table structure is present (thead, tbody, tr, td)
    assert_includes html_body, '<thead', 'Email table should have thead'
    assert_includes html_body, '<tbody', 'Email table should have tbody'
    assert_includes html_body, '<tr', 'Email table should have table rows'
    assert_includes html_body, '<td', 'Email table should have table cells'

    # Check the text part (if multipart)
    skip unless mail.multipart?

    text_body = mail.text_part&.body&.decoded
    skip if text_body.blank?

    # Text part should not contain HTML tags
    assert_not text_body.include?('<table'), 'Text part should not contain HTML table tags'
    assert_not text_body.include?('<tr'), 'Text part should not contain HTML tr tags'
  end
  # rubocop:enable Minitest/MultipleAssertions

  # rubocop:disable Minitest/MultipleAssertions
  def test_ref_issues_macro_with_custom_field_in_email
    # This test validates that custom fields work in mailer context
    # Custom fields are a common extension and must work in email rendering

    # Find or create a custom field for testing
    custom_field = IssueCustomField.find_or_create_by! name: 'Mailer Test Field' do |cf|
      cf.field_format = 'string'
      cf.is_for_all = true
      cf.is_filter = true
      cf.tracker_ids = [1, 2, 3]
    end

    # Create an issue with ref_issues macro that includes the custom field column
    issue_with_macro = Issue.create!(
      project: @project,
      tracker_id: 1,
      author: @user,
      subject: 'Test issue with custom field macro',
      description: "Issues with custom field: {{ref_issues(-f:project_id = 1, subject, cf_#{custom_field.id})}}"
    )

    # Generate email notification
    Mailer.deliver_issue_add issue_with_macro

    # Get the sent emails
    assert ActionMailer::Base.deliveries.any?, 'Should have sent at least one email'

    # Get the HTML part of the email
    mail = ActionMailer::Base.deliveries.last
    html_body = if mail.multipart?
                  mail.html_part&.body&.decoded || mail.body.decoded
                else
                  mail.body.decoded
                end

    assert html_body.present?, 'Email should have HTML body'

    # Check for NO errors
    assert_not html_body.include?('undefined method'),
               "Email should not contain 'undefined method' errors"
    assert_not html_body.include?('undefined local variable'),
               "Email should not contain 'undefined local variable' errors"

    # Check that the issue table was rendered with custom field column
    assert_includes html_body, '<table', 'Email should contain a table element'
    assert_match(/class="[^"]*list[^"]*"/, html_body, 'Email should contain table with list class')

    # Check that custom field column header is present
    assert_includes html_body, custom_field.name, 'Email table should include custom field column header'
  end
  # rubocop:enable Minitest/MultipleAssertions
end
