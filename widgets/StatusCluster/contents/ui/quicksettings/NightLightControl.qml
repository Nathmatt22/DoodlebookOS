/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import org.kde.plasma.workspace.dbus as DBus

// Reads the KWin Night Light state over DBus.
// Kept in its own file because DBus.Properties only exists in Plasma 6.8+; the quick
// settings panel loads it through a Loader so Plasma 6.3 (Debian 13) simply hides the
// Night Light readout instead of failing to load the whole panel.
DBus.Properties {
    id: nightLightControl

    busType: DBus.BusType.Session
    service: "org.kde.KWin.NightLight"
    path: "/org/kde/KWin/NightLight"
    iface: "org.kde.KWin.NightLight"

    readonly property bool available: Boolean(properties.available)
    readonly property bool running: Boolean(properties.running)
    readonly property bool inhibited: Boolean(properties.inhibited)
    readonly property bool daylight: Boolean(properties.daylight)
    readonly property int currentTemperature: Number(properties.currentTemperature)
    readonly property int targetTemperature: Number(properties.targetTemperature)
}
