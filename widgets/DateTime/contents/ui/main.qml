/*
    SPDX-FileCopyrightText: 2013 Heena Mahour <heena393@gmail.com>
    SPDX-FileCopyrightText: 2013 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>

    SPDX-License-Identifier: GPL-3.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.private.digitalclock
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    width: Kirigami.Units.gridUnit * 10
    height: Kirigami.Units.gridUnit * 4

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0
    function snap(val) {
        return Math.round(val * dpr) / dpr;
    }
    readonly property real effectiveHeight: {
        if (Plasmoid.containment && typeof Plasmoid.containment.height === "number" && Plasmoid.containment.height > 0) {
            return Plasmoid.formFactor === PlasmaCore.Types.Vertical ? Plasmoid.containment.width : Plasmoid.containment.height;
        }
        return 32.0;
    }
    readonly property real pillHeight: snap(effectiveHeight * 0.675)
    // 16 px fizycznych przy 125% skali (12.8 dp), dynamicznie przeliczane przez snap
    readonly property real calendarFontPixelSize: snap(pillHeight * (16.0 / 27.0))
    // 423 px fizycznych przy skali 125% (338.4 dp):
    readonly property real baseCalendarWidth: snap(338.4)
    // 441 px fizycznych przy skali 125% (352.8 dp):
    readonly property real baseCalendarHeight: snap(352.8)

    readonly property string dateFormatString: setDateFormatString()
    readonly property var currentTime: currentClock.dateTime
    readonly property string currentTimeZone: currentClock.resolvedTimeZone

    Clock {
        id: currentClock
        timeZone: Plasmoid.configuration.lastSelectedTimezone
    }

    Clock {
        id: systemClock
        // not defining a timezone keeps it up to date with the system timezone
    }

    // org.kde.plasma.clock (Plasma 6.6+) also provides TimeZoneUtils; sorting the tooltip
    // list by the current UTC offset only needs the time engine, present in every version.
    P5Support.DataSource {
        id: timeZoneDataSource
        engine: "time"
        connectedSources: root.allTimeZones
        interval: 60000
    }

    function sortedTimeZones(timeZones) {
        const offsetOf = timeZone => {
            const data = timeZoneDataSource.data ? timeZoneDataSource.data[timeZone] : undefined;
            return data && typeof data["Offset"] === "number" ? data["Offset"] : 0;
        };
        return timeZones.slice().sort((a, b) => offsetOf(a) - offsetOf(b));
    }

    function initTimeZones() {
        const timeZones = [];
        if (Plasmoid.configuration.selectedTimeZones.indexOf("Local") === -1) {
            timeZones.push("Local");
        }
        root.allTimeZones = timeZones.concat(Plasmoid.configuration.selectedTimeZones);
    }

    function formatTime(dateTime: date, showSeconds: bool): string {
        if (!compactRepresentationItem) {
            return "";
        }

        let formattedTime;
        if (showSeconds) {
            formattedTime = Qt.locale().toString(dateTime, compactRepresentationItem.item.timeFormatWithSeconds);
        } else {
            formattedTime = Qt.locale().toString(dateTime, compactRepresentationItem.item.timeFormat);
        }

        if (dateTime.getDay() !== currentClock.dateTime.getDay()) {
            formattedTime += " " + Qt.locale().toString(dateTime, "dddd");
        }

        return formattedTime;
    }

    function formatOffset(dateTime: date): string {
        const offset = Math.round((dateTime - currentClock.dateTime) / (1000 * 60));

        if (offset === 0) {
            return "";
        }

        const absoluteOffset = Math.abs(offset);
        const hourOffset = Math.floor(absoluteOffset / 60);
        const minuteOffset = absoluteOffset % 60;

        if (offset > 0) {
            if (minuteOffset === 0) {
                return i18ncp("@info offset from current time", " • %1 hour later", " • %1 hours later", hourOffset);
            } else {
                return i18nc("@info offset from current time in hours and minutes", " • %1:%2 later", hourOffset, minuteOffset);
            }
        } else {
            if (minuteOffset === 0) {
                return i18ncp("@info offset from current time", " • %1 hour earlier", " • %1 hours earlier", hourOffset);
            } else {
                return i18nc("@info offset from current time in hours and minutes", " • %1:%2 earlier", hourOffset, minuteOffset);
            }
        }
    }

    function selectedTimeZonesDeduplicatingExplicitLocalTimeZone():/* [string] */var {
        /*
         * Don't add this item if it's the same as the local time zone, which
         * would indicate that the user has deliberately added a dedicated entry
         * for the city of their normal time zone. This is not an error condition
         * because the user may have done this on purpose so that their normal
         * local time zone shows up automatically while they're traveling and
         * they've switched the current local time zone to something else. But
         * with this use case, when they're back in their normal local time zone,
         * the clocks list would show two entries for the same city. To avoid
         * this, let's suppress the duplicate.
         */
        const isLiterallyLocalOrResolvesToSomethingOtherThanLocal = timeZone =>
            timeZone == "Local" || timeZone != systemClock.resolvedTimeZone

        return sortedTimeZones(Plasmoid.configuration.selectedTimeZones
            .filter(isLiterallyLocalOrResolvesToSomethingOtherThanLocal));
    }

    preferredRepresentation: compactRepresentation

    fullRepresentation: CalendarView {
        id: calendarView
        Connections {
            target: root
            function onExpandedChanged() : void {
                if (root.expanded) {
                    if (Plasmoid.configuration) {
                        Plasmoid.configuration.popupWidth = root.baseCalendarWidth;
                        Plasmoid.configuration.popupHeight = root.baseCalendarHeight;
                    }
                    Qt.callLater(calendarView.adjustWindowPosition);
                }
                calendarView.monthView.viewHeader.monthYearButton.forceActiveFocus(Qt.OtherFocusReason)
                calendarView.monthView.resetToToday();
            }
        }
    }

    compactRepresentation: Loader {
        id: conditionalLoader

        property bool containsMouse: (item as MouseArea)?.containsMouse ?? false
        Layout.minimumWidth: (item as Item)?.Layout.minimumWidth
        Layout.minimumHeight: (item as Item)?.Layout.minimumHeight
        Layout.preferredWidth: (item as Item)?.Layout.preferredWidth
        Layout.preferredHeight: (item as Item)?.Layout.preferredHeight
        Layout.maximumWidth: (item as Item)?.Layout.maximumWidth
        Layout.maximumHeight: (item as Item)?.Layout.maximumHeight
        Layout.fillHeight: (item as Item)?.Layout.fillHeight ?? true
        Layout.fillWidth: (item as Item)?.Layout.fillWidth ?? false

        sourceComponent: !currentClock.valid ? noTimezoneComponent : digitalClockComponent
    }

    Component {
        id: digitalClockComponent
        DigitalClock {
            activeFocusOnTab: true
            hoverEnabled: true

            Accessible.name: (tooltipLoader.item as Item)?.Accessible.name
            Accessible.description: (tooltipLoader.item as Item)?.Accessible.description
        }
    }

    Component {
        id: noTimezoneComponent
        NoTimezoneWarning { }
    }

    toolTipItem: Loader {
        id: tooltipLoader

        Layout.minimumWidth: item ? (item as Tooltip).implicitWidth : 0
        Layout.maximumWidth: item ? (item as Tooltip).implicitWidth : 0
        Layout.minimumHeight: item ? (item as Tooltip).implicitHeight : 0
        Layout.maximumHeight: item ? (item as Tooltip).implicitHeight : 0

        source: Qt.resolvedUrl("Tooltip.qml")
    }

    //We need Local to be *always* present, even if not disaplayed as
    //it's used for formatting in ToolTip.dateTimeChanged()
    property list<string> allTimeZones

    Connections {
        target: Plasmoid.configuration
        function onSelectedTimeZonesChanged() {
            root.initTimeZones();
        }
    }

    hideOnWindowDeactivate: true

    function setDateFormatString() {
        // remove "dddd" from the locale format string
        // /all/ locales in LongFormat have "dddd" either
        // at the beginning or at the end. so we just
        // remove it + the delimiter and space
        let format = Qt.locale().dateFormat(Locale.LongFormat);
        format = format.replace(/(^dddd.?\s)|(,?\sdddd$)/, "");
        return format;
    }

    Plasmoid.contextualActions: []

    Component.onCompleted: {
        if (Plasmoid.containment && Plasmoid.containment.location === PlasmaCore.Types.TopEdge) {
            Plasmoid.containment.backgroundHints = PlasmaCore.Types.NoBackground;
        }

        if (Plasmoid.configuration) {
            Plasmoid.configuration.popupWidth = root.baseCalendarWidth;
            Plasmoid.configuration.popupHeight = root.baseCalendarHeight;
        }

        initTimeZones();
    }
}
