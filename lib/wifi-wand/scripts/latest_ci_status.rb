# frozen_string_literal: true

require 'json'
require 'open3'
require 'shellwords'

module WifiWand
  module Scripts
    class LatestCiStatus
      def call
        branch = fetch_current_branch
        puts "Fetching latest CI run for branch: #{branch}..."

        run_data = fetch_latest_run(branch)

        if run_data.nil?
          puts "No workflow runs found for branch '#{branch}'."
          return
        end

        display_run_details(run_data)
      end

      private def fetch_current_branch
        run_command(%w[git rev-parse --abbrev-ref HEAD])
      end

      private def fetch_latest_run(branch)
        json_output, success = run_command_with_status(
          ['gh', 'run', 'list', '--branch', branch, '--limit', '1', '--json',
            'databaseId,status,conclusion,url,displayTitle,createdAt']
        )

        return JSON.parse(json_output).first if success

        warn "Failed to fetch runs. Ensure 'gh' is installed and you are authenticated."
        exit 1
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

        handle_status_action(status, conclusion, id)
      end

      private def handle_status_action(status, conclusion, id)
        if status == 'completed' && %w[failure startup_failure timed_out].include?(conclusion)
          puts
          puts colorize('Fetching failure logs...', 31)
          puts '------------------------'
          Kernel.system('gh', 'run', 'view', id.to_s, '--log-failed')
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
        stdout, _stderr, status = capture_command(cmd)
        [stdout.strip, status.success?]
      rescue Errno::ENOENT
        ["Command not found: #{command_display(cmd)}", false]
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
