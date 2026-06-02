# Contributing to Minecraft & Webmin Debian VM Installer

First off, thank you for considering contributing to this project! It's people like you who make the open-source community a better place.

---

## Code of Conduct

By participating in this project, you are expected to maintain a polite, respectful, and collaborative environment.

---

## How Can I Contribute?

### Reporting Bugs
If you find a bug (such as an installer error on a specific Debian version or a download resolver failure), please open a GitHub Issue and include:
- The exact error output.
- Your Debian version (e.g. Debian 12 Bookworm, Debian 13 Trixie).
- The Minecraft edition and version you selected during setup.

### Proposing Enhancements
If you want to add support for a new feature (like restoring the Proxmox VM description update hook, adding backup scripts, or supporting other system managers), please open an Issue first to discuss the design.

### Pull Requests
To submit a code change:
1. Fork the repository and create a new branch from `main`.
2. Implement your changes.
3. Verify your shell script syntax locally (see below).
4. Commit your changes and open a Pull Request.

---

## Development & Code Verification

Before committing any modifications to `setup-minecraft.sh`, please verify the script syntax using the following command:

```bash
# Basic syntax and parsing check
bash -n setup-minecraft.sh
```

Additionally, our CI/CD pipeline runs **ShellCheck** on all PRs. You can verify your script against ShellCheck locally if you have it installed:
```bash
shellcheck setup-minecraft.sh
```

---

## Coding Style Guidelines
- **Portability**: Keep commands as standard and portable across Debian/Ubuntu derivatives as possible.
- **Robustness**: Maintain `set -Eeuo pipefail` settings where appropriate and handle potential individual command failures gracefully with inline validation or cleanups.
- **Clean output**: Use the color variables defined in the script (`${BLUE}`, `${GREEN}`, `${RED}`) to format console feedback and ensure commands run silently when appropriate (e.g. using `-q` or `>/dev/null` for package setup, redirections, or curls).
