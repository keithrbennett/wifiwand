# Security Notes

`wifiwand` is intended for individual users on machines they control. It treats WiFi passwords as local
network credentials, not as login passwords, API keys, or other high-value application secrets.

Some commands may still expose WiFi passwords to local machine surfaces. This is a usability and debugging
tradeoff: `wifiwand` delegates WiFi operations to operating system tools and lets users pass credentials
directly when that is the simplest workflow.

Potential exposure surfaces include:

- Shell history when a password is typed as a command-line argument.
- Local process listings while `wifiwand` or child tools are running.
- Child process arguments passed to OS tools such as `nmcli`, `networksetup`, Swift helper paths, or
  `qrencode`.
- Verbose mode output, which may print password-bearing commands or command output.
- Terminal scrollback when a command prints password-bearing data or an ANSI QR code.
- Generated QR code files, which contain the WiFi password by design when generated for a secured network.
- Saved WiFi passwords retrieved from macOS Keychain or NetworkManager and reused for connect, restore, or QR
  generation workflows.

Avoid inline passwords and generated QR code files on shared or untrusted machines. If a generated QR code
contains a secured network credential, treat the image file as password-bearing and delete it when it is no
longer needed.

When local exposure matters, prefer OS-managed saved credentials, avoid verbose mode, and clear any shell
history entries or terminal scrollback that contain WiFi passwords.
