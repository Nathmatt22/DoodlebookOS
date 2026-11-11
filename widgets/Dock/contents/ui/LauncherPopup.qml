/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore

PlasmaCore.Dialog {
    id: root

    property var rootModel: null
    property var plasmoidConfiguration: null
    property Item visualParentItem: null
    property var dimOverlayItem: null
    readonly property bool shouldDimBackground: Boolean((root.plasmoidConfiguration && root.plasmoidConfiguration.dimBackground !== false) || (typeof Plasmoid !== "undefined" && Plasmoid.configuration && Plasmoid.configuration.dimBackground !== false))

    objectName: "popupWindow"
    flags: Qt.WindowStaysOnTopHint

    visualParent: visualParentItem
    location: (typeof Plasmoid !== "undefined" && Plasmoid.location !== undefined) ? Plasmoid.location : PlasmaCore.Types.BottomEdge
    floating: 12
    // Keep the popup alive while an item is dragged out of it: destroying the window that
    // owns the drag source mid-drag crashes plasmashell on Wayland (KDE bug 449426/488515).
    // FavoriteItem.performDrag() drives this and closes the popup once the drag is over.
    property bool dragInProgress: false
    hideOnWindowDeactivate: !dragInProgress

    // The dialog already has an onVisibleChanged handler, and its default property is its
    // QQuickItem content, so this watcher is declared as a property instead of a child element.
    readonly property Connections visibilityWatcher: Connections {
        target: root
        function onVisibleChanged() {
            if (!root.visible) {
                root.dragInProgress = false;
            }
        }
    }

    backgroundHints: PlasmaCore.Types.StandardBackground

    property int popupWidth: 680
    property int popupHeight: Math.round(Screen.height * 0.66)
    property real panelHeight: 52

    width: popupWidth
    height: popupHeight

    property int iconSize: 50
    readonly property real containerInnerPadding: 20
    readonly property real cellSizeWidth: Math.floor((popupWidth - (containerInnerPadding * 2)) / ((root.plasmoidConfiguration && root.plasmoidConfiguration.numberColumns) || (typeof Plasmoid !== "undefined" && Plasmoid.configuration ? Plasmoid.configuration.numberColumns : 6)))
    readonly property real cellSizeHeight: 102

    property alias launcherContainer: launcherBox.card
    property alias launcherContextMenu: launcherContextMenu

    function closeAnimated() {
        close();
    }

    function updatePosition() {
        if (!visualParent) {
            var scrHeight = Screen.height;
            var scrX = Screen.virtualX;
            var scrY = Screen.virtualY;

            var effPanelHeight = root.panelHeight;
            if (visualParentItem && visualParentItem.Window && visualParentItem.Window.window && visualParentItem.Window.window.height > 0) {
                effPanelHeight = visualParentItem.Window.window.height;
            }

            var bottomGap = 12;
            var panelTop = scrY + scrHeight - effPanelHeight;
            var targetX = scrX + Math.round((Screen.width - popupWidth) / 2);
            var targetY = Math.max(24, Math.round(panelTop - popupHeight - bottomGap));

            if (root.x !== targetX) {
                root.x = targetX;
            }
            if (root.y !== targetY) {
                root.y = targetY;
            }
        }
    }

    property bool skipResetOnOpen: false

    function openWithQuery(term) {
        skipResetOnOpen = true;
        if (shouldDimBackground && dimOverlayItem && typeof dimOverlayItem.showOverlay === "function") {
            dimOverlayItem.showOverlay();
        }

        updatePosition();
        root.visible = true;
        updatePosition();
        root.requestActivate();

        if (main && typeof main.setQuery === "function") {
            main.setQuery(term);
        }
        skipResetOnOpen = false;
    }

    function toggle() {
        if (root.visible) {
            close();
        } else {
            open();
        }
    }

    function open() {
        if (shouldDimBackground && dimOverlayItem && typeof dimOverlayItem.showOverlay === "function") {
            dimOverlayItem.showOverlay();
        }

        updatePosition();
        root.visible = true;
        updatePosition();
        root.requestActivate();
        if (!skipResetOnOpen && main && typeof main.reset === "function") {
            main.reset();
        }
    }

    function close() {
        if (launcherContextMenu && launcherContextMenu.visible) {
            launcherContextMenu.close();
        }

        if (dimOverlayItem && typeof dimOverlayItem.hideOverlay === "function") {
            dimOverlayItem.hideOverlay();
        }

        root.visible = false;
        if (main && typeof main.reset === "function") {
            main.reset();
        }
    }

    onVisibleChanged: {
        if (launcherContextMenu && launcherContextMenu.visible) {
            launcherContextMenu.close();
        }
        if (typeof Plasmoid !== "undefined") {
            Plasmoid.expanded = visible;
        }
        if (visible) {
            updatePosition();
            if (root.rootModel && typeof root.rootModel.refresh === "function") {
                root.rootModel.refresh();
            }
            if (!skipResetOnOpen && main && typeof main.reset === "function") {
                main.reset();
            }
        } else {
            if (dimOverlayItem && typeof dimOverlayItem.hideOverlay === "function") {
                dimOverlayItem.hideOverlay();
            }
        }
    }

    onWidthChanged: {
        if (visible) {
            updatePosition();
        }
    }

    onHeightChanged: {
        if (visible) {
            updatePosition();
        }
    }

    mainItem: Item {
        id: launcherBox
        implicitWidth: root.popupWidth
        implicitHeight: root.popupHeight
        Layout.preferredWidth: root.popupWidth
        Layout.preferredHeight: root.popupHeight
        Layout.minimumWidth: root.popupWidth
        Layout.minimumHeight: root.popupHeight
        Layout.maximumWidth: root.popupWidth
        Layout.maximumHeight: root.popupHeight

        property alias card: launcherCard

        Rectangle {
            id: launcherCard
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width
            height: parent.height
            radius: 0
            opacity: 1.0
            color: "transparent"
            border.color: "transparent"
            border.width: 0
            clip: false

            Item {
                id: cardContent
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                height: root.popupHeight

                MainView {
                    id: main
                    anchors.fill: parent
                    anchors.margins: root.containerInnerPadding
                }

                LauncherContextMenu {
                    id: launcherContextMenu
                    anchors.fill: parent
                    launcherPopup: root
                }
            }
        }
    }

    Component.onCompleted: {
        updatePosition();
        if (root.rootModel) {
            root.rootModel.refreshed.connect(function() {
                if (main && typeof main.reset === "function") {
                    main.reset();
                }
            });
        }
    }
}
