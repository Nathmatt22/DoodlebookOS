/*
    SPDX-FileCopyrightText: 2026 DoodlebookOS
    SPDX-License-Identifier: GPL-3.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

// Backend subsystem imports
import org.kde.plasma.private.mpris as Mpris
import org.kde.notificationmanager as NotificationManager
import org.kde.plasma.networkmanagement as PlasmaNM
import org.kde.plasma.private.battery as PlasmaBattery
import org.kde.plasma.private.volume as Volume
import org.kde.plasma.private.clipboard as Klipper
import org.kde.taskmanager as TaskManager

// Sub-module UI components
import "media" as Media
import "notifications" as NotificationsUI
import "notifications/global" as NotifGlobal
import "quicksettings" as QuickSettingsUI

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    Plasmoid.contextualActions: []

    Connections {
        target: Plasmoid
        function onActivated() {
            root.toggleQSPopup();
        }
    }

    // Native Klipper engine instance - maintains clipboard history & prevents Wayland timeout drop
    Klipper.KlipperInterface {
        id: klipperInterface
    }
    Klipper.HistoryModel {
        id: clipboardHistoryModel
    }

    readonly property bool isVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property real dpr: Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1.0
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

    readonly property bool hasMaximizedWindow: root.isTop && maximizedTasksModel.count > 0

    readonly property real effectiveHeight: {
        var h = 0;
        if (Plasmoid.containment && typeof Plasmoid.containment.height === "number" && Plasmoid.containment.height > 20) {
            h = isVertical ? Plasmoid.containment.width : Plasmoid.containment.height;
        } else if (parent && (isVertical ? parent.width : parent.height) > 20) {
            h = isVertical ? parent.width : parent.height;
        }
        return (h > 20) ? h : 32.0;
    }

    function snap(val) {
        return Math.round(val * dpr) / dpr;
    }

    // ==========================================
    // UNIFIED RAIL METRICS (Top Bar Design Tokens - Option B Full Symmetry)
    // ==========================================
    readonly property real railHeight: snap(effectiveHeight * 0.675)             // 27 px physical at 40 px panel height (21.6 dp)
    readonly property real qsIconHeight: snap(effectiveHeight * 0.400)           // 16 px physical at 40 px panel height (12.8 dp)
    readonly property real railTopMargin: snap((effectiveHeight - railHeight) / 2) // 6.5 px physical (centered in rail)
    readonly property real clusterRightMargin: Math.max(0, snap(effectiveHeight * 0.67) - 4.0) // 22 px physical
    readonly property real itemSpacing: snap(effectiveHeight * 0.20)            // 8 px physical

    // Common Colors & Styling Tokens
    readonly property color topBarContentColor: {
        if (hasMaximizedWindow) {
            return "#ffffff";
        }
        if (Plasmoid.configuration && Plasmoid.configuration.contentColor && Plasmoid.configuration.contentColor.length > 0) {
            return Plasmoid.configuration.contentColor;
        }
        return Kirigami.Theme.textColor;
    }
    readonly property bool isLightContent: {
        var c = topBarContentColor;
        return (c.r * 0.299 + c.g * 0.587 + c.b * 0.114) > 0.5;
    }
    readonly property color highlightedContentColor: Kirigami.Theme.highlightedTextColor
    readonly property color highlightCapsuleColor: Kirigami.Theme.highlightColor
    readonly property color effectiveAccentColor: {
        if (Plasmoid.configuration && Plasmoid.configuration.useCustomAccentColor && Plasmoid.configuration.accentColor) {
            return Plasmoid.configuration.accentColor;
        }
        return Kirigami.Theme.highlightColor;
    }

    // ==========================================
    // 1. MEDIA BACKEND (MediaPill)
    // ==========================================
    Item {
        id: mediaBackend
        visible: false

        readonly property string rawTrack: mpris2Model.currentPlayer?.track ?? ""

        readonly property string track: {
            let raw = String(rawTrack);
            // 1. Usunięcie prefiksu powiadomień np. "(3) ", "(99+) "
            raw = raw.replace(/^\(\d+\+?\)\s*/, "");
            // 2. Usunięcie powszechnych sufiksów serwisów np. " - YouTube", " - SoundCloud"
            raw = raw.replace(/\s*-\s*YouTube(?:\s*Music)?$/i, "");
            raw = raw.replace(/\s*-\s*SoundCloud$/i, "");
            raw = raw.trim();
            if (raw.length === 0) {
                return (identity.length > 0) ? identity : i18n("Media");
            }
            return raw;
        }

        readonly property string artist: mpris2Model.currentPlayer?.artist ?? ""
        readonly property string identity: mpris2Model.currentPlayer?.identity ?? ""

        readonly property string artUrl: {
            const raw = String(mpris2Model.currentPlayer?.artUrl ?? "");
            if (raw.length > 0 && raw.startsWith("/")) return "file://" + raw;
            return raw;
        }

        readonly property bool isChromeFallbackArt: {
            const url = artUrl.toLowerCase();
            return url.includes(".com.google.chrome") || url.includes(".org.chromium.chromium") || url.includes("google-chrome");
        }

        readonly property bool hasRealArtwork: artUrl.length > 0 && !isChromeFallbackArt

        readonly property string appIcon: {
            const idLower = identity.toLowerCase();
            if (idLower.includes("chrome") || idLower.includes("chromium") || isChromeFallbackArt) return "google-chrome";
            if (idLower.includes("firefox")) return "firefox";
            if (idLower.includes("spotify")) return "spotify";
            if (idLower.includes("vlc")) return "vlc";
            if (mpris2Model.currentPlayer?.iconName) {
                const icon = String(mpris2Model.currentPlayer.iconName);
                if (icon !== "multimedia-audio-player" && icon !== "audio-x-generic") return icon;
            }
            return "multimedia-audio-player";
        }

        readonly property bool canSeek: mpris2Model.currentPlayer?.canSeek ?? false

        readonly property int playbackStatus: mpris2Model.currentPlayer?.playbackStatus ?? Mpris.PlaybackStatus.Stopped
        readonly property bool isPlaying: mediaBackend.playbackStatus === Mpris.PlaybackStatus.Playing

        property double position: mpris2Model.currentPlayer?.position ?? 0
        property double length: mpris2Model.currentPlayer?.length ?? 0

        readonly property bool hasMedia: mpris2Model.currentPlayer !== null && rawTrack.trim().length > 0
        readonly property bool hasActiveMedia: hasMedia && (playbackStatus === Mpris.PlaybackStatus.Playing || playbackStatus === Mpris.PlaybackStatus.Paused)

        property bool effectiveVisible: hasActiveMedia

        Timer {
            id: hideDebounceTimer
            interval: 3500 // 3.5s grace period WYŁĄCZNIE przy pauzie wciąż istniejącego utworu
            repeat: false
            onTriggered: {
                if (mediaDialog.visible) {
                    return;
                }
                mediaBackend.effectiveVisible = mediaBackend.hasActiveMedia;
            }
        }

        function syncVisibility(): void {
            if (hasActiveMedia) {
                hideDebounceTimer.stop();
                mediaBackend.effectiveVisible = true;
            } else if (!hasMedia) {
                // Gdy brak mediów / brak utworu / zamknięto źródło -> natychmiast ukrywamy!
                hideDebounceTimer.stop();
                mediaBackend.effectiveVisible = false;
                if (mediaDialog.visible) {
                    mediaDialog.visible = false;
                }
            } else if (!mediaDialog.visible) {
                // Utwór istnieje, ale jest na pauzie -> odczekaj 3.5s bufora
                hideDebounceTimer.restart();
            }
        }

        onHasActiveMediaChanged: syncVisibility()
        onHasMediaChanged: syncVisibility()
        onRawTrackChanged: syncVisibility()

        Connections {
            target: mediaDialog
            function onVisibleChanged() {
                if (!mediaDialog.visible) {
                    if (!mediaBackend.hasMedia) {
                        mediaBackend.effectiveVisible = false;
                    } else if (!mediaBackend.hasActiveMedia) {
                        hideDebounceTimer.restart();
                    }
                }
            }
        }

        function togglePlaying(): void {
            if (mpris2Model.currentPlayer) {
                if (isPlaying) mpris2Model.currentPlayer.Pause();
                else mpris2Model.currentPlayer.Play();
            }
        }

        function seek(newPosMicros: double): void {
            if (mpris2Model.currentPlayer) mpris2Model.currentPlayer.position = newPosMicros;
        }

        function changeVolume(delta: double): void {
            if (mpris2Model.currentPlayer) mpris2Model.currentPlayer.changeVolume(delta, true);
        }

        Mpris.Mpris2Model {
            id: mpris2Model
        }
    }

    // ==========================================
    // 2. NOTIFICATIONS BACKEND
    // ==========================================
    NotificationManager.Settings {
        id: notifSettings
    }

    NotificationManager.Notifications {
        id: notifHistoryModel
        showExpired: true
        showDismissed: true
        showJobs: notifSettings.jobsInNotifications
        sortMode: NotificationManager.Notifications.SortByTypeAndUrgency
        groupMode: NotificationManager.Notifications.GroupDisabled
        blacklistedDesktopEntries: notifSettings.historyBlacklistedApplications
        blacklistedNotifyRcNames: notifSettings.historyBlacklistedServices
        urgencies: NotificationManager.Notifications.CriticalUrgency
                 | NotificationManager.Notifications.NormalUrgency
                 | NotificationManager.Notifications.LowUrgency
    }

    // ignoreBlacklistDuringInhibition only exists in Plasma 6.8+. Declaring it here makes the
    // whole widget fail to load on older releases, so it is applied through a Binding, which
    // is ignored (only warning) where the property does not exist.
    Binding {
        target: notifHistoryModel
        property: "ignoreBlacklistDuringInhibition"
        value: true
    }

    readonly property var plasmoidRef: Plasmoid
    property alias notifBellButton: notifBellButton
    property alias mediaPillButton: mediaPillButton
    property alias qsPillButton: qsPillButton
    readonly property bool notifPopupVisible: notifDialog.visible

    Component.onCompleted: {
        NotifGlobal.Globals.adopt(root);
        root.updateWifiSignal();
        root.updateUnreadNotifs();
    }

    Component.onDestruction: {
        NotifGlobal.Globals.forget(root);
    }

    property int unreadNotifCount: 0

    function updateUnreadNotifs() {
        if (notifDialog.visible) {
            unreadNotifCount = 0;
            return;
        }
        var unread = notifHistoryModel ? notifHistoryModel.unreadNotificationsCount : 0;
        unreadNotifCount = Math.min(99, Math.max(0, unread));
    }

    Connections {
        target: notifHistoryModel
        function onRowsInserted() { root.updateUnreadNotifs(); }
        function onRowsRemoved() { root.updateUnreadNotifs(); }
        function onDataChanged() { root.updateUnreadNotifs(); }
        function onModelReset() { root.updateUnreadNotifs(); }
        function onUnreadNotificationsCountChanged() { root.updateUnreadNotifs(); }
    }

    Connections {
        target: NotifGlobal.Globals.popupNotificationsModel
        function onRowsInserted() { root.updateUnreadNotifs(); }
        function onRowsRemoved() { root.updateUnreadNotifs(); }
        function onModelReset() { root.updateUnreadNotifs(); }
    }
    readonly property bool isDndActive: Boolean(notifSettings.notificationsInhibitedUntil && notifSettings.notificationsInhibitedUntil > new Date())

    function toggleDoNotDisturbMode(): void {
        if (isDndActive) {
            notifSettings.notificationsInhibitedUntil = undefined;
        } else {
            var d = new Date();
            d.setFullYear(d.getFullYear() + 1);
            notifSettings.notificationsInhibitedUntil = d;
        }
        notifSettings.save();
    }

    PlasmaCore.Action {
        id: clearHistoryAction
        text: typeof i18n === "function" ? i18n("Clear All Notifications") : "Clear All Notifications"
        icon.name: "edit-clear-history"
        visible: notifHistoryModel.expiredNotificationsCount > 0
        onTriggered: {
            notifHistoryModel.clear(NotificationManager.Notifications.ClearExpired);
        }
    }

    // ==========================================
    // 3. QUICK SETTINGS BACKEND
    // ==========================================
    property alias nmStatus: nmStatus
    property alias batteryModel: batteryModel
    readonly property bool hasInternalBattery: batteryModel ? Boolean(batteryModel.hasCumulative || (batteryModel.hasInternalBatteries && batteryModel.percent > 0)) : false
    property alias paSinkModel: paSinkModel

    PlasmaNM.NetworkStatus {
        id: nmStatus
    }

    PlasmaNM.EnabledConnections {
        id: nmEnabled
    }

    PlasmaNM.NetworkModel {
        id: nmNetworkModel
    }

    PlasmaNM.AppletProxyModel {
        id: nmAppletProxyModel
        sourceModel: nmNetworkModel
    }

    property int activeWifiSignal: -1
    property bool hasActiveWifi: false
    property bool hasActiveWired: false

    function updateWifiSignal() {
        var foundWired = false;
        var foundWifi = false;
        var wifiSig = -1;

        var count = nmAppletProxyModel.rowCount();
        for (var i = 0; i < count; i++) {
            var idx = nmAppletProxyModel.index(i, 0);
            var state = nmAppletProxyModel.data(idx, PlasmaNM.NetworkModel.ConnectionStateRole);
            var type = nmAppletProxyModel.data(idx, PlasmaNM.NetworkModel.TypeRole);

            if (state === PlasmaNM.Enums.Activated) {
                if (type === PlasmaNM.Enums.Wired) {
                    foundWired = true;
                } else if (type === PlasmaNM.Enums.Wireless && !foundWifi) {
                    var sig = nmAppletProxyModel.data(idx, PlasmaNM.NetworkModel.SignalRole);
                    if (sig !== undefined && sig !== null && !isNaN(sig)) {
                        wifiSig = Number(sig);
                    } else {
                        wifiSig = 100;
                    }
                    foundWifi = true;
                }
            }
        }

        hasActiveWired = foundWired;
        hasActiveWifi = foundWifi;
        activeWifiSignal = wifiSig;
    }

    Connections {
        target: nmAppletProxyModel
        function onDataChanged() { root.updateWifiSignal(); }
        function onRowsInserted() { root.updateWifiSignal(); }
        function onRowsRemoved() { root.updateWifiSignal(); }
        function onModelReset() { root.updateWifiSignal(); }
    }

    Connections {
        target: nmEnabled
        function onWirelessEnabledChanged() { root.updateWifiSignal(); }
    }

    readonly property url currentWifiIcon: {
        if (hasActiveWired) {
            return Qt.resolvedUrl("quicksettings/icons/ethernet.svg");
        }

        if (!nmEnabled.wirelessEnabled) {
            return Qt.resolvedUrl("quicksettings/icons/wifi_off.svg");
        }

        // If no active Wi-Fi connection found
        if (!hasActiveWifi) {
            return Qt.resolvedUrl("quicksettings/icons/wifi_0.svg");
        }

        // Map signal strength (0-100%) to 3 stages (2 arcs + dot)
        if (activeWifiSignal <= 33) {
            return Qt.resolvedUrl("quicksettings/icons/wifi_1.svg");
        } else if (activeWifiSignal <= 66) {
            return Qt.resolvedUrl("quicksettings/icons/wifi_2.svg");
        } else {
            return Qt.resolvedUrl("quicksettings/icons/wifi_3.svg");
        }
    }

    PlasmaBattery.BatteryControlModel {
        id: batteryModel
    }

    readonly property url currentBatteryIcon: {
        var bm = batteryModel;
        if (!bm) {
            return Qt.resolvedUrl("quicksettings/icons/battery_android_full_bolt.svg");
        }
        var hasInternal = root.hasInternalBattery;
        var plugged = Boolean(bm.pluggedIn);
        var st = bm.state;
        var pct = bm.percent;

        // Desktop PC or device without internal battery
        if (!hasInternal) {
            return Qt.resolvedUrl("quicksettings/icons/battery_android_full_bolt.svg");
        }

        var val = (pct !== undefined && pct !== null) ? pct : 100;
        // On AC power: actively charging (state 1), fully charged (state 3), or plugged in
        var isPlugged = (plugged || st === 1 || st === 3);

        // Actively charging or plugged in on AC power
        if (isPlugged) {
            if (val <= 15) {
                return Qt.resolvedUrl("quicksettings/icons/battery_android_bolt.svg");
            } else if (val <= 35) {
                return Qt.resolvedUrl("quicksettings/icons/battery_android_2_bolt.svg");
            } else if (val <= 55) {
                return Qt.resolvedUrl("quicksettings/icons/battery_android_4_bolt.svg");
            } else if (val <= 75) {
                return Qt.resolvedUrl("quicksettings/icons/battery_android_5_bolt.svg");
            } else if (val <= 92) {
                return Qt.resolvedUrl("quicksettings/icons/battery_android_6_bolt.svg");
            } else {
                return Qt.resolvedUrl("quicksettings/icons/battery_android_full_bolt.svg");
            }
        }

        // On battery (Discharging)
        if (val <= 5) {
            return Qt.resolvedUrl("quicksettings/icons/battery_android_alert.svg");
        } else if (val <= 15) {
            return Qt.resolvedUrl("quicksettings/icons/battery_android_0.svg");
        } else if (val <= 35) {
            return Qt.resolvedUrl("quicksettings/icons/battery_android_2.svg");
        } else if (val <= 55) {
            return Qt.resolvedUrl("quicksettings/icons/battery_android_4.svg");
        } else if (val <= 75) {
            return Qt.resolvedUrl("quicksettings/icons/battery_android_5.svg");
        } else if (val <= 92) {
            return Qt.resolvedUrl("quicksettings/icons/battery_android_6.svg");
        } else {
            return Qt.resolvedUrl("quicksettings/icons/battery_android_full.svg");
        }
    }

    Volume.SinkModel {
        id: paSinkModel
    }

    // ==========================================
    // POPUP MANAGEMENT (Handshake & Seamless Switching)
    // ==========================================
    Timer {
        id: popupSwitchTimer
        interval: 35
        repeat: false
        property string targetPopup: ""
        onTriggered: {
            if (targetPopup === "media") {
                mediaDialog.visible = true;
            } else if (targetPopup === "notif") {
                notifDialog.visible = true;
            } else if (targetPopup === "qs") {
                qsDialog.visible = true;
            }
            targetPopup = "";
        }
    }

    function closeAllPopups() {
        popupSwitchTimer.stop();
        mediaDialog.visible = false;
        notifDialog.visible = false;
        qsDialog.visible = false;
    }

    function requestTogglePopup(name) {
        popupSwitchTimer.stop();

        var isTargetOpen = false;
        if (name === "media") isTargetOpen = mediaDialog.visible;
        else if (name === "notif") isTargetOpen = notifDialog.visible;
        else if (name === "qs") isTargetOpen = qsDialog.visible;

        if (isTargetOpen) {
            closeAllPopups();
            return;
        }

        var anyOtherOpen = mediaDialog.visible || notifDialog.visible || qsDialog.visible;
        closeAllPopups();

        if (anyOtherOpen) {
            popupSwitchTimer.targetPopup = name;
            popupSwitchTimer.restart();
        } else {
            if (name === "media") mediaDialog.visible = true;
            else if (name === "notif") notifDialog.visible = true;
            else if (name === "qs") qsDialog.visible = true;
        }
    }

    function toggleQSPopup() {
        requestTogglePopup("qs");
    }

    // ==========================================
    // CLUSTER COMPACT PANEL REPRESENTATION
    // ==========================================
    preferredRepresentation: fullRepresentation
    compactRepresentation: null

    Layout.fillHeight: !isVertical
    Layout.fillWidth: isVertical

    implicitWidth: isVertical ? effectiveHeight : (clusterRow.implicitWidth + clusterRightMargin)
    implicitHeight: isVertical ? (clusterRow.implicitHeight + clusterRightMargin) : effectiveHeight
    width: implicitWidth
    height: implicitHeight
    Layout.minimumWidth: implicitWidth
    Layout.preferredWidth: implicitWidth
    Layout.minimumHeight: implicitHeight
    Layout.preferredHeight: implicitHeight

    Item {
        id: panelContainer
        anchors.fill: parent
        z: 1

        Row {
            id: clusterRow
            anchors.right: root.isVertical ? undefined : parent.right
            anchors.rightMargin: root.isVertical ? 0 : root.clusterRightMargin
            anchors.bottom: root.isVertical ? parent.bottom : undefined
            anchors.bottomMargin: root.isVertical ? root.clusterRightMargin : 0
            anchors.verticalCenter: root.isVertical ? undefined : parent.verticalCenter
            anchors.horizontalCenter: root.isVertical ? parent.horizontalCenter : undefined
            spacing: root.itemSpacing
            height: root.railHeight

            // ----------------------------------------------------
            // 1. MEDIA PILL BUTTON
            // ----------------------------------------------------
            Rectangle {
                id: mediaPillButton
                visible: mediaBackend.effectiveVisible && mediaBackend.hasMedia
                height: root.railHeight
                radius: height / 2

                readonly property bool isPillHovered: mediaMouse.containsMouse || ppMouse.containsMouse
                width: visible ? root.snap(128) : 0
                implicitWidth: width
                implicitHeight: height

                readonly property bool isExpanded: mediaDialog.visible

                color: isExpanded ? root.effectiveAccentColor : "#000000"

                border.color: "#46484d"
                border.width: 1

                Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                Behavior on border.color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

                property bool mediaWasOpen: false

                MouseArea {
                    id: mediaMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                    onPressed: mouse => {
                        mediaPillButton.mediaWasOpen = mediaDialog.visible;
                    }

                    onClicked: mouse => {
                        if (mouse.button === Qt.MiddleButton) {
                            mediaBackend.togglePlaying();
                        } else if (mouse.button === Qt.LeftButton) {
                            if (mediaPillButton.mediaWasOpen) {
                                root.closeAllPopups();
                            } else {
                                root.requestTogglePopup("media");
                            }
                        }
                    }

                    onWheel: wheel => {
                        var delta = (wheel.inverted ? -1 : 1) * (wheel.angleDelta.y ? wheel.angleDelta.y : -wheel.angleDelta.x);
                        if (delta > 0) mediaBackend.changeVolume(0.05);
                        else if (delta < 0) mediaBackend.changeVolume(-0.05);
                    }
                }

                // Left play/pause circular button
                Rectangle {
                    id: playPauseCircle
                    anchors.left: parent.left
                    anchors.leftMargin: (Math.round(((mediaPillButton.height - height) / 2) * root.dpr) + 1) / root.dpr
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property real baseTargetSize: root.snap(Math.round((mediaPillButton.height - root.snap(root.railHeight * 0.19)) * 0.78 * root.dpr) / root.dpr)
                    width: baseTargetSize
                    height: width
                    radius: width / 2
                    color: mediaPillButton.isExpanded
                        ? root.highlightedContentColor
                        : (mediaPillButton.isPillHovered ? (root.isLightContent ? "#ffffff" : "#18181c") : "transparent")
                    Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

                    scale: ppMouse.pressed ? 0.92 : (ppMouse.containsMouse ? 1.08 : 1.0)
                    Behavior on scale { NumberAnimation { duration: Kirigami.Units.shortDuration; easing.type: Easing.OutQuad } }

                    // App Logo (stan spoczynku: widoczny, gdy NIE najechano i NIE jest otwarte okno)
                    Kirigami.Icon {
                        id: appLogoIcon
                        anchors.fill: parent
                        source: mediaBackend.appIcon
                        opacity: (mediaPillButton.isPillHovered || mediaPillButton.isExpanded) ? 0.0 : 1.0
                        visible: opacity > 0.0
                        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
                    }

                    // Play/Pause Icon (widoczny, gdy najechano LUB otwarte jest okno dialogowe)
                    Media.PlayPauseIcon {
                        id: playPauseSymbol
                        anchors.centerIn: parent
                        isPlaying: mediaBackend.isPlaying
                        iconSize: root.snap(5.6)
                        color: mediaPillButton.isExpanded
                            ? root.effectiveAccentColor
                            : (root.isLightContent ? "#18181c" : "#ffffff")
                        opacity: (mediaPillButton.isPillHovered || mediaPillButton.isExpanded) ? 1.0 : 0.0
                        visible: opacity > 0.0
                        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
                    }

                    MouseArea {
                        id: ppMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            mediaBackend.togglePlaying();
                        }
                    }
                }

                // Scrolling Title Text
                Media.MarqueeText {
                    id: marqueeTitle
                    anchors.left: playPauseCircle.right
                    anchors.leftMargin: Kirigami.Units.smallSpacing * 1.5
                    anchors.right: parent.right
                    anchors.rightMargin: Kirigami.Units.smallSpacing * 1.5
                    anchors.verticalCenter: parent.verticalCenter
                    height: parent.height

                    text: mediaBackend.track
                    font.family: "Google Sans Flex"
                    font.weight: Font.DemiBold
                    font.pixelSize: root.snap(10.4)
                    color: mediaPillButton.isExpanded
                        ? root.highlightedContentColor
                        : "#ffffff"
                    scrollOnClickOnly: false
                    scrollOnHoverOnly: true
                    hovered: mediaPillButton.isPillHovered
                }

                // Left fade overlay (visible when text is scrolled to the left)
                Rectangle {
                    anchors.left: marqueeTitle.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 2
                    anchors.bottomMargin: 2
                    width: root.snap(18)
                    z: 5
                    opacity: (marqueeTitle.textOffset < -1.0) ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: mediaPillButton.isExpanded ? root.effectiveAccentColor : "#000000" }
                        GradientStop { position: 1.0; color: "#00000000" }
                    }
                }

                // Right fade overlay (visible when text overflows the right boundary)
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 1
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: 1
                    anchors.bottomMargin: 1
                    width: root.snap(24)
                    radius: height / 2
                    z: 5
                    opacity: marqueeTitle.overflowing ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }

                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#00000000" }
                        GradientStop { position: 0.75; color: mediaPillButton.isExpanded ? root.effectiveAccentColor : "#000000" }
                        GradientStop { position: 1.0; color: mediaPillButton.isExpanded ? root.effectiveAccentColor : "#000000" }
                    }
                }
            }

            // ----------------------------------------------------
            // 2. NOTIFICATIONS BELL BUTTON
            // ----------------------------------------------------
            Item {
                id: notifBellButton
                height: root.railHeight
                width: height
                implicitWidth: width
                implicitHeight: height

                readonly property bool isActive: notifMouse.pressed || notifDialog.visible
                readonly property bool isHovered: notifMouse.containsMouse && !isActive

                // Background highlight capsule
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: root.highlightCapsuleColor
                    opacity: notifBellButton.isActive ? 1.0 : (notifBellButton.isHovered ? 0.25 : 0.0)
                    Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
                }

                Image {
                    id: bellIconImg
                    anchors.centerIn: parent
                    width: root.snap(root.effectiveHeight * 0.40)
                    height: width
                    source: (root.unreadNotifCount > 0)
                        ? (root.isLightContent
                            ? Qt.resolvedUrl("notifications/icons/notifications_unread.svg")
                            : Qt.resolvedUrl("notifications/icons/notifications_unread_dark.svg"))
                        : (root.isDndActive
                            ? Qt.resolvedUrl("notifications/icons/doodlebookos-notifications-disabled.svg")
                            : Qt.resolvedUrl("notifications/icons/notifications.svg"))
                    sourceSize.width: Math.round(width * root.dpr)
                    sourceSize.height: Math.round(height * root.dpr)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    visible: false
                }

                MultiEffect {
                    anchors.fill: bellIconImg
                    source: bellIconImg
                    colorization: notifBellButton.isActive ? 1.0 : (root.unreadNotifCount > 0 ? 0.0 : 1.0)
                    colorizationColor: notifBellButton.isActive ? root.highlightedContentColor : root.topBarContentColor
                    Behavior on colorization { NumberAnimation { duration: Kirigami.Units.shortDuration } }
                    Behavior on colorizationColor { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                }

                property bool notifWasOpen: false

                MouseArea {
                    id: notifMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                    onPressed: mouse => {
                        notifBellButton.notifWasOpen = notifDialog.visible;
                    }

                    onClicked: mouse => {
                        if (mouse.button === Qt.MiddleButton) {
                            root.toggleDoNotDisturbMode();
                        } else if (mouse.button === Qt.LeftButton) {
                            if (notifBellButton.notifWasOpen) {
                                root.closeAllPopups();
                            } else {
                                root.requestTogglePopup("notif");
                            }
                        }
                    }
                }
            }

            // ----------------------------------------------------
            // 3. QUICK SETTINGS BUTTON (Wi-Fi + Power)
            // ----------------------------------------------------
            Item {
                id: qsPillButton
                readonly property real qsPadding: root.snap(root.effectiveHeight * 0.175) // 7 px on each side and between icons
                readonly property real qsIconH: root.qsIconHeight // 16 px icon height

                height: root.railHeight // Normalized Quick Settings pill height
                width: qsPadding + qsIconsRow.implicitWidth + qsPadding
                implicitWidth: width
                implicitHeight: height
                readonly property bool isActive: qsMouse.pressed || qsDialog.visible
                readonly property bool isHovered: qsMouse.containsMouse && !isActive

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: root.highlightCapsuleColor
                    opacity: qsPillButton.isActive ? 1.0 : (qsPillButton.isHovered ? 0.25 : 0.0)
                    Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
                }

                component QSIcon: Item {
                    id: qsi
                    property url source
                    readonly property real iconHeight: qsPillButton.qsIconH

                    // Hidden reader for original SVG aspect ratio (without sourceSize lock)
                    Image {
                        id: rawMetrics
                        source: qsi.source
                        visible: false
                    }

                    readonly property real svgAspect: (rawMetrics.implicitHeight > 0) ? (rawMetrics.implicitWidth / rawMetrics.implicitHeight) : 1.0
                    readonly property real iconWidth: Math.round((iconHeight * svgAspect) * root.dpr) / root.dpr

                    implicitWidth: iconWidth
                    implicitHeight: iconHeight
                    width: iconWidth
                    height: iconHeight

                    Image {
                        id: srcImg
                        anchors.fill: parent
                        source: qsi.source
                        sourceSize.width: Math.round(qsi.iconWidth * root.dpr)
                        sourceSize.height: Math.round(qsi.iconHeight * root.dpr)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        visible: false
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: srcImg
                        colorization: 1.0
                        colorizationColor: qsPillButton.isActive ? root.highlightedContentColor : root.topBarContentColor
                        Behavior on colorizationColor { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                    }
                }

                Row {
                    id: qsIconsRow
                    anchors.centerIn: parent
                    spacing: qsPillButton.qsPadding

                    QSIcon {
                        source: root.currentWifiIcon
                    }

                    QSIcon {
                        source: root.currentBatteryIcon
                    }
                }

                property bool qsWasOpen: false

                MouseArea {
                    id: qsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onPressed: mouse => {
                        qsPillButton.qsWasOpen = qsDialog.visible;
                    }

                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) {
                            if (qsPillButton.qsWasOpen) {
                                root.closeAllPopups();
                            } else {
                                root.requestTogglePopup("qs");
                            }
                        }
                    }
                }
            }
        }
    }

    // ==========================================
    // POPUP DIALOGS (PlasmaCore.Dialog)
    // ==========================================

    // 1. Media Popup Dialog
    PlasmaCore.Dialog {
        id: mediaDialog
        visualParent: mediaPillButton
        location: Plasmoid.location
        flags: Qt.Popup | Qt.WindowStaysOnTopHint
        hideOnWindowDeactivate: true
        backgroundHints: PlasmaCore.Types.NoBackground
        width: mediaExpandedView ? mediaExpandedView.implicitWidth : root.snap(360.0)
        height: mediaExpandedView ? mediaExpandedView.implicitHeight : root.snap(158.4)

        mainItem: Media.ExpandedRepresentation {
            id: mediaExpandedView
            root: mediaBackend
        }
    }

    // 2. Notifications Popup Dialog
    PlasmaCore.AppletPopup {
        id: notifDialog
        visualParent: notifBellButton
        popupDirection: Qt.BottomEdge
        margin: 1
        removeBorderStrategy: PlasmaCore.AppletPopup.Never
        hideOnWindowDeactivate: true
        backgroundHints: PlasmaCore.AppletPopup.StandardBackground
        width: notifFullView ? notifFullView.implicitWidth : root.snap(338.4)
        height: notifFullView ? notifFullView.implicitHeight : root.snap(240.0)

        onVisibleChanged: {
            if (notifDialog.visible) {
                NotifGlobal.Globals.popupNotificationsModel.hideInhibitionSummary();
                var popupModel = NotifGlobal.Globals.popupNotificationsModel;
                if (popupModel) {
                    for (var p = popupModel.rowCount() - 1; p >= 0; --p) {
                        popupModel.expire(popupModel.index(p, 0));
                    }
                }
            } else {
                if (notifHistoryModel) {
                    notifHistoryModel.lastRead = undefined; // reset to now in C++
                    notifHistoryModel.collapseAllGroups();
                }
            }
            NotifGlobal.Globals.positionPopups();
            root.updateUnreadNotifs();
        }

        mainItem: NotificationsUI.FullRepresentation {
            id: notifFullView
            appletInterface: root
            clearHistoryAction: clearHistoryAction
            historyModel: notifHistoryModel
        }
    }

    // 3. Quick Settings Drawer Dialog
    PlasmaCore.AppletPopup {
        id: qsDialog
        visualParent: qsPillButton
        popupDirection: Qt.BottomEdge
        margin: 1
        removeBorderStrategy: PlasmaCore.AppletPopup.Never
        hideOnWindowDeactivate: true
        backgroundHints: PlasmaCore.AppletPopup.StandardBackground
        width: qsFullView ? qsFullView.implicitWidth : root.snap(338.4)
        height: qsFullView ? qsFullView.implicitHeight : root.snap(440.0)

        mainItem: QuickSettingsUI.FullRepresentation {
            id: qsFullView
            appletRoot: root
        }
    }
}
