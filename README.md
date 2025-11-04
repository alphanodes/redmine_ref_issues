# Redmine ref_issues macro

[![Run Rubocop](https://github.com/AlphaNodes/redmine_ref_issues/workflows/Run%20Rubocop/badge.svg)](https://github.com/AlphaNodes/redmine_ref_issues/actions?query=workflow%3A%22Run+Rubocop%22) [![Run Brakeman](https://github.com/AlphaNodes/redmine_ref_issues/workflows/Run%20Brakeman/badge.svg)](https://github.com/AlphaNodes/redmine_ref_issues/actions?query=workflow%3A%22Run+Brakeman%22) [![Run Tests](https://github.com/AlphaNodes/redmine_ref_issues/workflows/Tests/badge.svg)](https://github.com/AlphaNodes/redmine_ref_issues/actions?query=workflow%3ATests)

## Features

- one macro to create issue lists
  - with existing issue queries
  - with parameters (without issue queries)

This is a fork of [redmine_wiki_lists](https://github.com/tkusukawa/redmine_wiki_lists), which reduce functionality to just one macro - ref_issues

## Requirements

- Redmine `>= 6.1.0`
- Ruby `>= 3.2`

## Installing

1. Clone this repository into `redmine/plugins/redmine_ref_issues`.

   ```shell
   cd redmine
   git clone https://github.com/alphanodes/redmine_ref_issues.git plugins/redmine_ref_issues
   bundle config set --local without 'development test'
   bundle install
   ```

2. Restart your Redmine application server.

## Usage

Syntax

```PowerShell
{{ref_issues([option].., [column]..)}}
```

Options

```text
-s[=WORD[｜WORD]..]
select issues that contain WORDs in subject.

-d[=WORD[｜WORD]..]
select issues that contain WORDs in description.
　
-w[=WORD[｜WORD]..]
select issues that contain WORDs in subject or description.

-p[=IDENTIFIRE]
Specify the project by identifire.

-i=CUSTOM_QUERY_ID
Use custom query by id.

-q=CUSTOM_QUERY_NAME
Use custom query by query name.

-0
Do not display the table If query result is 0.

f:<ATTRIBUTE>␣<OPERATOR>␣<[VALUE[|VALUE...]]>
filter. Attributes are shown below.
e.x. {{ref_issues(-f:tracker_id = 3)}}
　
[ATTRIBUTE]
issue_id,tracker_id,project_id,subject,description,
due_date,category_id,status_id,assigned_to_id,priority_id,
fixed_version_id,author_id,lock_version,created_on,updated_on,
start_date,done_ratio,estimated_hours,parent_id,root_id,
lft,rgt,is_private,closed_on,
cf_*,

tracker,category,status,assigned_to,version,project,
treated, author

[OPERATOR]
=:is, !:is not, o:open, c:closed, !*:none,
*:any, >=:>=, <=:<=, ><:between, >t+:in more than,
>w:this week, lw:last week, l2w:last 2 weeks, m:this month, lm:last month,
y:this year, >t-:less than days ago, ~:contains, !~:doesn't contain,
=p:any issues in project, =!p:any issues not in project, !p:no issues in project,

　
You can specify two or more select option, it affect AND condition.
　
If you use this macro in a Issue, you can use the field value of the issue as VALUE by writing to the following field(column) name in the [] (brackets).
> Besides [<column>], You can use [id], [current_project_id], [current_user], [current_user_id], [<number> days_ago] .
　
-l[=column]
Put linked text.
　
-t[=column]
Put markup text.

-sum[=column]
Sum of specified column for issues.
　
-c
number of issues.
```

### column

You can choose columns that you want to display.
If you do not specify the columns, same columns with customquery are displayed.

- project
- tracker
- parent
- status
- priority
- subject
- author
- assigned_to
- updated_on
- category
- fixed_version
- start_date
- due_date
- estimated_hours
- done_ratio
- created_on
- closed_on
- relations

### Examples

1. Use custom query by ID

   ```PowerShell
   {{ref_issues(-i=9)}}
   ```

2. Use custom query by name

   ```PowerShell
   {{ref_issues(-q=MyCustomQuery1)}}
   ```

3. List up issues that contain 'sorting' in subject

   ```PowerShell
   {{ref_issues(-f:subject ~ sorting)}}
   ```

4. List up issues that author_id is 1 and status is not 'To Do'. specify display column(project,subject,author,assigned_to,status)

   ```PowerShell
   {{ref_issues(-f:author_id = 1, -f:status ! To Do, project, subject, author, assigned_to, status)}}
   ```

5. List up tickets that tracker is Support(3) or Question(6), and restrict by project=Wiki Lists

   ```PowerShell
   {{ref_issues(-f:tracker == Question | Support, -f:project = Wiki Lists)}}
   ```

6. Pickup issues that have subject=Sample, and put linked ID

   ```PowerShell
   {{ref_issues(-f:subject = Sample, -l=id)}}
   ```

7. Pickup issues that have subject=Sample, and put markuped description

   ```PowerShell
   {{ref_issues(-f:subject = Sample, -t=description)}}
   ```

8. Put number of issues that contain 'sorting' in subject

   ```PowerShell
   {{ref_issues(-f:subject ~ sorting, -c)}}
   ```

9. Filter by issue_id (between)

     ```PowerShell
     {{ref_issues(-f:issue_id >< 1389|1391)}}
     ```

10. Filter by issue_id (or)

     ```PowerShell
    {{ref_issues(-f:issue_id == 1389|1391)}}
    ```

11. Do not display the table If query result is 0.

    ```PowerShell
    {{ref_issues(-0,-f:subject = Sample2)}}
    ```

12. OR condition by name

    ```PowerShell
    {ref_issues(-f:category == sample|error, subject, category)}}
    ```

13. Created or updated by user jsmith from 2017-05-01 to yesterday

    ```PowerShell
    {{ref_issues(-f:treated jsmith 2017-05-01|[1days_ago])}}
    ```

14. Put sum of estimated_hours of issues that contain 'sorting' in subject

    ```PowerShell
    {{ref_issues(-f:subject ~ sorting, -sum:estimated_hours)}}
    ```

## Running tests

Make sure you have the latest database structure loaded to the test database:

```shell
bundle exec rake db:drop db:create db:migrate RAILS_ENV=test
```

Run the following command to start tests:

```shell
bundle exec rake redmine:plugins:test NAME=redmine_ref_issues RAILS_ENV=test
```

## Uninstall

```shell
cd $REDMINE_ROOT
rm -rf plugins/redmine_ref_issues
```

## Known bugs

- [Macro not working in email notification](https://www.r-labs.org/issues/1405)

## Contribution

If you want to contribute to this plugin, please create a Pull Request.

## License

This plugin is licensed under the terms of GNU/GPL v2.
See [LICENSE](LICENSE) for details.

## Redmine Copyright

The redmine_ref_issues is a plugin extension for Redmine Project Management Software, whose Copyright follows.
Copyright (C) 2006-  Jean-Philippe Lang

Redmine is a flexible project management web application written using Ruby on Rails framework.
More details can be found in the doc directory or on the official website <http://www.redmine.org>

This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program; if not, write to the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

## Credits

The source code is a fork of [redmine_wiki_lists](https://github.com/tkusukawa/redmine_wiki_lists)

Special thanks to the original author and contributors for making this awesome hook for Redmine.
