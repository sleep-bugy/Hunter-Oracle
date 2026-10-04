# Hunter-Oracle

> **Automated 24/7 OCI API Hunter for Oracle Cloud Ampere A1 (ARM64) Always Free Instances.**

An autonomous, lightweight background daemon that continuously queries the Oracle Cloud Infrastructure (OCI) API across all Availability Domains to immediately claim an **Ampere A1 (ARM64)** compute instance the exact moment host capacity becomes available.

---

## Table of Contents

- [Why Hunter-Oracle?](#why-hunter-oracle)
- [Key Features](#key-features)
- [Instance Modes & Resource Allocation](#instance-modes--resource-allocation)
- [Prerequisites](#prerequisites)
- [Where to Find Oracle Cloud Credentials (Console Navigation Guide)](#where-to-find-oracle-cloud-credentials-console-navigation-guide)
  - [1. Tenancy / Compartment OCID](#1-tenancy--compartment-ocid)
  - [2. User OCID](#2-user-ocid)
  - [3. API Signing Key and Fingerprint](#3-api-signing-key-and-fingerprint)
  - [4. Virtual Cloud Network (VCN) & Public Subnet OCID](#4-virtual-cloud-network-vcn--public-subnet-ocid)
  - [5. SSH Public Key](#5-ssh-public-key)
  - [6. Telegram Notifications (Optional)](#6-telegram-notifications-optional)
- [Quick Start Guide](#quick-start-guide)
  - [Step 1: Clone the Repository](#step-1-clone-the-repository)
  - [Step 2: Install OCI CLI](#step-2-install-oci-cli)
  - [Step 3: Configure `oracle-hunter.sh`](#step-3-configure-oracle-huntersh)
  - [Step 4: Test Run](#step-4-test-run)
- [Running 24/7 as a Background Service (Systemd)](#running-247-as-a-background-service-systemd)
  - [Option A: User-Level Service (No Root / Sudo Required - Recommended)](#option-a-user-level-service-no-root--sudo-required---recommended)
  - [Option B: System-Wide Service (Root / Sudo)](#option-b-system-wide-service-root--sudo)
- [FAQ & Troubleshooting](#faq--troubleshooting)

---

## Why Hunter-Oracle?

Oracle Cloud Infrastructure (OCI) offers one of the most generous Always Free tiers in the industry:
- **Up to 4 OCPU** (Ampere Altra ARM64)
- **24 GB RAM**
- **200 GB Boot Storage**
- **Free Public IPv4 Address**

Because of high demand, trying to create an Ampere A1 VM manually through the Oracle Web Console almost always fails with:
```
Out of host capacity.
```
**Hunter-Oracle** solves this by polling the OCI API programmatically every few seconds, sweeping through all Availability Domains, automatically handling API rate limits, and securing your VM as soon as capacity is freed up.

---

## Key Features

- **Ubuntu Minimal ARM by Default**: Automatically discovers and provisions the latest **Ubuntu 24.04 Minimal ARM** (or 22.04 Minimal ARM) for a clean, bloat-free system that boots fast and consumes minimal RAM.
- **Smart Capacity Retry**: Distinguishes between normal capacity shortage (`OutOfHostCapacity`) and configuration errors, gracefully retrying without spamming.
- **Rate-Limit & 429 Cooldown**: Automatically detects OCI API rate limits (`TooManyRequests / 429`) and pauses for a 60-second cooldown window to prevent account throttling.
- **Duplicate Prevention**: Checks if your instance is already running before making launch calls, preventing accidental multiple VM launches.
- **Instant Telegram Alerts**: Sends a formatted alert with the instance name, OCID, specifications, Availability Domain, and OS directly to your Telegram chat upon successful creation.
- **Rootless Systemd Daemon**: Can be installed as a standard user systemd service (`systemctl --user`) with lingering enabled—no root or sudo password required on your hunting machine.

---

## Instance Modes & Resource Allocation

Oracle Cloud allows free tier accounts up to **4 OCPU** and **24 GB RAM** total for Ampere A1. You can configure the resource allocation in `oracle-hunter.sh`:

| Mode | OCPU | RAM | Best For |
| :---: | :---: | :---: | :--- |
| **`MODE=1`** | **2 OCPU** | **12 GB** | **(Recommended)** Balanced single VM; leaves headroom for another 2 OCPU / 12 GB instance later. |
| **`MODE=2`** | **1 OCPU** | **6 GB** | Lightweight instance; allows you to run up to four separate instances across accounts/regions. |
| **`MODE=3`** | **4 OCPU** | **24 GB** | **Max Power**: Allocates the entire Always Free Ampere capacity into a single powerhouse VM. |

---

## Prerequisites

1. An active **Oracle Cloud Infrastructure (OCI)** account.
2. A machine that stays online 24/7 (local Debian/Ubuntu server, Raspberry Pi, homelab, or cheap VPS).
3. **OCI CLI** (`oci`) installed and authenticated.
4. An SSH key pair on your machine (`~/.ssh/id_ed25519.pub` or `~/.ssh/id_rsa.pub`).

---

## Where to Find Oracle Cloud Credentials (Console Navigation Guide)

To configure the hunter, you need a few IDs from your Oracle Cloud Console. Follow the exact paths below:

### 1. Tenancy / Compartment OCID
- Log in to [Oracle Cloud Console](https://cloud.oracle.com/).
- Click the **Profile icon** in the top right corner.
- Click **Tenancy: `<your_tenancy_name>`**.
- Under **Tenancy Information**, look for **OCID** and click **Copy**.
- *(Note: If you use the root compartment, your Compartment OCID is identical to your Tenancy OCID).*

### 2. User OCID
- Click the **Profile icon** in the top right corner.
- Click **My Profile** (or **User Settings**).
- Under the **User Information** tab, find **OCID** and click **Copy**.

### 3. API Signing Key and Fingerprint
- In **My Profile / User Settings**, scroll down to the **Resources** menu on the left side.
- Click **API Keys**.
- Click **Add API Key**.
- Choose **Generate API Key Pair**.
- Click **Download Private Key** (save this as `~/.oci/oci_api_key.pem` on your hunting machine).
- Click **Add**.
- A dialog will show a configuration preview containing your `fingerprint`, `tenancy`, `user`, and `region`. Copy or verify this in `~/.oci/config`.
- Set safe permissions on the private key:
  ```bash
  chmod 600 ~/.oci/oci_api_key.pem
  ```

### 4. Virtual Cloud Network (VCN) & Public Subnet OCID
Your instance needs a subnet with an internet gateway to receive a public IP address:
1. Click the **Navigation Menu (☰ hamburger icon)** at the top left corner.
2. Navigate to **Networking** ➔ **Virtual Cloud Networks**.
3. Ensure your compartment is selected.
4. Click on your existing VCN (e.g. `9router-vcn`).
   *(If you don't have one, click **Start VCN Wizard** ➔ select **Create VCN with Internet Connectivity** ➔ click **Start VCN Wizard** and finish).*
5. On your VCN details page, look at the **Subnets** list.
6. Click on your **Public Subnet** (e.g. `public subnet-...`).
7. Under **Subnet Information**, find **OCID** and click **Copy**.

### 5. SSH Public Key
Ensure you have an SSH key pair generated on your machine:
```bash
ssh-keygen -t ed25519 -C "oracle-a1-key"
```
The public key will be located at:
```bash
~/.ssh/id_ed25519.pub
```

### 6. Telegram Notifications (Optional)
Receive a ping the second your VM is captured:
- **Bot Token**: Open Telegram, search for `@BotFather`, send `/newbot`, and copy the API token.
- **Chat ID**: Message `@userinfobot` or `@raw_data_bot` on Telegram to get your numeric user ID (e.g. `5354946036`), or use a group Chat ID (e.g. `-1003774416163`). Make sure your bot is added to the group first!
- **Topic ID / Thread ID (Supergroups with Forum Topics)**: If sending to a specific topic inside a forum supergroup, copy the link of any message in that topic (e.g. `https://t.me/c/3774416163/14431/14432`). The first number after `/c/<chat_id>/` is your `TELEGRAM_TOPIC_ID` (or topic creation `message_id`).

---

## Quick Start Guide

### Step 1: Clone the Repository
```bash
git clone git@github.com:sleep-bugy/Hunter-Oracle.git
cd Hunter-Oracle
```

### Step 2: Install OCI CLI
If OCI CLI is not already installed on your machine, run the official installer:
```bash
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
```
Configure your credentials:
```bash
oci setup config
```
*Provide your User OCID, Tenancy OCID, Region (e.g. `ap-batam-1`), and path to your private key `~/.oci/oci_api_key.pem`.*

Verify the setup:
```bash
oci iam availability-domain list
```

### Step 3: Configure `oracle-hunter.sh`
Open `oracle-hunter.sh` in your text editor:
```bash
nano oracle-hunter.sh
```
Fill in the required fields:
```bash
COMPARTMENT_ID="ocid1.tenancy.oc1..your_tenancy_or_compartment_ocid"
SUBNET_ID="ocid1.subnet.oc1.your_public_subnet_ocid"

MODE=1  # 1 = 2 OCPU / 12 GB, 2 = 1 OCPU / 6 GB, 3 = 4 OCPU / 24 GB

# Optional Telegram notifications
TELEGRAM_BOT_TOKEN="your_bot_token"
TELEGRAM_CHAT_ID="your_chat_id"
```

### Step 4: Test Run
Test the hunter directly in your terminal:
```bash
chmod +x oracle-hunter.sh
./oracle-hunter.sh
```
You will see output similar to:
```
[2026-10-05 00:45:00] Checking for existing instance...
[2026-10-05 00:45:01] Fetching Availability Domains...
[2026-10-05 00:45:02] Availability Domains found: HnRA:AP-BATAM-1-AD-1
[2026-10-05 00:45:03] Searching for Ubuntu 24.04 Minimal ARM image...
[2026-10-05 00:45:04] Selected OS Image: Canonical-Ubuntu-24.04-Minimal-aarch64-2026.09.18-0
[2026-10-05 00:45:05] ==================================================
[2026-10-05 00:45:05] Oracle A1 Always Free Autopilot Started
[2026-10-05 00:45:05] Shape   : VM.Standard.A1.Flex
[2026-10-05 00:45:05] RAM     : 12 GB
[2026-10-05 00:45:05] OCPU    : 2
[2026-10-05 00:45:05] OS      : Canonical-Ubuntu-24.04-Minimal-aarch64-2026.09.18-0
[2026-10-05 00:45:05] ==================================================
[2026-10-05 00:45:06] Attempt #1 | AD=HnRA:AP-BATAM-1-AD-1 | 2 OCPU / 12 GB RAM
[2026-10-05 00:45:10] Host capacity exhausted in HnRA:AP-BATAM-1-AD-1 → Retrying in 20s...
```

---

## Running 24/7 as a Background Service (Systemd)

Run the included automated installer script:
```bash
chmod +x install.sh
./install.sh
```

The installer intelligently determines whether you are running as a regular user or as root:

### Option A: User-Level Service (No Root / Sudo Required - Recommended)
When run without `sudo`, it creates a user systemd service in `~/.config/systemd/user/oracle-a1-autopilot.service` and enables process lingering:

- **Start Hunter:**
  ```bash
  systemctl --user start oracle-a1-autopilot
  ```
- **Check Status:**
  ```bash
  systemctl --user status oracle-a1-autopilot
  ```
- **View Live Logs:**
  ```bash
  journalctl --user -u oracle-a1-autopilot -f
  ```
- **Stop Hunter:**
  ```bash
  systemctl --user stop oracle-a1-autopilot
  ```

*(Even when you close your SSH terminal, the service continues running in the background).*

### Option B: System-Wide Service (Root / Sudo)
If executed with root privileges (`sudo ./install.sh`):

- **Start Hunter:**
  ```bash
  sudo systemctl start oracle-a1-autopilot
  ```
- **View Live Logs:**
  ```bash
  sudo journalctl -u oracle-a1-autopilot -f
  ```
- **Stop Hunter:**
  ```bash
  sudo systemctl stop oracle-a1-autopilot
  ```

---

## FAQ & Troubleshooting

### Q: Why do I see `Out of host capacity`?
**A:** This is standard for Oracle Ampere A1 instances in popular regions. Demand exceeds current hardware availability. Let the script run in the background; whenever another user releases capacity or Oracle adds nodes, the script will claim it within seconds.

### Q: What is `429 TooManyRequests`?
**A:** Oracle Cloud enforces API request rate limits. If too many calls are made within a short period, Oracle responds with HTTP 429. **Hunter-Oracle** automatically handles this by activating a 60-second cooldown period, after which it safely resumes hunting.

### Q: How do I SSH into the VM after it is created?
**A:** Check your Telegram alert or the OCI Console for your instance's Public IP address. Then connect using the username `ubuntu` and your SSH private key:
```bash
ssh -i ~/.ssh/id_ed25519 ubuntu@<PUBLIC_IP_ADDRESS>
```

### Q: How do I know when the VM is created?
**A:** Once launched, the hunter automatically logs `🎉 SUCCESS!`, triggers your Telegram bot alert, and exits cleanly so it does not launch unwanted duplicate instances.

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
