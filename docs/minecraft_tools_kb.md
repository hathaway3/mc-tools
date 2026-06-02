# Knowledge Base: Minecraft Debian Installer Tool

This document captures context, design patterns, and engineering details for the Proxmox Debian Minecraft Installer project. It serves as a brief context window for subsequent agent updates to conserve tokens.

---

## Technical Context

- **Target Host OS**: Debian (optimized for Proxmox VE VMs).
- **Installed Packages**: `curl`, `wget`, `jq` (JSON parsing), `gnupg` (key management), `screen` (console wrapping), `unzip`, `lsb-release` (optional release info helper), `unattended-upgrades` (automated security patches), `qemu-guest-agent` (Proxmox integration), and `webmin` (web control panel).
- **Webmin Repository Setup**: Set up using Webmin's official installer script `setup-repos.sh` executed with the `-f` (force/non-interactive) flag.
- **Temurin JDK Repository**: Adoptium APT repository added via `deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb <codename> main`.

---

## Minecraft-to-JDK Mapping Rules

To support older Minecraft versions, the script checks the minor and patch numbers of the user-provided version string to install the correct Adoptium Temurin package:
- **Java 8** (`temurin-8-jdk`): Minecraft versions $\le$ `1.12` (essential for Forge $\le$ 1.12.2 due to classloader changes in Java 9+).
- **Java 11** (`temurin-11-jdk`): Minecraft versions `1.13` to `1.16`.
- **Java 17** (`temurin-17-jdk`): Minecraft versions `1.17` to `1.20.4`.
- **Java 21** (`temurin-21-jdk`): Minecraft versions $\ge$ `1.20.5`.

---

## Folder Layout Specification

- **Root / User Directory**: `/opt/minecraft` (system user/group `minecraft:minecraft`).
- **Instances Subdirectory**: `/opt/minecraft/instances`
- **Instance Folder**: `/opt/minecraft/instances/<instancename>`
- **Executables**:
  - Vanilla/Legacy Forge: `/opt/minecraft/instances/<instancename>/minecraft_server.jar`
  - Bedrock: `/opt/minecraft/instances/<instancename>/bedrock_server` (executable ELF binary)
  - Modern Forge: `/opt/minecraft/instances/<instancename>/run.sh`

---

## Systemd Architecture (Template + Overrides)

To avoid wrapper utilities, the project uses a single Systemd template with instance-specific drop-in overrides. This permits starting and stopping all servers uniformly using `systemctl start minecraft@<instance>`.

1. **Master Service Template**: `/etc/systemd/system/minecraft@.service`
   - Defines standard Java boot: `/usr/bin/screen -DmS mc-%i /usr/bin/java -Xmx4G -jar minecraft_server.jar nogui`
   - Incorporates your specific stop sequence (warning messages at 15s, 10s, 5s, `save-all`, and `stop` inside screen).
2. **Bedrock Drop-In Override**: `/etc/systemd/system/minecraft@<name>.service.d/override.conf`
   - Clears `ExecStart` and redefines it to `/usr/bin/screen -DmS mc-%i /bin/bash -c "LD_LIBRARY_PATH=. ./bedrock_server"`.
   - Clears `ExecStop` and redirects shutdown commands to screen ending with the `stop` command.
3. **Modern Forge Drop-In Override**: `/etc/systemd/system/minecraft@<name>.service.d/override.conf`
   - Clears `ExecStart` and redefines it to `/usr/bin/screen -DmS mc-%i /bin/bash run.sh` (which references memory flags configured in `user_jvm_args.txt`).

---

## Essential Commands & Troubleshooting

### Screen Session Attachment
Because the services run as the unprivileged `minecraft` user, the screen socket is owned by `minecraft`. Root sessions cannot directly attach with `screen -r mc-<name>`. 
- **Attach Command**:
  ```bash
  sudo -u minecraft script /dev/null -c "screen -r mc-<name>"
  ```
  *(The `script /dev/null` prefix is required to allocate a pseudo-terminal owned by the target user, which avoids terminal permission errors).*

### Forge Server Setup Details
- The Forge installer is executed in headless mode: `java -jar installer.jar --installServer`.
- For Forge $\ge$ `1.17`, running the installer generates a `run.sh` and `user_jvm_args.txt`. The script modifies `user_jvm_args.txt` to include `-Xmx4G`.
- For older Forge versions, the generated jar file is moved/renamed to `minecraft_server.jar` to match the default Java template.

### Bedrock Server Setup Details
- The latest Bedrock URL is fetched via: `https://net-secondary.web.minecraft-services.net/api/v1.0/download/links`
- Since Mojang does not host arbitrary archived Bedrock builds, if a requested version's download fails with 404, the script prompts the user to enter a custom download URL.

---

## GoDaddy DNS Tool

The project includes an optional script `update-godaddy-dns.sh` to map domain names to the Minecraft server port:
- **A Record**: Maps the root domain or a subdomain (e.g. `mc`) to the VM's public IP.
- **SRV Record**: Maps `_minecraft._tcp.[subdomain]` to point to the A record on the target port.
- **Root Domain Handling**: If `@` is selected as the subdomain, it target-points to `${DOMAIN}` directly instead of `${SUBDOMAIN}.${DOMAIN}` and uses `_minecraft._tcp` as the SRV name.
- **GoDaddy API Endpoints**:
  - `PUT /v1/domains/{domain}/records/A/{name}`
  - `PUT /v1/domains/{domain}/records/SRV/{name}`
- **Payload format**: GoDaddy expects an array containing objects with `data`, `port`, `priority`, `protocol`, `service`, `ttl`, `weight` parameters.
