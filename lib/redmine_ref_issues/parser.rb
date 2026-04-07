# frozen_string_literal: true

module RedmineRefIssues
  class Parser
    attr_reader :search_words_s, :search_words_d, :search_words_w, :columns,
                :custom_query_name, :custom_query_id, :additional_filter, :only_text, :only_link, :count_flag, :zero_flag, :sum_field

    def initialize(obj, args = nil, project = nil)
      parse_args obj, args, project if args
    end

    def parse_args(obj, args, project) # rubocop:disable Metrics/MethodLength
      args ||= []
      @project = project
      @search_words_s = []
      @search_words_d = []
      @search_words_w = []
      @columns = []
      @restrict_project = nil
      @additional_filter = []
      @only_link = nil
      @only_text = nil
      @count_flag = nil
      @zero_flag = nil
      @sum_field = nil

      args.each do |arg|
        arg.strip!
        arg.gsub! '&gt;', '>'
        arg.gsub! '&lt;', '<'

        case arg
        when /\A-([^=:]*)\s*([=:])\s*(.*)\z/
          opt = Regexp.last_match(1).strip
          sep = Regexp.last_match(2).strip
          words = Regexp.last_match(3).strip
        when /\A-([^=:]*)\z/
          opt = Regexp.last_match(1).strip
          sep = nil
          words = default_words(obj).join('|')
        else
          @columns << get_column(arg)
          next
        end

        case opt
        when 's', 'sw', 'Dw', 'sDw', 'Dsw'
          @search_words_s.push words_to_word_array(obj, words)
        when 'd', 'dw', 'Sw', 'Sdw', 'dSw'
          @search_words_d.push words_to_word_array(obj, words)
        when 'w', 'sdw'
          @search_words_w.push words_to_word_array(obj, words)
        when 'q'
          raise "- no CustomQuery name:#{arg}" unless sep

          @custom_query_name = words
        when 'i'
          raise "- no CustomQuery ID:#{arg}" unless sep

          @custom_query_id = words
        when 'p'
          @restrict_project = sep ? Project.find(words) : project
        when 'f'
          raise "- no additional filter:#{arg}" unless sep

          filter = ''
          operator = ''
          values = nil

          case words
          when /\A([^\s]*)\s+([^\s]*)\z/
            filter = Regexp.last_match 1
            operator = refer_field obj, Regexp.last_match(2)
          when /\A([^\s]*)\s+([^\s]*)\s+(.*)\z/
            filter = Regexp.last_match 1
            operator = refer_field obj, Regexp.last_match(2)
            values = words_to_word_array obj, Regexp.last_match(3)
          when /\A(.*)=(.*)\z/
            filter = Regexp.last_match 1
            operator = '='
            values = words_to_word_array obj, Regexp.last_match(2)
          else
            filter = words
            operator = '='
            values = default_words obj
          end

          @additional_filter << { filter: filter, operator: operator, values: values }
        when 't'
          @only_text = sep ? words : 'subject'
        when 'l'
          @only_link = sep ? words : 'subject'
        when 'c'
          @count_flag = true
        when '0'
          @zero_flag = true
        when 'sum'
          raise "- no sum field:#{arg}" unless sep

          @sum_field = words
        else
          raise "- unknown option:#{arg}"
        end
      end
    end

    def search_conditions?
      return true if @custom_query_id
      return true if @custom_query_name
      return true if @search_words_s.present?
      return true if @search_words_d.present?
      return true if @search_words_w.present?
      return true if @additional_filter.present?

      false
    end

    def query(project)
      # Get custom query from name if option has custom query
      if @custom_query_id
        @query = IssueQuery.visible.find_by id: @custom_query_id
        raise "- can not find CustomQuery ID: #{@custom_query_id}" unless @query
      elsif @custom_query_name
        scope = IssueQuery.where name: @custom_query_name
        scope = if project
                  scope.where project_id: nil
                else
                  scope.where(project_id: nil).or(scope.where(project_id: project.id))
                end

        @query = scope.find_by(user_id: User.current.id) ||
                 scope.find_by(visibility: Query::VISIBILITY_PUBLIC)

        raise "- can not find CustomQuery Name:'#{@custom_query_name}'" unless @query
      else
        @query = IssueQuery.new name: '_', filters: {}
      end

      @query.user = User.current
      @query.project = @restrict_project if @restrict_project

      # Query Extend the model
      overwrite_sql_for_field @query
      @query.available_filters['description'] = { type: :text, order: 8 }
      @query.available_filters['subjectdescription'] = { type: :text, order: 8 }
      @query.available_filters['fixed_version_id'] = { type: :int }
      @query.available_filters['category_id'] = { type: :int }
      @query.available_filters['parent_id'] = { type: :int }
      @query.available_filters['id'] = { type: :int }
      @query.available_filters['treated'] = { type: :date }
      @query.available_filters['sprint_id'] = { type: :int }

      @query
    end

    def default_words(obj)
      words = []

      if obj.instance_of? WikiContent # For Wiki, use the page name and alias as the search word
        words.push obj.page.title # Page name
        redirects = WikiRedirect.where redirects_to: obj.page.title # Page name

        redirects.each do |redirect|
          words << redirect.title # Alias
        end
      elsif obj.instance_of? Issue # For tickets, use ticket subject as the search word
        words << obj.subject
      elsif obj.instance_of?(Journal) && obj.journalized_type == 'Issue'
        # Even in the case of ticket comments, use the ticket number notation as the search word
        words << "##{obj.journalized_id}"
      end

      words
    end

    private

    def get_column(name)
      name_sym = name.to_sym

      IssueQuery.available_columns.each do |col|
        return name_sym if name_sym == col.name.to_sym
      end

      return :assigned_to if name_sym == :assigned
      return :updated_on if name_sym == :updated
      return :created_on if name_sym == :created
      return name_sym if name.start_with? 'cf_'

      raise "- unknown column:#{name}"
    end

    # @todo A dumb patch that was made for lack of mention of how to work with Query. Basically, you need to patch IssueQuery
    def overwrite_sql_for_field(query)
      def query.sql_for_field(field, operator, value, db_table, db_field, is_custom_filter = false) # rubocop:disable Metrics/ParameterLists, Style/OptionalBooleanParameter
        if operator == '~'
          # monkey patched for ref_issues: originally treat single value  -> extend multiple value
          sql = +'('
          if db_field == 'subjectdescription'
            value.each do |v|
              sql << ' OR ' if sql != '('
              pattern = "'%#{self.class.connection.quote_string v.to_s}%'"
              sql << "#{Redmine::Database.like "#{db_table}.subject", pattern} " \
                     "OR #{Redmine::Database.like "#{db_table}.description", pattern}"
            end
          else
            value.each do |v|
              sql << ' OR ' if sql != '('
              pattern = "'%#{self.class.connection.quote_string v.to_s}%'"
              sql << Redmine::Database.like(RedmineRefIssues.cast_table_field(db_table, db_field), pattern)
            end
          end

          sql << ')'
          return sql
        elsif operator == '=='
          sql = +'('
          value.each do |v|
            sql << ' OR ' if sql != '('
            sql << "LOWER(#{RedmineRefIssues.cast_table_field db_table, db_field}) = " \
                   "'#{self.class.connection.quote_string v.to_s.downcase}'"
            next unless field =~ /^cf_([0-9]+)$/

            custom_field_id = Regexp.last_match 1
            custom_field_enumerations = CustomFieldEnumeration.where custom_field_id: custom_field_id, name: v
            custom_field_enumerations.each do |custom_field_enumeration|
              sql << " OR #{db_table}.#{db_field} = '#{custom_field_enumeration.id}'"
            end
          end

          sql << ')'
          return sql
        elsif db_field == 'treated'
          raise '- too many values for treated' if value.length > 2
          raise '- too few values for treated' if value.length < 2

          start_date = value[0]
          end_date = value[1]
          if /^\d+$/.match?(operator)
            user = operator
          else
            user_obj = User.find_by login: operator
            raise "- can not find user <#{operator}>" if user_obj.nil?

            user = user_obj.id.to_s
          end

          sql =  '(' \
                 "(issues.author_id = #{user} " \
                 "AND (CAST(issues.created_on AS DATE) BETWEEN '#{start_date}' AND '#{end_date}')) " \
                 'OR (' \
                 "(select count(*) from journals where journalized_type = 'Issue' AND journalized_id = issues.id " \
                 "AND journals.user_id = #{user} " \
                 "AND (CAST(journals.created_on AS DATE) BETWEEN '#{start_date}' AND '#{end_date}') " \
                 ') > 0' \
                 ')' \
                 ')'

          return sql
        end

        super
      end
    end

    def words_to_word_array(obj, words)
      words.split('|').collect do |word|
        word.strip!
        refer_field obj, word
      end
    end

    def refer_field(obj, word)
      return User.current.id.to_s if word.include? '[current_user_id]'
      return User.current.login if word.include? '[current_user]'
      return @project.id.to_s if word.include? '[current_project_id]'
      return (User.current.today - Regexp.last_match(1).to_i).strftime '%Y-%m-%d' if word =~ /\[(.*)days_ago\]/

      if word =~ /\A\[(.*)\]\z/
        atr = Regexp.last_match 1
        if obj.instance_of? Issue
          issue = obj
        elsif obj.instance_of?(Journal) && obj.journalized_type == 'Issue'
          issue = obj.issue
        else
          raise "- can not use reference '#{word}' except for issues."
        end

        if issue.attributes.key? atr
          word = issue.attributes[atr]
        else
          issue.custom_field_values.each do |cf|
            word = cf.value if "cf_#{cf.custom_field.id}" == atr || cf.custom_field.name == atr
          end
        end
      end

      word.to_s
    end
  end
end
