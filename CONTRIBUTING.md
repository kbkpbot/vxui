# Contributing to vxui

Thank you for your interest in contributing to vxui! This document provides guidelines and instructions for contributing.

## 🌐 Language

We accept contributions in:
- **English** (preferred for code, documentation, and issues)
- **Chinese** (中文 - accepted for discussions and issues)

## 🚀 Getting Started

### Prerequisites

- [V](https://vlang.io) v0.4.0 or later
- Git
- A supported browser (Chrome, Chromium, Edge, or Firefox)

### Setup Development Environment

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/YOUR_USERNAME/vxui.git
   cd vxui
   ```
3. Install dependencies (none required, just V!)
4. Run tests:
   ```bash
   v test vxui_test.v
   ```

## 📋 Contribution Guidelines

### Reporting Bugs

Before creating a bug report:

1. Check if the bug is already reported in [Issues](https://github.com/kbkpbot/vxui/issues)
2. Ensure you're using the latest version
3. Try to isolate the problem

When reporting bugs, include:

- **OS and version** (e.g., Ubuntu 22.04, macOS 14, Windows 11)
- **V version** (`v --version`)
- **Browser and version**
- **Steps to reproduce**
- **Expected behavior**
- **Actual behavior**
- **Error messages or logs**

### Suggesting Features

Feature requests are welcome! Please:

1. Check existing issues first
2. Clearly describe the feature and its use case
3. Explain why it would be useful

### Code Contributions

#### Style Guide

- Follow [V Style Guide](https://docs.vlang.io/concepts/style-guide.html)
- Run `v fmt -w .` before committing
- Keep functions small and focused
- Add comments for public functions
- Write tests for new features

#### Commit Messages

Use clear, descriptive commit messages:

```
type: subject

body (optional)

footer (optional)
```

Types:
- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `style:` Code formatting (no logic change)
- `refactor:` Code restructuring
- `test:` Adding tests
- `chore:` Maintenance tasks

Examples:
```
feat: add Firefox browser support
fix: handle websocket disconnection gracefully
docs: update README with Windows instructions
```

#### Pull Request Process

1. Create a new branch:
   ```bash
   git checkout -b feature/my-feature
   ```

2. Make your changes and add tests

3. Ensure all tests pass:
   ```bash
   v test vxui_test.v
   ```

4. Format code:
   ```bash
   v fmt -w .
   ```

5. Commit your changes:
   ```bash
   git commit -m "feat: add new feature"
   ```

6. Push to your fork:
   ```bash
   git push origin feature/my-feature
   ```

7. Create a Pull Request on GitHub

### Pull Request Checklist

- [ ] Code follows V style guide
- [ ] Code is formatted with `v fmt`
- [ ] Tests pass (`v test vxui_test.v`)
- [ ] New features have tests
- [ ] Documentation is updated (if needed)
- [ ] Commit messages are clear
- [ ] PR description explains the changes

## 🏗️ Project Structure

```
vxui/
├── browser.v      # Browser detection and launching
├── router.v       # Routing logic
├── utils.v        # Utility functions
├── vxui.v         # Core WebSocket server
├── vxui_test.v    # Test suite
└── examples/      # Example applications
```

## 🔒 Security

If you discover a security vulnerability:

1. **DO NOT** open a public issue
2. Email the maintainer directly: [kbkpbot@gmail.com](mailto:kbkpbot@gmail.com)
3. Include details about the vulnerability
4. Allow time for a fix before public disclosure

## 💬 Community

- GitHub Issues: Bug reports and feature requests
- GitHub Discussions: General questions and discussions

## 📜 Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md).

By participating, you agree to uphold this code.

## 🙏 Recognition

Contributors will be recognized in our README and release notes.

Thank you for contributing to vxui!
