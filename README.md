# Mobile Terminal

A native iOS SSH client with full terminal emulation, designed for running Claude Code and other TUI applications on your iPhone or iPad.

![iOS 18.0+](https://img.shields.io/badge/iOS-18.0%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **Full Terminal Emulation** - SwiftTerm-powered terminal with complete ANSI escape code support
- **Rich TUI Rendering** - Colors, cursor positioning, and formatting work perfectly
- **SSH Client** - Native SSH using Citadel (SwiftNIO SSH)
- **Authentication** - Password and SSH key (Ed25519, RSA) support
- **Mobile-Optimized Toolbar** - Quick access to Esc, Ctrl+C, arrow keys, and more
- **Voice Input** - Speak commands instead of typing
- **Biometric Auth** - Face ID/Touch ID for secure server access
- **Session Persistence** - Keep screen awake during SSH sessions
- **Command History** - Quick access to previous commands

## Screenshots

*Coming soon*

## Requirements

- iOS 18.0 or later
- Xcode 15.0 or later
- Swift 5.9

## Installation

### Clone the Repository

```bash
git clone https://github.com/yourusername/MobileTerminal.git
cd MobileTerminal
```

### Open in Xcode

1. Open `MobileTerminal.xcodeproj` in Xcode
2. Wait for Swift Package Manager to resolve dependencies
3. Select your development team in Signing & Capabilities
4. Build and run on your device

### Dependencies

The project uses Swift Package Manager for dependencies:

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) - Terminal emulation
- [Citadel](https://github.com/orlandos-nl/Citadel) - SSH client (SwiftNIO-based)

## Usage

### Adding a Server

1. Tap the **+** button on the main screen
2. Enter server details:
   - Name: A friendly name for the server
   - Host: IP address or hostname
   - Port: SSH port (default: 22)
   - Username: Your SSH username
3. Choose authentication method:
   - **Password**: Enter your password
   - **SSH Key**: Import your private key

### Connecting

1. Tap on a server to connect
2. The terminal will open with full TUI support
3. Use the toolbar for mobile-friendly controls

### Toolbar Controls

| Button | Action |
|--------|--------|
| Esc | Send escape key |
| ^C | Send Ctrl+C (interrupt) |
| ^D | Send Ctrl+D (EOF) |
| Tab | Tab completion |
| ↑↓←→ | Arrow keys |
| Enter | Confirm/submit |
| Del | Backspace |

### Running Claude Code

This app was specifically designed to run [Claude Code](https://claude.ai/claude-code) with full TUI support:

```bash
claude
```

You'll see the full colored interface with proper rendering.

## Project Structure

```
MobileTerminal/
├── App/
│   ├── MobileTerminalApp.swift    # App entry point
│   └── ContentView.swift          # Root view
├── Views/
│   ├── Terminal/
│   │   ├── SwiftTermView.swift    # SwiftTerm wrapper
│   │   ├── SSHTerminalView.swift  # SSH terminal screen
│   │   └── TerminalToolbar.swift  # Mobile controls
│   ├── ServerList/                # Server management
│   └── Settings/                  # App settings
├── Services/
│   ├── SSHClient.swift            # SSH connection logic
│   ├── CredentialManager.swift    # Keychain storage
│   └── SSHKeyManager.swift        # SSH key management
├── Models/
│   └── ServerConnection.swift     # Server data model
└── Server/                        # Server-side scripts
```

## Server Setup (Optional)

For persistent sessions, you can set up tmux on your server. See the [Server README](Server/README.md) for instructions.

## Security

- All credentials are stored in the iOS Keychain
- SSH keys are stored securely and never leave the device
- No data is sent to third parties
- Face ID/Touch ID optional for additional security

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) by Miguel de Icaza
- [Citadel](https://github.com/orlandos-nl/Citadel) by Orlandos
- Apple's SwiftNIO team

## Author

**Jaspal Singh** - [SaveDelete.com](https://savedelete.com)

---

If you find this project useful, please consider giving it a star!
