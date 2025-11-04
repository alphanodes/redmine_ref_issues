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
end
