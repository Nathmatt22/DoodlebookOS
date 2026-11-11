/*
    SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
    SPDX-License-Identifier: GPL-3.0-or-later

    Local replacement for the Clock type of the org.kde.plasma.clock module, needed here
    because Globals.qml imports it too. See the copy in the DateTime widget for details:
    the module only exists from Plasma 6.6 on, so it is reimplemented on top of the
    "time" data engine which every Plasma version provides.
*/

import QtQuick
import org.kde.plasma.plasma5support as P5Support

QtObject {
    id: clock

    property string timeZone: ""
    property bool trackSeconds: false

    onTimeZoneChanged: everResolved = false

    readonly property string requestedTimeZone: (timeZone.length > 0 && timeZone !== "Local") ? timeZone : "Local"
    readonly property var zoneData: timeDataSource.data ? timeDataSource.data[requestedTimeZone] : undefined

    readonly property string resolvedTimeZone: {
        const data = zoneData;
        if (data && typeof data["Timezone"] === "string" && data["Timezone"].length > 0) {
            return data["Timezone"];
        }
        return requestedTimeZone;
    }

    readonly property string timeZoneCode: (zoneData && zoneData["Timezone Abbreviation"]) ? zoneData["Timezone Abbreviation"] : ""

    readonly property string timeZoneOffset: {
        const offset = zoneData ? zoneData["Offset"] : undefined;
        if (typeof offset !== "number") {
            return "";
        }
        const sign = offset < 0 ? "-" : "+";
        const absolute = Math.abs(offset);
        const hours = Math.floor(absolute / 3600);
        const minutes = Math.floor((absolute % 3600) / 60);
        return "UTC" + sign + (hours < 10 ? "0" : "") + hours + ":" + (minutes < 10 ? "0" : "") + minutes;
    }

    readonly property date dateTime: {
        const data = zoneData;
        const local = data ? data["DateTime"] : undefined;
        if (!(local instanceof Date)) {
            return new Date();
        }
        const offset = typeof data["Offset"] === "number" ? data["Offset"] : 0;
        return new Date(local.getTime() + local.getTimezoneOffset() * 60000 + offset * 1000);
    }

    property bool everResolved: false
    readonly property bool valid: requestedTimeZone === "Local" ? true : (!everResolved || zoneData !== undefined)

    property P5Support.DataSource timeDataSource: P5Support.DataSource {
        engine: "time"
        connectedSources: [clock.requestedTimeZone]
        interval: clock.trackSeconds ? 1000 : 60000

        onNewData: {
            if (clock.zoneData !== undefined) {
                clock.everResolved = true;
            }
        }
    }
}
