# frozen_string_literal: true

module RedmineRefIssues
  module WikiMacros
    module RefIssuesMacro
      Redmine::WikiFormatting::Macros.register do
        desc <<-DESCRIPTION
    Display a list of issues which refer to the current wiki page or issue.

    Without -s, -d, -w, -f, -i or -q, issues are listed whose subject or
    description contain the wiki page title (or one of its aliases), the issue
    subject or, in an issue comment, the issue number (#ID). Only issues visible
    to the current user are listed, from all projects unless -p or a saved query
    restricts them. All matching issues are shown, sorted by the sort order of
    the saved query or by ID descending. Wrong options raise a macro error with
    usage information.

    Syntax:

      {{ref_issues([OPTION, ...] [, COLUMN, ...])}}

      Options:
      -s[=WORD|WORD...] : subject contains one of the words
      -d[=WORD|WORD...] : description contains one of the words
      -w[=WORD|WORD...] : subject or description contains one of the words
      -i=QUERY_ID : use the saved issue query with this ID
      -q=NAME : use the saved issue query with this name
      -p[=IDENTIFIER] : restrict to the current project or the given project
      -f:FILTER OPERATOR [VALUE|VALUE...] : additional filter
      -t[=ATTRIBUTE] : show only the formatted text of an attribute (default: subject)
      -l[=ATTRIBUTE] : show only an attribute as link to the issue (default: subject)
      -c : show only the number of issues
      -sum=ATTRIBUTE : show only the sum of an attribute
      -0 : show nothing if no issue matches
      Without =WORD, -s, -d and -w use the default words described above.

      FILTER: issue query filter (status_id, tracker_id, cf_N, ...) or tracker,
      category, status, version, project (by name), assigned_to, author (by login).
      -f:treated USER DATE|DATE lists issues created or commented by USER in
      this period. OPERATOR as in issue queries (=, !, o, c, ~, >=, <=, ...).
      VALUE can be [current_user], [current_user_id], [current_project_id],
      [N days_ago] or, in issues, [ATTRIBUTE] for a value of the issue.
      ATTRIBUTE: issue attribute (subject, due_date, estimated_hours, ...) or
      custom field (cf_N or its name).
      COLUMN: issue query column (subject, status, assigned_to, cf_N, ...).

    Examples:

      {{ref_issues}}
      ...Issues whose subject or description contain the title of this wiki page

      {{ref_issues(-w, -f:status_id o)}}
      ...Only the open ones of these issues

      {{ref_issues(-p, -f:tracker = Bug, -f:status_id o, subject, status, assigned_to)}}
      ...Open bugs of the current project with the given columns

      {{ref_issues(-i=12, -sum=estimated_hours)}}
      ...Sum of the estimated time of the issues of saved query 12

      {{ref_issues(-s=Release|Deploy, -l, -0)}}
      ...Links to issues with 'Release' or 'Deploy' in the subject, nothing if none match
        DESCRIPTION
        macro :ref_issues do |obj, args|
          parser = nil

          begin
            parser = RedmineRefIssues::Parser.new obj, args, @project
          rescue StandardError => e
            raise RedmineRefIssues.unexpected_error(e) unless RedmineRefIssues.expected_error? e

            attributes = IssueQuery.available_columns
            msg = <<-TEXT
      - <br>parameter error: #{ERB::Util.html_escape e.message}<br><br>
      usage: {{ref_issues([option].., [column]..)}}<br>
      <br>[options]<br>
      -i=CustomQueryID : specify custom query by id<br>
      -q=CustomQueryName : specify custom query by name<br>
      -p[=identifier] : restrict project<br>
      -f:FILTER[=WORD[|WORD...]] : additional filter<br>
      -t[=column] : display text<br>
      -l[=column] : display linked text<br>
      -sum[=column] : sum column<br>
      -c : count issues<br>
      -0 : no display if no issues
      <br>[columns]<br> {
            TEXT

            while attributes
              attributes[0...5].each do |a|
                msg += "#{a.name}, "
              end

              attributes = attributes[5..]
              msg += '<br>' if attributes
            end

            msg += 'cf_* }<br/>'
            raise msg.html_safe
          end

          begin
            unless parser.search_conditions? # If there are no search condition
              # Get the keyword to search
              parser.search_words_w << parser.default_words(obj)
            end

            @query = parser.query @project

            extend SortHelper
            extend QueriesHelper
            extend IssuesHelper

            if respond_to? :session
              # Web context: use session-based sorting
              sort_clear
              sort_init(@query.sort_criteria.empty? ? [%w[id desc]] : @query.sort_criteria)
              sort_update @query.sortable_columns
            else
              # Mailer context: set sort criteria directly from query without session
              @sort_criteria = @query.sort_criteria.empty? ? Redmine::SortCriteria.new([%w[id desc]]) : @query.sort_criteria
              @sortable_columns = @query.sortable_columns
            end
            # @issue_count_by_group = @query.issue_count_by_group

            parser.search_words_s.each do |words|
              @query.add_filter 'subject', '~', words
            end

            parser.search_words_d.each do |words|
              @query.add_filter 'description', '~', words
            end

            parser.search_words_w.each do |words|
              @query.add_filter 'subjectdescription', '~', words
            end

            models = { 'tracker' => Tracker,
                       'category' => IssueCategory,
                       'status' => IssueStatus,
                       'assigned_to' => User,
                       'author' => User,
                       'version' => Version,
                       'project' => Project }
            ids = { 'tracker' => 'tracker_id',
                    'category' => 'category_id',
                    'status' => 'status_id',
                    'assigned_to' => 'assigned_to_id',
                    'author' => 'author_id',
                    'version' => 'fixed_version_id',
                    'project' => 'project_id' }
            attributes = { 'tracker' => 'name',
                           'category' => 'name',
                           'status' => 'name',
                           'assigned_to' => 'login',
                           'author' => 'login',
                           'version' => 'name',
                           'project' => 'name' }

            parser.additional_filter.each do |filter_set|
              filter = filter_set[:filter]
              operator = filter_set[:operator]
              values = filter_set[:values]

              if models.key? filter
                unless values.nil?
                  tgt_objs = []
                  values.each do |value|
                    tgt_obj = models[filter].find_by attributes[filter] => value
                    raise "- can not resolve '#{value}' in #{models[filter]}.#{attributes[filter]} " if tgt_obj.nil?

                    tgt_objs << tgt_obj.id.to_s
                  end
                  values = tgt_objs
                end
                filter = ids[filter]
              end

              res = @query.add_filter filter, operator, values

              next unless res.nil?

              filter_str = filter_set[:filter] + filter_set[:operator] + filter_set[:values].join('|')
              cr_count = 0
              msg = "- failed add_filter: #{ERB::Util.html_escape filter_str}<br><br>[FILTER]<br>"

              @query.available_filters.each_key do |k|
                if cr_count >= 5
                  msg += '<br>'
                  cr_count = 0
                end

                msg += "#{k}, "
                cr_count += 1
              end

              models.each_key do |k|
                if cr_count >= 5
                  msg += '<br>'
                  cr_count = 0
                end

                msg += "#{k}, "
                cr_count += 1
              end

              msg += '<br><br>[OPERATOR]<br>'
              cr_count = 0

              Query.operators_labels.each do |k, l|
                if cr_count >= 5
                  msg += '<br>'
                  cr_count = 0
                end

                msg += "#{k}:#{l}, "
                cr_count += 1
              end

              msg += '<br>'
              raise msg.html_safe
            end

            @query.column_names = parser.columns unless parser.columns.empty?
            @issues = @query.issues order: sort_clause

            if parser.zero_flag && @issues.empty?
              disp = ''
            elsif parser.only_text || parser.only_link
              disp = +''
              atr = parser.only_text if parser.only_text
              atr = parser.only_link if parser.only_link
              word = nil

              @issues.each do |issue|
                if issue.attributes.key? atr
                  word = issue.attributes[atr].to_s
                else
                  issue.visible_custom_field_values.each do |cf|
                    word = cf.value if "cf_#{cf.custom_field.id}" == atr || cf.custom_field.name == atr
                  end
                end

                if word.nil?
                  raise "- unknown attribute:#{ERB::Util.html_escape atr}<br>attributes: #{issue.attributes.keys.join ', '}".html_safe
                end

                disp.presence&.<<(' ')

                disp << if parser.only_link
                          link_to word.to_s, issue_path(issue)
                        else
                          textilizable word, object: issue, inline_attachments: false
                        end
              end
            elsif parser.count_flag
              disp = @issues.size.to_s
            elsif parser.sum_field
              sum = 0.0
              atr = parser.sum_field if parser.sum_field

              @issues.each do |issue|
                if issue.attributes.key? atr
                  sum += issue.attributes[atr].to_f
                else
                  issue.visible_custom_field_values.each do |cf|
                    sum += cf.value.to_f if "cf_#{cf.custom_field.id}" == atr || cf.custom_field.name == atr
                  end
                end
              end

              disp = sum.to_s
            else
              # Detect mailer context: no controller or no valid request object
              is_mailer_context = !respond_to?(:controller) || controller.nil? || !respond_to?(:request) || request.nil?

              if params[:format] == 'pdf'
                # PDF context: render without context menu
                disp = render 'issues/list.html', issues: @issues, query: @query
              elsif is_mailer_context
                # Mailer context: generate simple HTML table directly without Rails helpers
                # This avoids issues with route helpers (issue_path, etc.) not being available
                disp = +'<div class="autoscroll">'
                disp << '<table class="list issues">'

                # Table header
                disp << '<thead><tr>'
                @query.inline_columns.each do |column|
                  disp << "<th class=\"#{ERB::Util.html_escape column.css_classes}\">#{ERB::Util.html_escape column.caption}</th>"
                end
                disp << '</tr></thead>'

                # Table body
                disp << '<tbody>'
                @issues.each_with_index do |issue, index|
                  row_class = index.even? ? 'even' : 'odd'
                  disp << "<tr class=\"#{row_class} #{ERB::Util.html_escape issue.css_classes}\">"

                  @query.inline_columns.each do |column|
                    # Use Redmine's column value methods - works for all columns including custom fields and plugin columns
                    value = column.value_object issue

                    # Format the value without HTML (similar to CSV export)
                    # This works for all column types: standard, custom fields, plugin columns, etc.
                    formatted_value = if value.is_a? Array
                                        value.map { |v| format_object(v, html: false) }.join(', ')
                                      else
                                        format_object value, html: false
                                      end

                    disp << "<td class=\"#{ERB::Util.html_escape column.css_classes}\">#{ERB::Util.html_escape formatted_value.to_s}</td>"
                  end

                  disp << '</tr>'
                end
                disp << '</tbody></table></div>'
              else
                # Web context: render with context menu
                disp = +context_menu.to_s
                disp << render('issues/list', issues: @issues, query: @query)
              end
            end

            disp.html_safe
          rescue StandardError => e
            # Messages carry macro arguments, so they are escaped here once; messages
            # built as HTML on purpose (with <br>) are already html_safe and kept.
            raise ERB::Util.html_escape(e.message) if RedmineRefIssues.expected_error? e

            raise RedmineRefIssues.unexpected_error(e)
          end
        end
      end
    end
  end
end
