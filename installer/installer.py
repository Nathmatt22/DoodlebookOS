#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# SPDX-FileCopyrightText: 2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
"""
DoodlebookOS — OOBE Setup Wizard (Alpha Release)
Applies the complete DoodlebookOS desktop preset automatically.
"""

import os
import re
import sys
import time
import json
import shutil
import subprocess
import datetime
from pathlib import Path

from PySide6.QtCore import QObject, Property, Signal, Slot, QThread, QUrl
from PySide6.QtGui import QGuiApplication, QFontDatabase, QIcon
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtDBus import QDBusInterface, QDBusConnection


DEFAULT_LAUNCHERS = (
    "preferred://browser,"
    "preferred://filemanager,"
    "applications:org.kde.konsole.desktop,"
    "applications:org.kde.discover.desktop,"
    "applications:systemsettings.desktop"
)


def hex_to_rgb_csv(hex_color: str) -> str:
    h = hex_color.lstrip("#")
    if len(h) == 6:
        r = int(h[0:2], 16)
        g = int(h[2:4], 16)
        b = int(h[4:6], 16)
        return f"{r},{g},{b}"
    return "66,133,244"


def find_system_applet_plugin(so_name: str) -> Path | None:
    """Locate a native KDE Plasma applet C++ plugin (.so) installed in the host system."""
    candidates = [
        Path(f"/usr/lib64/qt6/plugins/plasma/applets/{so_name}"),
        Path(f"/usr/lib/qt6/plugins/plasma/applets/{so_name}"),
        Path(f"/usr/lib/x86_64-linux-gnu/qt6/plugins/plasma/applets/{so_name}"),
        Path(f"/usr/lib/aarch64-linux-gnu/qt6/plugins/plasma/applets/{so_name}"),
    ]
    for p in candidates:
        if p.exists():
            return p
    return None


class InstallWorker(QThread):
    logAdded = Signal(str)
    progressChanged = Signal(float, str, str)
    finishedInstall = Signal(bool, str)
    displayScaleChanged = Signal()

    def __init__(
        self,
        repo_dir: Path,
        opt_panels: bool = True,
        opt_theme: bool = True,
        opt_fonts: bool = True,
        opt_wallpaper: bool = True,
        opt_qol: bool = True,
        accent_mode: str = "scheme",
        accent_hex: str = "#4285F4",
        is_pl: bool = False,
    ):
        super().__init__()
        self.repo_dir = repo_dir
        self.opt_panels = opt_panels
        self.opt_theme = opt_theme
        self.opt_fonts = opt_fonts
        self.opt_wallpaper = opt_wallpaper
        self.opt_qol = opt_qol
        self.accent_mode = accent_mode  # "scheme", "wallpaper", or "custom"
        self.accent_hex = accent_hex    # e.g. "#4285F4"
        self.is_pl = is_pl

    def log(self, msg: str):
        self.logAdded.emit(msg)

    def run_cmd(self, cmd, cwd=None, check=False):
        self.log(f"$ {' '.join(str(c) for c in cmd)}")
        try:
            proc = subprocess.Popen(
                [str(c) for c in cmd],
                cwd=str(cwd) if cwd else None,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
            )
            for line in proc.stdout:
                line_s = line.rstrip("\n")
                if line_s:
                    self.log("  " + line_s)
            proc.wait()
            if check and proc.returncode != 0:
                raise RuntimeError(f"Command exited with code {proc.returncode}")
            return proc.returncode == 0
        except Exception as e:
            self.log(f"[!] {e}")
            if check:
                raise
            return False

    def _dbus_evaluate_script(self, script_str: str) -> bool:
        """Send script directly over QtDBus socket (bypasses Linux 128KB CLI arg limit)."""
        try:
            bus = QDBusConnection.sessionBus()
            iface = QDBusInterface("org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", bus)
            if iface.isValid():
                reply = iface.call("evaluateScript", script_str)
                err = reply.errorMessage()
                if err:
                    self.log(f"[!] DBus evaluateScript warning: {err}")
                    return False
                self.log("[✓] Desktop layout script executed via QtDBus.")
                return True
        except Exception as e:
            self.log(f"[!] QtDBus evaluateScript exception: {e}")
        return False

    def _dbus_load_lnf_layout(self, pkg_id: str) -> bool:
        """Call org.kde.PlasmaShell.loadLookAndFeelDefaultLayout directly via QtDBus."""
        try:
            bus = QDBusConnection.sessionBus()
            iface = QDBusInterface("org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", bus)
            if iface.isValid():
                reply = iface.call("loadLookAndFeelDefaultLayout", pkg_id)
                err = reply.errorMessage()
                if not err:
                    self.log(f"[✓] Loaded Global Theme desktop layout ({pkg_id}) via DBus.")
                    return True
                self.log(f"[!] loadLookAndFeelDefaultLayout warning: {err}")
        except Exception as e:
            self.log(f"[!] loadLookAndFeelDefaultLayout exception: {e}")
        return False

    def _detect_optimal_scale(self, out: dict) -> float:
        """Detect optimal Wayland display scale for an output using PPI, resolution and laptop protection."""
        modes = out.get("modes", [])
        curr_mode_id = str(out.get("currentModeId", ""))
        active_mode = None
        for m in modes:
            if str(m.get("id")) == curr_mode_id:
                active_mode = m
                break
        if not active_mode and modes:
            active_mode = modes[0]

        native_w = active_mode.get("size", {}).get("width", 1920) if active_mode else 1920
        native_h = active_mode.get("size", {}).get("height", 1080) if active_mode else 1080

        size_mm = out.get("sizeMM", {})
        mm_w = float(size_mm.get("width", 0))
        mm_h = float(size_mm.get("height", 0))

        diag_inch = 0.0
        ppi = 0.0
        if mm_w > 0 and mm_h > 0:
            w_in = mm_w / 25.4
            h_in = mm_h / 25.4
            diag_inch = (w_in ** 2 + h_in ** 2) ** 0.5
            ppi = native_w / w_in

        # Fallback for VMs or missing/corrupted EDID
        if mm_w <= 0 or diag_inch < 9.0 or diag_inch > 60.0 or ppi < 40:
            if native_h <= 1080:
                return 1.0
            elif native_h <= 1600:
                return 1.25
            else:
                return 1.5

        if ppi < 105:
            return 1.0
        elif ppi <= 135:
            return 1.25
        elif ppi <= 165:
            if native_h <= 1200:
                return 1.25
            return 1.5
        else:
            if native_h >= 2160:
                return 1.75 if diag_inch > 24 else 2.0
            return 1.5

    def _apply_display_scaling(self):
        """Detect and apply optimal Wayland display scale per output and configure XWayland sharpness."""
        if not self.opt_theme:
            return
        if shutil.which("kwriteconfig6"):
            self.run_cmd(["kwriteconfig6", "--file", "kwinrc", "--group", "Xwayland", "--key", "XwaylandClientsScale", "true"])
        if not shutil.which("kscreen-doctor"):
            return
        try:
            raw_ks = subprocess.check_output(["kscreen-doctor", "-j"], text=True)
            ks_data = json.loads(raw_ks)
            applied = False
            for out in ks_data.get("outputs", []):
                if out.get("connected") and out.get("name"):
                    scale = self._detect_optimal_scale(out)
                    out_name = out["name"]
                    curr_scale = float(out.get("scale", 1.0))
                    if abs(curr_scale - scale) > 0.01:
                        self.log(f"[i] Selecting optimal Wayland scale for {out_name}: {scale:.2f} (was {curr_scale:.2f})")
                        self.run_cmd(["kscreen-doctor", f"output.{out_name}.scale.{scale}"])
                        applied = True
            if applied:
                time.sleep(0.5)
                self.displayScaleChanged.emit()
        except Exception as e:
            self.log(f"[!] kscreen-doctor auto-scaling error: {e}")

    def _apply_accent_color(self):
        """Configure KDE Plasma 6 accent color: from current color scheme by default, or wallpaper/custom preset."""
        if self.accent_mode == "scheme":
            self.log("[i] Setting KDE Plasma accent color: from current color scheme (DoodlebookOS_LIGHT)...")
            if shutil.which("kwriteconfig6"):
                self.run_cmd([
                    "kwriteconfig6", "--file", "kdeglobals", "--group", "General",
                    "--key", "accentColorFromWallpaper", "--type", "bool", "false"
                ])
                self.run_cmd([
                    "kwriteconfig6", "--file", "kdeglobals", "--group", "General",
                    "--key", "AccentColor", "--delete"
                ])
            if shutil.which("plasma-apply-colorscheme"):
                self.run_cmd(["plasma-apply-colorscheme", "DoodlebookOS_LIGHT"])
        elif self.accent_mode == "wallpaper":
            self.log("[i] Setting KDE Plasma accent color: from current wallpaper...")
            if shutil.which("kwriteconfig6"):
                self.run_cmd([
                    "kwriteconfig6", "--file", "kdeglobals", "--group", "General",
                    "--key", "accentColorFromWallpaper", "--type", "bool", "true"
                ])
            try:
                bus = QDBusConnection.sessionBus()
                ps_iface = QDBusInterface("org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell", bus)
                if ps_iface.isValid():
                    c_reply = ps_iface.call("color")
                    if c_reply.arguments():
                        val = int(c_reply.arguments()[0])
                        r = (val >> 16) & 0xFF
                        g = (val >> 8) & 0xFF
                        b = val & 0xFF
                        hex_col = f"#{r:02x}{g:02x}{b:02x}"
                        acc_iface = QDBusInterface("org.kde.kded6", "/AccentColor", "org.kde.plasmashell.accentColor", bus)
                        if acc_iface.isValid():
                            acc_iface.call("setAccentColor", val)
                        if shutil.which("plasma-apply-colorscheme"):
                            self.run_cmd(["plasma-apply-colorscheme", "DoodlebookOS_LIGHT"])
                            self.run_cmd(["plasma-apply-colorscheme", "-a", hex_col])
                        if shutil.which("kwriteconfig6"):
                            self.run_cmd([
                                "kwriteconfig6", "--file", "kdeglobals", "--group", "General",
                                "--key", "accentColorFromWallpaper", "--type", "bool", "true"
                            ])
            except Exception as e:
                self.log(f"[!] Could not get wallpaper color via DBus: {e}")
        else:
            rgb_csv = hex_to_rgb_csv(self.accent_hex)
            self.log(f"[i] Setting custom Material 3 Expressive accent color: {self.accent_hex} ({rgb_csv})...")
            if shutil.which("kwriteconfig6"):
                self.run_cmd([
                    "kwriteconfig6", "--file", "kdeglobals", "--group", "General",
                    "--key", "accentColorFromWallpaper", "--delete"
                ])
                self.run_cmd([
                    "kwriteconfig6", "--file", "kdeglobals", "--group", "General",
                    "--key", "LastUsedCustomAccentColor", rgb_csv
                ])
                self.run_cmd([
                    "kwriteconfig6", "--file", "kdeglobals", "--group", "General",
                    "--key", "AccentColor", rgb_csv
                ])
            if shutil.which("plasma-apply-colorscheme"):
                self.run_cmd(["plasma-apply-colorscheme", "DoodlebookOS_LIGHT"])
                self.run_cmd(["plasma-apply-colorscheme", "-a", self.accent_hex])

        if shutil.which("dbus-send"):
            self.run_cmd([
                "dbus-send", "--type=signal", "/KGlobalSettings",
                "org.kde.KGlobalSettings.notifyChange", "int32:0", "int32:0"
            ])

    def _resolve_default_launchers(self, raw_launchers: str) -> str:
        """Resolve generic URLs like preferred://browser to actual installed desktop files for stable task matching."""
        items = [x.strip() for x in raw_launchers.split(",") if x.strip()]
        resolved = []
        for it in items:
            if it == "preferred://browser":
                b_app = ""
                try:
                    out = subprocess.check_output(["xdg-settings", "get", "default-web-browser"], text=True).strip()
                    if out and out.endswith(".desktop"):
                        b_app = f"applications:{out}"
                except Exception:
                    pass
                if not b_app:
                    for cand in ["firefox.desktop", "org.mozilla.firefox.desktop", "google-chrome.desktop", "chromium.desktop"]:
                        for p in [Path("/usr/share/applications"), Path.home() / ".local/share/applications"]:
                            if (p / cand).exists():
                                b_app = f"applications:{cand}"
                                break
                        if b_app:
                            break
                resolved.append(b_app if b_app else it)
            elif it == "preferred://filemanager":
                if Path("/usr/share/applications/org.kde.dolphin.desktop").exists():
                    resolved.append("applications:org.kde.dolphin.desktop")
                else:
                    resolved.append(it)
            else:
                resolved.append(it)
        return ",".join(resolved)

    def _extract_existing_user_lists(self, appletsrc: Path) -> str:
        """Preserve user's pinned dock launchers if already present."""
        launchers = DEFAULT_LAUNCHERS
        if not appletsrc.exists():
            return self._resolve_default_launchers(launchers)
        try:
            txt = appletsrc.read_text(encoding="utf-8", errors="ignore")
            has_doodle_dock = ("org.doodlebookos.dock" in txt) or ("DoodlebookOS-Dock" in txt)
            m_launch = re.search(r"^launchers=(.+)$", txt, re.MULTILINE)
            if has_doodle_dock and m_launch and m_launch.group(1).strip():
                # Filter out legacy removed PWA desktop shortcuts if upgrading
                raw_items = [x.strip() for x in m_launch.group(1).strip().split(",") if x.strip()]
                legacy_pwas = {
                    "applications:gemini.desktop",
                    "applications:gmail.desktop",
                    "applications:google-calendar.desktop",
                    "applications:youtube.desktop",
                    "applications:google-photos.desktop",
                }
                filtered = [x for x in raw_items if x not in legacy_pwas]
                if filtered:
                    launchers = ",".join(filtered)
        except Exception as e:
            self.log(f"[!] Could not read previous app lists: {e}")
        return self._resolve_default_launchers(launchers)

    def run(self):
        try:
            home = Path.home()
            total_steps = 6.0
            step = 0.0

            def advance(pl_text: str, en_text: str):
                nonlocal step
                step += 1.0
                self.progressChanged.emit(min(0.96, step / total_steps), pl_text, en_text)
                self.log(f"\n=== {en_text} ===")

            # Save user's pinned dock apps BEFORE modifying layout
            appletsrc = home / ".config" / "plasma-org.kde.plasma.desktop-appletsrc"
            saved_launchers = self._extract_existing_user_lists(appletsrc)

            # 1. Automatic Backup
            advance(
                "Tworzenie kopii zapasowej obecnego pulpitu...",
                "Backing up your current desktop configuration...",
            )
            ts = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
            backup_dir = home / ".config" / "doodlebookos-backups" / ts
            backup_dir.mkdir(parents=True, exist_ok=True)
            for fname in [
                "plasmarc",
                "kdeglobals",
                "kwinrc",
                "plasmashellrc",
                "kglobalshortcutsrc",
                "kcminputrc",
                "klaunchrc",
                "plasma-org.kde.plasma.desktop-appletsrc",
            ]:
                src = home / ".config" / fname
                if src.exists():
                    shutil.copy2(src, backup_dir / fname)
            latest_link = home / ".config" / "doodlebookos-backups" / "latest"
            if latest_link.exists() or latest_link.is_symlink():
                latest_link.unlink()
            latest_link.symlink_to(backup_dir)
            self.log(f"[✓] Backup saved to: {backup_dir}")

            # 2. Configure QT_PLUGIN_PATH
            advance(
                "Konfigurowanie ścieżek wtyczek KDE Plasma 6...",
                "Configuring KDE Plasma 6 plugin paths...",
            )
            env_d = home / ".config" / "environment.d"
            env_d.mkdir(parents=True, exist_ok=True)
            plugin_path = (
                f"{home}/.local/lib64/qt6/plugins:{home}/.local/lib64/plugins:"
                f"{home}/.local/lib/qt6/plugins:{home}/.local/lib/plugins:"
                "/usr/lib64/qt6/plugins:/usr/lib/qt6/plugins:/usr/lib/x86_64-linux-gnu/qt6/plugins"
            )
            (env_d / "10-qt-plugins.conf").write_text(f"QT_PLUGIN_PATH={plugin_path}\n", encoding="utf-8")
            os.environ["QT_PLUGIN_PATH"] = plugin_path
            if shutil.which("systemctl"):
                self.run_cmd(["systemctl", "--user", "set-environment", f"QT_PLUGIN_PATH={plugin_path}"])
            if shutil.which("dbus-update-activation-environment"):
                self.run_cmd(["dbus-update-activation-environment", "--systemd", f"QT_PLUGIN_PATH={plugin_path}"])

            # 3. Fonts (Google Sans Flex), DoodlebookOS-Cursors, Wallpapers & Topbar Color Helper
            advance(
                "Instalowanie czcionki Google Sans Flex, kursorów i tapet...",
                "Installing Google Sans Flex font, cursors, and wallpapers...",
            )
            extras_dir = self.repo_dir / "extras"
            if self.opt_fonts:
                f_src = extras_dir / "fonts" / "GoogleSansFlex"
                if f_src.exists():
                    d_fonts = home / ".local" / "share" / "fonts" / "GoogleSansFlex"
                    d_fonts.mkdir(parents=True, exist_ok=True)
                    for f in f_src.iterdir():
                        if f.is_file():
                            shutil.copy2(f, d_fonts / f.name)
                if shutil.which("fc-cache"):
                    self.run_cmd(["fc-cache", "-f", str(home / ".local" / "share" / "fonts")])

            # Cursors: DoodlebookOS-Cursors
            for c_name in ["DoodlebookOS-Cursors"]:
                cursor_src = extras_dir / "cursors" / c_name
                if cursor_src.exists():
                    for c_dir in [home / ".local" / "share" / "icons", home / ".icons"]:
                        c_dir.mkdir(parents=True, exist_ok=True)
                        dest_cursor = c_dir / c_name
                        if dest_cursor.exists() or dest_cursor.is_symlink():
                            if dest_cursor.is_symlink() or dest_cursor.is_file():
                                dest_cursor.unlink()
                            else:
                                shutil.rmtree(dest_cursor)
                        shutil.copytree(cursor_src, dest_cursor, symlinks=True)

            # Icon Theme: DoodlebookOS
            icon_src = extras_dir / "icons" / "DoodlebookOS"
            if icon_src.exists():
                icons_base = home / ".local" / "share" / "icons"
                icons_base.mkdir(parents=True, exist_ok=True)
                dest_icon = icons_base / "DoodlebookOS"
                if dest_icon.exists() or dest_icon.is_symlink():
                    if dest_icon.is_symlink() or dest_icon.is_file():
                        dest_icon.unlink()
                    else:
                        shutil.rmtree(dest_icon)
                shutil.copytree(icon_src, dest_icon, symlinks=True)

            # Wallpapers (DoodlebookOS Light & Dark)
            dest_wp_dir = home / ".local" / "share" / "wallpapers" / "DoodlebookOS"
            if self.opt_wallpaper:
                dest_wp_dir.mkdir(parents=True, exist_ok=True)
                wp_src_dir = extras_dir / "wallpapers"
                if wp_src_dir.exists():
                    for wp_f in wp_src_dir.iterdir():
                        if wp_f.is_file() and not wp_f.is_symlink():
                            shutil.copy2(wp_f, dest_wp_dir / wp_f.name)
                            # Create compatibility alias for .png <-> .jpeg
                            stem = wp_f.stem
                            if wp_f.suffix.lower() in [".jpeg", ".jpg"]:
                                png_alias = dest_wp_dir / f"{stem}.png"
                                if not png_alias.exists():
                                    try:
                                        png_alias.symlink_to(wp_f.name)
                                    except Exception:
                                        pass
                            elif wp_f.suffix.lower() == ".png":
                                jpeg_alias = dest_wp_dir / f"{stem}.jpeg"
                                if not jpeg_alias.exists():
                                    try:
                                        jpeg_alias.symlink_to(wp_f.name)
                                    except Exception:
                                        pass

            # Resolve wallpaper to apply: prefer Light over Dark, checking all common extensions
            wallpaper_dest = None
            for name in ["DoodlebookOS_Wallpaper_LIGHT", "DoodlebookOS_Wallpaper_DARK"]:
                for ext in [".jpeg", ".jpg", ".png", ".webp"]:
                    cand = dest_wp_dir / f"{name}{ext}"
                    if cand.exists():
                        wallpaper_dest = cand
                        break
                if wallpaper_dest:
                    break

            # Top bar color adapter helper & theme switcher
            bin_dir = home / ".local" / "bin"
            bin_dir.mkdir(parents=True, exist_ok=True)
            topbar_helper = extras_dir / "scripts" / "doodlebookos-topbar-color"
            if topbar_helper.exists():
                dest_helper = bin_dir / "doodlebookos-topbar-color"
                shutil.copy2(topbar_helper, dest_helper)
                dest_helper.chmod(0o755)
            theme_helper = extras_dir / "scripts" / "dostheme"
            if theme_helper.exists():
                dest_theme_helper = bin_dir / "dostheme"
                shutil.copy2(theme_helper, dest_theme_helper)
                dest_theme_helper.chmod(0o755)

            # KRunner Bridge Daemon (Launcher Replacement)
            bridge_src = self.repo_dir / "system-overrides" / "krunner-bridge" / "doodlebook-krunner-bridge.py"
            krunner_svc_src = self.repo_dir / "system-overrides" / "krunner-bridge" / "systemd" / "plasma-krunner.service"
            if bridge_src.exists():
                dest_bridge = bin_dir / "doodlebook-krunner-bridge.py"
                shutil.copy2(bridge_src, dest_bridge)
                dest_bridge.chmod(0o755)
            if krunner_svc_src.exists():
                user_systemd = home / ".config" / "systemd" / "user"
                user_systemd.mkdir(parents=True, exist_ok=True)
                shutil.copy2(krunner_svc_src, user_systemd / "plasma-krunner.service")

            # Icon Studio (Material 3 Icon Personalizer)
            icon_studio_dir = self.repo_dir / "tools" / "icon-studio"
            if icon_studio_dir.exists():
                dest_studio_dir = home / ".local" / "share" / "doodlebookos" / "icon-studio"
                if dest_studio_dir.exists():
                    shutil.rmtree(dest_studio_dir)
                shutil.copytree(icon_studio_dir, dest_studio_dir)
                wrapper_path = bin_dir / "doodlebook-icon-studio"
                wrapper_path.write_text(
                    "#!/usr/bin/env bash\n"
                    f'exec python3 "{dest_studio_dir}/icon_studio.py" "$@"\n',
                    encoding="utf-8"
                )
                wrapper_path.chmod(0o755)
                apps_dir = home / ".local" / "share" / "applications"
                apps_dir.mkdir(parents=True, exist_ok=True)
                dest_desktop = apps_dir / "doodlebook-icon-studio.desktop"
                desktop_content = (dest_studio_dir / "icon-studio.desktop").read_text(encoding="utf-8")
                desktop_content = re.sub(r"^Exec=.*", f"Exec={wrapper_path}", desktop_content, flags=re.MULTILINE)
                dest_desktop.write_text(desktop_content, encoding="utf-8")

            # 4. Themes: DoodlebookOS & Look and Feel
            advance(
                "Instalowanie motywu globalnego i stylu DoodlebookOS...",
                "Installing Global Theme and DoodlebookOS style...",
            )
            theme_src_dir = self.repo_dir / "themes" / "plasma-theme"
            dest_theme_base = home / ".local" / "share" / "plasma" / "desktoptheme"
            dest_theme_base.mkdir(parents=True, exist_ok=True)
            if theme_src_dir.exists():
                for pt in theme_src_dir.iterdir():
                    if pt.is_dir():
                        dest_t = dest_theme_base / pt.name
                        if not dest_t.is_symlink():
                            if dest_t.exists():
                                shutil.rmtree(dest_t)
                            shutil.copytree(pt, dest_t, symlinks=True)

            lnf_src = self.repo_dir / "themes" / "look-and-feel" / "DoodlebookOS"
            if lnf_src.exists():
                dest_lnf = home / ".local" / "share" / "plasma" / "look-and-feel" / "org.doodlebookos.desktop"
                dest_lnf.parent.mkdir(parents=True, exist_ok=True)
                if dest_lnf.exists():
                    shutil.rmtree(dest_lnf)
                shutil.copytree(lnf_src, dest_lnf)

            # Install Color Schemes (DoodlebookOS_DARK, DoodlebookOS_LIGHT)
            colors_src = self.repo_dir / "themes" / "color-schemes"
            if colors_src.exists():
                dest_colors = home / ".local" / "share" / "color-schemes"
                dest_colors.mkdir(parents=True, exist_ok=True)
                for cf in colors_src.iterdir():
                    if cf.is_file():
                        shutil.copy2(cf, dest_colors / cf.name)

            # Compile and Install DoodlebookOS Window Decoration (KDecoration3) and Application Style (KStyle)
            windeco_script = self.repo_dir / "themes" / "window-decoration" / "DoodlebookOS" / "build.sh"
            appstyle_script = self.repo_dir / "themes" / "app-style" / "DoodlebookOS" / "build.sh"
            if windeco_script.exists() or appstyle_script.exists():
                advance(
                    "Kompilowanie dekoracji okien i stylu aplikacji C++...",
                    "Compiling C++ window decoration and application style...",
                )
                if windeco_script.exists():
                    self.run_cmd(["bash", str(windeco_script)], check=False)
                if appstyle_script.exists():
                    self.run_cmd(["bash", str(appstyle_script)], check=False)

            # Clear SVG cache so theme updates immediately
            for cache_file in (home / ".cache").glob("plasma*"):
                if cache_file.is_file():
                    try:
                        cache_file.unlink()
                    except OSError:
                        pass

            # 5. Install Core QML Widgets
            advance(
                "Instalowanie widżetów DoodlebookOS...",
                "Installing DoodlebookOS widgets...",
            )
            plasmoids_dir = home / ".local" / "share" / "plasma" / "plasmoids"
            plasmoids_dir.mkdir(parents=True, exist_ok=True)

            def create_alias_symlink(alias_p: Path, target_p: Path):
                if alias_p.exists() or alias_p.is_symlink():
                    if alias_p.is_symlink() or alias_p.is_file():
                        alias_p.unlink()
                    else:
                        shutil.rmtree(alias_p)
                try:
                    alias_p.symlink_to(target_p)
                except Exception:
                    pass

            def plasma_qml_module_exists(module_uri: str) -> bool:
                rel = module_uri.replace(".", "/")
                for qml_root in (
                    Path("/usr/lib/x86_64-linux-gnu/qt6/qml"),
                    Path("/usr/lib/aarch64-linux-gnu/qt6/qml"),
                    Path("/usr/lib64/qt6/qml"),
                    Path("/usr/lib/qt6/qml"),
                ):
                    if (qml_root / rel).is_dir():
                        return True
                return False

            def adapt_notifications_import(dest_p: Path):
                """Plasma 6.6 turned the notifications applet into a real QML module; older
                releases register NotificationWindow under a private URI instead. QML has
                no conditional imports, so pick the one matching the running Plasma."""
                if dest_p.is_symlink():
                    return
                qml_file = dest_p / "contents" / "ui" / "notifications" / "NotificationPopup.qml"
                if not qml_file.is_file():
                    return
                modern = "import plasma.applet.org.kde.plasma.notifications as NotificationsApplet"
                legacy = "import org.kde.plasma.private.notifications as NotificationsApplet"
                text = qml_file.read_text(encoding="utf-8")
                if plasma_qml_module_exists("plasma.applet.org.kde.plasma.notifications"):
                    old, new = legacy, modern
                else:
                    old, new = modern, legacy
                if old in text:
                    qml_file.write_text(text.replace(old, new), encoding="utf-8")
                    self.log(f"[i] Notifications popup: import adapted to {new.split()[1]}")

            def copy_plasmoid_if_not_symlink(src_p: Path, dst_p: Path):
                if dst_p.is_symlink() and dst_p.resolve().exists():
                    self.log(f"[i] Keeping existing symlinked widget: {dst_p}")
                    return
                if dst_p.exists() or dst_p.is_symlink():
                    if dst_p.is_symlink() or dst_p.is_file():
                        dst_p.unlink()
                    else:
                        shutil.rmtree(dst_p)
                shutil.copytree(src_p, dst_p, symlinks=True)

            copy_plasmoid_if_not_symlink(
                self.repo_dir / "widgets" / "Dock",
                plasmoids_dir / "org.doodlebookos.dock",
            )
            create_alias_symlink(plasmoids_dir / "DoodlebookOS-Dock", plasmoids_dir / "org.doodlebookos.dock")

            copy_plasmoid_if_not_symlink(
                self.repo_dir / "widgets" / "StatusCluster",
                plasmoids_dir / "org.doodlebookos.statuscluster",
            )
            adapt_notifications_import(plasmoids_dir / "org.doodlebookos.statuscluster")
            create_alias_symlink(plasmoids_dir / "DoodlebookOS-StatusCluster", plasmoids_dir / "org.doodlebookos.statuscluster")

            copy_plasmoid_if_not_symlink(
                self.repo_dir / "widgets" / "DateTime",
                plasmoids_dir / "org.doodlebookos.datetime",
            )
            create_alias_symlink(plasmoids_dir / "DoodlebookOS-DateTime", plasmoids_dir / "org.doodlebookos.datetime")

            copy_plasmoid_if_not_symlink(
                self.repo_dir / "widgets" / "PanelSpacer",
                plasmoids_dir / "org.doodlebookos.panelspacer",
            )
            create_alias_symlink(plasmoids_dir / "DoodlebookOS-PanelSpacer", plasmoids_dir / "org.doodlebookos.panelspacer")

            copy_plasmoid_if_not_symlink(
                self.repo_dir / "widgets" / "Desktop",
                plasmoids_dir / "org.kde.desktopcontainment",
            )
            create_alias_symlink(plasmoids_dir / "org.kde.plasma.folder", plasmoids_dir / "org.kde.desktopcontainment")
            create_alias_symlink(plasmoids_dir / "DoodlebookOS-Desktop", plasmoids_dir / "org.kde.desktopcontainment")

            copy_plasmoid_if_not_symlink(
                self.repo_dir / "widgets" / "AppGroup",
                plasmoids_dir / "org.doodlebookos.appgroup",
            )
            create_alias_symlink(plasmoids_dir / "org.doodlebookos.folder", plasmoids_dir / "org.doodlebookos.appgroup")
            create_alias_symlink(plasmoids_dir / "DoodlebookOS-Folder", plasmoids_dir / "org.doodlebookos.appgroup")

            copy_plasmoid_if_not_symlink(
                self.repo_dir / "widgets" / "Clock",
                plasmoids_dir / "org.doodlebookos.clock",
            )
            create_alias_symlink(plasmoids_dir / "local.pixelclock", plasmoids_dir / "org.doodlebookos.clock")
            create_alias_symlink(plasmoids_dir / "DoodlebookOS-Clock", plasmoids_dir / "org.doodlebookos.clock")

            copy_plasmoid_if_not_symlink(
                self.repo_dir / "widgets" / "Weather",
                plasmoids_dir / "org.doodlebookos.weather",
            )
            create_alias_symlink(plasmoids_dir / "local.pixelweather", plasmoids_dir / "org.doodlebookos.weather")
            create_alias_symlink(plasmoids_dir / "DoodlebookOS-Weather", plasmoids_dir / "org.doodlebookos.weather")

            # Link native system C++ applet plugins for StatusCluster (notifications) and DateTime (digitalclock)
            plugin_target_dirs = [
                home / ".local" / "lib64" / "plugins" / "plasma" / "applets",
                home / ".local" / "lib64" / "qt6" / "plugins" / "plasma" / "applets",
                home / ".local" / "lib" / "plugins" / "plasma" / "applets",
                home / ".local" / "lib" / "qt6" / "plugins" / "plasma" / "applets",
            ]
            sys_notif_so = find_system_applet_plugin("org.kde.plasma.notifications.so")
            sys_clock_so = find_system_applet_plugin("org.kde.plasma.digitalclock.so")
            for pdir in plugin_target_dirs:
                pdir.mkdir(parents=True, exist_ok=True)
                if sys_notif_so:
                    create_alias_symlink(pdir / "org.doodlebookos.statuscluster.so", sys_notif_so)
                if sys_clock_so:
                    create_alias_symlink(pdir / "org.doodlebookos.datetime.so", sys_clock_so)

            # Disable native desktop right-click context menu so DoodlebookContextMenu handles it
            found_c_ids = {"0", "1", "27", "28", "184"}
            if appletsrc.exists():
                try:
                    rc_txt = appletsrc.read_text(encoding="utf-8", errors="ignore")
                    found_c_ids.update(re.findall(r"\[Containments\]\[([0-9]+)\]", rc_txt))
                except Exception:
                    pass
            for c_id in sorted(found_c_ids, key=lambda x: int(x) if x.isdigit() else 0):
                self.run_cmd([
                    "kwriteconfig6",
                    "--file", "plasma-org.kde.plasma.desktop-appletsrc",
                    "--group", "ActionPlugins",
                    "--group", c_id,
                    "--key", "RightButton;NoModifier", ""
                ])

            if shutil.which("kbuildsycoca6"):
                self.run_cmd(["kbuildsycoca6", "--noincremental"])

            # 6. Apply Desktop Layout, Global Theme, Accent Color, Fonts, Wallpaper & QOL
            advance(
                "Stosowanie układu pulpitu, motywu, kolorów akcentu i czcionek...",
                "Applying desktop layout, theme, accent color, and fonts...",
            )

            # Apply optimal display scaling and Xwayland sharpness before loading desktop layout
            self._apply_display_scaling()

            # 6a. Apply the Global Theme & Serialized Desktop Layout
            if self.opt_panels:
                layout_js_path = (
                    self.repo_dir
                    / "themes"
                    / "look-and-feel"
                    / "DoodlebookOS"
                    / "contents"
                    / "layouts"
                    / "org.kde.plasma.desktop-layout.js"
                )
                applied_via_lnf = False
                if shutil.which("plasma-apply-lookandfeel"):
                    applied_via_lnf = self.run_cmd([
                        "plasma-apply-lookandfeel",
                        "-a",
                        "org.doodlebookos.desktop",
                        "--resetLayout",
                    ])
                if not applied_via_lnf:
                    applied_via_lnf = self._dbus_load_lnf_layout("org.doodlebookos.desktop")
                if not applied_via_lnf and layout_js_path.exists():
                    raw_layout_js = (
                        "var oldPanels = panels(); for (var i = 0; i < oldPanels.length; ++i) { oldPanels[i].remove(); }\n"
                        + layout_js_path.read_text(encoding="utf-8")
                    )
                    self._dbus_evaluate_script(raw_layout_js)

                # Personalize newly created panels with preserved launchers & desktop widgets
                esc_launchers = json.dumps(saved_launchers)
                esc_wp = json.dumps(f"file://{wallpaper_dest}") if (self.opt_wallpaper and wallpaper_dest and wallpaper_dest.exists()) else '""'
                set_meta_str = "true" if self.opt_qol else "false"
                default_apps_json = json.dumps(json.dumps([
                    {"name": "Dolphin", "icon": "system-file-manager", "exec": "dolphin"},
                    {"name": "Konsole", "icon": "utilities-terminal", "exec": "konsole"},
                    {"name": "Discover", "icon": "plasmadiscover", "exec": "plasma-discover"},
                    {"name": "System Settings", "icon": "preferences-system", "exec": "systemsettings"},
                ]))

                fixup_js = f"""
                var allPanels = panels();
                for (var i = 0; i < allPanels.length; ++i) {{
                    var p = allPanels[i];
                    p.floating = false;
                    p.lengthMode = "fill";
                    if (p.location === "bottom") {{
                        p.height = 52;
                    }} else if (p.location === "top") {{
                        p.height = 32;
                        p.userBackgroundHints = 0;
                    }}
                    var ws = p.widgets();

                    for (var j = 0; j < ws.length; ++j) {{
                        var w = ws[j];
                        if (w.type === "org.doodlebookos.dock") {{
                            w.currentConfigGroup = ["General"];
                            w.writeConfig("launchers", {esc_launchers});
                            if ({set_meta_str}) {{
                                w.globalShortcut = "Meta";
                            }}
                        }}
                    }}
                }}

                var wpUrl = {esc_wp};
                var ds = desktops();
                for (var d = 0; d < ds.length; ++d) {{
                    var desk = ds[d];
                    if (wpUrl.length > 0) {{
                        desk.wallpaperPlugin = "org.kde.image";
                        desk.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
                        desk.writeConfig("Image", wpUrl);
                    }}
                    var sGeom = screenGeometry(desk.screen);
                    var sW = (sGeom && sGeom.width > 0) ? sGeom.width : 1920;
                    var sH = (sGeom && sGeom.height > 0) ? sGeom.height : 1080;
                    var topOffset = Math.round(sH * 0.05);
                    var glanceX = Math.round(sW * 0.05);

                    var deskWs = desk.widgets();
                    var hasClock = false;
                    var hasWeather = false;
                    var existingAppGroups = 0;
                    for (var k = 0; k < deskWs.length; ++k) {{
                        var wType = deskWs[k].type;
                        if (wType === "org.doodlebookos.clock" || wType === "local.pixelclock") hasClock = true;
                        if (wType === "org.doodlebookos.weather" || wType === "local.pixelweather") hasWeather = true;
                        if (wType === "org.doodlebookos.appgroup" || wType === "org.doodlebookos.folder") {{
                            existingAppGroups++;
                            deskWs[k].currentConfigGroup = ["General"];
                            if (!deskWs[k].readConfig("appsJson", "")) {{
                                deskWs[k].writeConfig("appsJson", {default_apps_json});
                            }}
                        }}
                    }}
                    if (!hasClock) {{
                        desk.addWidget("org.doodlebookos.clock", glanceX, topOffset + 16, 220, 220);
                    }}
                    if (!hasWeather) {{
                        desk.addWidget("org.doodlebookos.weather", glanceX, topOffset + 252, 220, 220);
                    }}
                    if (existingAppGroups === 0) {{
                        var colX = Math.round(sW - 130);
                        var fObj = desk.addWidget("org.doodlebookos.appgroup", colX, topOffset + 16, 90, 100);
                        if (fObj) {{
                            fObj.currentConfigGroup = ["General"];
                            fObj.writeConfig("folderTitle", "System");
                            fObj.writeConfig("appsJson", {default_apps_json});
                        }}
                    }}
                }}
                """
                self._dbus_evaluate_script(fixup_js)
                time.sleep(1.2)
                if appletsrc.exists():
                    try:
                        rc_txt = appletsrc.read_text(encoding="utf-8", errors="ignore")
                        for c_id in sorted(set(re.findall(r"\[Containments\]\[([0-9]+)\]", rc_txt)), key=lambda x: int(x) if x.isdigit() else 0):
                            self.run_cmd([
                                "kwriteconfig6",
                                "--file", "plasma-org.kde.plasma.desktop-appletsrc",
                                "--group", "ActionPlugins",
                                "--group", c_id,
                                "--key", "RightButton;NoModifier", ""
                            ])
                    except Exception:
                        pass

            # 6b. Wallpaper (apply before accent color so 'from wallpaper' extracts the new wallpaper's color)
            if self.opt_wallpaper and wallpaper_dest and wallpaper_dest.exists() and shutil.which("plasma-apply-wallpaperimage"):
                self.run_cmd(["plasma-apply-wallpaperimage", str(wallpaper_dest)])
                time.sleep(0.5)

            # 6c. Global Theme, Desktop Theme, Cursors & Hot Corners
            if self.opt_theme:
                plasma_theme = "DoodlebookOS_Light"
                if shutil.which("plasma-apply-desktoptheme"):
                    self.run_cmd(["plasma-apply-desktoptheme", plasma_theme])
                if shutil.which("kwriteconfig6"):
                    self.run_cmd(["kwriteconfig6", "--file", "plasmarc", "--group", "Theme", "--key", "name", plasma_theme])
                    self.run_cmd(["kwriteconfig6", "--file", "kdeglobals", "--group", "KDE", "--key", "SingleClick", "true"])
                    self.run_cmd(["kwriteconfig6", "--file", "kdeglobals", "--group", "KDE", "--key", "LookAndFeelPackage", "org.doodlebookos.desktop"])
                    self.run_cmd(["kwriteconfig6", "--file", "kdeglobals", "--group", "Icons", "--key", "Theme", "DoodlebookOS"])

                    # Disable KDE screen edges & electric borders / hot corners (Plasma 6 standard)
                    for edge in ["Top", "TopRight", "Right", "BottomRight", "Bottom", "BottomLeft", "Left", "TopLeft"]:
                        self.run_cmd(["kwriteconfig6", "--file", "kwinrc", "--group", "ScreenEdges", "--key", edge, "None"])
                        self.run_cmd(["kwriteconfig6", "--file", "kwinrc", "--group", "ElectricBorders", "--key", edge, "None"])
                    # Plasma 6 Overview & WindowView & TabBox edge triggers
                    self.run_cmd(["kwriteconfig6", "--file", "kwinrc", "--group", "Effect-overview", "--key", "BorderActivate", "9"])
                    self.run_cmd(["kwriteconfig6", "--file", "kwinrc", "--group", "Effect-overview", "--key", "GridBorderActivate", "9"])
                    self.run_cmd(["kwriteconfig6", "--file", "kwinrc", "--group", "Effect-overview", "--key", "TouchBorderActivate", "9"])
                    self.run_cmd(["kwriteconfig6", "--file", "kwinrc", "--group", "Effect-windowview", "--key", "BorderActivate", "9"])
                    self.run_cmd(["kwriteconfig6", "--file", "kwinrc", "--group", "Effect-windowview", "--key", "TouchBorderActivate", "9"])
                    self.run_cmd(["kwriteconfig6", "--file", "kwinrc", "--group", "TabBox", "--key", "BorderActivate", "9"])
                    self.run_cmd(["kwriteconfig6", "--file", "kwinrc", "--group", "TabBox", "--key", "TouchBorderActivate", "9"])
                    self.run_cmd(["kwriteconfig6", "--file", "kwinrc", "--group", "Plugins", "--key", "overviewEnabled", "false"])

                    # Native KDE Plasma 6 Motion & Animation effects (zero third-party dependencies)
                    for eff in ["scale", "squash", "maximize", "fadingpopups", "slidingpopups", "blur"]:
                        self.run_cmd(["kwriteconfig6", "--file", "kwinrc", "--group", "Plugins", "--key", f"{eff}Enabled", "true"])
                    # Disable third-party rounded corners effects if present (DoodlebookOS window decoration handles this natively)
                    for extra_eff in ["kwin4_effect_shapecorners", "shapecorners", "round-corners"]:
                        self.run_cmd(["kwriteconfig6", "--file", "kwinrc", "--group", "Plugins", "--key", f"{extra_eff}Enabled", "false"])

                    self.run_cmd(["kwriteconfig6", "--file", "kwinrc", "--group", "Effect-scale", "--key", "InScale", "0.85"])
                    self.run_cmd(["kwriteconfig6", "--file", "kwinrc", "--group", "Effect-scale", "--key", "OutScale", "0.85"])
                    self.run_cmd(["kwriteconfig6", "--file", "kwinrc", "--group", "Effect-blur", "--key", "BlurStrength", "5"])
                    self.run_cmd(["kwriteconfig6", "--file", "kwinrc", "--group", "Effect-blur", "--key", "NoiseStrength", "0"])
                    for touch_edge in ["Top", "Left", "Right", "Bottom"]:
                        self.run_cmd(["kwriteconfig6", "--file", "kwinrc", "--group", "TouchEdges", "--key", touch_edge, "None"])

                    # Disable bouncing cursor feedback
                    self.run_cmd(["kwriteconfig6", "--file", "klaunchrc", "--group", "BusyCursorSettings", "--key", "BusyCursorStyle", "false"])
                    self.run_cmd(["kwriteconfig6", "--file", "klaunchrc", "--group", "FeedbackStyle", "--key", "BusyCursor", "false"])

                    # Cursors
                    self.run_cmd(["kwriteconfig6", "--file", "kcminputrc", "--group", "Mouse", "--key", "cursorTheme", "DoodlebookOS-Cursors"])

                    # Window Decoration (DoodlebookOS) - activate only if compiled shared library exists
                    deco_so_1 = home / ".local" / "lib64" / "qt6" / "plugins" / "org.kde.kdecoration3" / "org.doodlebookos.decoration.so"
                    deco_so_2 = home / ".local" / "lib" / "qt6" / "plugins" / "org.kde.kdecoration3" / "org.doodlebookos.decoration.so"
                    if deco_so_1.exists() or deco_so_2.exists():
                        self.run_cmd(["kwriteconfig6", "--file", "kwinrc", "--group", "org.kde.kdecoration2", "--key", "library", "org.doodlebookos.decoration"])
                        self.run_cmd(["kwriteconfig6", "--file", "kwinrc", "--group", "org.kde.kdecoration2", "--key", "theme", "DoodlebookOS"])

                    # Application Style (DoodlebookOS) - activate only if compiled shared library exists
                    style_so_1 = home / ".local" / "lib64" / "qt6" / "plugins" / "styles" / "doodlebookos6.so"
                    style_so_2 = home / ".local" / "lib" / "qt6" / "plugins" / "styles" / "doodlebookos6.so"
                    if style_so_1.exists() or style_so_2.exists():
                        self.run_cmd(["kwriteconfig6", "--file", "kdeglobals", "--group", "KDE", "--key", "widgetStyle", "DoodlebookOS"])

                    # Reconfigure KWin to apply effect and decoration changes immediately
                    if shutil.which("qdbus-qt6"):
                        self.run_cmd(["qdbus-qt6", "org.kde.KWin", "/KWin", "org.kde.KWin.reconfigure"])
                        self.run_cmd(["qdbus-qt6", "org.kde.KWin", "/Effects", "org.kde.kwin.Effects.reconfigure"])
                    elif shutil.which("qdbus"):
                        self.run_cmd(["qdbus", "org.kde.KWin", "/KWin", "org.kde.KWin.reconfigure"])
                        self.run_cmd(["qdbus", "org.kde.KWin", "/Effects", "org.kde.kwin.Effects.reconfigure"])

            # Always apply the user's chosen Accent Color mode (Wallpaper vs Custom M3 Expressive)
            self._apply_accent_color()

            # 6d. System Fonts (Google Sans Flex)
            if self.opt_fonts and shutil.which("kwriteconfig6"):
                self.log("[i] Setting Google Sans Flex as the system font in all KDE sections...")
                for key, val in [
                    ("font", "Google Sans Flex,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"),
                    ("menuFont", "Google Sans Flex,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"),
                    ("smallestReadableFont", "Google Sans Flex,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"),
                    ("toolBarFont", "Google Sans Flex,9,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"),
                    ("wmFont", "Google Sans Flex,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"),
                    ("XftAntialias", "true"),
                    ("XftHintStyle", "hintslight"),
                    ("XftSubPixel", "rgb"),
                ]:
                    self.run_cmd(["kwriteconfig6", "--file", "kdeglobals", "--group", "General", "--key", key, val])
                self.run_cmd([
                    "kwriteconfig6", "--file", "kdeglobals", "--group", "WM",
                    "--key", "activeFont", "Google Sans Flex,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"
                ])
                if shutil.which("dbus-send"):
                    self.run_cmd([
                        "dbus-send", "--type=signal", "/KGlobalSettings",
                        "org.kde.KGlobalSettings.notifyChange", "int32:1", "int32:0"
                    ])

                fc_file = home / ".config" / "fontconfig" / "fonts.conf"
                if fc_file.exists():
                    try:
                        fc_txt = fc_file.read_text(encoding="utf-8")
                        if "<const>hintmedium</const>" in fc_txt:
                            fc_txt = fc_txt.replace("<const>hintmedium</const>", "<const>hintslight</const>")
                            fc_file.write_text(fc_txt, encoding="utf-8")
                    except Exception as e:
                        self.log(f"[!] Could not update fonts.conf: {e}")

            # 6e. QOL settings & Global Shortcuts
            if self.opt_qol and shutil.which("kwriteconfig6"):
                self.run_cmd(["kwriteconfig6", "--file", "plasmarc", "--group", "OSD", "--key", "Enabled", "false"])
                self.run_cmd(["kwriteconfig6", "--file", "plasmarc", "--group", "PlasmaToolTips", "--key", "Delay", "--", "-1"])
                self.run_cmd(["kwriteconfig6", "--file", "kdeglobals", "--group", "General", "--key", "ShowDesktopPreviewBanner", "false"])
                self.run_cmd(["kwriteconfig6", "--file", "kdeglobals", "--group", "KDE", "--key", "AnimationDurationFactor", "0.5"])

                # Klipper Clipboard popup shortcut: Meta+V
                self.run_cmd([
                    "kwriteconfig6", "--file", "kglobalshortcutsrc", "--group", "plasmashell",
                    "--key", "show-on-mouse-pos", "Meta+V,Meta+V,Show Clipboard Items at Mouse Position"
                ])

            qdbus_bin = shutil.which("qdbus-qt6") or shutil.which("qdbus6") or shutil.which("qdbus")
            if qdbus_bin:
                self.run_cmd([qdbus_bin, "org.kde.KWin", "/KWin", "reconfigure"])

            if shutil.which("systemctl"):
                self.log("[i] Stopping KDE Plasma shell to flush layout configuration...")
                subprocess.run(["systemctl", "--user", "stop", "plasma-plasmashell.service"], check=False)

            if appletsrc.exists():
                try:
                    rc_txt = appletsrc.read_text(encoding="utf-8", errors="ignore")
                    for c_id in sorted(set(re.findall(r"\[Containments\]\[([0-9]+)\]", rc_txt)), key=lambda x: int(x) if x.isdigit() else 0):
                        self.run_cmd([
                            "kwriteconfig6",
                            "--file", "plasma-org.kde.plasma.desktop-appletsrc",
                            "--group", "ActionPlugins",
                            "--group", c_id,
                            "--key", "RightButton;NoModifier", ""
                        ])
                except Exception:
                    pass

            if shutil.which("systemctl"):
                self.log("[i] Starting KDE Plasma shell (plasma-plasmashell.service)...")
                subprocess.run(["systemctl", "--user", "start", "plasma-plasmashell.service"], check=False)
                time.sleep(1.5)

            # Adapt top bar colors to wallpaper brightness
            topbar_bin = home / ".local" / "bin" / "doodlebookos-topbar-color"
            if topbar_bin.exists():
                self.run_cmd([str(topbar_bin)])

            # Install & enable doodlebookos-topbar and plasma-krunner systemd user daemons
            service_src = self.repo_dir / "extras" / "scripts" / "doodlebookos-topbar.service"
            if service_src.exists():
                user_systemd = home / ".config" / "systemd" / "user"
                user_systemd.mkdir(parents=True, exist_ok=True)
                shutil.copy2(service_src, user_systemd / "doodlebookos-topbar.service")
            if shutil.which("systemctl"):
                subprocess.run(["systemctl", "--user", "daemon-reload"], check=False)
                subprocess.run(["systemctl", "--user", "enable", "--now", "doodlebookos-topbar.service"], check=False)
                subprocess.run(["systemctl", "--user", "restart", "plasma-krunner.service"], check=False)

            self.progressChanged.emit(1.0, "Wszystko gotowe!", "All set!")
            self.finishedInstall.emit(True, "OK")
        except Exception as e:
            self.progressChanged.emit(0.0, f"Błąd: {e}", f"Error: {e}")
            self.finishedInstall.emit(False, str(e))


class InstallerBackend(QObject):
    logUpdated = Signal()
    progressUpdated = Signal()
    statusUpdated = Signal()
    busyChanged = Signal()
    installFinished = Signal(bool, str)
    restoreFinished = Signal(bool, str)
    displayScaleChanged = Signal()
    themeChanged = Signal()

    def __init__(self, repo_dir: Path):
        super().__init__()
        self.repo_dir = repo_dir
        self._logs = []
        self._progress = 0.0
        self._status_pl = "Gotowy do konfiguracji"
        self._status_en = "Ready to set up"
        self._busy = False
        self._is_dark = self._detect_is_dark()
        self._worker = None

    def _detect_is_dark(self) -> bool:
        try:
            res = subprocess.run(
                ["kreadconfig6", "--file", "kdeglobals", "--group", "General", "--key", "ColorScheme"],
                capture_output=True,
                text=True,
                check=False,
            )
            cs = res.stdout.strip().lower()
            if "dark" in cs:
                return True
        except Exception:
            pass
        return False

    @Property(bool, notify=themeChanged)
    def isDarkTheme(self) -> bool:
        return self._is_dark

    @Property(str, notify=logUpdated)
    def logText(self) -> str:
        return "\n".join(self._logs)

    @Property(float, notify=progressUpdated)
    def progress(self) -> float:
        return self._progress

    @Property(str, notify=statusUpdated)
    def statusPl(self) -> str:
        return self._status_pl

    @Property(str, notify=statusUpdated)
    def statusEn(self) -> str:
        return self._status_en

    @Property(bool, notify=busyChanged)
    def isBusy(self) -> bool:
        return self._busy

    def _append_log(self, line: str):
        self._logs.append(line)
        self.logUpdated.emit()
        try:
            cache_dir = Path.home() / ".cache"
            cache_dir.mkdir(parents=True, exist_ok=True)
            with open(cache_dir / "doodlebookos-installer.log", "a", encoding="utf-8") as lf:
                lf.write(line + "\n")
        except Exception:
            pass

    def _on_progress(self, val: float, pl_text: str, en_text: str):
        self._progress = val
        self._status_pl = pl_text
        self._status_en = en_text
        self.progressUpdated.emit()
        self.statusUpdated.emit()

    def _on_finished(self, ok: bool, msg: str):
        self._busy = False
        self._is_dark = self._detect_is_dark()
        self.themeChanged.emit()
        self.busyChanged.emit()
        self.installFinished.emit(ok, msg)

    @Slot(bool)
    def setDarkTheme(self, enable: bool):
        self._is_dark = enable
        self.themeChanged.emit()
        mode = "dark" if enable else "light"
        script = Path.home() / ".local" / "bin" / "dostheme"
        if not script.exists():
            script = self.repo_dir / "extras" / "scripts" / "dostheme"
        if script.exists():
            try:
                subprocess.run(["bash", str(script), mode], check=False)
                self._append_log(f"[Theme] Switched to DoodlebookOS {mode.capitalize()}")
            except Exception as e:
                self._append_log(f"[Theme Error] Failed to switch theme: {e}")

    @Slot()
    def copyLogToClipboard(self):
        cb = QGuiApplication.clipboard()
        if cb:
            cb.setText("\n".join(self._logs))

    @Slot(bool, bool, bool, bool, bool, str, str, bool)
    def startSetup(
        self,
        opt_panels: bool,
        opt_theme: bool,
        opt_fonts: bool,
        opt_wallpaper: bool,
        opt_qol: bool,
        accent_mode: str,
        accent_hex: str,
        is_pl: bool = False,
    ):
        if self._busy:
            return
        try:
            cache_dir = Path.home() / ".cache"
            cache_dir.mkdir(parents=True, exist_ok=True)
            (cache_dir / "doodlebookos-installer.log").write_text("Starting DoodlebookOS setup...\n", encoding="utf-8")
        except Exception:
            pass
        self._logs = ["Starting DoodlebookOS setup..."]
        self.logUpdated.emit()
        self._busy = True
        self.busyChanged.emit()
        self._on_progress(0.03, "Rozpoczynanie instalacji...", "Starting installation...")

        self._worker = InstallWorker(
            self.repo_dir,
            opt_panels=opt_panels,
            opt_theme=opt_theme,
            opt_fonts=opt_fonts,
            opt_wallpaper=opt_wallpaper,
            opt_qol=opt_qol,
            accent_mode=accent_mode,
            accent_hex=accent_hex,
            is_pl=is_pl,
        )
        self._worker.logAdded.connect(self._append_log)
        self._worker.progressChanged.connect(self._on_progress)
        self._worker.finishedInstall.connect(self._on_finished)
        self._worker.displayScaleChanged.connect(self.displayScaleChanged)
        self._worker.start()

    @Slot()
    def restoreOrUninstall(self):
        uninstall_sh = self.repo_dir / "uninstall.sh"
        if uninstall_sh.exists():
            subprocess.Popen(["bash", str(uninstall_sh)], start_new_session=True)
            self.restoreFinished.emit(True, "Uninstalling DoodlebookOS and restoring previous desktop backup...")
        else:
            self.restoreFinished.emit(False, "Could not find uninstall.sh script.")

    @Slot()
    def logoutSession(self):
        qdbus_bin = shutil.which("qdbus-qt6") or shutil.which("qdbus6") or shutil.which("qdbus")
        if qdbus_bin:
            subprocess.Popen([qdbus_bin, "org.kde.Shutdown", "/Shutdown", "logout"], start_new_session=True)
        elif shutil.which("loginctl"):
            user = os.environ.get("USER", "")
            if user:
                subprocess.Popen(["loginctl", "terminate-user", user], start_new_session=True)


def run_cli(repo_dir: Path):
    from PySide6.QtCore import QCoreApplication
    app = QCoreApplication(sys.argv)

    print("\n\033[1;36m═════════════════════════════════════════════════════════════════════════\033[0m")
    print("\033[1;32m  DoodlebookOS Setup Wizard (CLI Mode)                                   \033[0m")
    print("\033[1;36m═════════════════════════════════════════════════════════════════════════\033[0m\n")

    worker = InstallWorker(
        repo_dir=repo_dir,
        opt_panels=True,
        opt_theme=True,
        opt_fonts=True,
        opt_wallpaper=True,
        opt_qol=True,
        accent_mode="scheme",
        accent_hex="#4285F4",
        is_pl=False,
    )

    def on_progress(pct, pl, en):
        print(f"\033[1;33m[{int(pct*100):3d}%]\033[0m {en}")

    def on_log(msg):
        if msg.startswith("[✓]") or msg.startswith("[i]") or msg.startswith("[!]"):
            print(f"       {msg}")

    worker.progressChanged.connect(on_progress)
    worker.logAdded.connect(on_log)

    worker.run()

    print("\n\033[1;32m═════════════════════════════════════════════════════════════════════════\033[0m")
    print("\033[1;32m  SUCCESS! DoodlebookOS has been installed successfully!                 \033[0m")
    print("\033[1;32m═════════════════════════════════════════════════════════════════════════\033[0m\n")
    sys.exit(0)


def main():
    repo_dir = Path(__file__).resolve().parent.parent

    if "--cli" in sys.argv or "-c" in sys.argv or not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        run_cli(repo_dir)
        return

    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    app = QGuiApplication(sys.argv)
    app.setApplicationName("DoodlebookOS Setup")
    app.setOrganizationName("DoodlebookOS")

    fonts_dir = repo_dir / "extras" / "fonts" / "GoogleSansFlex"
    if fonts_dir.exists():
        for font_file in fonts_dir.glob("*.ttf"):
            QFontDatabase.addApplicationFont(str(font_file))

    logo_path = repo_dir / "installer" / "ui" / "assets" / "DoodlebookOS_Logo.png"
    if logo_path.exists():
        app.setWindowIcon(QIcon(str(logo_path)))
    else:
        app.setWindowIcon(QIcon.fromTheme("preferences-desktop-theme-global"))

    backend = InstallerBackend(repo_dir)

    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("backend", backend)

    qml_file = Path(__file__).resolve().parent / "ui" / "Main.qml"
    engine.load(QUrl.fromLocalFile(str(qml_file)))

    if not engine.rootObjects():
        sys.exit(1)

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
