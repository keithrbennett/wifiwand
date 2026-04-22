# frozen_string_literal: true

require_relative 'spec_helper'

RSpec.describe 'docs/MACOS_HELPER.md' do
  let(:helper_doc) { File.read(File.expand_path('../docs/MACOS_HELPER.md', __dir__)) }
  let(:removed_signing_doc) { ['docs/dev/', 'MACOS_CODE_SIGNING', '.md'].join }

  it 'links maintainers to the current macOS code-signing instructions' do
    expect(helper_doc).to include(
      '[dev/docs/MACOS_CODE_SIGNING_INSTRUCTIONS.md](../dev/docs/MACOS_CODE_SIGNING_INSTRUCTIONS.md)'
    )
    expect(helper_doc).not_to include(removed_signing_doc)
  end
end
