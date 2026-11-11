/*
    SPDX-FileCopyrightText: 2015 Martin Klapetek <mklapetek@kde.org>
    SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>

    SPDX-License-Identifier: GPL-3.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.private.digitalclock
import "i18n.js" as I18n

Rectangle {
    id: toolTipContentItem

    function i18n(k, a1, a2) { return I18n.t(k, a1, a2); }
    function i18nc(c, k, a1, a2) { return I18n.t(k, a1, a2); }

    property int minimumTextWidth: Kirigami.Units.gridUnit * 25
    property int maximumTextWidth: Math.max(minimumTextWidth, clocks.implicitWidth)

    implicitWidth: mainLayout.implicitWidth + Kirigami.Units.gridUnit
    implicitHeight: mainLayout.implicitHeight + Kirigami.Units.gridUnit

    color: Kirigami.Theme.backgroundColor
    radius: 14
    border.width: 0
    border.color: "transparent"

    LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: false

    /**
     * These accessible properties are used in the compact representation,
     * not here.
     */
    Accessible.name: i18nc("@info:tooltip %1 is a localized long date", "Today is %1", tooltipSubtext.text)
    Accessible.description: {
        const description = tooltipSubLabelText.visible ? [tooltipSubLabelText.text] : [];
        for (let i = 0; i < timeZoneRepeater.count; i += 2) {
            description.push(`${(timeZoneRepeater.itemAt(i) as PlasmaComponents.Label).text}: ${(timeZoneRepeater.itemAt(i + 1) as PlasmaComponents.Label).text}`);
        }
        return description.join('; ');
    }

    Clock {
        id: clock
        timeZone: Plasmoid.configuration.lastSelectedTimezone
    }


    ColumnLayout {
        id: mainLayout

        anchors {
            left: parent.left
            top: parent.top
            margins: Kirigami.Units.largeSpacing
        }

        spacing: 0

        Kirigami.Heading {
            id: tooltipMaintext

            Layout.maximumWidth: toolTipContentItem.maximumTextWidth

            level: 3
            // keep this consistent with toolTipMainText in analog-clock
            property var mainText: {
                const text = clocks.visible ? Qt.formatDate(clock.dateTime, Qt.locale(), Locale.LongFormat) : Qt.locale().toString(clock.dateTime, "dddd");
                return text.charAt(0).toUpperCase() + text.slice(1);
            }
            property bool anyTimezoneSet: !!mainText
            text: anyTimezoneSet ? mainText : i18nc("@label main text shown in digital clock's tooltip when timezone is missing", "Time zone is not set")
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
        }

        PlasmaComponents.Label {
            id: tooltipSubtext

            Layout.maximumWidth: toolTipContentItem.maximumTextWidth
            maximumLineCount: 2
            wrapMode: Text.Wrap

            property var subText: {
                if (Plasmoid.configuration.showSeconds === 0) {
                    return Qt.formatDate(clock.dateTime, Qt.locale(), root.dateFormatString);
                } else {
                    return "%1\n%2"
                        .arg(Qt.formatTime(clock.dateTime, Qt.locale(), Locale.LongFormat))
                        .arg(Qt.formatDate(clock.dateTime, Qt.locale(), root.dateFormatString))
                }
            }
            text: tooltipMaintext.anyTimezoneSet ? subText : i18nc("@label sub text shown in digital clock's tooltip when timezone is missing", "Click the clock icon to open Date & Time settings and set a time zone.")
            opacity: 0.75
            visible: !clocks.visible
            font.features: { "tnum": 1 }
            textFormat: Text.PlainText
        }

        PlasmaComponents.Label {
            id: tooltipSubLabelText
            Layout.maximumWidth: toolTipContentItem.maximumTextWidth
            text: (root.fullRepresentationItem as CalendarView)?.monthView.todayAuxilliaryText ?? ""
            textFormat: Text.PlainText
            opacity: 0.75
            visible: !clocks.visible && text.length > 0
            wrapMode: Text.Wrap
        }

        GridLayout {
            id: clocks
            Layout.minimumHeight: childrenRect.height
            visible: timeZoneRepeater.count > 0 && tooltipMaintext.anyTimezoneSet
            columns: 2
            rowSpacing: 0
            Layout.alignment: Qt.AlignHCenter

            Repeater {
                id: timeZoneRepeater

                model: root.selectedTimeZonesDeduplicatingExplicitLocalTimeZone()
                    // Duplicate each entry, because that's how we do "tables" with 2 columns in QML. :-\
                    // An alternative would be a nested Repeater with an ObjectModel.
                    .reduce((array, item) => {
                        array.push(item, item);
                        return array;
                    }, [])

                PlasmaComponents.Label {
                    id: label
                    required property int index
                    required property string modelData

                    readonly property string tzLabel: {
                        switch (Plasmoid.configuration.displayTimezoneFormat) {
                        case 0: // Code
                            return tzClock.timeZoneCode;
                        case 1: // City
                            return TimeZonesI18n.i18nCity(tzClock.resolvedTimeZone);
                        case 2: // Offset from UTC time
                            return tzClock.timeZoneOffset;
                        }
                    }

                    // Layout.fillWidth is buggy here
                    Layout.alignment: index % 2 === 0 ? Qt.AlignRight : Qt.AlignLeft
                    text: index % 2 === 0
                        ? i18nc("@label %1 is a city or time zone name", "%1:", tzLabel)
                        : formatTime(tzClock.dateTime, Plasmoid.configuration.showSeconds > 0) + formatOffset(tzClock.dateTime)
                    Clock {
                        id: tzClock
                        timeZone: label.modelData
                        trackSeconds: Plasmoid.configuration.showSeconds
                    }

                    textFormat: Text.PlainText

                    font.weight: tzClock.resolvedTimeZone == root.currentTimeZone ? Font.Bold : Font.Normal
                    font.features: {
                        if (index % 2 === 1) {
                            return { "tnum": 1 }
                        } else {
                            return {}
                        }
                    }
                    wrapMode: Text.NoWrap
                    elide: Text.ElideNone
                }
            }
        }

        PlasmaComponents.Label {
            Layout.maximumWidth: toolTipContentItem.maximumTextWidth
            visible: ApplicationIntegration.calendarInstalled
            // ApplicationIntegration.calendarApplicationName only exists from Plasma 6.8 on.
            text: ApplicationIntegration.calendarApplicationName !== undefined
                ? i18nc("@info:tooltip %1 is the name of a calendar application", "Middle-click to open %1", ApplicationIntegration.calendarApplicationName)
                : i18nc("@info:tooltip", "Middle-click to open the calendar")
            textFormat: Text.PlainText
            opacity: 0.75
            wrapMode: Text.Wrap
        }
    }
}
