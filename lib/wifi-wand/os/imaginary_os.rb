# This class is intended as a placeholder class to test multiple OS support
# until we have a real Os class for an additional OS.

require_relative 'base_os'

module WifiWand

class ImaginaryOs < BaseOs

  def initialize()
    super(:imaginary, 'Imaginary OS')
  end

  def current_os_is_this_os?
    false
  end

  def create_model(options)
    raise "I was only kidding. This class is imaginary."
  end
end
end
