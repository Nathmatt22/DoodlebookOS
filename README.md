<p align="center">
  <img src=".github/assets/banner_logo.jpg" alt="DoodlebookOS" width="500">
</p>

<h3 align="center">Material 3 Expressive Desktop Suite for KDE Plasma 6</h3>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPLv3-blue.svg" alt="License: GPL v3"></a>
  <a href="https://kde.org"><img src="https://img.shields.io/badge/KDE_Plasma-6.8.2%2B-blue?logo=kde&logoColor=white" alt="KDE Plasma"></a>
  <a href="https://wayland.freedesktop.org"><img src="https://img.shields.io/badge/Display-Wayland-brightgreen" alt="Wayland"></a>
  <a href="https://ko-fi.com/panoptikuum"><img src="https://img.shields.io/badge/Support_on-Ko--fi-ff5e5b?logo=kofi&logoColor=white" alt="Support on Ko-fi"></a>
</p>

<p align="center">
  <a href="#key-features">Key Features</a> •
  <a href="#system-prerequisites">Prerequisites</a> •
  <a href="#installation">Installation</a> •
  <a href="#switching-dark--light-mode">Usage</a> •
  <a href="#uninstallation--restoring-backups">Uninstall</a> •
  <a href="#roadmap-to-beta-v10">Roadmap</a>
</p>

**DoodlebookOS** is a comprehensive Material 3 Expressive desktop environment suite crafted natively for **KDE Plasma 6 on Wayland**. It recreates the clean, unified Android PC / GooglebookOS-inspired desktop experience featuring custom QML plasmoids, native C++ application styles and window decorations, real-time wallpaper contrast adaptation, dedicated icon personalizers, and a guided graphical setup wizard.

<p align="center">
  <img src=".github/assets/screenshot_01_desktop.png" alt="DoodlebookOS Desktop Preview" width="100%">
</p>

> [!WARNING]
> **Experimental Early Alpha Release**  
> DoodlebookOS is currently in active early alpha development and has been developed and tested exclusively on my single reference hardware configuration. Expect bugs, visual glitches, or potential installation failures on different hardware or software configurations. **Do not install this on mission-critical production systems.**

> [!IMPORTANT]
> **Strongly Recommended: Fresh Installation or Clean User Account**  
> I strongly advise testing DoodlebookOS on a **freshly installed Linux system** or a **dedicated new user account** (`sudo useradd -m testuser`). Running the installer on an established desktop with existing customizations or conflicting panel setups may lead to unpredictable results or break your existing desktop layout.

---

### Live Demonstrations & Showcase

| Application Launcher | Quick Settings Drawer |
| :---: | :---: |
| <img src=".github/assets/demo_launcher.gif" width="100%" alt="Application Launcher Demo"> | <img src=".github/assets/demo_quicksettings.gif" width="100%" alt="Quick Settings Drawer Demo"> |

| Desktop Application Folders | Single-Column Calendar |
| :---: | :---: |
| <img src=".github/assets/demo_appgroup.gif" width="100%" alt="Desktop Folders Demo"> | <img src=".github/assets/demo_calendar.gif" width="100%" alt="Calendar Demo"> |

| Material 3 Context Menu & Widgets | Notification Center |
| :---: | :---: |
| <img src=".github/assets/screenshot_09_context_menu.jpg" width="100%" alt="Material 3 Context Menu and Desktop Widgets"> | <img src=".github/assets/demo_notifications.gif" width="100%" alt="Notification Center Demo"> |

| OOBE Setup Wizard (Welcome) | OOBE Setup Wizard (Compiling) |
| :---: | :---: |
| <img src=".github/assets/screenshot_07_installer_welcome.png" width="100%" alt="Installer Welcome"> | <img src=".github/assets/screenshot_08_installer_progress.png" width="100%" alt="Installer Progress"> |

---

## Display Compatibility: Single Monitor Recommended

- **Single Display (Tested & Recommended):** DoodlebookOS is architected, tested, and calibrated exclusively for a single monitor.
- **Multi-Monitor Setups (Untested / Experimental):** Multi-display behavior is currently completely untested and unsupported. Panels and widget positioning may not behave correctly across multiple displays.

---

## System Prerequisites

| Requirement | Specification | Notes |
| :--- | :--- | :--- |
| **Reference Platform (Tier 1)** | **Fedora 45 (KDE Plasma Desktop Edition)** | The exact reference environment where DoodlebookOS is developed and verified. |
| **Desktop Environment** | **KDE Plasma 6.8.2+** | **Plasma 5 is not supported** (Qt6 / KF6 architecture required). |
| **Display Server** | **Wayland** | **Wayland session is required**. X11 is not supported due to Wayland layer-shell popups and fractional scaling. |
| **Other Distros (Experimental)** | **Arch Linux**, **openSUSE Tumbleweed**, **KDE neon / Kubuntu 26.10+** | Community testing tier; requires up-to-date Qt6/KF6 packages and may need manual dependency resolution. |
| **Virtual Machines (VM)** | **3D Acceleration Required (`VirtIO-GPU` / `VirGL`)** | Required when testing in QEMU/KVM, Boxes, or VirtualBox for KWin Wayland compositing and real-time top bar luminance sampling. |

> [!NOTE]
> **Debian 13 (trixie) and other Plasma 6.0–6.7 systems:** Debian 13 ships KDE Plasma 6.3.6 with Qt 6.8 and KDE Frameworks 6.13. The suite installs and runs there, but a few Plasma internals introduced in 6.4+ are missing, so the desktop folder view falls back to a compatibility mode (KRunner type-ahead search stays disabled). `install.sh` installs the distribution's split KDE QML module packages automatically — without them the custom widgets cannot load at all.

---

## 🔰 New to Linux? Start Here

If you do not have Linux installed yet, you can try DoodlebookOS on a clean setup by following these simple steps:

1. **Download Fedora KDE:** Grab the official ISO for [Fedora KDE Desktop Edition](https://fedoraproject.org/spins/kde/).
2. **Create a Bootable USB:** Flash the downloaded ISO to a USB flash drive using a tool like [Fedora Media Writer](https://fedoraproject.org/workstation/download) or [Balena Etcher](https://etcher.balena.io/).
3. **Install Fedora:** Boot from the USB drive and complete the guided installation.
4. **Install DoodlebookOS:** Boot into your fresh Fedora desktop and follow the [Graphical Setup Wizard](#1-graphical-setup-wizard-recommended) instructions below.

---

## What the Installer Does & System Permissions

Here is exactly what the installer does on your computer and why:

### 1. Administrator Privileges (`sudo` / `pkexec`)
Administrator privileges are requested during the prerequisite phase only for:
- **System Build & Runtime Dependencies:** Installs required development packages (`cmake`, `ninja`, Qt6/KF6 compilation headers, `python3-pyside6`, `python3-pillow`) through your distribution's native package manager (`dnf`, `pacman`, `apt-get`, or `zypper`).
- **Klipper Clipboard Override:** Backs up the system `KlipperPopup.qml` (located in `/usr/lib64/qt6/qml/org/kde/plasma/private/clipboard/` or `/usr/lib/qt6/qml/...` depending on your distro) to `.orig` and installs the Material 3 masonry clipboard popup override (`Meta+V`). *(Note: Major system updates to `plasma-workspace` may overwrite this file; re-running the installer will restore the custom popup).*

### 2. User-Space Installation (`~/.local/`)
Apart from the Klipper clipboard override above, all core components are compiled and installed strictly in your user space:
- **Plasmoids & Containments:** Installed into `~/.local/share/plasma/plasmoids/`.
- **C++ Native Plugins:** Compiled via `cmake` and installed into `~/.local/lib64/` or `~/.local/lib/` (Application Style `doodlebookos6.so`, Window Decoration `org.doodlebookos.decoration.so`, and Applet bindings).
- **Themes & Assets:** Installed into `~/.local/share/` (Plasma desktop themes, color schemes, cursors, fonts, wallpapers).
- **Desktop Tools:** `Icon Studio` installed to `~/.local/bin/doodlebook-icon-studio`.

### 3. Automated Configuration Backup
Before any panel layout or theme configuration is altered, the installer creates an automatic snapshot of your existing KDE configuration in:
```text
~/.config/doodlebookos-backups/latest
```
You can restore your original desktop configuration at any time by running `./uninstall.sh`.

---

## Key Features

- **Unified Top Bar:**
  - **DateTime (`org.doodlebookos.datetime`):** Top-left pill featuring clean typography and a single-column Material You monthly calendar popup.
  - **StatusCluster (`org.doodlebookos.statuscluster`):** Top-right status pill integrating media controls, notification center (`org.freedesktop.Notifications`), and an Android-style Quick Settings drawer (Wi-Fi, Bluetooth, Dark Mode, Battery Saver, Mic mute, Screenshot, Quick Share).
  - **Adaptive Wallpaper Contrast (`doodlebookos-topbar-color`):** Background daemon that analyzes the wallpaper luminance directly behind top bar pills and dynamically adjusts foreground contrast (dark vs. light text and icons).
- **Material 3 Shelf Dock:**
  - **Dock (`org.doodlebookos.dock`):** Centered application shelf with live window indicators, pin management, a full-screen Material You launcher (`Meta`), and a KDE Connect **Phone Hub** integration.
- **Material 3 Desktop Widgets:**
  - **Cookie Analog Clock:** 12-sided cookie clock with curved hands and minute dots.
  - **Live Weather Widget:** Open-Meteo live weather widget with automatic IP geolocation.
  - **Desktop Application Folders:** Desktop application folder bubbles (`AppGroup`) with live item previews.
  - **Desktop Containment (`org.kde.desktopcontainment`):** Simplified right-click menu with a live wallpaper carousel.
- **Native Tools & System Overrides:**
  - **Icon Studio (`doodlebook-icon-studio`):** Dedicated PySide6 / QML tool for personalizing application, PWA, and launcher icons.
  - **Material 3 Masonry Clipboard:** System clipboard popup (`Meta+V`) with full rich-text, image preview, and pin management.
- **Native Themes & Window Styling:**
  - Custom Qt6/KF6 application style (`DoodlebookOS`) with smooth hover animations.
  - Native KDecoration3 C++ window decoration (`org.doodlebookos.decoration`).
  - Google Sans Flex variable typography and dual color schemes (`DoodlebookOS_LIGHT` and `DoodlebookOS_DARK`).

---

## Installation

### 1. Graphical Setup Wizard (Recommended)

Clone the repository and run the guided OOBE installer:

```bash
git clone https://github.com/PanOptikuum/DoodlebookOS.git
cd DoodlebookOS
chmod +x install-gui.sh
./install-gui.sh
```

Alternatively, double-click `DoodlebookOS-Installer.desktop` in your file manager.

### 2. Command-Line Installer

For headless or automated installations:

```bash
git clone https://github.com/PanOptikuum/DoodlebookOS.git
cd DoodlebookOS
chmod +x install.sh
./install.sh
```

---

## Switching Dark & Light Mode

You can toggle between Dark and Light mode at any time using the Quick Settings **Dark theme** tile in the top-right Status Cluster, or via the command line (if `~/.local/bin` is in your `$PATH`, you can run `dostheme` directly):

```bash
~/.local/bin/dostheme toggle   # Toggle between Dark and Light mode
~/.local/bin/dostheme dark     # Switch to DoodlebookOS Dark
~/.local/bin/dostheme light    # Switch to DoodlebookOS Light
```

---

## Uninstallation & Restoring Backups

To completely remove DoodlebookOS and restore your previous KDE Plasma panels, themes, and configuration:

```bash
./uninstall.sh
```

The uninstaller will:
1. Stop and disable background daemons (`doodlebookos-topbar.service`).
2. Restore your original system clipboard files from `.orig` backups.
3. Remove user-space plasmoids, C++ libraries, themes, and icons.
4. Restore your previous KDE configuration from `~/.config/doodlebookos-backups/latest`.
5. Restart Plasma Shell to return you directly to your previous desktop.

### Recovering a failed desktop load

If Plasma reports **“an error occurred while loading DoodlebookOS Desktop”**, the desktop containment override could not be loaded by the installed Plasma version. From a terminal, drop the override and restart the shell:

```bash
rm -rf ~/.local/share/plasma/plasmoids/{org.kde.desktopcontainment,org.kde.plasma.folder,DoodlebookOS-Desktop}
systemctl --user restart plasma-plasmashell
```

Your panels, widgets and settings are untouched; run `./install.sh` again after updating the repository, or `./uninstall.sh` to go back to your previous configuration.

---

## Roadmap to Beta (v1.0)

- [ ] **Multi-monitor independent panels:** Independent per-monitor panel replication and configuration.
- [ ] **Expanded desktop widget ecosystem:** UpNext agenda widget and native Material 3 system resource monitor.
- [ ] **KDE System Settings KCM:** Dedicated graphical configuration module integrated directly into KDE System Settings.
- [ ] **Package repository distribution:** Official AUR (Arch) and COPR (Fedora) packages.

---

## Support & Community

If you enjoy DoodlebookOS and want to support its ongoing development, consider buying me a coffee!

[![Support on Ko-fi](https://img.shields.io/badge/Support_on-Ko--fi-ff5e5b?style=for-the-badge&logo=kofi&logoColor=white)](https://ko-fi.com/panoptikuum)

- **Discussions & Ideas:** Join the conversation in [GitHub Discussions](https://github.com/PanOptikuum/DoodlebookOS/discussions).
- **Bug Reports:** Report issues using the [Issue Templates](https://github.com/PanOptikuum/DoodlebookOS/issues).

---

## Repository Structure

- [`widgets/`](widgets/README.md) — 8 custom KDE Plasma 6 QML applets and desktop containment
- [`themes/`](themes/README.md) — C++ application style, KDecoration3 window decoration, Plasma styles, and Global Look-and-Feel
- [`system-overrides/`](system-overrides/README.md) — KRunner DBus bridge and Klipper masonry clipboard override
- [`extras/`](extras/README.md) — Cursors, Google Sans Flex font, wallpapers, and background contrast daemons
- [`tools/`](tools/icon-studio/README.md) — Icon Studio personalizer
- [`installer/`](installer/) — PySide6 & QML graphical installer wizard and installation backend

---

## License

- **DoodlebookOS Code, Applets & Themes:** Licensed under the [GNU General Public License v3.0 or later](LICENSE).
- **Fonts (`Google Sans Flex`):** Licensed under the [SIL Open Font License 1.1](extras/fonts/GoogleSansFlex/OFL.txt).

---

## Disclaimer

DoodlebookOS is an independent open-source project and is not affiliated with, sponsored, or endorsed by Google LLC. ChromeOS, Chromebook, Pixel, Android, and Material You / Material Design are trademarks of Google LLC.
