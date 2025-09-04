## Adding a Method and Command to Generate Network QR Code

Add the ability to generate a QR code from the currently connected network, in the form of a BaseModel#generate_qr_code method that contains the behavior to both Ubuntu and macOS, and calls subclass methods for OS-specific logic.

To generate the QR code image, use the qrencode executable from the qrencode library, available with `brew` on Mac, and `apt` on Ubuntu.

In the generate method, check for the presence of `qrencode` in the path, and if absent, report to the user with instructions such as "Required operating system dependency 'qrencode` library not found. Use #{os-specific-command} to install it." ("brew install qrencode" for Mac, 'sudo apt install qrencode' for Ubuntu).

Probably the only OS-specific functionality will be getting the network's security type. Create a 'get_connection_security_type' method in the Ubuntu and Mac models, and register the method in the base model as a required subclass method (see existing list in the source code).

Implement it for both Ubuntu and macOS, but we are running on Ubuntu and will not be able to test the Mac implementation here.

The output of the generate method should be a PNG file whose name is "#{network_name}-qr-code.png".

If there are any close calls in your engineering decisions, refrain from writing the code and ask me first.
