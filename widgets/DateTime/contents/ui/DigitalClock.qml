/*
    SPDX-FileCopyrightText: 2013 Heena Mahour <heena393@gmail.com>
    SPDX-FileCopyrightText: 2013 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2013 Martin Klapetek <mklapetek@kde.org>
    SPDX-FileCopyrightText: 2014 David Edmundson <davidedmundson@kde.org>
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
import org.kde.taskmanager as TaskManager

MouseArea {
    id: main
    objectName: "digital-clock-compactrepresentation"
    hoverEnabled: true

    Kirigami.Theme.colorSet: Kirigami.Theme.Window
    Kirigami.Theme.inherit: true

    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0
    readonly property bool isVert: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property real effectiveHeight: {
        if (Plasmoid.containment && typeof Plasmoid.containment.height === "number" && Plasmoid.containment.height > 0) {
            return isVert ? Plasmoid.containment.width : Plasmoid.containment.height;
        }
        return isVert ? (parent && parent.width > 0 ? parent.width : 32) : (parent && parent.height > 0 ? parent.height : 32);
    }
    function snap(val) {
        return Math.round(val * dpr) / dpr;
    }

    // Design Tokens / Normalized Top Bar Metrics (Full Symmetry ChromeOS)
    readonly property real pillHeight: snap(effectiveHeight * 0.675)          // 27px physical on 32dp (21.6 dp)
    readonly property real pillTopMargin: snap((effectiveHeight - pillHeight) / 2) // Centered in rail (6.5px physical / 5.2 dp)
    readonly property real pillSidePadding: snap(effectiveHeight * 0.25)      // 25% side padding inside pill (10px physical)
    readonly property real pillLeftMargin: Math.max(0, snap(effectiveHeight * 0.62) - 4.0) // 20px physical (left edge)
    readonly property real fontPixelSize: snap(pillHeight * 0.54)             // 54% of pill height (14px physical)
    readonly property real dateLeftMargin: snap(effectiveHeight * 0.38)       // 15px physical between time & date
    readonly property real pillWidth: isVert ? Math.min(main.width, pillHeight) : (contentItem.width + pillSidePadding * 2)

    implicitWidth: isVert ? effectiveHeight : (pillLeftMargin + pillWidth)
    implicitHeight: isVert ? (pillLeftMargin + pillWidth) : effectiveHeight

    property string timeFormat
    property string timeFormatWithSeconds

    // This is quite convoluted in Qt 6:
    // Qt.formatDate with locale only accepts Locale.FormatType as format type,
    // no Qt.DateFormat (ISODate) and no format string.
    // Locale.toString on the other hand only formats a date *with* time...
    readonly property var dateFormatter: {
        if (Plasmoid.configuration.dateFormat === "custom") {
            Plasmoid.configuration.customDateFormat; // create a binding dependency on this property.
            return (d) => {
                let s = Qt.locale().toString(d, Plasmoid.configuration.customDateFormat || "ddd, d MMM");
                return s ? s.charAt(0).toUpperCase() + s.slice(1) : "";
            };
        } else if (Plasmoid.configuration.dateFormat === "isoDate") {
            return (d) => {
                return Qt.formatDate(d, Qt.ISODate);
            };
        } else if (Plasmoid.configuration.dateFormat === "longDate") {
            return (d) => {
                let s = Qt.formatDate(d, Qt.locale(), Locale.LongFormat);
                return s ? s.charAt(0).toUpperCase() + s.slice(1) : "";
            };
        } else if (Plasmoid.configuration.dateFormat === "shortDate") {
            return (d) => {
                return Qt.formatDate(d, Qt.locale(), Locale.ShortFormat);
            };
        } else {
            // defaultDate: "ddd, d MMM" capitalized (e.g. "Mon, Oct 12")
            return (d) => {
                let s = Qt.locale().toString(d, "ddd, d MMM");
                return s ? s.charAt(0).toUpperCase() + s.slice(1) : "";
            };
        }
    }

    property string lastDate: ""

    // This is the index in the list of user selected time zones
    property int tzIndex: 0

    property bool wasExpanded
    property int wheelDelta: 0

    Accessible.role: Accessible.Button
    Accessible.onPressAction: clicked(null)

    Clock {
        id: clock
        timeZone: Plasmoid.configuration.lastSelectedTimezone
        trackSeconds: Plasmoid.configuration.showSeconds == 2 // show seconds always
        onDateTimeChanged: main.dateTimeChanged()
        onTimeZoneChanged: main.setupLabels()
    }

    // TimeZoneUtils came with org.kde.plasma.clock (Plasma 6.6+); the time engine exposes the
    // offsets needed to order the configured zones the same way, on every Plasma version.
    P5Support.DataSource {
        id: timeZoneDataSource
        engine: "time"
        connectedSources: Plasmoid.configuration.selectedTimeZones
        interval: 60000
    }

    function sortedTimeZones(timeZones) {
        const offsetOf = timeZone => {
            const data = timeZoneDataSource.data ? timeZoneDataSource.data[timeZone] : undefined;
            return data && typeof data["Offset"] === "number" ? data["Offset"] : 0;
        };
        return timeZones.slice().sort((a, b) => offsetOf(a) - offsetOf(b));
    }

    Connections {
        target: Plasmoid
        function onContextualActionsAboutToShow() {
            ClipboardMenu.secondsIncluded = (Plasmoid.configuration.showSeconds === 2);
            // ClipboardMenu.timezone only exists from Plasma 6.8 on.
            if (typeof ClipboardMenu.timezone !== "undefined") {
                ClipboardMenu.timezone = clock.resolvedTimeZone;
            }
        }
    }

    Connections {
        target: Plasmoid.configuration
        function onSelectedTimeZonesChanged() {
            // If the currently selected time zone was removed,
            // default to the first one in the list
            if (Plasmoid.configuration.selectedTimeZones.indexOf(Plasmoid.configuration.lastSelectedTimezone) === -1) {
                Plasmoid.configuration.lastSelectedTimezone = Plasmoid.configuration.selectedTimeZones[0];
            }

            main.setupLabels();
            main.setTimeZoneIndex();
        }

        function onDisplayTimezoneFormatChanged() {
            main.setupLabels();
        }

        function onLastSelectedTimezoneChanged() {
            main.timeFormatCorrection();
        }

        function onShowDateChanged() {
            main.timeFormatCorrection();
        }

        function onUse24hFormatChanged() {
            main.timeFormatCorrection();
        }

        function onShowSecondsChanged() {
            main.setupLabels();
        }
    }

    states: [
        State {
            name: "horizontalPanel"
            when: Plasmoid.formFactor !== PlasmaCore.Types.Vertical

            PropertyChanges {
                main.Layout.fillHeight: true
                main.Layout.fillWidth: false
                main.Layout.preferredWidth: main.implicitWidth
                main.Layout.minimumWidth: main.implicitWidth
                main.Layout.maximumWidth: main.implicitWidth
                main.Layout.preferredHeight: main.implicitHeight
                main.Layout.minimumHeight: main.implicitHeight
                main.Layout.maximumHeight: main.implicitHeight

                contentItem.height: main.fontPixelSize
                contentItem.width: labelsGrid.width + (dateLabel.visible ? (dateLabel.width + dateLabel.anchors.leftMargin) : 0)

                dateLabel.height: main.fontPixelSize
                dateLabel.width: dateLabel.paintedWidth
                dateLabel.font.pixelSize: main.fontPixelSize
                dateLabel.verticalAlignment: Text.AlignVCenter
                dateLabel.anchors.leftMargin: main.dateLeftMargin
                dateLabel.fontSizeMode: Text.FixedSize

                timeLabel.height: main.fontPixelSize
                timeLabel.width: sizehelper.contentWidth
                timeLabel.font.pixelSize: main.fontPixelSize
                timeLabel.verticalAlignment: Text.AlignVCenter
                timeLabel.fontSizeMode: Text.FixedSize

                sizehelper.height: main.fontPixelSize
                sizehelper.font.pixelSize: main.fontPixelSize
                sizehelper.fontSizeMode: Text.FixedSize
            }

            AnchorChanges {
                target: labelsGrid

                anchors.left: contentItem.left
                anchors.verticalCenter: contentItem.verticalCenter
            }

            AnchorChanges {
                target: dateLabel

                anchors.left: labelsGrid.right
                anchors.verticalCenter: labelsGrid.verticalCenter
            }
        },

        State {
            name: "verticalPanel"
            when: Plasmoid.formFactor === PlasmaCore.Types.Vertical

            PropertyChanges {
                main.Layout.fillHeight: false
                main.Layout.fillWidth: true
                main.Layout.maximumHeight: contentItem.height + 16
                main.Layout.minimumHeight: main.Layout.maximumHeight

                contentItem.height: sizehelper.height
                contentItem.width: main.width

                labelsGrid.rows: 1

                timeLabel.height: sizehelper.contentHeight
                timeLabel.width: labelsGrid.width
                timeLabel.font.pixelSize: Math.min(timeLabel.height, main.fontPixelSize)
                timeLabel.fontSizeMode: Text.Fit

                dateLabel.height: timeLabel.height
                dateLabel.width: dateLabel.paintedWidth
                dateLabel.fontSizeMode: Text.Fit
                dateLabel.anchors.leftMargin: timeMetrics.advanceWidth(" ")

                sizehelper.width: main.width
                sizehelper.fontSizeMode: Text.HorizontalFit
                sizehelper.font.pixelSize: main.fontPixelSize
            }

            AnchorChanges {
                target: labelsGrid
                anchors.left: contentItem.left
                anchors.verticalCenter: contentItem.verticalCenter
            }

            AnchorChanges {
                target: dateLabel
                anchors.left: labelsGrid.right
                anchors.verticalCenter: labelsGrid.verticalCenter
            }
        }
    ]

    acceptedButtons: Qt.LeftButton | Qt.RightButton | (ApplicationIntegration.calendarInstalled ? Qt.MiddleButton : 0)
    onPressed: mouse => {
        wasExpanded = root.expanded;
        if (mouse && mouse.button === Qt.RightButton) {
            mouse.accepted = true;
        }
    }
    onClicked: mouse => {
        if (!mouse) {
            root.expanded = !wasExpanded;
            return;
        }
        if (mouse.button === Qt.MiddleButton && ApplicationIntegration.calendarInstalled) {
            ApplicationIntegration.launchCalendar();
        } else if (mouse.button === Qt.LeftButton || mouse.button === Qt.RightButton) {
            mouse.accepted = true;
            root.expanded = !wasExpanded;
        }
    }
    onWheel: wheel => {
        if (!Plasmoid.configuration.wheelChangesTimezone) {
            return;
        }

        var delta = (wheel.inverted ? -1 : 1) * (wheel.angleDelta.y ? wheel.angleDelta.y : wheel.angleDelta.x);
        var newIndex = tzIndex;
        wheelDelta += delta;
        // magic number 120 for common "one click"
        // See: https://doc.qt.io/qt-5/qml-qtquick-wheelevent.html#angleDelta-prop
        while (wheelDelta >= 120) {
            wheelDelta -= 120;
            newIndex--;
        }
        while (wheelDelta <= -120) {
            wheelDelta += 120;
            newIndex++;
        }

        if (newIndex >= Plasmoid.configuration.selectedTimeZones.length) {
            newIndex = 0;
        } else if (newIndex < 0) {
            newIndex = Plasmoid.configuration.selectedTimeZones.length - 1;
        }

        if (newIndex !== tzIndex) {
            Plasmoid.configuration.lastSelectedTimezone = Plasmoid.configuration.selectedTimeZones[newIndex];
            tzIndex = newIndex;
        }
    }

    readonly property bool isTop: Plasmoid.location === PlasmaCore.Types.TopEdge || (Plasmoid.containment && Plasmoid.containment.location === PlasmaCore.Types.TopEdge)

    TaskManager.VirtualDesktopInfo {
        id: virtualDesktopInfo
    }

    TaskManager.TasksModel {
        id: maximizedTasksModel

        activity: Plasmoid.containment ? Plasmoid.containment.activity : ""
        filterByActivity: true
        screenGeometry: Plasmoid.containment ? Plasmoid.containment.screenGeometry : Qt.rect(0, 0, 0, 0)
        filterByScreen: true
        filterMinimized: true
        filterNotMaximized: true

        Component.onCompleted: {
            if (maximizedTasksModel.hasOwnProperty("filterByCurrentVirtualDesktop")) {
                maximizedTasksModel.filterByCurrentVirtualDesktop = true;
            } else {
                maximizedTasksModel.virtualDesktop = Qt.binding(() => virtualDesktopInfo.currentDesktop);
                maximizedTasksModel.filterByVirtualDesktop = true;
            }
        }
    }

    readonly property bool hasMaximizedWindow: isTop && maximizedTasksModel.count > 0

    readonly property color baseContentColor: hasMaximizedWindow
        ? "#ffffff"
        : ((Plasmoid.configuration && Plasmoid.configuration.contentColor && Plasmoid.configuration.contentColor.length > 0)
            ? Plasmoid.configuration.contentColor
            : Kirigami.Theme.textColor)

    readonly property bool isActive: Boolean(main.pressed || root.expanded)
    readonly property bool isHovered: Boolean(main.containsMouse && !isActive)

    readonly property color highlightedContentColor: Kirigami.Theme.highlightedTextColor
    readonly property color highlightCapsuleColor: Kirigami.Theme.highlightColor

    readonly property color labelColor: isActive
        ? highlightedContentColor
        : baseContentColor

    // Button container matching StatusCluster pill symmetry
    Item {
        id: unifiedButton
        x: main.isVert ? 0 : main.pillLeftMargin
        y: main.isVert ? 0 : main.pillTopMargin
        width: main.pillWidth
        height: main.isVert ? (contentItem.height + main.pillSidePadding * 2) : main.pillHeight
        z: -1

        // Hover / Pressed background highlight
        Rectangle {
            id: highlightRect
            anchors.fill: parent
            radius: height / 2
            color: main.highlightCapsuleColor
            opacity: main.isActive ? 1.0 : (main.isHovered ? 0.25 : 0.0)
            Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
        }
    }

   /*
    * Visible elements
    *
    */
    Item {
        id: contentItem
        anchors.verticalCenter: unifiedButton.verticalCenter
        anchors.horizontalCenter: unifiedButton.horizontalCenter

        Grid {
            id: labelsGrid

            rows: 1
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter

            flow: Grid.TopToBottom
            // between time and timezone; timezone is styled differently, so
            // smallSpacing is more appropriate than a space
            columnSpacing: Kirigami.Units.smallSpacing

            Text {
                id: timeLabel

                font {
                    family: "Google Sans Flex"
                    weight: 600
                    pixelSize: main.fontPixelSize
                    features: { "tnum": 1 }
                }
                renderType: Text.QtRendering
                color: main.labelColor
                Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                minimumPixelSize: 1

                text: Qt.locale().toString(clock.dateTime, Plasmoid.configuration.showSeconds === 2 ? main.timeFormatWithSeconds : main.timeFormat)
                textFormat: Text.PlainText

                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
            }
        }

        Text {
            id: dateLabel

            visible: Plasmoid.configuration.showDate

            font {
                family: timeLabel.font.family
                weight: timeLabel.font.weight
                pixelSize: timeLabel.font.pixelSize
            }
            renderType: Text.QtRendering
            color: main.labelColor
            Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
            minimumPixelSize: 1

            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
        }
    }
    /*
     * end: Visible Elements
     *
     */

    Text {
        id: sizehelper

        font {
            family: timeLabel.font.family
            weight: timeLabel.font.weight
            pixelSize: timeLabel.font.pixelSize
            features: { "tnum": 1 }
        }
        minimumPixelSize: 1

        visible: false
        textFormat: Text.PlainText
    }

    FontMetrics {
        id: timeMetrics

        font.family: timeLabel.font.family
        font.weight: timeLabel.font.weight
        font.pixelSize: timeLabel.font.pixelSize
    }

    // Qt's QLocale does not offer any modular time creating like Klocale did
    // eg. no "gimme time with seconds" or "gimme time without seconds and with time zone".
    // QLocale supports only two formats - Long and Short. Long is unusable in many situations
    // and Short does not provide seconds. So if seconds are enabled, we need to add it here.
    //
    // What happens here is that it looks for the delimiter between "h" and "m", takes it
    // and appends it after "mm" and then appends "ss" for the seconds.
    function timeFormatCorrection(timeFormatString = Qt.locale().timeFormat(Locale.ShortFormat)) {
        const regexp = /(hh*)(.+)(mm)/i
        const match = regexp.exec(timeFormatString);

        const hours = match[1];
        const delimiter = match[2];
        const minutes = match[3]
        const seconds = "ss";
        const amPm = "AP";
        const uses24hFormatByDefault = timeFormatString.toLowerCase().indexOf("ap") === -1;

        // Normalize uppercase H to h/hh for consistent 12h/24h representation
        let result = hours.toLowerCase() + delimiter + minutes;

        let result_sec = result + delimiter + seconds;

        // add "AM/PM" either if the setting is the default and locale uses it OR if the user unchecked "use 24h format"
        if ((Plasmoid.configuration.use24hFormat === Qt.PartiallyChecked && !uses24hFormatByDefault) || Plasmoid.configuration.use24hFormat === Qt.Unchecked) {
            result += " " + amPm;
            result_sec += " " + amPm;
        }

        timeFormat = result;
        timeFormatWithSeconds = result_sec;
        setupLabels();
    }

    function setupLabels() {
        if (Plasmoid.configuration.showDate) {
            dateLabel.text = main.dateFormatter(clock.dateTime);
        } else {
            // clear it so it doesn't take space in the layout
            dateLabel.text = "";
        }

        // find widest character between 0 and 9
        let maximumWidthNumber = 0;
        let maximumAdvanceWidth = 0;
        for (let i = 0; i <= 9; i++) {
            const advanceWidth = timeMetrics.advanceWidth(i);
            if (advanceWidth > maximumAdvanceWidth) {
                maximumAdvanceWidth = advanceWidth;
                maximumWidthNumber = i;
            }
        }
        // replace all placeholders with the widest number (two digits)
        const format = (Plasmoid.configuration.showSeconds === 2 ? main.timeFormatWithSeconds : main.timeFormat).replace(/(h+|m+|s+)/g, "" + maximumWidthNumber + maximumWidthNumber); // make sure maximumWidthNumber is formatted as string
        // build the time string twice, once with an AM time and once with a PM time
        const date = new Date(2000, 0, 1, 1, 0, 0);
        const timeAm = Qt.formatTime(date, format);
        const advanceWidthAm = timeMetrics.advanceWidth(timeAm);
        date.setHours(13);
        const timePm = Qt.formatTime(date, format);
        const advanceWidthPm = timeMetrics.advanceWidth(timePm);
        // set the sizehelper's text to the widest time string
        if (advanceWidthAm > advanceWidthPm) {
            sizehelper.text = timeAm;
        } else {
            sizehelper.text = timePm;
        }
    }

    function dateTimeChanged() {
        let doCorrections = false;

        if (Plasmoid.configuration.showDate) {
            // If the date has changed, force size recalculation, because the day name
            // or the month name can now be longer/shorter, so we need to adjust applet size
            const currentDate = Qt.formatDateTime(clock.dateTime, "yyyy-MM-dd");
            if (lastDate !== currentDate) {
                doCorrections = true;
                lastDate = currentDate
            }
        }

        if (doCorrections) {
            timeFormatCorrection();
        }
    }

    function setTimeZoneIndex() {
        tzIndex = Plasmoid.configuration.selectedTimeZones.indexOf(Plasmoid.configuration.lastSelectedTimezone);
    }

    Component.onCompleted: {
        Plasmoid.configuration.selectedTimeZones = sortedTimeZones(Plasmoid.configuration.selectedTimeZones);

        setTimeZoneIndex();
        dateTimeChanged();
        timeFormatCorrection();

        dateFormatterChanged
            .connect(setupLabels);

        stateChanged
            .connect(setupLabels);
    }
}
