# Contributing Guide 📘

Welcome to **PyzhCraft**
This guide helps you contribute effectively and keep changes easy to review

---

## 1. Code of Conduct ✨

- Be respectful, constructive, and professional
- Keep communication clear in issues and pull requests
- Welcome contributors from all backgrounds and skill levels

---

## 2. Reporting Issues 🐞

When you find a bug or want to suggest an improvement:

1. Open a new issue on GitHub
2. Use a clear title, for example: `[BUG] Crash on macOS 14.1 - Java path not found`
3. Include:
   - OS version
   - PyzhCraft version (release or commit hash)
   - Reproduction steps, expected behavior, and actual behavior
   - Logs or screenshots when possible

---

## 3. Submitting Code (Pull Requests) 🚀

1. Fork the repository and sync with the latest `dev` branch
2. Create a feature branch from `dev`, for example `feature/fix-java-path`
3. Keep changes focused and small
4. Write clear commit messages with a verb, for example `Fix Java detection on macOS`
5. Run local checks before pushing
6. Open a pull request targeting `dev`
7. In the PR description, include:
   - Why the change is needed
   - What changed
   - Screenshots or logs when relevant

---

## 4. Code Style & Quality 🌱

- Language: Swift with SwiftUI
- Follow Swift naming conventions and keep identifiers clear
- Add comments for public APIs or complex logic
- Respect the project structure
- Add tests when appropriate
- Handle edge cases safely

---

## 5. Branching Rules 🌲

- `dev` is the main development branch
- Create feature branches from `dev`
- Open pull requests with `dev` as the base branch

---

## 6. Local Development Setup 💻

- Use an Xcode version compatible with the project
- Ensure your Swift version matches project requirements
- Install a compatible Java runtime for launcher features
- Build, run, and test locally before submitting

---

## 7. Merging & Releases 📦

- Maintainers review pull requests before merging into `dev`
- Stable versions are tagged and released from `dev`
- Releases are validated to avoid major regressions

---

## 8. Thanks 💖

Every issue, pull request, and suggestion helps improve PyzhCraft
