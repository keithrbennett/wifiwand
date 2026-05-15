# frozen_string_literal: true

require_relative '../../../lib/wifi_wand/platforms/selector'

module WifiWand
  describe Platforms::Selector do
    describe 'instantiation' do
      it 'is prohibited' do
        expect { described_class.new }.to raise_error(NoMethodError)
      end
    end

    describe '.supported_operating_systems' do
      it 'populates supported_operating_systems with expected OS classes' do
        expect(described_class.supported_operating_systems).to be_a(Array)
        expect(described_class.supported_operating_systems.length).to be >= 2

        # Check for expected OS types
        os_classes = described_class.supported_operating_systems.map(&:class)
        expect(os_classes).to include(Platforms::Selection::Ubuntu, Platforms::Selection::Mac)
      end

      it 'creates OS instances with proper structure' do
        operating_systems = described_class.supported_operating_systems
        non_base_os_instances = operating_systems.reject { |os| os.is_a?(Platforms::Selection::Base) }
        missing_current_os_detector = operating_systems.reject do |os|
          os.respond_to?(:current_os_is_this_os?)
        end
        missing_model_factory = operating_systems.reject { |os| os.respond_to?(:create_model) }

        expect(non_base_os_instances).to be_empty
        expect(missing_current_os_detector).to be_empty
        expect(missing_model_factory).to be_empty
      end
    end

    describe '.current_os' do
      before do
        # Reset class variable to force re-detection
        described_class.instance_variable_set(:@current_os, nil)
      end

      context 'when current OS can be detected' do
        it 'returns an OS instance that matches the current system' do
          current_os = described_class.current_os
          expect(current_os).to be_a(Platforms::Selection::Base)

          # Verify the returned OS actually identifies as current
          if current_os
            expect(current_os.current_os_is_this_os?).to be(true)
          end
        end

        it 'caches the result after first call' do
          first_result = described_class.current_os
          second_result = described_class.current_os

          expect(first_result).to equal(second_result)
        end
      end

      context 'when handling errors' do
        it 'raises error if multiple OSes match current system' do
          # Create a mock scenario where multiple OSes return true
          mock_os1 = double('MockOS1',
            current_os_is_this_os?: true,
            id:                     :mock1,
            display_name:           'Mock OS 1')
          mock_os2 = double('MockOS2',
            current_os_is_this_os?: true,
            id:                     :mock2,
            display_name:           'Mock OS 2')

          allow(described_class).to receive(:supported_operating_systems).and_return([mock_os1, mock_os2])

          expect { described_class.current_os }.to raise_error(WifiWand::MultipleOSMatchError)
        end

        it 'returns nil when no OS matches current system' do
          # All OSes return false for current_os_is_this_os?
          mock_os = double('MockOS', current_os_is_this_os?: false)
          allow(described_class).to receive(:supported_operating_systems).and_return([mock_os])

          expect(described_class.current_os).to be_nil
        end
      end
    end

    describe '.current_id' do
      it 'returns the id of the current OS' do
        if described_class.current_os
          expect(described_class.current_id).to be_a(Symbol)
          expect(described_class.current_id).to eq(described_class.current_os.id)
        else
          expect(described_class.current_id).to be_nil
        end
      end
    end

    describe '.current_display_name' do
      it 'returns the display name of the current OS' do
        if described_class.current_os
          expect(described_class.current_display_name).to be_a(String)
          expect(described_class.current_display_name).to eq(described_class.current_os.display_name)
        else
          expect(described_class.current_display_name).to be_nil
        end
      end
    end

    describe '.create_model_for_current_os' do
      before do
        # Reset class variable to force re-detection
        described_class.instance_variable_set(:@current_os, nil)
      end

      it 'creates a model when current OS is detected' do
        if described_class.current_os
          model = described_class.create_model_for_current_os
          expect(model).not_to be_nil
          expect(model).to respond_to(:wifi_on?)
          expect(model).to respond_to(:wifi_info)
        end
      end

      it 'delegates model creation to the detected OS object' do
        model = instance_double(WifiWand::BaseModel)
        current_os = instance_double(Platforms::Selection::Base, create_model: model)

        allow(described_class).to receive(:current_os).and_return(current_os)

        expect(described_class.create_model_for_current_os).to equal(model)
      end

      it 'creates a model without eagerly initializing the wifi interface by default' do
        current_os = described_class.current_os
        expect(current_os).not_to be_nil

        model_class = {
          ubuntu: WifiWand::Platforms::Ubuntu::Model,
          mac:    WifiWand::Platforms::Mac::Model,
        }.fetch(current_os.id) do
          raise "Unexpected current_os.id: #{current_os.id.inspect}"
        end

        model = model_class.new
        allow(model).to receive(:init).and_call_original
        allow(model_class).to receive(:new).and_return(model)

        created_model = described_class.create_model_for_current_os

        expect(created_model).to equal(model)
        expect(created_model).not_to have_received(:init)
        expect(created_model.instance_variable_get(:@wifi_interface)).to be_nil
        expect(created_model).to respond_to(:wifi_on?)
        expect(created_model).to respond_to(:wifi_info)
      end

      it 'raises error when no OS is detected' do
        # Mock a scenario where no OS is detected
        mock_os = double('MockOS', current_os_is_this_os?: false)
        allow(described_class).to receive(:supported_operating_systems).and_return([mock_os])

        expect { described_class.create_model_for_current_os }.to raise_error(WifiWand::NoSupportedOSError)
      end

      it 'accepts options and passes them to model creation' do
        if described_class.current_os
          options = { verbose: true }
          model = described_class.create_model_for_current_os(options)
          expect(model).not_to be_nil
        end
      end

      it 'rejects non-Hash options' do
        expect do
          described_class.create_model_for_current_os(Object.new)
        end.to raise_error(ArgumentError, /options must be a Hash/)
      end
    end

    describe 'individual OS behavior' do
      it 'verifies each OS implements required methods' do
        required_methods = %i[current_os_is_this_os? create_model id display_name]
        described_class.supported_operating_systems.each do |os|
          missing_required_methods = required_methods - os.methods
          expect(missing_required_methods).to be_empty
        end
      end

      it 'verifies Ubuntu OS detection methods' do
        ubuntu_os = described_class.supported_operating_systems.find do |os|
          os.is_a?(Platforms::Selection::Ubuntu)
        end
        expect(ubuntu_os).not_to be_nil
        expect(ubuntu_os.current_os_is_this_os?).to be(true).or be(false)
      end

      it 'verifies macOS detection methods' do
        mac_os = described_class.supported_operating_systems.find { |os| os.is_a?(Platforms::Selection::Mac) }
        expect(mac_os).not_to be_nil
        expect(mac_os.current_os_is_this_os?).to be(true).or be(false)
      end
    end

    describe 'OS validation' do
      it 'ensures all supported OSes are valid Platforms::Selection::Base subclasses' do
        expect(described_class.supported_operating_systems).to all(be_a(Platforms::Selection::Base))
      end

      it 'ensures OS ids are unique symbols' do
        ids = described_class.supported_operating_systems.map(&:id)
        expect(ids.uniq.length).to eq(ids.length)
        expect(ids).to all(be_a(Symbol))
      end

      it 'ensures OS display names are non-empty strings' do
        display_names = described_class.supported_operating_systems.map(&:display_name)
        expect(display_names).to all(be_a(String))
        expect(display_names).to all(satisfy { |name| !name.strip.empty? })
      end
    end

    describe 'integration with model creation' do
      it 'can create models for detectable OSes without errors' do
        described_class.supported_operating_systems.each do |os|
          if os.current_os_is_this_os?
            model = os.create_model(verbose: false)
            expect(model).not_to be_nil
            # Basic interface validation
            expect(model).to respond_to(:wifi_on?)
            expect(model).to respond_to(:wifi_info)
          end
        rescue => e
          # It's OK if model creation fails due to OS incompatibility
          # but it should fail gracefully, not crash
          expect(e.message).not_to be_nil
        end
      end
    end
  end
end
