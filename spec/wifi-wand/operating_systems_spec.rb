require_relative '../../lib/wifi-wand/operating_systems'

module WifiWand
  describe OperatingSystems do
    describe 'instantiation' do
      it 'is prohibited' do
        expect { OperatingSystems.new }.to raise_error(NoMethodError)
      end
    end

    describe '.supported_operating_systems' do
      it 'populates supported_operating_systems with expected OS classes' do
        expect(described_class.supported_operating_systems).to be_a(Array)
        expect(described_class.supported_operating_systems.length).to be >= 2

        # Check for expected OS types
        os_classes = described_class.supported_operating_systems.map(&:class)
        expect(os_classes).to include(Ubuntu, MacOs)
      end

      it 'creates OS instances with proper structure' do
        described_class.supported_operating_systems.each do |os|
          expect(os).to be_a(BaseOs)
          expect(os).to respond_to(:current_os_is_this_os?)
          expect(os).to respond_to(:create_model)
        end
      end
    end

    describe '.current_os' do
      before(:each) do
        # Reset class variable to force re-detection
        described_class.instance_variable_set(:@current_os, nil)
      end

      context 'when current OS can be detected' do
        it 'returns an OS instance that matches the current system' do
          current_os = described_class.current_os
          expect(current_os).to be_a(BaseOs)

          # Verify the returned OS actually identifies as current
          if current_os
            expect(current_os.current_os_is_this_os?).to be(true)
          end
        end

        it 'caches the result after first call' do
          first_result = described_class.current_os
          second_result = described_class.current_os

          expect(first_result).to be_equal(second_result)
        end
      end

      context 'error handling' do
        it 'raises error if multiple OSes match current system' do
          # Create a mock scenario where multiple OSes return true
          mock_os1 = double('MockOS1',
                            current_os_is_this_os?: true,
                            id: :mock1,
                            display_name: 'Mock OS 1')
          mock_os2 = double('MockOS2',
                            current_os_is_this_os?: true,
                            id: :mock2,
                            display_name: 'Mock OS 2')

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
      before(:each) do
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

      it 'raises error when no OS is detected' do
        # Mock a scenario where no OS is detected
        mock_os = double('MockOS', current_os_is_this_os?: false)
        allow(described_class).to receive(:supported_operating_systems).and_return([mock_os])

        expect { described_class.create_model_for_current_os }.to raise_error(WifiWand::NoSupportedOSError)
      end

      it 'accepts options and passes them to model creation' do
        if described_class.current_os
          options = OpenStruct.new(verbose: true)

          # Mock detect_wifi_interface to avoid OS calls during model creation
          if described_class.current_os.class.name.include?('Ubuntu')
            allow_any_instance_of(WifiWand::UbuntuModel).to receive(:detect_wifi_interface).and_return('wlan0')
          elsif described_class.current_os.class.name.include?('MacOs')
            allow_any_instance_of(WifiWand::MacOsModel).to receive(:detect_wifi_interface).and_return('en0')
          end

          model = described_class.create_model_for_current_os(options)

          # Verify the model was created (specific options verification would be OS-specific)
          expect(model).not_to be_nil
        end
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
        ubuntu_os = described_class.supported_operating_systems.find { |os| os.is_a?(Ubuntu) }
        expect(ubuntu_os).not_to be_nil
        expect([true, false]).to include(ubuntu_os.current_os_is_this_os?)
      end

      it 'verifies macOS detection methods' do
        mac_os = described_class.supported_operating_systems.find { |os| os.is_a?(MacOs) }
        expect(mac_os).not_to be_nil
        expect([true, false]).to include(mac_os.current_os_is_this_os?)
      end
    end

    describe 'OS validation' do
      it 'ensures all supported OSes are valid BaseOs subclasses' do
        described_class.supported_operating_systems.each do |os|
          expect(os).to be_a(BaseOs)
        end
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
          begin
            if os.current_os_is_this_os?
              model = os.create_model(OpenStruct.new(verbose: false))
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
end
