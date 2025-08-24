require_relative '../../spec_helper'
require_relative '../../../lib/wifi-wand/models/mac_os_model'

module WifiWand
  describe MacOsModel, :os_macos do
    describe "version support" do
      subject(:model) { create_mac_os_test_model }

      it "compares version strings correctly" do
        test_cases = [
          ["12.0",     true,  "identical"],
          ["12.1",     true,  "newer minor"],
          ["13.0",     true,  "newer major"],
          ["11.6",     false, "older minor"],
          ["11.0",     false, "older major"],
          ["12.0.1",   true,  "patch version"],
          ["12",       true,  "short format"]
        ]

        test_cases.each do |version, expected, description|
          result = model.send(:supported_version?, version)
          expect(result).to eq(expected),
                            "Version #{version} (#{description}): expected #{expected}, got #{result}"
        end
      end

      context "with current macOS version" do
        it "validates current version meets minimum requirement" do
          current_version = model.instance_variable_get(:@macos_version)
          skip "macOS version not detected" unless current_version

          result = model.send(:supported_version?, current_version)
          expect(result).to be(true), "Current version #{current_version} should be supported"
        end
      end

      context "basic validation" do
        it "validates supported version detection" do
          expect(model.send(:supported_version?, "12.0")).to be true
          expect(model.send(:supported_version?, "11.6")).to be false
        end

        it "handles invalid inputs gracefully" do
          expect(model.send(:supported_version?, nil)).to be false
        end
      end

      context "#validate_macos_version" do
        it "accepts supported versions" do
          model = create_mac_os_test_model
          model.instance_variable_set(:@macos_version, "12.0")
          expect { model.send(:validate_macos_version) }.not_to raise_error
        end

        it "rejects unsupported versions" do
          model = create_mac_os_test_model
          model.instance_variable_set(:@macos_version, "11.6")
          expect { model.send(:validate_macos_version) }.to raise_error(WifiWand::UnsupportedSystemError)
        end

        it "handles nil version gracefully" do
          model = create_mac_os_test_model
          model.instance_variable_set(:@macos_version, nil)
          expect { model.send(:validate_macos_version) }.not_to raise_error
        end
      end

      context "#detect_macos_version" do
        it "detects macOS version when command succeeds" do
          model = create_mac_os_test_model
          allow(model).to receive(:run_os_command).with("sw_vers -productVersion").and_return("15.6\n")
          expect(model.send(:detect_macos_version)).to eq("15.6")
        end

        it "returns nil when command fails" do
          model = create_mac_os_test_model
          allow(model).to receive(:run_os_command).with("sw_vers -productVersion").and_raise(StandardError.new("Command failed"))
          expect { model.send(:detect_macos_version) }.not_to raise_error
          expect(model.send(:detect_macos_version)).to be_nil
        end
      end

      # System-modifying tests (will change wifi state)
      context 'system-modifying operations', :disruptive do
        subject { create_mac_os_test_model }

        describe '#wifi_on' do
          it 'turns wifi on when it is off' do
            subject.wifi_off
            expect(subject.wifi_on?).to be(false)

            subject.wifi_on
            expect(subject.wifi_on?).to be(true)
          end

          it 'does nothing when wifi is already on' do
            subject.wifi_on
            expect(subject.wifi_on?).to be(true)

            expect { subject.wifi_on }.not_to raise_error
            expect(subject.wifi_on?).to be(true)
          end
        end

        describe '#wifi_off' do
          it 'turns wifi off when it is on' do
            subject.wifi_on
            expect(subject.wifi_on?).to be(true)

            subject.wifi_off
            expect(subject.wifi_on?).to be(false)
          end

          it 'does nothing when wifi is already off' do
            subject.wifi_off
            expect(subject.wifi_on?).to be(false)

            expect { subject.wifi_off }.not_to raise_error
            expect(subject.wifi_on?).to be(false)
          end
        end

        describe '#disconnect' do
          it 'disconnects from current network' do
            expect { subject.disconnect }.not_to raise_error
            expect { subject.disconnect }.not_to raise_error
          end
        end

        describe '#remove_preferred_network' do
          it 'handles removal of non-existent network' do
            expect { subject.remove_preferred_network('non_existent_network_123') }.not_to raise_error
          end
        end
      end

      # Network connection tests (highest risk)
      context 'network connection operations', :disruptive do
        subject { create_mac_os_test_model }

        describe '#_connect' do
          it 'raises error for non-existent network' do
            expect { subject._connect('non_existent_network_123') }.to raise_error(WifiWand::NetworkNotFoundError)
          end
        end
      end
    end
  end
end
