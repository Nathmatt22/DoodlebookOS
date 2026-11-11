/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami
import org.kde.plasma.core as PlasmaCore
import org.kde.notificationmanager as NotificationManager

Item {
    id: mainDockRoot

    property var tasksModel: null
    property var launcherPopup: null
    property var phoneHubPopup: null
    property alias phoneHubBtn: phoneHubBtn

    readonly property bool isVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0

    // Full-bleed panel thickness discovery:
    // KDE Plasma's horizontal panel layout gives AppletContainer only 48 dp inside a 52 dp panel
    // (reserving 2 dp top and 2 dp bottom). By walking up to the layout/containment/panel ancestor,
    // we obtain the true panel thickness (52 dp) so the Dock can fill 100% of the bar edge-to-edge.
    readonly property real effectiveHeight: {
        var p = parent;
        while (p) {
            if (p.panel && typeof p.panel.thickness === "number" && p.panel.thickness > 0) {
                return p.panel.thickness;
            }
            if (p.thickness && typeof p.thickness === "number" && p.thickness > 0) {
                return p.thickness;
            }
            if (!isVertical && p.height && p.height > 0 && p !== parent && p !== (parent ? parent.parent : null)) {
                return p.height;
            }
            if (isVertical && p.width && p.width > 0 && p !== parent && p !== (parent ? parent.parent : null)) {
                return p.width;
            }
            p = p.parent;
        }
        return 52;
    }

    function snap(val) {
        return Math.round(val * dpr) / dpr;
    }

    // Design Tokens / Normalized UI Metrics (Total height = 100%)
    QtObject {
        id: metrics
        readonly property real iconRatio: 0.70               // 70% of dock height (icon)
        readonly property real iconTopRatio: 0.12            // 12% top padding
        readonly property real bottomZoneRatio: 0.18         // 18% bottom indicator zone (sum = 100%)
        readonly property real slotSpacingRatio: 0.46        // space between task items
        readonly property real launcherSpacingRatio: 16.0 / 52.0 // 16 dp space after launcher button (at 52 dp dock)
        readonly property real leftButtonSpacingRatio: 0.38  // space after phonehub button
        readonly property real separatorGapRatio: 0.48       // gap around separator
        readonly property real separatorWidthRatio: 0.05     // width of separator (min 1 physical px)
        readonly property real separatorHeightRatio: 0.37    // height of separator
        readonly property real separatorBottomRatio: 0.33    // separator bottom margin
    }

    readonly property real iconSize: snap(effectiveHeight * metrics.iconRatio)
    readonly property real iconTopMargin: snap(effectiveHeight * metrics.iconTopRatio)
    readonly property real slotSpacing: snap(effectiveHeight * metrics.slotSpacingRatio)
    readonly property real launcherSpacing: snap(effectiveHeight * metrics.launcherSpacingRatio)
    readonly property real leftButtonSpacing: snap(effectiveHeight * metrics.leftButtonSpacingRatio)
    readonly property real separatorGap: snap(effectiveHeight * metrics.separatorGapRatio)
    readonly property real separatorWidth: Math.max(1 / dpr, snap(effectiveHeight * metrics.separatorWidthRatio))
    readonly property real separatorHeight: snap(effectiveHeight * metrics.separatorHeightRatio)
    readonly property real separatorBottomMargin: snap(effectiveHeight * metrics.separatorBottomRatio)
    readonly property real slotPitch: iconSize + slotSpacing

    property bool isDragging: false
    property int dragSourceIndex: -1
    property int dragTargetIndex: -1

    // Dragging a dock icon (launcher reordering) is a drag source too: report it so no surface
    // hosting a drag is torn down mid-gesture, which crashes plasmashell on Wayland.
    onIsDraggingChanged: {
        if (typeof kicker !== "undefined" && kicker && typeof kicker.setDragInProgress === "function") {
            kicker.setDragInProgress(isDragging);
        }
    }

    readonly property int launcherCount: {
        if (!mainDockRoot.tasksModel || !mainDockRoot.tasksModel.launcherList) return 0;
        return mainDockRoot.tasksModel.launcherList.length;
    }

    property int unpinnedTaskCount: 0
    readonly property bool hasUnpinnedTasks: unpinnedTaskCount > 0

    property int notificationEpoch: 0

    NotificationManager.Notifications {
        id: notificationModel
        showExpired: true
        showDismissed: false
        urgencies: NotificationManager.Notifications.CriticalUrgency | NotificationManager.Notifications.NormalUrgency | NotificationManager.Notifications.LowUrgency

        onCountChanged: mainDockRoot.notificationEpoch++
        onRowsInserted: mainDockRoot.notificationEpoch++
        onRowsRemoved: mainDockRoot.notificationEpoch++
        onDataChanged: mainDockRoot.notificationEpoch++
    }

    function normalizeAppKey(str) {
        if (!str) return "";
        var s = str.toString().toLowerCase().trim();
        var lastSlash = s.lastIndexOf("/");
        if (lastSlash !== -1) s = s.substring(lastSlash + 1);
        if (s.endsWith(".desktop")) s = s.substring(0, s.length - 8);
        return s.replace(/[^a-z0-9]/g, "");
    }

    function hasNotificationForApp(appId, appName, launcherUrl) {
        if (!notificationModel || notificationModel.count === 0) return false;
        var keyId = normalizeAppKey(appId);
        var keyName = normalizeAppKey(appName);
        var keyUrl = normalizeAppKey(launcherUrl);

        for (var i = 0; i < notificationModel.count; ++i) {
            var idx = notificationModel.index(i, 0);
            var isRead = notificationModel.data(idx, NotificationManager.Notifications.ReadRole);
            if (isRead === true) continue;

            var dEntry = normalizeAppKey(notificationModel.data(idx, NotificationManager.Notifications.DesktopEntryRole));
            var aName = normalizeAppKey(notificationModel.data(idx, NotificationManager.Notifications.ApplicationNameRole));

            if (dEntry.length > 0) {
                if (keyId.length > 0 && (dEntry === keyId || (keyId.length >= 4 && dEntry.indexOf(keyId) !== -1) || (dEntry.length >= 4 && keyId.indexOf(dEntry) !== -1))) return true;
                if (keyUrl.length > 0 && (dEntry === keyUrl || (keyUrl.length >= 4 && dEntry.indexOf(keyUrl) !== -1) || (dEntry.length >= 4 && keyUrl.indexOf(dEntry) !== -1))) return true;
                if (keyName.length > 0 && (dEntry === keyName || (keyName.length >= 4 && dEntry.indexOf(keyName) !== -1) || (dEntry.length >= 4 && keyName.indexOf(dEntry) !== -1))) return true;
            }

            if (aName.length > 0) {
                if (keyName.length > 0 && (aName === keyName || (keyName.length >= 4 && aName.indexOf(keyName) !== -1) || (aName.length >= 4 && keyName.indexOf(aName) !== -1))) return true;
                if (keyId.length > 0 && (aName === keyId || (keyId.length >= 4 && aName.indexOf(keyId) !== -1) || (aName.length >= 4 && keyId.indexOf(aName) !== -1))) return true;
            }
        }
        return false;
    }

    function checkUnpinnedTasks() {
        var count = 0;
        if (taskRepeater) {
            for (var i = 0; i < taskRepeater.count; ++i) {
                var it = taskRepeater.itemAt(i);
                if (it && it.isUnpinnedTask) {
                    count++;
                }
            }
        }
        mainDockRoot.unpinnedTaskCount = count;
    }

    Connections {
        target: mainDockRoot.tasksModel
        function onCountChanged() {
            Qt.callLater(mainDockRoot.checkUnpinnedTasks);
        }
        function onDataChanged() {
            Qt.callLater(mainDockRoot.checkUnpinnedTasks);
        }
        function onRowsInserted() {
            Qt.callLater(mainDockRoot.checkUnpinnedTasks);
        }
        function onRowsRemoved() {
            Qt.callLater(mainDockRoot.checkUnpinnedTasks);
        }
    }

    implicitWidth: isVertical ? effectiveHeight : mainRow.implicitWidth
    implicitHeight: isVertical ? mainRow.implicitHeight : effectiveHeight
    width: implicitWidth
    height: effectiveHeight
    y: (!isVertical && parent && parent.height > 0) ? -Math.round((effectiveHeight - parent.height) / 2) : 0
    x: (isVertical && parent && parent.width > 0) ? -Math.round((effectiveHeight - parent.width) / 2) : 0

    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    Layout.minimumWidth: implicitWidth
    Layout.minimumHeight: implicitHeight
    Layout.fillHeight: !isVertical
    Layout.fillWidth: isVertical

    Item {
        id: popupAnchorItem
        anchors.horizontalCenter: parent.horizontalCenter
        y: -20
        width: 1
        height: 1
    }
    property alias popupAnchor: popupAnchorItem

    Item {
        id: clickAnchorItem
        width: 1
        height: 1
    }

    property var activeContextMenu: null

    function registerContextMenu(menuObj) {
        if (activeContextMenu && activeContextMenu !== menuObj && activeContextMenu.visible) {
            activeContextMenu.close();
        }
        if (menuObj !== taskbarContextMenu && taskbarContextMenu.visible) {
            taskbarContextMenu.close();
        }
        activeContextMenu = menuObj;
    }

    function closeAllContextMenus() {
        if (activeContextMenu && activeContextMenu.visible) {
            activeContextMenu.close();
        }
        if (taskbarContextMenu.visible) {
            taskbarContextMenu.close();
        }
        activeContextMenu = null;
    }

    TaskbarContextMenu {
        id: taskbarContextMenu
    }

    readonly property color panelBgColor: {
        if (typeof kicker !== "undefined" && kicker.launcherPopup && kicker.launcherPopup.launcherContainer && kicker.launcherPopup.launcherContainer.card && kicker.launcherPopup.launcherContainer.card.color) {
            return kicker.launcherPopup.launcherContainer.card.color;
        }
        return Kirigami.Theme.backgroundColor;
    }
    readonly property color panelTextColor: Kirigami.Theme.textColor

    // Floating ChromeOS speech-bubble Tooltip dialog
    DockTooltip {
        id: dockTooltip
        dockHeight: mainDockRoot.effectiveHeight
        panelBgColor: mainDockRoot.panelBgColor
        panelTextColor: mainDockRoot.panelTextColor
    }

    // Floating Window Preview and Selection Popup when application has multiple instances
    WindowPreviewPopup {
        id: windowPreviewPopup
        tasksModel: mainDockRoot.tasksModel
        panelBgColor: mainDockRoot.panelBgColor
        panelTextColor: mainDockRoot.panelTextColor
        dockHeight: mainDockRoot.effectiveHeight
    }

    function requestShowTooltip(item, text) {
        if (mainDockRoot.isDragging) return;
        if (typeof Plasmoid !== "undefined" && Plasmoid.configuration && Plasmoid.configuration.showTooltips === false) return;
        if (mainDockRoot.launcherPopup && mainDockRoot.launcherPopup.visible) return;
        if (mainDockRoot.phoneHubPopup && mainDockRoot.phoneHubPopup.visible) return;
        if (windowPreviewPopup.visible) return;
        dockTooltip.requestShow(item, text);
    }

    function requestHideTooltip(item) {
        dockTooltip.requestHide(item);
    }

    function requestToggleWindowPreview(item, index, count, appName, icon, winIds) {
        if (mainDockRoot.isDragging) return;
        if (mainDockRoot.launcherPopup && mainDockRoot.launcherPopup.visible) {
            mainDockRoot.launcherPopup.close();
        }
        if (mainDockRoot.phoneHubPopup && mainDockRoot.phoneHubPopup.visible) {
            mainDockRoot.phoneHubPopup.visible = false;
        }
        dockTooltip.requestHide(null);
        if (windowPreviewPopup.visible && windowPreviewPopup.targetItem === item) {
            windowPreviewPopup.requestHideImmediately();
            return;
        }
        windowPreviewPopup.requestShow(item, index, count, appName, icon, winIds);
    }

    function requestHideWindowPreviewImmediately() {
        windowPreviewPopup.requestHideImmediately();
    }

    function startDrag(sourceIndex) {
        dockTooltip.requestHide(null);
        windowPreviewPopup.requestHideImmediately();
        isDragging = true;
        dragSourceIndex = sourceIndex;
        dragTargetIndex = sourceIndex;
    }

    function updateDragTarget(sourceIndex, sourceItemOrGlobalX, mouseX) {
        if (sourceIndex < 0 || !mainDockRoot.isDragging) return;
        var count = mainDockRoot.launcherCount;
        if (count <= 1) return;

        var localX = 0;
        if (typeof sourceItemOrGlobalX === "object" && sourceItemOrGlobalX !== null) {
            var rowPt = tasksRow.mapFromItem(sourceItemOrGlobalX, mouseX, 0);
            localX = rowPt.x;
        } else {
            var rowPt2 = tasksRow.mapFromItem(null, sourceItemOrGlobalX, 0);
            localX = rowPt2.x;
        }

        // Voronoi partition: threshold is halfway between consecutive icon slots
        var target = Math.floor((localX + mainDockRoot.slotSpacing / 2) / mainDockRoot.slotPitch);
        if (target < 0) target = 0;
        if (target >= count) target = count - 1;

        if (mainDockRoot.dragTargetIndex !== target) {
            mainDockRoot.dragTargetIndex = target;
        }
    }

    function finishDrag(sourceIndex, targetIndex) {
        if (sourceIndex >= 0 && targetIndex >= 0 && sourceIndex !== targetIndex) {
            isDragging = false;
            dragSourceIndex = -1;
            dragTargetIndex = -1;
            reorderLaunchers(sourceIndex, targetIndex);
        } else {
            cancelDrag();
        }
    }

    function cancelDrag() {
        dragTargetIndex = dragSourceIndex;
        resetDragTimer.restart();
    }

    Timer {
        id: resetDragTimer
        interval: 220
        repeat: false
        onTriggered: {
            mainDockRoot.isDragging = false;
            mainDockRoot.dragSourceIndex = -1;
            mainDockRoot.dragTargetIndex = -1;
        }
    }

    function reorderLaunchers(fromIndex, toIndex) {
        if (!mainDockRoot.tasksModel || fromIndex === toIndex) return;
        var count = mainDockRoot.launcherCount;
        if (fromIndex < 0 || fromIndex >= count || toIndex < 0 || toIndex >= count) return;

        var moved = false;
        if (typeof mainDockRoot.tasksModel.move === "function") {
            try {
                moved = mainDockRoot.tasksModel.move(fromIndex, toIndex);
                if (typeof mainDockRoot.tasksModel.syncLaunchers === "function") {
                    mainDockRoot.tasksModel.syncLaunchers();
                }
            } catch (e) {
                console.warn("[DoodlebookOS-Dock] tasksModel.move error:", e);
                moved = false;
            }
        }

        if (!moved) {
            // Fallback only if model.move failed
            var list = mainDockRoot.tasksModel.launcherList ? mainDockRoot.tasksModel.launcherList.slice() : [];
            if (list.length > 0 && fromIndex < list.length && toIndex < list.length) {
                var item = list.splice(fromIndex, 1)[0];
                list.splice(toIndex, 0, item);
                mainDockRoot.tasksModel.launcherList = list;
            }
        }

        if (typeof Plasmoid !== "undefined" && Plasmoid.configuration) {
            Plasmoid.configuration.launchers = mainDockRoot.tasksModel.launcherList;
            if (typeof Plasmoid.configuration.writeConfig === "function") {
                Plasmoid.configuration.writeConfig();
            }
        }
    }

    Connections {
        target: mainDockRoot.launcherPopup
        function onVisibleChanged() {
            if (mainDockRoot.launcherPopup && mainDockRoot.launcherPopup.visible) {
                dockTooltip.requestHide(null);
                windowPreviewPopup.requestHideImmediately();
                mainDockRoot.closeAllContextMenus();
            }
        }
    }

    Connections {
        target: mainDockRoot.phoneHubPopup
        function onVisibleChanged() {
            if (mainDockRoot.phoneHubPopup && mainDockRoot.phoneHubPopup.visible) {
                dockTooltip.requestHide(null);
                windowPreviewPopup.requestHideImmediately();
                mainDockRoot.closeAllContextMenus();
            }
        }
    }

    Component.onCompleted: {
        if (typeof kicker !== "undefined") {
            kicker.compactRepItem = mainDockRoot;
        }
        Qt.callLater(mainDockRoot.checkUnpinnedTasks);
    }

    MouseArea {
        id: dockBgMouseArea
        anchors.fill: parent
        z: 0
        acceptedButtons: Qt.RightButton
        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) {
                mouse.accepted = true;
            }
        }
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                mainDockRoot.registerContextMenu(taskbarContextMenu);
                clickAnchorItem.x = mouse.x;
                clickAnchorItem.y = mouse.y;
                taskbarContextMenu.requestShow(clickAnchorItem);
            }
        }
    }

    RowLayout {
        id: mainRow
        anchors.centerIn: parent
        spacing: 0

        // 1. App Launcher Button (Left-most element)
        LauncherButton {
            id: launcherBtn
            buttonHeight: mainDockRoot.effectiveHeight
            isVertical: mainDockRoot.isVertical
            customIcon: (typeof Plasmoid !== "undefined" && Plasmoid.configuration && Plasmoid.configuration.launcherIcon) ? Plasmoid.configuration.launcherIcon : ""
            active: mainDockRoot.launcherPopup ? mainDockRoot.launcherPopup.visible : false
            Layout.rightMargin: mainDockRoot.launcherSpacing
            onClicked: {
                mainDockRoot.closeAllContextMenus();
                dockTooltip.requestHide(null);
                windowPreviewPopup.requestHideImmediately();
                if (mainDockRoot.phoneHubPopup && mainDockRoot.phoneHubPopup.visible) {
                    mainDockRoot.phoneHubPopup.visible = false;
                }
                if (mainDockRoot.launcherPopup) {
                    mainDockRoot.launcherPopup.toggle();
                }
            }
            onRightClicked: mouse => {
                mainDockRoot.closeAllContextMenus();
                mouse.accepted = true;
            }
        }

        // 1b. Phone Hub Button
        PhoneHubButton {
            id: phoneHubBtn
            buttonHeight: mainDockRoot.effectiveHeight
            isVertical: mainDockRoot.isVertical
            active: mainDockRoot.phoneHubPopup ? mainDockRoot.phoneHubPopup.visible : false
            Layout.rightMargin: !mainDockRoot.hasUnpinnedTasks ? mainDockRoot.separatorGap : mainDockRoot.leftButtonSpacing
            onClicked: {
                mainDockRoot.closeAllContextMenus();
                dockTooltip.requestHide(null);
                windowPreviewPopup.requestHideImmediately();
                if (mainDockRoot.launcherPopup && mainDockRoot.launcherPopup.visible) {
                    mainDockRoot.launcherPopup.close();
                }
                if (mainDockRoot.phoneHubPopup) {
                    mainDockRoot.phoneHubPopup.toggle();
                }
            }
            onRightClicked: mouse => {
                mainDockRoot.closeAllContextMenus();
                mouse.accepted = true;
            }
        }

        // 2. Subtle Divider separating Launcher/Phone and Task Items
        // (Appears on the left ONLY when there are NO unpinned tasks; disappears when unpinned tasks are present)
        Rectangle {
            id: leftShelfDivider
            visible: !mainDockRoot.hasUnpinnedTasks
            Layout.preferredWidth: visible ? mainDockRoot.separatorWidth : 0
            Layout.preferredHeight: mainDockRoot.separatorHeight
            Layout.alignment: Qt.AlignBottom
            Layout.bottomMargin: mainDockRoot.separatorBottomMargin
            Layout.leftMargin: 0
            Layout.rightMargin: visible ? mainDockRoot.separatorGap : 0
            radius: width / 2
            color: (Kirigami.Theme.textColor.r > 0.5 || Kirigami.Theme.textColor.g > 0.5 || Kirigami.Theme.textColor.b > 0.5)
                   ? Qt.rgba(1, 1, 1, 0.45)
                   : Qt.rgba(0, 0, 0, 0.40)
        }

        // 3. Task Manager Items (Pinned apps and running windows)
        Item {
            id: tasksContainer
            objectName: "tasksContainer"
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: tasksRow.width
            Layout.preferredHeight: mainDockRoot.effectiveHeight
            implicitWidth: tasksRow.width
            implicitHeight: mainDockRoot.effectiveHeight

            // Target slot placeholder indicator (shows the opened slot in the dock)
            Rectangle {
                id: dropSlotPlaceholder
                visible: mainDockRoot.isDragging && mainDockRoot.dragTargetIndex >= 0
                x: mainDockRoot.dragTargetIndex * mainDockRoot.slotPitch
                y: mainDockRoot.iconTopMargin
                width: mainDockRoot.iconSize
                height: mainDockRoot.iconSize
                radius: 12
                color: Qt.rgba(1, 1, 1, 0.08)
                border.color: Qt.rgba(1, 1, 1, 0.20)
                border.width: 1
                z: 0

                Behavior on x {
                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                }
            }

            Row {
                id: tasksRow
                objectName: "tasksRow"
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: mainDockRoot.slotSpacing

                Repeater {
                    id: taskRepeater
                    model: mainDockRoot.tasksModel
                    delegate: TaskItem {
                        dockHeight: mainDockRoot.effectiveHeight
                        tasksModel: mainDockRoot.tasksModel
                        dockRoot: mainDockRoot
                        onIsUnpinnedTaskChanged: Qt.callLater(mainDockRoot.checkUnpinnedTasks)
                        Component.onCompleted: Qt.callLater(mainDockRoot.checkUnpinnedTasks)
                        Component.onDestruction: Qt.callLater(mainDockRoot.checkUnpinnedTasks)
                    }
                }
            }

            DropArea {
                id: dropArea
                anchors.fill: parent

                onDropped: (drop) => {
                    if (drop.hasUrls && drop.urls.length > 0 && mainDockRoot.tasksModel) {
                        mainDockRoot.tasksModel.requestAddLauncher(drop.urls[0]);
                    }
                }
            }
        }
    }
}
