# Minecraft & Webmin Debian VM Installer

A comprehensive, interactive installer script designed to set up and manage Minecraft servers (Vanilla Java, Bedrock Dedicated, and Forge Modded) and Webmin administration panel on a Debian VM (specifically optimized for Proxmox).

---

## What the Script Installs

1. **System Tools & Optimization**:
   - `unattended-upgrades`: Sets up automatic, unattended security updates for Debian.
   - `qemu-guest-agent`: Integrates the VM with the Proxmox VE host for accurate status reporting, memory ballooning control, and graceful shutdown commands.
   - Utilities: `curl`, `wget`, `jq`, `gnupg`, `screen`, `unzip`, and `lsb-release`.
2. **Webmin Administration Panel**:
   - Automatically sets up Webmin's official repository keys and sources.
   - Installs the latest stable Webmin release, accessible at `https://<Your_Server_IP>:10000/`.
3. **Eclipse Temurin JDK**:
   - Configures official Adoptium package signing keys and repositories.
   - Dynamically installs the correct LTS or version-specific Temurin JDK based on the Minecraft version selected:
     - Minecraft ≤ 1.12 $\rightarrow$ Java 8 (`temurin-8-jdk`)
     - Minecraft 1.13 to 1.16 $\rightarrow$ Java 11 (`temurin-11-jdk`)
     - Minecraft 1.17 to 1.20.4 $\rightarrow$ Java 17 (`temurin-17-jdk`)
     - Minecraft 1.20.5+ $\rightarrow$ Java 21 (`temurin-21-jdk`)

---

## Folder Layout

The script organizes files under a structured layout to support multiple concurrent server instances cleanly:

```
/opt/minecraft/                 <-- User Home Directory
├── instances/                  <-- Main Directory for Instances
│   ├── server1/                <-- Instance 1 (e.g. Java Vanilla)
│   │   ├── minecraft_server.jar
│   │   ├── eula.txt
│   │   └── server.properties
│   ├── server2/                <-- Instance 2 (e.g. Modern Forge)
│   │   ├── run.sh
│   │   ├── user_jvm_args.txt   <-- Modifies memory flags here (-Xmx4G)
│   │   ├── eula.txt
│   │   └── mods/
│   └── server3/                <-- Instance 3 (e.g. Bedrock Dedicated)
│       ├── bedrock_server
│       └── server.properties
```

---

## How to Install and Run

1. **Upload the Script**:
   Copy [setup-minecraft.sh](setup-minecraft.sh) to your target Debian VM.

2. **Make it Executable**:
   ```bash
   chmod +x setup-minecraft.sh
   ```

3. **Run as Root**:
   ```bash
   sudo ./setup-minecraft.sh
   ```

4. **Respond to Prompts**:
   - Select your server type (Java, Bedrock, or Forge).
   - Input your instance name (e.g. `server1` or `survival`).
   - Enter your Minecraft version (e.g. `1.20.4`).
   - Choose whether to enable and start the instance immediately.

---

## Managing Instances (Systemd)

Instances are managed via a master Systemd template (`minecraft@.service`) combined with instance-specific drop-in overrides to run Bedrock and Forge seamlessly.

### Core Commands
Use the standard Systemd syntax, replacing `<instance_name>` with your custom instance folder name:

*   **Start a server**:
    ```bash
    sudo systemctl start minecraft@<instance_name>
    ```
*   **Stop a server** (gracefully announces to players and saves the world over 15 seconds):
    ```bash
    sudo systemctl stop minecraft@<instance_name>
    ```
*   **Restart a server**:
    ```bash
    sudo systemctl restart minecraft@<instance_name>
    ```
*   **Enable auto-start on boot**:
    ```bash
    sudo systemctl enable minecraft@<instance_name>
    ```
*   **Disable auto-start on boot**:
    ```bash
    sudo systemctl disable minecraft@<instance_name>
    ```
*   **Check status**:
    ```bash
    sudo systemctl status minecraft@<instance_name>
    ```

---

## Accessing the Server Console (Screen)

Minecraft instances run in detached `screen` sessions under a dedicated non-privileged system user (`minecraft`) for security. 

### How to Attach to Console
To view active terminal output or issue console commands (such as `/op`, `/gamemode`, etc.):

Run the following command as `root` (or using `sudo`):
```bash
sudo -u minecraft script /dev/null -c "screen -r mc-<instance_name>"
```
*(Using `script /dev/null` opens a pseudo-terminal owned by the `minecraft` user to prevent any TTY permission denied errors).*

### How to Detach safely
To close the console view without shutting down the Minecraft server:
- Press `Ctrl + A`, then press `D`.
- This detaches the screen and leaves it running in the background.

---

## Adjusting Server Memory

- **Vanilla Java & Older Forge**: Memory allocation is governed by the template file `/etc/systemd/system/minecraft@.service`. By default, it is configured with `-Xmx4G`.
- **Modern Forge (1.17+)**: Memory is configured in the instance's directory within `/opt/minecraft/instances/<instance_name>/user_jvm_args.txt`. Open this file and adjust the `-Xmx4G` line.

---

## Updating GoDaddy DNS (Optional)

If you use GoDaddy to manage your domain, you can use the secondary script [update-godaddy-dns.sh](update-godaddy-dns.sh) to automatically map a subdomain (or root domain) and port configuration to your server's public IP address using A and SRV records.

### How it works
1. **A Record**: Maps your subdomain (e.g. `mc.yourdomain.com`) to the public IP of your VM.
2. **SRV Record**: Maps the `_minecraft._tcp.mc` service definition to point to the A record on your Minecraft server's specific port. This enables players to connect with just `mc.yourdomain.com` without typing the port (even if running on a non-standard port!).

### How to Run
1. Make the script executable:
   ```bash
   chmod +x update-godaddy-dns.sh
   ```
2. Run the script:
   ```bash
   ./update-godaddy-dns.sh
   ```
3. Enter your GoDaddy API credentials (API Key and Secret can be created at the [GoDaddy Developer Portal](https://developer.godaddy.com/keys)).

---

## License

This project is licensed under the Apache License, Version 2.0. See the [LICENSE](LICENSE) file for the full license text.
