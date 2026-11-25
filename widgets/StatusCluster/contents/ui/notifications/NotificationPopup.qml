/*
    SPDX-FileCopyrightText: 2019 Kai Uwe Broulik <kde@privat.broulik.de>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.core as PlasmaCore
import org.kde.kquickcontrolsaddons as KQuickAddons
import plasma.applet.org.kde.plasma.notifications as NotificationsApplet

NotificationsApplet.NotificationWindow {
    id: notificationPopup

    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0
    function snap(val) {
        return Math.round(val * dpr) / dpr;
    }

    backgroundHints: PlasmaCore.Types.NoBackground

    property int popupWidth: snap(309.6)

    // Maximum width the popup can take to not break out of the screen geometry.
    readonly property int availableWidth: (Screen.desktopAvailableWidth > 0 ? Screen.desktopAvailableWidth : Screen.width) - 32

    readonly property int minimumContentWidth: popupWidth
    readonly property int maximumContentWidth: Math.min((availableWidth > 0 ? availableWidth : Number.MAX_VALUE), popupWidth * 3)

    property alias modelInterface: notificationItem.modelInterface

    property int modelTimeout
    property int dismissTimeout

    property var defaultActionFallbackWindowIdx

    signal expired
    signal hoverEntered
    signal hoverExited

    property int defaultTimeout: 5000
    readonly property int effectiveTimeout: {
        if (modelTimeout === -1) {
            return defaultTimeout;
        }
        if (dismissTimeout) {
            return dismissTimeout;
        }
        return modelTimeout;
    }

    // On wayland we need focus to copy to the clipboard, we change on mouse interaction until the cursor leaves
    takeFocus: notificationItem.modelInterface.replying || focusListener.wantsFocus

    visible: false

    height: mainItem.implicitHeight + topPadding + bottomPadding
    width: mainItem.implicitWidth + leftPadding + rightPadding

    // Hide the rectangular theme frame drawn by PlasmaWindow behind our own rounded card
    function setFrameBackgroundVisible(frameVisible) {
        const content = notificationPopup.contentItem;
        if (!content) {
            return;
        }
        const kids = content.children;
        for (let i = 0; i < kids.length; ++i) {
            if (kids[i] !== notificationPopup.mainItem) {
                kids[i].visible = frameVisible;
            }
        }
    }

    function hideFrameBackground() {
        setFrameBackgroundVisible(false);
    }

    Component.onCompleted: hideFrameBackground()
    onVisibleChanged: {
        if (visible) {
            hideFrameBackground();
        }
    }

    mainItem: KQuickAddons.MouseEventListener {
        id: focusListener
        property bool wantsFocus: false

        implicitWidth: Math.min(Math.max(notificationPopup.minimumContentWidth, notificationItem.Layout.preferredWidth), Math.max(notificationPopup.minimumContentWidth, notificationPopup.maximumContentWidth))
        implicitHeight: notificationItem.implicitHeight

        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        onPressed: wantsFocus = true
        onContainsMouseChanged: {
            wantsFocus = wantsFocus && containsMouse;
            if (containsMouse) {
                notificationPopup.hoverEntered();
            } else {
                notificationPopup.hoverExited();
            }
        }

        // Activate default action when dragging a file over the notification.
        DropArea {
            id: activateDefaultActionDropArea
            anchors.fill: parent

            property bool containsAcceptableDrag: false
            property point lastPosition: Qt.point(-1, -1)

            onEntered: (event) => {
                if (notificationItem.modelInterface.hasDefaultAction) {
                    dragActivationTimer.restart();
                    containsAcceptableDrag = true;
                    lastPosition = Qt.point(drag.x, drag.y);
                } else {
                    drag.accepted = false;
                }
            }
            onPositionChanged: {
                if (containsAcceptableDrag) {
                    const manhattanLength = Math.abs((drag.x - lastPosition.x) + (drag.y - lastPosition.y));
                    if (manhattanLength > Application.styleHints.startDragDistance) {
                        dragActivationTimer.restart();
                        lastPosition = Qt.point(drag.x, drag.y);
                    }
                }
            }
            onDropped: {
                containsAcceptableDrag = false;
            }
            onExited: {
                containsAcceptableDrag = false;
                dragActivationTimer.stop();
            }
        }

        Timer {
            id: dragActivationTimer
            interval: 250 // same as Task Manager
            repeat: false
            onTriggered: notificationItem.modelInterface.defaultActionInvoked()
        }

        Item {
            anchors.fill: parent

            LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
            LayoutMirroring.childrenInherit: true

            Timer {
                id: timer
                interval: notificationPopup.effectiveTimeout
                running: {
                    if (!notificationPopup.visible) {
                        return false;
                    }
                    if (focusListener.containsMouse) {
                        return false;
                    }
                    if (interval <= 0) {
                        return false;
                    }
                    if (activateDefaultActionDropArea.containsAcceptableDrag) {
                        return false;
                    }
                    if (notificationItem.modelInterface.replying
                            && (notificationPopup.active || notificationItem.modelInterface.hasPendingReply)) {
                        return false;
                    }
                    return true;
                }
                onTriggered: {
                    if (notificationPopup.dismissTimeout) {
                        notificationPopup.modelInterface.dismissClicked();
                    } else {
                        notificationPopup.expired();
                    }
                }
            }

            DelegatePopup {
                id: notificationItem
                anchors.fill: parent

                Layout.preferredHeight: implicitHeight
                Layout.preferredWidth: notificationPopup.snap(309.6)

                modelInterface {
                    closable: true
                    timeout: timer.running ? timer.interval : 0

                    // When notification is updated, restart hide timer
                    onTimeChanged: {
                        if (timer.running) {
                            timer.restart();
                        }
                    }
                }
            }
        }
    }
}
