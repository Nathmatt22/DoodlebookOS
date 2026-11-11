/*
    SPDX-FileCopyrightText: 2011-2013 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2011-2019 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2014-2015 Eike Hein <hein@kde.org>
    SPDX-FileCopyrightText: 2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>

    SPDX-License-Identifier: GPL-3.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.ksvg as KSvg
import org.kde.kirigami as Kirigami

import org.kde.private.desktopcontainment.folder as Folder

import org.kde.plasma.private.containmentlayoutmanager as ContainmentLayoutManager

import "code/FolderTools.js" as FolderTools

ContainmentItem {
    id: root

    switchWidth: { switchSize(); }
    switchHeight: { switchSize(); }

    // Only exists because the default CompactRepresentation doesn't:
    // - open on drag
    // - allow defining a custom drop handler
    // TODO remove once it gains that feature (perhaps optionally?)
    compactRepresentation: (isFolder && !isContainment) ? compactRepresentation : null

    objectName: isFolder ? "folder" : "desktop"

    width: inPanel ? undefined : preferredWidth(false) // Initial size when adding to e.g. desktop.
    height: inPanel ? undefined : preferredHeight(false) // Initial size when adding to e.g. desktop.

    function switchSize() {
        // Support expanding into the full representation on very thick vertical panels.
        if (inPanel && Plasmoid.formFactor === PlasmaCore.Types.Vertical) {
            return Kirigami.Units.gridUnit * 8;
        }

        return 0;
    }

    LayoutMirroring.enabled: Application.layoutDirection === Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    property bool isFolder: (Plasmoid.pluginName === "org.kde.plasma.folder" || Plasmoid.pluginName === "org.kde.desktopcontainment")
    property bool isContainment: Plasmoid.isContainment
    property bool inPanel: (Plasmoid.location !== PlasmaCore.Types.Floating)
    property bool useListViewMode: inPanel && Plasmoid.configuration.viewMode === 0

    // Corona.isScreenUiReady() was added in Plasma 6.4. Calling it unconditionally throws on
    // older Plasma (Debian 13 ships 6.3.6) and would leave the folder view inactive forever,
    // so older releases simply treat the screen as ready.
    function screenUiReady(screen: int): bool {
        const corona = Plasmoid.containment?.corona;
        if (corona && typeof corona.isScreenUiReady === "function") {
            return corona.isScreenUiReady(screen);
        }
        return true;
    }

    property bool isUiReady: screenUiReady(root.screen)

    readonly property int hoverActivateDelay: 750 // Magic number that matches Dolphin's auto-expand folders delay.

    readonly property FolderViewLayerLoader folderViewLayer: fullRepresentationItem.folderViewLayer
    readonly property ContainmentLayoutManager.AppletsLayout appletsLayout: fullRepresentationItem.appletsLayout

    signal closeAllWidgetEditModes()

    // Plasmoid.title is set by a Binding {} in FolderViewLayer
    toolTipSubText: ""
    Plasmoid.icon: (!Plasmoid.configuration.useCustomIcon && folderViewLayer.ready) ? symbolicizeIconName(folderViewLayer.view?.model.iconName) : Plasmoid.configuration.icon

    onScreenChanged: isUiReady = screenUiReady(root.screen)

    // We want to do this here rather than in the model because we don't always want
    // symbolic icons everywhere, but we do know that we always want them in this
    // specific representation right here
    function symbolicizeIconName(iconName) {
        const symbolicSuffix = "-symbolic";
        if (iconName?.endsWith(symbolicSuffix)) {
            return iconName;
        }

        return iconName + symbolicSuffix;
    }

    function addLauncher(desktopUrl) {
        if (!isFolder) {
            return;
        }

        folderViewLayer.view.linkHere(desktopUrl);
    }

    function preferredWidth(forMinimumSize: bool): real {
        if ((isContainment || !folderViewLayer.ready) || (inPanel && !compactRepresentationItem.visible)) {
            return -1;
        } else if (useListViewMode) {
            return (forMinimumSize ? folderViewLayer.view.cellHeight * 4 : Kirigami.Units.gridUnit * 16);
        }

        return (folderViewLayer.view.cellWidth * (forMinimumSize ? 1 : 3)) + (Kirigami.Units.gridUnit * 2);
    }

    function preferredHeight(forMinimumSize: bool): real {
        let height;
        if ((isContainment || !folderViewLayer.ready) || (inPanel && !compactRepresentationItem.visible)) {
            return -1;
        } else if (useListViewMode) {
            height = (folderViewLayer.view.cellHeight * (forMinimumSize ? 1 : 15)) + Kirigami.Units.smallSpacing;
        } else {
            height = (folderViewLayer.view.cellHeight * (forMinimumSize ? 1 : 2)) + Kirigami.Units.gridUnit;
        }

        if (Plasmoid.configuration.labelMode !== 0) {
            height += (folderViewLayer.item as FolderViewLayer).labelHeight;
        }

        return height;
    }

    function isDrag(fromX, fromY, toX, toY) {
        const length = Math.abs(fromX - toX) + Math.abs(fromY - toY);
        return length >= Application.styleHints.startDragDistance;
    }

    onFocusChanged: {
        if (focus && isFolder) {
            (folderViewLayer.item as Item)?.forceActiveFocus();
        }
    }

    onExternalData: (mimetype, data) => {
        Plasmoid.configuration.url = data
    }

    component ShortDropBehavior : Behavior {
        NumberAnimation {
            duration: Kirigami.Units.shortDuration
            easing.type: Easing.InOutQuad
        }
    }

    component LongDropBehavior : Behavior {
        NumberAnimation {
            duration: Kirigami.Units.longDuration
            easing.type: Easing.InOutQuad
        }
    }

    KSvg.FrameSvgItem {
        id: highlightItemSvg

        visible: false

        imagePath: root.inPanel ? "widgets/viewitem" : ""
        prefix: "hover"
    }

    KSvg.FrameSvgItem {
        id: listItemSvg

        visible: false

        imagePath: root.inPanel ? "widgets/viewitem" : ""
        prefix: "normal"
    }

    // FIXME: the use and existence of this property is a workaround
    preloadFullRepresentation: true
    fullRepresentation: FolderViewDropArea {
        id: dropArea

        anchors {
            fill: parent
            leftMargin: (root.isContainment && root.availableScreenRect) ? root.availableScreenRect.x : 0
            topMargin: (root.isContainment && root.availableScreenRect) ? root.availableScreenRect.y : 0

            rightMargin: (root.isContainment && root.availableScreenRect && parent)
                ? (parent.width - root.availableScreenRect.x - root.availableScreenRect.width) : 0

            bottomMargin: Math.max(52, (root.isContainment && root.availableScreenRect && parent)
                ? (parent.height - root.availableScreenRect.y - root.availableScreenRect.height) : 0)
        }

        LongDropBehavior on anchors.topMargin { }
        LongDropBehavior on anchors.leftMargin { }
        LongDropBehavior on anchors.rightMargin { }
        LongDropBehavior on anchors.bottomMargin { }

        property alias folderViewLayer: folderViewLayer
        property alias appletsLayout: appletsLayout

        // Layout size bindings are set in Component.onCompleted

        preventStealing: true

        onDragEnter: event => {
            if (root.isContainment && Plasmoid.immutable && !(root.isFolder && FolderTools.isFileDrag(event))) {
                event.ignore();
            }

            // Don't allow any drops while listing.
            if (root.isFolder && folderViewLayer.view.status === Folder.FolderModel.Listing) {
                event.ignore();
            }

            // Firefox tabs are regular drags. Since all of our drop handling is asynchronous
            // we would accept this drop and have Firefox not spawn a new window. (Bug 337711)
            if (event.mimeData.formats.indexOf("application/x-moz-tabbrowser-tab") !== -1) {
                event.ignore();
            }
        }

        onDragMove: event => {
            // TODO: We should reject drag moves onto file items that don't accept drops
            // (cf. QAbstractItemModel::flags() here, but DeclarativeDropArea currently
            // is currently incapable of rejecting drag events.

            // Trigger autoscroll.
            if (root.isFolder && FolderTools.isFileDrag(event)) {
                handleDragMove(folderViewLayer.view, mapToItem(folderViewLayer.view, event.x, event.y));
            } else if (root.isContainment) {
                appletsLayout.showPlaceHolderAt(
                    Qt.rect(event.x - appletsLayout.minimumItemWidth / 2,
                    event.y - appletsLayout.minimumItemHeight / 2,
                    appletsLayout.minimumItemWidth,
                    appletsLayout.minimumItemHeight)
                );
            }
        }

        onDragLeave: event => {
            // Cancel autoscroll.
            if (root.isFolder) {
                handleDragEnd(folderViewLayer.view);
            }

            if (root.isContainment) {
                appletsLayout.hidePlaceHolder();
            }
        }

        onDrop: event => {
            if (root.isFolder && FolderTools.isFileDrag(event)) {
                handleDragEnd(folderViewLayer.view);
                folderViewLayer.view.drop(root, event, mapToItem(folderViewLayer.view, event.x, event.y));
            } else if (root.isContainment) {
                root.processMimeData(event.mimeData,
                    event.x - appletsLayout.placeHolder.width / 2,
                    event.y - appletsLayout.placeHolder.height / 2);
                event.accept(event.proposedAction);
                appletsLayout.hidePlaceHolder();
            }
        }

        Component {
            id: compactRepresentation
            CompactRepresentation { folderView: folderViewLayer.view }
        }

        Connections {
            target: Plasmoid.containment.corona
            ignoreUnknownSignals: true

            function onEditModeChanged() {
                appletsLayout.editMode = Plasmoid.containment.corona.editMode;
            }

            // When adding panels, sizes change. We want to make sure all panels
            // are loaded, and when they all are loaded, we tell the folderViewLayer loader to start.
            function onScreenUiReadyChanged(screen: int, newLayoutReady: bool) {
                if (root.screen === screen) {
                    root.isUiReady = newLayoutReady;
                }
            }
        }

        // Desktop Background Right-Click Trigger (Material 3 Expressive Context Menu)
        MouseArea {
            id: desktopBackgroundMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            hoverEnabled: false
            onPressed: mouse => {
                if (mouse.button === Qt.RightButton) {
                    mouse.accepted = true;
                    var pt = mapToItem(root, mouse.x, mouse.y);
                    doodlebookContextMenu.openDesktopMenu(pt.x, pt.y, folderViewLayer.model, folderViewLayer.view);
                } else {
                    root.closeAllWidgetEditModes();
                }
            }
            onPressAndHold: mouse => {
                var pt = mapToItem(root, mouse.x, mouse.y);
                doodlebookContextMenu.openDesktopMenu(pt.x, pt.y, folderViewLayer.model, folderViewLayer.view);
            }
        }

        ContainmentLayoutManager.AppletsLayout {
            id: appletsLayout
            anchors.fill: parent
            relayoutLock: width !== root.availableScreenRect.width || height !== root.availableScreenRect.height
            // NOTE: use root.availableScreenRect and not own width and height as they are updated not atomically
            configKey: "ItemGeometries-" + Math.round(root.screenGeometry.width) + "x" + Math.round(root.screenGeometry.height)
            fallbackConfigKey: root.availableScreenRect.width > root.availableScreenRect.height ? "ItemGeometriesHorizontal" : "ItemGeometriesVertical"

            Binding on containment {
                value: Plasmoid
                when: Plasmoid.isContainment
            }
            containmentItem: root
            editModeCondition: Plasmoid.immutable
                    ? ContainmentLayoutManager.AppletsLayout.Locked
                    : ContainmentLayoutManager.AppletsLayout.AfterPressAndHold

            // Sets the containment in edit mode when we go in edit mode as well
            onEditModeChanged: Plasmoid.containment.corona.editMode = editMode;

            minimumItemWidth: Kirigami.Units.gridUnit * 3
            minimumItemHeight: minimumItemWidth

            cellWidth: Kirigami.Units.iconSizes.small
            cellHeight: cellWidth
            defaultItemWidth: cellWidth * 6
            defaultItemHeight: cellHeight * 6

            eventManagerToFilter: (folderViewLayer.item as FolderViewLayer)?.view.view ?? null

            appletContainerComponent: ContainmentLayoutManager.BasicAppletContainer {
                id: appletContainer

                editModeCondition: Plasmoid.immutable
                    ? ContainmentLayoutManager.ItemContainer.Locked
                    : ContainmentLayoutManager.ItemContainer.AfterPressAndHold

                configOverlaySource: "ConfigOverlay.qml"

                MouseArea {
                    id: widgetRightClickArea
                    anchors.fill: parent
                    z: 99999
                    acceptedButtons: Qt.RightButton
                    enabled: true
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            mouse.accepted = true;
                            appletContainer.editMode = !appletContainer.editMode;
                        }
                    }
                }

                Connections {
                    target: root
                    function onCloseAllWidgetEditModes() {
                        if (appletContainer.editMode) {
                            appletContainer.editMode = false;
                        }
                    }
                }

                Connections {
                    target: appletsLayout
                    function onEditModeChanged(): void {
                        if (!Plasmoid.containment.corona.editMode) {
                            appletContainer.cancelEdit();
                        }
                    }
                }

                readonly property bool isFolderApplet: Boolean(applet && applet.plasmoid && applet.plasmoid.pluginName === "org.doodlebookos.appgroup")

                // Optical horizontal alignment to the nearest desktop icon column (sub-grid fine tuning)
                readonly property real folderColumnOffset: {
                    if (!isFolderApplet) return 0;
                    var fv = (folderViewLayer.item as FolderViewLayer)?.view;
                    if (!fv || fv.cellWidth <= 0) return 0;
                    var cW = fv.cellWidth;
                    var centerX = appletContainer.x + (appletContainer.width / 2.0);
                    var targetCol = Math.round((centerX - (cW / 2.0)) / cW);
                    var targetCenterX = (targetCol * cW) + (cW / 2.0);
                    return Math.round(targetCenterX - centerX);
                }

                // Optical vertical alignment to the nearest desktop icon row (sub-grid fine tuning)
                readonly property real folderRowOffset: {
                    if (!isFolderApplet) return 0;
                    var fv = (folderViewLayer.item as FolderViewLayer)?.view;
                    if (!fv || fv.cellHeight <= 0) return 0;
                    var cH = fv.cellHeight;
                    var targetRow = Math.round(appletContainer.y / cH);
                    var targetY = targetRow * cH;
                    return Math.round(targetY - appletContainer.y);
                }

                Translate {
                    id: folderAlignTranslate
                    x: appletContainer.folderColumnOffset
                    y: appletContainer.folderRowOffset
                }

                onAppletChanged: {
                    applet.visible = true;
                    if (appletContainer.isFolderApplet) {
                        applet.transform = [folderAlignTranslate];
                    }
                }

                Drag.dragType: Drag.Automatic
                Drag.active: false
                Drag.supportedActions: Qt.MoveAction
                Drag.mimeData: {
                    "text/x-plasmoidinstanceid": Plasmoid.containment.id+':'+appletContainer.applet.plasmoid.id
                }
                Drag.onDragFinished: dropEvent => {
                    if (dropEvent == Qt.MoveAction) {
                        appletContainer.visible = true
                        appletContainer.applet.visible = true
                    } else {
                        appletContainer.visible = true
                    }
                }

                onUserDrag: (newPosition, dragCenter) => {
                    const pos = mapToItem(root.parent, dragCenter.x, dragCenter.y);
                    const newCont = root.containmentItemAt(pos.x, pos.y);
                    // User likely touched screen edges, so ignore that.
                    if (!newCont) {
                        return;
                    }

                    if (newCont.plasmoid !== Plasmoid) {
                        // First go out of applet edit mode, get rid of the config overlay, release mouse grabs in preparation of applet reparenting
                        cancelEdit();
                        appletsLayout.hidePlaceHolder();
                        appletContainer.grabToImage(result => {
                            appletContainer.Drag.imageSource = result.url
                            appletContainer.visible = false
                            appletContainer.Drag.active = true
                        })
                    }
                }

                ShortDropBehavior on x { }
                ShortDropBehavior on y { }
            }

            placeHolder: ContainmentLayoutManager.PlaceHolder {}

            component FolderViewLayerLoader: Loader {
                property bool ready: status === Loader.Ready
                property FolderView view: (item as FolderViewLayer)?.view ?? null
                property Folder.FolderModel model: (item as FolderViewLayer)?.model ?? null

                source: "FolderViewLayer.qml"
            }


            FolderViewLayerLoader {
                id: folderViewLayer

                anchors.fill: parent

                focus: true

                // Do not set this active by default for desktop, and disable it when folderMode is not used
                active: {
                    if (root.isFolder){
                        if (!root.isContainment) {
                            // We are a folder widget
                            return true;
                        } else {
                            // For desktop, test if the screen is ready
                            return root.isUiReady;
                        }
                    }
                    return false;
                }
                asynchronous: false

                onFocusChanged: {
                    if (!focus && model) {
                        model.clearSelection();
                    }
                }

                Binding {
                    target: folderViewLayer.item
                    property: "inPanel"
                    value: root.inPanel
                }

                Binding {
                    target: folderViewLayer.item
                    property: "useListViewMode"
                    value: root.useListViewMode
                }

                Connections {
                    target: folderViewLayer.view

                    // `FolderViewDropArea` is not a FocusScope. We need to forward manually.
                    function onPressed() {
                        folderViewLayer.forceActiveFocus();
                        root.closeAllWidgetEditModes();
                    }
                }
            }

        }

        DoodlebookContextMenu {
            id: doodlebookContextMenu
            parent: root
            containment: root
            plasmoid: Plasmoid
            z: 999999
        }

        PlasmaCore.Action {
            id: configAction
            text: i18nc("@action:inmenu opens config dialog", "Desktop and Wallpaper")
            icon.name: "preferences-desktop-wallpaper"
            shortcut:"Ctrl+Shift+D"
            onTriggered: Plasmoid.containment.configureRequested(Plasmoid)
        }

        Component.onCompleted: {
            // Layout bindings need to be set delayed; the intermediate steps as the other bindings happen cause loops
            Qt.callLater( () => {
                dropArea.Layout.minimumWidth = Qt.binding(() => root.preferredWidth(root.inPanel))
                dropArea.Layout.minimumHeight = Qt.binding(() => root.preferredHeight(root.inPanel))

                dropArea.Layout.preferredWidth = Qt.binding(() => root.preferredWidth(false))
                dropArea.Layout.preferredHeight = Qt.binding(() => root.preferredHeight(false))

                // Maximum size is intentionally unbounded
            })

            if (!Plasmoid.isContainment) {
                return;
            }

            if (typeof Plasmoid.containment.setContainmentActions === "function") {
                Plasmoid.containment.setContainmentActions("RightButton;NoModifier", "");
            }

            Plasmoid.setInternalAction("configure", configAction)
        }
    }
}
