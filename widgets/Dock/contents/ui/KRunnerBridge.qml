/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import org.kde.plasma.workspace.dbus as DBus

// Bridge to KRunner: opens the dock launcher when KRunner itself is invoked (Meta).
// It lives in its own file because DBus.Properties only exists in Plasma 6.8+, and the
// dock must keep loading on older Plasma (Debian 13 ships 6.3.6) where the type is absent.
DBus.Properties {
    id: krunnerBridge

    busType: DBus.BusType.Session
    service: "org.kde.krunner"
    path: "/App"
    iface: "org.kde.krunner.App"

    property int lastTriggerCount: -1
    property var launcherPopup: null

    onPropertiesChanged: (iface, changed, invalidated) => {
        if (!launcherPopup) {
            return;
        }

        if (changed && typeof changed.triggerCount !== "undefined") {
            var count = Number(changed.triggerCount);
            if (lastTriggerCount === -1) {
                lastTriggerCount = count;
                return;
            }
            if (count > lastTriggerCount) {
                lastTriggerCount = count;
                var q = (changed.queryText !== undefined) ? changed.queryText.toString() : "";
                if (q.length > 0) {
                    launcherPopup.openWithQuery(q);
                } else {
                    launcherPopup.toggle();
                }
            }
        }
    }
}
