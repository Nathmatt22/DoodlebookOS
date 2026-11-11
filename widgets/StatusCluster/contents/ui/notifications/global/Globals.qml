/*
    SPDX-FileCopyrightText: 2019 Kai Uwe Broulik <kde@privat.broulik.de>

    SPDX-License-Identifier: GPL-2.0-only OR GPL-3.0-only OR LicenseRef-KDE-Accepted-GPL
*/

pragma ComponentBehavior: Bound
pragma Singleton
import QtQuick
import QtQuick.Window
import QtQml

import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

import org.kde.notificationmanager as NotificationManager
import org.kde.taskmanager as TaskManager


import ".."

// This singleton object contains stuff shared between all notification plasmoids, namely:
// - Popup creation and placement
// - Do not disturb mode
QtObject {
    id: globals

    property bool inhibited: false

    onInhibitedChanged: {
        // Update server state so notifications added while inhibited are handled properly
        NotificationManager.Server.inhibited = inhibited;

        if (!inhibited) {
            const urgency = notificationSettings.lowPriorityHistory ? NotificationManager.Notifications.LowUrgency : NotificationManager.Notifications.NormalUrgency;
            popupNotificationsModel.showInhibitionSummary(urgency, notificationSettings.historyBlacklistedApplications, notificationSettings.historyBlacklistedServices);
        }
    }

    // Some parts of the code rely on plasmoid and since we're in a singleton here
    // this is named "plasmoid"
    property var plasmoidItem: null
    property var plasmoid: null

    // all notification plasmoids
    property var plasmoidItems: []

    property int popupLocation: {
        // if we are on mobile, we can ignore the settings totally and just
        // align it to top center
        if (Kirigami.Settings.isMobile) {
            return Qt.AlignTop | Qt.AlignHCenter;
        }

        switch (notificationSettings.popupPosition) {
        // Auto-determine location based on plasmoid location
        case NotificationManager.Settings.CloseToWidget:
            if (!plasmoid) {
                return Qt.AlignBottom | Qt.AlignRight; // just in case
            }

            var alignment = 0;
            if (plasmoid.location === PlasmaCore.Types.LeftEdge) {
                alignment |= Qt.AlignLeft;
            } else if (plasmoid.location === PlasmaCore.Types.RightEdge) {
                alignment |= Qt.AlignRight;
            // No horizontal alignment flag has it place it left or right depending on
            // which half of the *panel* the notification plasmoid is in
            }

            if (plasmoid.location === PlasmaCore.Types.TopEdge) {
                alignment |= Qt.AlignTop;
            } else if (plasmoid.location === PlasmaCore.Types.BottomEdge) {
                alignment |= Qt.AlignBottom;
            // No vertical alignment flag has it place it top or bottom edge depending on
            // which half of the *screen* the notification plasmoid is in
            }
            return alignment;

        case NotificationManager.Settings.TopLeft:
            return Qt.AlignTop | Qt.AlignLeft;
        case NotificationManager.Settings.TopCenter:
            return Qt.AlignTop | Qt.AlignHCenter;
        case NotificationManager.Settings.TopRight:
            return Qt.AlignTop | Qt.AlignRight;
        case NotificationManager.Settings.BottomLeft:
            return Qt.AlignBottom | Qt.AlignLeft;
        case NotificationManager.Settings.BottomCenter:
            return Qt.AlignBottom | Qt.AlignHCenter;
        case NotificationManager.Settings.BottomRight:
            return Qt.AlignBottom | Qt.AlignRight;
        }
    }

    readonly property rect screenRect: {
        var w = (Screen.desktopAvailableWidth > 0) ? Screen.desktopAvailableWidth : Screen.width;
        var h = (Screen.desktopAvailableHeight > 0) ? Screen.desktopAvailableHeight : Screen.height;
        return Qt.rect(0, 0, w > 0 ? w : 1920, h > 0 ? h : 1080);
    }
    onScreenRectChanged: repositionTimer.start()

    readonly property Item visualParent: {
        if (!plasmoidItem) {
            return null;
        }
        return (plasmoidItem.hasOwnProperty("notifBellButton") ? plasmoidItem.notifBellButton : null)
            || (plasmoid && plasmoid.systemTrayRepresentation)
            || plasmoidItem.compactRepresentationItem
            || plasmoidItem.fullRepresentationItem
            || plasmoidItem;
    }
    onVisualParentChanged: positionPopups()

    property var obstructingDialog: null
    readonly property var focusDialog: (plasmoid && plasmoid.focussedPlasmaDialog) ? plasmoid.focussedPlasmaDialog : null
    onFocusDialogChanged: {
        if (focusDialog && !(focusDialog instanceof NotificationPopup)) {
            // keep around the last focusDialog so notifications don't jump around if there is an open but unfocused (eg pinned) Plasma dialog
            // and exclude NotificationPopups so that notifications don't jump down on close when the focusDialog becomes NotificationPopup
            obstructingDialog = focusDialog;
        }
        positionPopups()
    }
    onObstructingDialogChanged: repositionTimer.start()

    // The minimum width of the popup's content item, the Dialog itself adds some margins
    // Make it wider when on the top or the bottom center, since there's more horizontal
    // space available without looking weird
    // On mobile however we don't really want to have larger notifications
    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0
    function snap(val) {
        return Math.round(val * dpr) / dpr;
    }

    property int popupWidth: snap(309.6)
    property int popupEdgeDistance: snap(6.4) // 8px fizycznych od krawędzi ekranu i paska
    property int popupSpacing: snap(8.0)

    // How much vertical screen real estate the notification popups may consume
    readonly property real popupMaximumScreenFill: 0.8

    onPopupLocationChanged: Qt.callLater(positionPopups)

    Component.onCompleted: checkInhibition()

    function adopt(plasmoid) {
        // this doesn't Q_EMIT a change, only in ratePlasmoids() it will detect the change
        globals.plasmoidItems.push(plasmoid);
        ratePlasmoids();
    }

    function forget(plasmoid) {
        // this doesn't Q_EMIT a change, only in ratePlasmoids() it will detect the change
        globals.plasmoidItems = globals.plasmoidItems.filter(p => p !== plasmoid);
        ratePlasmoids();
    }

    // Sorts plasmoids based on a heuristic to find a suitable plasmoid to follow when placing popups
    function ratePlasmoids() {
        var plasmoidScore = function(plasmoidItem) {
            if (!plasmoidItem) {
                return 0;
            }

            const plasmoid = plasmoidItem.plasmoidRef || plasmoidItem.Plasmoid || plasmoidItem.plasmoid;
            if (!plasmoid) {
                return 0;
            }
            var score = 0;

            // Prefer plasmoids in a panel, prefer horizontal panels over vertical ones
            // right over left and bottom over top: they need to have all different scores
            // even if we wouldn't have a clear preference between ie top and bottom,
            // in order to have a stable sorting algorithm
            switch (plasmoid.location) {
            case PlasmaCore.Types.LeftEdge:
                score += 1;
                break;
            case PlasmaCore.Types.RightEdge:
                score += 2;
                break;
            case PlasmaCore.Types.TopEdge:
                score += 3;
                break;
            case PlasmaCore.Types.BottomEdge:
                score += 4;
            }

            // Prefer iconified plasmoids
            if (!plasmoidItem.expanded) {
                ++score;
            }

            // Prefer plasmoids on primary screen
            if (plasmoid && plasmoid.containment && plasmoid.containment.screen === 0) {
                ++score;
            }

            return score;
        }

        var newPlasmoidItems = plasmoidItems;
        newPlasmoidItems.sort(function (a, b) {
            var scoreA = plasmoidScore(a);
            var scoreB = plasmoidScore(b);
            // Sort descending by score
            if (scoreA < scoreB) {
                return 1;
            } else if (scoreA > scoreB) {
                return -1;
            } else {
                return 0;
            }
        });
        globals.plasmoidItems = newPlasmoidItems;
        if (newPlasmoidItems.length === 0) {
            globals.plasmoidItem = null;
            globals.plasmoid = null;
            return;
        }
        globals.plasmoidItem = newPlasmoidItems[0];
        globals.plasmoid = globals.plasmoidItem.plasmoidRef || globals.plasmoidItem.Plasmoid || globals.plasmoidItem.plasmoid;
    }

    function checkInhibition() {
        globals.inhibited = Qt.binding(function() {
            var inhibited = false;

            if (!NotificationManager.Server.valid) {
                return false;
            }

            var inhibitedUntil = notificationSettings.notificationsInhibitedUntil;
            if (!isNaN(inhibitedUntil.getTime())) {
                inhibited |= (Date.now() < inhibitedUntil.getTime());
            }

            if (notificationSettings.notificationsInhibitedByApplication) {
                inhibited |= true;
            }

            if (notificationSettings.inhibitNotificationsWhenFullscreen) {
                inhibited |= notificationSettings.fullscreenFocused;
            }

            if (notificationSettings.inhibitNotificationsWhenScreensMirrored) {
                inhibited |= notificationSettings.screensMirrored;
            }

            return inhibited;
        });
    }

    function rectIntersect(rect1 /*dialog*/, rect2 /*popup*/) {
        return rect1.x < rect2.x + rect2.width
                && rect2.x < rect1.x + rect1.width
                && rect1.y < rect2.y + rect2.height
                && rect2.y < rect1.y + rect1.height;
    }

    function positionPopups() {
        if (!plasmoid && !plasmoidItem) {
            return;
        }

        const screenRect = globals.screenRect;
        if (screenRect.width <= 0 || screenRect.height <= 0) {
            return;
        }
        if (!globals.visualParent) {
            return;
        }

        let effectivePopupLocation = popupLocation;

        const visualParent = globals.visualParent;
        const visualParentWindow = visualParent.Window.window;

        // When no horizontal alignment is specified, place it depending on which half of the *panel*
        // the notification plasmoid is in
        if (visualParentWindow) {
            if (!(effectivePopupLocation & (Qt.AlignLeft | Qt.AlignHCenter | Qt.AlignRight))) {
                const iconHCenter = visualParent.mapToItem(null /*mapToScene*/, 0, 0).x + visualParent.width / 2;

                if (iconHCenter < visualParentWindow.width / 2) {
                    effectivePopupLocation |= Qt.AlignLeft;
                } else {
                    effectivePopupLocation |= Qt.AlignRight;
                }
            }
        }

        // When no vertical alignment is specified, place it depending on which half of the *screen*
        // the notification plasmoid is in
        if (!(effectivePopupLocation & (Qt.AlignTop | Qt.AlignBottom))) {
            const screenVCenter = screenRect.y + screenRect.height / 2;
            const iconVCenter = visualParent.mapToGlobal(0, visualParent.height / 2).y;

            if (iconVCenter < screenVCenter) {
                effectivePopupLocation |= Qt.AlignTop;
            } else {
                effectivePopupLocation |= Qt.AlignBottom;
            }
        }

        let topY = screenRect.y;
        if (visualParentWindow && visualParentWindow.y === 0 && visualParentWindow.height > 0) {
            topY = Math.max(topY, visualParentWindow.y + visualParentWindow.height);
        }
        let y = topY;
        if (effectivePopupLocation & Qt.AlignBottom) {
            y = screenRect.y + screenRect.height - popupEdgeDistance;
        } else {
            y += popupEdgeDistance;
        }

        for (var i = 0; i < popupInstantiator.count; ++i) {
            let popup = popupInstantiator.objectAt(i);
            if (!popup) {
                continue;
            }


            const effectiveW = popup.width > 0 ? popup.width : (popup.popupWidth > 0 ? popup.popupWidth : globals.popupWidth);
            const leftMostX = screenRect.x + popupEdgeDistance;
            const rightMostX = screenRect.x + screenRect.width - popupEdgeDistance - effectiveW;

            // If available screen rect is narrower than the popup, center it in the available rect
            if (screenRect.width < effectiveW || effectivePopupLocation & Qt.AlignHCenter) {
                popup.x = screenRect.x + (screenRect.width - effectiveW) / 2
            } else if (effectivePopupLocation & Qt.AlignLeft) {
                popup.x = leftMostX;
            } else if (effectivePopupLocation & Qt.AlignRight) {
                popup.x = rightMostX;
            }

            if (effectivePopupLocation & Qt.AlignTop) {
                // We want to calculate the new position based on its original target position to avoid positioning it and then
                // positioning it again, hence the temporary Qt.rect with explicit "y" and not just the popup as a whole
                if (obstructingDialog && obstructingDialog.visible
                        && rectIntersect(obstructingDialog, Qt.rect(popup.x, y, popup.width, popup.height))) {
                    y = obstructingDialog.y + obstructingDialog.height + popupEdgeDistance;
                }
                popup.y = y;
                // If the popup isn't ready yet, ignore its occupied space for now.
                // We'll reposition everything in onHeightChanged eventually.
                y += popup.height + (popup.height > 0 ? popupSpacing : 0);
            } else {
                y -= popup.height;
                if (obstructingDialog && obstructingDialog.visible
                        && rectIntersect(obstructingDialog, Qt.rect(popup.x, y, popup.width, popup.height))) {
                    y = obstructingDialog.y - popup.height - popupEdgeDistance;
                }
                popup.y = y;
                if (popup.height > 0) {
                    y -= popupSpacing;
                }
            }

            // don't let notifications take more than popupMaximumScreenFill of the screen
            var visible = true;
            if (i > 0) { // however always show at least one popup
                if (effectivePopupLocation & Qt.AlignTop) {
                    visible = (popup.y + popup.height < screenRect.y + (screenRect.height * popupMaximumScreenFill));
                } else {
                    visible = (popup.y > screenRect.y + (screenRect.height * (1 - popupMaximumScreenFill)));
                }
            }

            if (globals.plasmoidItem && globals.plasmoidItem.notifPopupVisible) {
                visible = false;
            }

            popup.visible = visible;
        }
    }

    property NotificationManager.Notifications popupNotificationsModel: NotificationManager.Notifications {
        limit: Math.max(5, Math.ceil(Screen.height / (Kirigami.Units.gridUnit * 4)))
        showExpired: false
        showDismissed: false
        showAddedDuringInhibition: false
        blacklistedDesktopEntries: globals.notificationSettings.popupBlacklistedApplications
        blacklistedNotifyRcNames: globals.notificationSettings.popupBlacklistedServices
        whitelistedDesktopEntries: globals.inhibited ? globals.notificationSettings.doNotDisturbPopupWhitelistedApplications : []
        whitelistedNotifyRcNames: globals.inhibited ? globals.notificationSettings.doNotDisturbPopupWhitelistedServices : []
        showJobs: globals.notificationSettings.jobsInNotifications
        sortMode: NotificationManager.Notifications.SortByTypeAndUrgency
        sortOrder: Qt.AscendingOrder
        groupMode: NotificationManager.Notifications.GroupDisabled
        window: globals.visualParent ? globals.visualParent.Window.window : null
        urgencies: {
            var urgencies = 0;

            // Critical always except in do not disturb mode when disabled in settings
            if (!globals.inhibited || globals.notificationSettings.criticalPopupsInDoNotDisturbMode) {
                urgencies |= NotificationManager.Notifications.CriticalUrgency;
            }

            // Normal only when not in do not disturb mode
            if (!globals.inhibited) {
                urgencies |= NotificationManager.Notifications.NormalUrgency;
            }

            // Low only when enabled in settings and not in do not disturb mode
            if (!globals.inhibited && globals.notificationSettings.lowPriorityPopups) {
                urgencies |=NotificationManager.Notifications.LowUrgency;
            }

            return urgencies;
        }
    }

    property NotificationManager.Settings notificationSettings: NotificationManager.Settings {
        onNotificationsInhibitedUntilChanged: globals.checkInhibition()
    }

    property TaskManager.TasksModel tasksModel: TaskManager.TasksModel {
        groupMode: TaskManager.TasksModel.GroupApplications
        groupInline: false
    }

    // Periodically verifies whether system inhibition state changed
    property Clock clockSource: Clock {
        onDateTimeChanged: {
            globals.checkInhibition();
        }
    }

    property Instantiator popupInstantiator: Instantiator {
        model: globals.popupNotificationsModel
        delegate: NotificationPopup {
            id: popup

            required property int index
            required property var model

            required property string notificationId
            required property bool hasDefaultAction
            required property list<string> actionLabels
            required property string configureActionLabel
            required property bool hasReplyAction
            required property int urgency
            required property int timeout
            required property list<url> urls
            required property int type
            required property int jobState
            required property string applicationName
            required property string applicationIconName
            required property string originName
            required property date updated
            required property date created
            required property bool configurable
            required property bool dismissable
            required property bool closable
            required property string summary
            required property string body
            required property string accessibleDescription
            required property var image
            required property var iconName
            required property int percentage
            required property list<string> actionNames
            required property string replyActionLabel
            required property string replyPlaceholderText
            required property bool resident
            required property string notifyRcName
            required property string desktopEntry

            readonly property bool isTransient: (model && model.transient !== undefined) ? Boolean(model.transient) : false // "transient" is a reserved keyword, cannot declare it as required property
            readonly property bool hasSomeActions: hasDefaultAction || (actionLabels).length > 0 || (configureActionLabel).length > 0 || hasReplyAction

            popupWidth: globals.popupWidth

            isCritical: urgency === NotificationManager.Notifications.CriticalUrgency || (urgency === NotificationManager.Notifications.NormalUrgency && !globals.notificationSettings.inhibitNotificationsWhenFullscreen)

            modelTimeout: timeout
            // Increase default timeout for notifications with a URL so you have enough time
            // to interact with the thumbnail or bring the window to the front where you want to drag it into
            defaultTimeout: globals.notificationSettings.popupTimeout + (urls && urls.length > 0 ? 5000 : 0)
            // When configured to not keep jobs open permanently, we autodismiss them after the standard timeout
            dismissTimeout: !globals.notificationSettings.permanentJobPopups
                            && type === NotificationManager.Notifications.JobType
                            && jobState !== NotificationManager.Notifications.JobStateStopped
                            ? defaultTimeout : 0

            modelInterface {
                index: popup.index

                notificationType: popup.type

                applicationName: popup.applicationName
                applicationIconSource: popup.applicationIconName
                originName: popup.originName

                time: isNaN(popup.updated) ? popup.created : popup.updated

                configurable: popup.configurable
                dismissable: popup.dismissable && globals.notificationSettings.permanentJobPopups
                closable: popup.closable

                summary: popup.summary
                body: popup.body
                accessibleDescription: popup.accessibleDescription
                icon: popup.iconName
                image: popup.image
                hasDefaultAction: popup.hasDefaultAction

                urls: popup.urls
                urgency: popup.urgency

                jobState: popup.jobState
                percentage: popup.percentage

                configureActionLabel: popup.configureActionLabel
                actionNames: popup.actionNames
                actionLabels: popup.actionLabels

                hasReplyAction: popup.hasReplyAction
                replyActionLabel: popup.replyActionLabel
                replyPlaceholderText: popup.replyPlaceholderText

                // Explicit close, even when resident
                onCloseClicked: globals.popupNotificationsModel.close(globals.popupNotificationsModel.index(index, 0))
                onDismissClicked: {
                    if (model && index >= 0 && index < globals.popupNotificationsModel.rowCount()) {
                        model.dismissed = true;
                    }
                }
                onConfigureClicked: globals.popupNotificationsModel.configure(globals.popupNotificationsModel.index(index, 0))
                onDefaultActionInvoked: {
                    if (defaultActionFallbackWindowIdx) {
                        if (!defaultActionFallbackWindowIdx.valid) {
                            console.warn("Failed fallback notification activation as window no longer exists");
                            return;
                        }

                        // When it's a group, activate the window highest in stacking order (presumably last used)
                        if (globals.tasksModel.data(defaultActionFallbackWindowIdx, TaskManager.AbstractTasksModel.IsGroupParent)) {
                            let highestStacking = -1;
                            let highestIdx = undefined;

                            for (let i = 0; i < globals.tasksModel.rowCount(defaultActionFallbackWindowIdx); ++i) {
                                const idx = globals.tasksModel.index(i, 0, defaultActionFallbackWindowIdx);

                                const stacking = globals.tasksModel.data(idx, TaskManager.AbstractTasksModel.StackingOrder);

                                if (stacking > highestStacking) {
                                    highestStacking = stacking;
                                    highestIdx = globals.tasksModel.makePersistentModelIndex(defaultActionFallbackWindowIdx.row, i);
                                }
                            }

                            if (highestIdx && highestIdx.valid) {
                                globals.tasksModel.requestActivate(highestIdx);
                                if (!resident) {
                                    globals.popupNotificationsModel.close(globals.popupNotificationsModel.index(index, 0))
                                }

                            }
                            return;
                        }

                        globals.tasksModel.requestActivate(defaultActionFallbackWindowIdx);
                        if (!resident) {
                            globals.popupNotificationsModel.close(globals.popupNotificationsModel.index(index, 0))
                        }
                        return;
                    }

                    const behavior = resident ? NotificationManager.Notifications.None : NotificationManager.Notifications.Close;
                    globals.popupNotificationsModel.invokeDefaultAction(globals.popupNotificationsModel.index(index, 0), behavior)
                }
                onActionInvoked: actionName => {
                    const behavior = resident ? NotificationManager.Notifications.None : NotificationManager.Notifications.Close;
                    globals.popupNotificationsModel.invokeAction(globals.popupNotificationsModel.index(index, 0), actionName, behavior)
                }
                onReplied: text => {
                    const behavior = resident ? NotificationManager.Notifications.None : NotificationManager.Notifications.Close;
                    globals.popupNotificationsModel.reply(globals.popupNotificationsModel.index(index, 0), text, behavior);
                }
                onOpenUrl: url => {
                    Qt.openUrlExternally(url);
                    // Client isn't informed of this action, so we always hide the popup
                    if (resident) {
                        if (model && index >= 0 && index < globals.popupNotificationsModel.rowCount()) {
                            model.expired = true;
                        }
                    } else {
                        globals.popupNotificationsModel.close(globals.popupNotificationsModel.index(index, 0))
                    }
                }
            }

            onHoverEntered: {
                if (model && index >= 0 && index < globals.popupNotificationsModel.rowCount()) {
                    model.read = true;
                }
            }
            onExpired: {
                if (index < 0 || index >= globals.popupNotificationsModel.rowCount()) {
                    return;
                }
                if (resident || (hasSomeActions && !isTransient)) {
                    // When resident, only mark it as expired so the popup disappears
                    // but don't actually invalidate the notification.
                    // Also don't invalidate if the popup has any actions,
                    // so it remains usable in history, except when explicitly transient.
                    if (model) {
                        model.expired = true;
                    }
                } else {
                    globals.popupNotificationsModel.expire(globals.popupNotificationsModel.index(index, 0))
                }
            }
            // popup width is fixed
            onHeightChanged: globals.positionPopups()

            Component.onCompleted: {
                if (globals.inhibited) {
                    if (model && index >= 0 && index < globals.popupNotificationsModel.rowCount()) {
                        model.wasAddedDuringInhibition = false; // Don't count already shown notifications
                    }
                }

                if (type === NotificationManager.Notifications.NotificationType && desktopEntry) {
                    // Register apps that were seen spawning a popup so they can be configured later
                    // Apps with notifyrc can already be configured anyway
                    if (!notifyRcName) {
                        globals.notificationSettings.registerKnownApplication(desktopEntry);
                        globals.notificationSettings.save();
                    }

                    // If there is no default action, check if there is a window we could activate instead
                    if (!popup.hasDefaultAction) {
                        for (let i = 0; i < globals.tasksModel.rowCount(); ++i) {
                            const idx = globals.tasksModel.index(i, 0);

                            const appId = globals.tasksModel.data(idx, TaskManager.AbstractTasksModel.AppId);
                            if (appId === desktopEntry + ".desktop") {
                                // Takes a row number, not a QModelIndex
                                defaultActionFallbackWindowIdx = globals.tasksModel.makePersistentModelIndex(i);
                                if (model && index >= 0 && index < globals.popupNotificationsModel.rowCount()) {
                                    model.hasDefaultAction = true;
                                }
                                break;
                            }
                        }
                    }
                }

                // Tell the model that we're handling the timeout now
                if (index >= 0 && index < globals.popupNotificationsModel.rowCount()) {
                    globals.popupNotificationsModel.stopTimeout(globals.popupNotificationsModel.index(index, 0));
                }
            }
        }
        onObjectAdded: (index, object) => {
            globals.positionPopups();
            if (!globals.plasmoidItem || !globals.plasmoidItem.notifPopupVisible) {
                object.visible = true;
            }
            if (index >= 0 && index < globals.popupNotificationsModel.rowCount()) {
                globals.popupNotificationsModel.playSoundHint(globals.popupNotificationsModel.index(index, 0));
            }
        }
        onObjectRemoved: (index, object) => {
            var notificationId = object.notificationId
            // Popup might have been destroyed because of a filter change, tell the model to do the timeout work for us again
            // cannot use QModelIndex here as the model row is already gone
            globals.popupNotificationsModel.startTimeout(notificationId);

            globals.repositionTimer.start();
        }
    }

    // Normally popups are repositioned through Qt.callLater but in case of e.g. screen geometry changes we want to compress that
    property Timer repositionTimer: Timer {
        interval: 250
        onTriggered: globals.positionPopups()
    }

    // Tracks the visual parent's window since mapToItem cannot signal
    // so that when user resizes panel we reposition the popups live
    property Connections visualParentWindowConnections: Connections {
        target: globals.visualParent ? globals.visualParent.Window.window : null
        function onXChanged() {
            globals.repositionTimer.start();
        }
        function onYChanged() {
            globals.repositionTimer.start();
        }
        function onWidthChanged() {
            globals.repositionTimer.start();
        }
        function onHeightChanged() {
            globals.repositionTimer.start();
        }
    }
    // Tracks movement, size and visibility of obstructingDialog, if any
    property Connections obstructingDialogConnections: Connections {
        target: globals.obstructingDialog
        function onVisibleChanged() {
            globals.repositionTimer.start();
        }
        function onXChanged() {
            globals.repositionTimer.start();
        }
        function onYChanged() {
            globals.repositionTimer.start();
        }
        function onWidthChanged() {
            globals.repositionTimer.start();
        }
        function onHeightChanged() {
            globals.repositionTimer.start();
        }
    }

}
