# Contributing to Mobile Terminal

First off, thank you for considering contributing to Mobile Terminal! It's people like you that make this app better for everyone.

## Code of Conduct

By participating in this project, you are expected to uphold a welcoming and inclusive environment for all contributors.

## How Can I Contribute?

### Reporting Bugs

Before creating bug reports, please check the existing issues to avoid duplicates. When you create a bug report, include as many details as possible:

- **Device and iOS version**
- **Steps to reproduce the issue**
- **Expected behavior**
- **Actual behavior**
- **Screenshots if applicable**
- **Console logs if available**

### Suggesting Features

Feature suggestions are welcome! Please create an issue with:

- **A clear description of the feature**
- **Why it would be useful**
- **Any implementation ideas you have**

### Pull Requests

1. **Fork the repo** and create your branch from `main`
2. **Follow the existing code style** - the project uses Swift conventions
3. **Test your changes** on a real device if possible
4. **Update documentation** if you're changing functionality
5. **Write a clear commit message** describing what you changed and why

## Development Setup

### Prerequisites

- macOS with Xcode 15.0+
- iOS device for testing (simulator has limited SSH functionality)
- Apple Developer account for device deployment

### Getting Started

1. Clone your fork:
   ```bash
   git clone https://github.com/yourusername/MobileTerminal.git
   ```

2. Open the project:
   ```bash
   open MobileTerminal.xcodeproj
   ```

3. Wait for Swift Package Manager to resolve dependencies

4. Select your development team in Signing & Capabilities

5. Build and run!

### Project Architecture

- **Views/** - SwiftUI views organized by feature
- **Services/** - Business logic and external integrations
- **Models/** - Data models
- **Utils/** - Helper utilities and extensions

### Key Components

- `SSHClient.swift` - Core SSH connection logic using Citadel
- `SwiftTermView.swift` - SwiftTerm integration for terminal rendering
- `CredentialManager.swift` - Secure credential storage using Keychain

## Style Guidelines

### Swift

- Use Swift's native types and conventions
- Prefer `let` over `var` where possible
- Use meaningful variable and function names
- Add comments for complex logic
- Use `// MARK: -` to organize code sections

### SwiftUI

- Keep views focused and composable
- Extract reusable components
- Use proper view modifiers
- Follow Apple's Human Interface Guidelines

### Git

- Use clear, descriptive commit messages
- Reference issues in commits when applicable
- Keep commits focused on single changes

## Testing

- Test on real devices when possible
- Test both password and SSH key authentication
- Test terminal rendering with various applications
- Test on different iPhone sizes

## Questions?

Feel free to open an issue for any questions about contributing.

Thank you for contributing!
