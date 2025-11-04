# frozen_string_literal: true

module RedmineRefIssues
  module WikiMacros
    module RefIssuesMacro
      Redmine::WikiFormatting::Macros.register do
        desc 'Displays a list of referer issues.'
        macro :ref_issues do |obj, args|
          parser = nil

          begin
            parser = RedmineRefIssues::Parser.new obj, args, @project
          rescue StandardError => e
            attributes = IssueQuery.available_columns
            msg = <<-TEXT
      - <br>parameter error: #{e}<br>
      #{e.backtrace[0]}<br><br>
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
              msg = "- failed add_filter: #{filter_str}<br><br>[FILTER]<br>"

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
                  issue.custom_field_values.each do |cf|
                    word = cf.value if "cf_#{cf.custom_field.id}" == atr || cf.custom_field.name == atr
                  end
                end

                if word.nil?
                  msg = +'attributes:'

                  issue.attributes.each do |a|
                    msg += "#{a}, "
                  end

                  raise msg.html_safe
                end

                disp << ' ' if disp.present?

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
                  issue.custom_field_values.each do |cf|
                    sum += cf.value.to_f if "cf_#{cf.custom_field.id}" == atr || cf.custom_field.name == atr
                  end
                end
              end

              disp = sum.to_s
            elsif params[:format] == 'pdf'
              disp = render 'issues/list.html', issues: @issues, query: @query
            else
              disp = +context_menu.to_s
              disp << render('issues/list', issues: @issues, query: @query)
            end

            disp.html_safe
          rescue StandardError, ActiveRecord::RecordInvalid => e
            msg = +e.to_s
            if msg[0] != '-'
              e.backtrace.each do |backtrace|
                msg << "<br>#{backtrace}"
              end
            end
            raise msg.html_safe
          end
        end
      end
    end
  end
end
