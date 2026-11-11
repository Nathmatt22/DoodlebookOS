/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

pragma ComponentBehavior: Bound
import QtQuick
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.taskmanager as TaskManager
import org.kde.plasma.private.kicker as Kicker

PlasmoidItem {
    id: kicker

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    property alias tasksModel: tasksModel
    property alias rootModel: rootModel
    property alias runnerModel: runnerModel
    property alias launcherPopup: launcherPopup
    property alias phoneHubPopup: phoneHubPopup
    property Item compactRepItem: null

    property QtObject globalFavorites: rootModel.favoritesModel
    property QtObject systemFavorites: rootModel.systemFavoritesModel

    TaskManager.VirtualDesktopInfo {
        id: virtualDesktopInfo
    }

    TaskManager.TasksModel {
        id: tasksModel
        property bool initialized: false

        virtualDesktop: virtualDesktopInfo.currentDesktop
        // filterByCurrentVirtualDesktop only exists in Plasma 6.8+; filterByVirtualDesktop is
        // the equivalent flag present in every supported release. The 6.8-only one is applied
        // in Component.onCompleted below, after a typeof check, so 6.3 keeps loading.
        filterByVirtualDesktop: false
        filterByScreen: false
        filterByActivity: false
        sortMode: TaskManager.TasksModel.SortManual
        launchInPlace: true
        separateLaunchers: true
        hideActivatedLaunchers: true
        groupMode: TaskManager.TasksModel.GroupApplications
        groupInline: false
        groupingWindowTasksThreshold: -1

        onLauncherListChanged: {
            if (!initialized) return;
            if (launcherList) {
                Plasmoid.configuration.launchers = launcherList;
                if (typeof Plasmoid.configuration.writeConfig === "function") {
                    Plasmoid.configuration.writeConfig();
                }
            }
        }

        Component.onCompleted: {
            if (typeof filterByCurrentVirtualDesktop !== "undefined") {
                filterByCurrentVirtualDesktop = false;
            }

            var raw = Plasmoid.configuration.launchers;
            var list = [];
            if (raw) {
                if (Array.isArray(raw)) {
                    list = Array.from(raw);
                } else if (typeof raw === "string") {
                    list = raw.split(",").map(s => s.trim()).filter(s => s.length > 0);
                } else if (typeof raw.length === "number") {
                    for (var i = 0; i < raw.length; ++i) {
                        list.push(raw[i]);
                    }
                }
            }
            if (list.length === 0) {
                list = [
                    "preferred://browser",
                    "preferred://filemanager",
                    "applications:org.kde.konsole.desktop",
                    "applications:org.kde.discover.desktop",
                    "applications:systemsettings.desktop"
                ];
                Plasmoid.configuration.launchers = list;
                if (typeof Plasmoid.configuration.writeConfig === "function") {
                    Plasmoid.configuration.writeConfig();
                }
            }
            tasksModel.launcherList = list;
            initialized = true;
        }
    }

    Kicker.RootModel {
        id: rootModel
        appletInterface: kicker
        autoPopulate: false
        appNameFormat: 0
        flat: true
        sorted: true
        showSeparators: false
        showAllApps: true
        showAllAppsCategorized: false
        showTopLevelItems: true
        showRecentApps: true
        showRecentDocs: true
        showPowerSession: false

        onRecentOrderingChanged: {
            Plasmoid.configuration.recentOrdering = recentOrdering;
        }

        Component.onCompleted: {
            favoritesModel.initForClient("org.kde.plasma.kicker.favorites.instance-" + Plasmoid.id);
            if (!Plasmoid.configuration.favoritesPortedToKAstats) {
                if (favoritesModel.count < 1) {
                    favoritesModel.portOldFavorites(Plasmoid.configuration.favoriteApps);
                }
                Plasmoid.configuration.favoritesPortedToKAstats = true;
            }
            rootModel.refresh();
        }
    }

    Connections {
        target: kicker.globalFavorites
        function onFavoritesChanged() {
            Plasmoid.configuration.favoriteApps = target.favorites;
        }
    }

    Connections {
        target: kicker.systemFavorites
        function onFavoritesChanged() {
            Plasmoid.configuration.favoriteSystemActions = target.favorites;
        }
    }

    Connections {
        target: Plasmoid.configuration
        function onFavoriteAppsChanged() {
            kicker.globalFavorites.favorites = Plasmoid.configuration.favoriteApps;
        }
        function onFavoriteSystemActionsChanged() {
            kicker.systemFavorites.favorites = Plasmoid.configuration.favoriteSystemActions;
        }
        function onAppsRefreshTriggerChanged() {
            rootModel.refresh();
        }
    }

    Kicker.RunnerModel {
        id: runnerModel
        favoritesModel: kicker.globalFavorites
        appletInterface: kicker
        mergeResults: true
    }

    readonly property Item dragSource: Item {
        id: dragSource
        property Item sourceItem

        Drag.dragType: Drag.Automatic
        // Let the desktop link the dragged .desktop file instead of only copying it.
        Drag.supportedActions: Qt.CopyAction | Qt.LinkAction
    }

    // A drag must not outlive the window that owns its source: destroying that surface while
    // the gesture is in flight crashes plasmashell on Wayland (KDE bugs 449426 / 488515).
    // Every drag started in this dock reports here, so the popups that host drag sources stay
    // alive until the gesture ends, whatever the starting point.
    property bool dragInProgress: false

    function setDragInProgress(active) {
        const wasActive = dragInProgress;
        dragInProgress = active;

        if (launcherPopup && typeof launcherPopup.dragInProgress !== "undefined") {
            launcherPopup.dragInProgress = active;
        }

        // The launcher popup was only kept open for the gesture; close it once it is over.
        if (!active && wasActive && launcherPopup && launcherPopup.visible) {
            launcherPopup.closeAnimated();
        }
    }

    preferredRepresentation: compactRepresentation

    compactRepresentation: CompactRepresentation {
        id: compactRep
        tasksModel: kicker.tasksModel
        launcherPopup: kicker.launcherPopup
        phoneHubPopup: kicker.phoneHubPopup
    }

    fullRepresentation: compactRepresentation

    PhoneHubPopup {
        id: phoneHubPopup
        visualParentItem: (kicker.compactRepItem && kicker.compactRepItem.phoneHubBtn) ? kicker.compactRepItem.phoneHubBtn : null
        popupHeight: Math.round(Screen.height * 0.60)
        panelHeight: kicker.compactRepItem ? kicker.compactRepItem.effectiveHeight : 52
    }

    // DimOverlay imports org.kde.layershell, which Debian ships as a separate package
    // (qml6-module-org-kde-layershell). If it is missing, the Loader keeps the dock alive
    // instead of failing the whole file; LauncherPopup already ignores a null overlay
    // because every call site checks typeof showOverlay === "function".
    Loader {
        id: dimOverlay

        source: "DimOverlay.qml"
        asynchronous: false

        readonly property real overlayBottomGap: kicker.compactRepItem ? kicker.compactRepItem.effectiveHeight : 52

        onLoaded: {
            if (item) {
                item.bottomGap = Qt.binding(() => overlayBottomGap);
            }
        }
    }

    LauncherPopup {
        id: launcherPopup
        rootModel: rootModel
        plasmoidConfiguration: Plasmoid.configuration
        dimOverlayItem: dimOverlay.item
        visualParentItem: (kicker.compactRepItem && kicker.compactRepItem.popupAnchor) ? kicker.compactRepItem.popupAnchor : kicker.compactRepItem
        popupWidth: Math.min(Screen.width - 40, (Plasmoid.configuration.popupWidth || 680))
        popupHeight: Math.round(Screen.height * 0.66)
        panelHeight: kicker.compactRepItem ? kicker.compactRepItem.effectiveHeight : 52
    }

    // DBus.Properties only exists in Plasma 6.8+. The bridge is loaded from its own file so
    // that older Plasma releases keep the dock usable instead of failing to load at all.
    Loader {
        id: krunnerBridgeLoader

        source: "KRunnerBridge.qml"
        asynchronous: false

        onLoaded: {
            if (item) {
                item.launcherPopup = launcherPopup;
            }
        }
    }

    Connections {
        target: Plasmoid
        function onActivated() {
            launcherPopup.toggle();
        }
    }

    Component.onCompleted: {
        if (Plasmoid.containment && typeof Plasmoid.containment.setContainmentActions === "function") {
            Plasmoid.containment.setContainmentActions("RightButton;NoModifier", "");
        }
    }
}