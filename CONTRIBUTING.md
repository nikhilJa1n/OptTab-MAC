# Contributing to AdvancedDock

Thank you for your interest in contributing to AdvancedDock! Contributions are what make the open-source community such an amazing place to learn, inspire, and create.

---

## How Can I Contribute?

### 1. Reporting Bugs
*   Check the [Issues](https://github.com/yourusername/AdvancedDock/issues) page to see if the bug has already been reported.
*   If not, open a new issue. Clearly describe the problem, steps to reproduce, and your system specs (macOS version, Mac model).

### 2. Suggesting Enhancements
*   Open an issue with the tag `enhancement`.
*   Explain the feature you would like to see, why it is useful, and how it fits into the scope of the app.

### 3. Submitting Pull Requests
1.  Fork the repository.
2.  Create a feature branch (`git checkout -b feature/AmazingFeature`).
3.  Commit your changes (`git commit -m 'Add some AmazingFeature'`).
4.  Push to the branch (`git push origin feature/AmazingFeature`).
5.  Open a Pull Request against the `main` branch.

---

## Development Setup

AdvancedDock is a Swift Package Manager executable target.

1.  Open the workspace folder in Xcode (Xcode will automatically resolve targets using the `Package.swift` manifest).
2.  Use the `build.sh` script to bundle the application (`./build.sh`).
3.  Note that to capture screen thumbnails, you must run the app with developer signing (standard in `build.sh`).

---

## Code of Conduct

Please be respectful and welcoming in all community spaces and communication channels.
