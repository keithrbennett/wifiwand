# frozen_string_literal: true

RSpec.shared_examples 'binds command context' do |bound_attributes:|
  describe '#bind' do
    it 'returns a bound command with context-derived execution properties' do
      command = described_class.new
      bound_command = command.bind(cli)

      expect(bound_command).to be_a(described_class)
      expect(bound_command.metadata).to eq(command.metadata)

      bound_attributes.each do |attribute, expected|
        resolved = expected.is_a?(Proc) ? instance_exec(&expected) : public_send(expected)
        expect(bound_command.public_send(attribute)).to eq(resolved)
      end
    end
  end
end

RSpec.shared_examples 'has default command help text' do |usage:, description:|
  describe '#help_text' do
    it 'includes usage and description' do
      help = described_class.new.help_text

      expect(help).to include(usage)
      expect(help).to include(description)
    end
  end
end
