## FAQ

This document is still evolving
If you find a problem and know the fix, open a pull request: [Pull Requests](https://github.com/suhang12332/Swift-Craft-Launcher/pulls)

---

### What is PyzhCraft

PyzhCraft is a Swift-based Minecraft launcher project focused on development, learning, and community collaboration

---

### What environment is required

- macOS 14+

---

### Common software issues

Q: I cannot add an account (after using versions older than `b2.0.0`)

A: Run this command in Terminal, then restart the launcher:

```bash
defaults delete com.su.code.PyzhCraft savedPlayers
```

Q: The resource list (mods, datapacks, and more) does not load, or resource install fails

A: Check these in order:
1. Verify your network can access Modrinth
2. Verify a game version is installed

Q: I cannot install a game version

A: Add an account first

---

### What should I do if I find a bug

- Search existing issues first
- If no match exists, open a new issue and include logs/screenshots

### Can I contribute code

Yes
Read the [Contributing Guide](../CONTRIBUTING.md), then fork, create a branch, and open a pull request

### How can I contact maintainers

- QQ group (recommended)
- GitHub issues

---

If something is missing from this FAQ, contributions are welcome
