# frozen_string_literal: true

module RedmineRefIssues
  VERSION = '1.0.3'

  include RedminePluginKit::PluginBase

  class << self
    def cast_table_field(db_table, db_field)
      if Redmine::Database.postgresql?
        "CAST(#{db_table}.#{db_field} AS TEXT)"
      else
        "#{db_table}.#{db_field}"
      end
    end

    # A date which ends up in the SQL: only a real date is accepted,
    # anything else would let a macro inject SQL.
    def sql_date(value)
      Date.iso8601(value.to_s).iso8601
    rescue Date::Error
      raise "- invalid date <#{value}>"
    end

    # Messages of expected macro errors (wrong options, unknown filters, ...)
    # start with '-' and are shown to the reader.
    def expected_error?(error)
      error.to_s.start_with? '-'
    end

    # Details of any other error (file paths, gem versions, SQL) only go to
    # the log, the page shows a generic message.
    def unexpected_error(error)
      Rails.logger.error "ref_issues macro failed: #{error.class}: #{error.message}\n#{Array(error.backtrace).join "\n"}"
      'unexpected error, details are in the log file'
    end

    def additionals_help_items
      [{ title: 'Redmine ref_issues macro',
         url: 'https://github.com/alphanodes/redmine_ref_issues#usage',
         id: :ref_issues }]
    end

    private

    def setup
      # Macros
      loader.load_macros!
    end
  end
end
