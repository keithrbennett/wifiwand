# frozen_string_literal: true

require 'open3'

module WifiWand
  module Platforms
    module Mac
      module Helper
        # Local development helper for the generated macOS helper files.
        #
        # The compiled helper executable and signing metadata are intentionally
        # tracked because packaged gem builds need to ship a prebuilt, signed
        # helper. During helper development, though, `swift:compile_helper`
        # rewrites those generated files and the source attestation manifest
        # frequently. Those generated edits are easy to stage accidentally with
        # `git add .`, which makes ordinary Ruby or Swift source commits carry a
        # large helper artifact update.
        #
        # `.gitignore` cannot solve that problem because these files are already
        # tracked. This utility toggles Git's local skip-worktree bit for the
        # generated helper artifacts only. Template/input files inside the app
        # bundle, such as Info.plist, stay visible to Git because edits to them
        # are source changes, not local build churn. The flag is stored in the
        # developer's local index, is not committed, and should be cleared before
        # preparing a real helper artifact release. The Swift source stays
        # unskipped so source changes remain visible to normal staging and review.
        class GitSkipWorktree
          class Error < StandardError; end

          DEFAULT_PATHS = [
            'libexec/macos/wifiwand-helper.app/Contents/CodeResources',
            'libexec/macos/wifiwand-helper.app/Contents/MacOS/wifiwand-helper',
            'libexec/macos/wifiwand-helper.app/Contents/_CodeSignature/CodeResources',
            'libexec/macos/wifiwand-helper.source-manifest.json',
          ].freeze

          StatusEntry = Struct.new(:flag, :path, keyword_init: true) do
            def skipped? = flag == 'S'
          end

          Result = Struct.new(:paths, :tracked_entries, keyword_init: true) do
            def skipped_count = tracked_entries.count(&:skipped?)
            def tracked_count = tracked_entries.count
            def skipped? = tracked_count.positive? && skipped_count == tracked_count
          end

          def initialize(repo_root: default_repo_root, paths: DEFAULT_PATHS, out_stream: $stdout)
            @repo_root = repo_root
            @paths = paths
            @out_stream = out_stream
          end

          def start(print_result: true)
            tracked_paths = tracked_files
            update_index('--skip-worktree', tracked_paths)
            result = status
            print_result('Started helper artifact skip-worktree', result) if print_result
            result
          end

          def stop(print_result: true)
            tracked_paths = tracked_files
            update_index('--no-skip-worktree', tracked_paths)
            result = status
            print_result('Stopped helper artifact skip-worktree', result) if print_result
            result
          end

          def status
            Result.new(paths: paths, tracked_entries: status_entries)
          end

          def print_status
            result = status
            print_result('Helper artifact skip-worktree status', result)
            result
          end

          private attr_reader :repo_root, :paths, :out_stream

          private def tracked_files
            output = run_git('ls-files', '-z', '--', *paths)
            output.split("\0").reject(&:empty?)
          end

          private def status_entries
            run_git('ls-files', '-v', '--', *paths).lines.filter_map do |line|
              match = line.chomp.match(/\A(?<flag>\S) (?<path>.+)\z/)
              StatusEntry.new(flag: match[:flag], path: match[:path]) if match
            end
          end

          private def update_index(option, tracked_paths)
            return if tracked_paths.empty?

            path_input = "#{tracked_paths.join("\0")}\0"
            run_git('update-index', option, '-z', '--stdin', stdin_data: path_input)
          end

          private def run_git(*args, stdin_data: nil)
            stdout, stderr, status = Open3.capture3(
              'git',
              *args,
              chdir:      repo_root,
              stdin_data: stdin_data
            )
            return stdout if status.success?

            error_text = stderr.empty? ? stdout : stderr
            raise Error, "git #{args.join(' ')} failed: #{error_text.strip}"
          end

          private def print_result(prefix, result)
            out_stream.puts "#{prefix}: #{result.skipped_count}/#{result.tracked_count} tracked files skipped"
            out_stream.puts "Targets: #{result.paths.join(', ')}"
          end

          private def default_repo_root
            File.expand_path('../../../../..', __dir__)
          end
        end
      end
    end
  end
end
