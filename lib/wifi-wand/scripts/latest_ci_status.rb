# frozen_string_literal: true

require 'json'
require 'open3'
require 'shellwords'
require 'uri'

module WifiWand
  module Scripts
    class LatestCiStatus
      def call
        branch = fetch_current_branch
        repository = fetch_repository
        puts "Fetching latest CI run for branch: #{branch}..."
        puts "Repository: #{repository}"

        run_data = fetch_latest_run(branch, repository)

        if run_data.nil?
          puts "No workflow runs found for branch '#{branch}'."
          return
        end

        display_run_details(run_data)
      end

      private def fetch_current_branch
        run_command(%w[git rev-parse --abbrev-ref HEAD])
      end

      private def fetch_repository
        remote_url = run_command(%w[git remote get-url origin])

        parse_github_repository(remote_url)
      end

      private def fetch_latest_run(branch, repository)
        run_list_response = run_command_with_status(gh_run_list_command(branch, repository))

        abort_with_gh_error('Failed to fetch runs', run_list_response) unless run_list_response[:success]

        run_data = parse_run_list_response(run_list_response[:stdout])
        return run_data unless run_data.nil?

        api_response = run_command_with_status(gh_api_run_lookup_command(branch, repository))
        unless api_response[:success]
          abort_with_gh_error('Failed to fetch runs from the Actions API', api_response)
        end

        parse_actions_api_response(api_response[:stdout])
      end

      private def display_run_details(run)
        id = run['databaseId']
        status = run['status']
        conclusion = run['conclusion']
        url = run['url']
        title = run['displayTitle']
        created_at = run['createdAt']

        color = status_color(status, conclusion)
        display_status = if status == 'completed'
          (conclusion || 'unknown').upcase
        else
          status.upcase
        end

        puts
        puts 'Latest Run Details:'
        puts '-------------------'
        puts "Title:      #{title}"
        puts "ID:         #{id}"
        puts "Time:       #{created_at}"
        puts "Status:     #{colorize(display_status, color)}"
        puts "URL:        #{url}"

        handle_status_action(status, conclusion, id, run['repository'])
      end

      private def handle_status_action(status, conclusion, id, repository)
        if status == 'completed' && %w[failure startup_failure timed_out].include?(conclusion)
          puts
          puts colorize('Fetching failure logs...', 31)
          puts '------------------------'
          Kernel.system('gh', 'run', 'view', id.to_s, '--repo', repository, '--log-failed')
        elsif status == 'in_progress'
          puts
          puts colorize('Build is currently running...', 34)
          puts "You can watch it with: gh run watch #{id}"
        elsif status == 'queued'
          puts
          puts colorize('Build is queued...', 34)
        end
      end

      private def colorize(text, color_code)
        "\e[#{color_code}m#{text}\e[0m"
      end

      private def status_color(status, conclusion)
        return 34 unless status == 'completed'

        case conclusion
        when 'success'
          32
        when 'failure', 'startup_failure', 'timed_out'
          31
        when 'cancelled'
          33
        else
          37
        end
      end

      private def parse_github_repository(remote_url)
        matched_repository = remote_url.match(%r{\Agit@github\.com:(.+?)(?:\.git)?\z}) ||
          remote_url.match(%r{\Ahttps://github\.com/(.+?)(?:\.git)?\z})

        return matched_repository[1] if matched_repository

        warn "Unable to determine GitHub repository from origin remote: #{remote_url}"
        exit 1
      end

      private def gh_run_list_command(branch, repository)
        ['gh', 'run', 'list', '--repo', repository, '--branch', branch, '--limit', '1', '--json',
          'databaseId,status,conclusion,url,displayTitle,createdAt']
      end

      private def gh_api_run_lookup_command(branch, repository)
        encoded_branch = URI.encode_www_form_component(branch)
        ['gh', 'api', "repos/#{repository}/actions/runs?branch=#{encoded_branch}&per_page=1"]
      end

      private def parse_run_list_response(json_output)
        JSON.parse(json_output).first
      rescue JSON::ParserError => e
        warn "Unable to parse gh run list output: #{e.message}"
        exit 1
      end

      private def parse_actions_api_response(json_output)
        parsed_response = JSON.parse(json_output)
        latest_run = parsed_response.fetch('workflow_runs', []).first
        return nil if latest_run.nil?

        {
          'databaseId'   => latest_run['id'],
          'status'       => latest_run['status'],
          'conclusion'   => latest_run['conclusion'],
          'url'          => latest_run['html_url'],
          'displayTitle' => latest_run['display_title'],
          'createdAt'    => latest_run['created_at'],
          'repository'   => latest_run.dig('repository', 'full_name'),
        }
      rescue JSON::ParserError => e
        warn "Unable to parse GitHub Actions API output: #{e.message}"
        exit 1
      end

      private def abort_with_gh_error(prefix, response)
        warn "#{prefix}. Ensure 'gh' is installed and you are authenticated."
        warn response[:stderr] unless response[:stderr].strip.empty?
        exit 1
      end

      private def run_command(cmd)
        stdout, stderr, status = capture_command(cmd)

        return stdout.strip if status.success?

        warn "Error running: #{command_display(cmd)}"
        warn stderr unless stderr.strip.empty?
        exit 1
      rescue Errno::ENOENT
        warn "ERROR: Command not found: #{command_display(cmd)}"
        exit 1
      end

      private def run_command_with_status(cmd)
        stdout, stderr, status = capture_command(cmd)
        {
          stdout:  stdout.strip,
          stderr:  stderr.strip,
          success: status.success?,
        }
      rescue Errno::ENOENT
        {
          stdout:  '',
          stderr:  "Command not found: #{command_display(cmd)}",
          success: false,
        }
      end

      private def capture_command(cmd)
        if cmd.is_a?(Array)
          Open3.capture3(*cmd)
        else
          Open3.capture3(cmd)
        end
      end

      private def command_display(cmd)
        return Shellwords.join(cmd) if cmd.is_a?(Array)

        cmd.to_s
      end
    end
  end
end
