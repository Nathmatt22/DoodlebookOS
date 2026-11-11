/*
 * SPDX-FileCopyrightText: 2024-2026 Maciej Kujawiński <maciek.kujawinski@gmail.com>
 * SPDX-FileCopyrightText: 2022 Friedrich Schriewer <friedrich.schriewer@gmx.net>
 * SPDX-FileCopyrightText: 2021 Prateek SU <pankajsunal123@gmail.com>
 * SPDX-FileCopyrightText: 2015 Eike Hein <hein@kde.org>
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import QtQuick
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

Item {
  id: favItem

  required property var model
  required property int index
  property var url: (typeof model !== "undefined" && model && "url" in model) ? model.url : ""
  property var triggerModel
  property bool isHiddenApp: false

  width: root.cellSizeWidth
  height: root.cellSizeHeight

  readonly property string appNameStr: ("name" in model && model.name) ? model.name : (("display" in model && model.display) ? model.display : "")

  readonly property string launcherUrlStr: {
    if (typeof model === "undefined" || !model) return "";
    if ("favoriteId" in model && model.favoriteId && model.favoriteId.toString().length > 0) {
      return model.favoriteId.toString();
    }
    if ("entryPath" in model && model.entryPath && model.entryPath.toString().length > 0) {
      return "file://" + model.entryPath.toString();
    }
    if ("url" in model && model.url && model.url.toString().includes("://")) {
      return model.url.toString();
    }
    return "";
  }

  readonly property bool isPinnedToDock: {
    if (!favItem.launcherUrlStr) return false;
    if (typeof kicker !== "undefined" && kicker.tasksModel && kicker.tasksModel.launcherList) {
      var list = kicker.tasksModel.launcherList;
      for (var i = 0; i < list.length; ++i) {
        var u = (list[i] || "").toString();
        if (u === favItem.launcherUrlStr || u.endsWith("/" + favItem.launcherUrlStr)) {
          return true;
        }
      }
    }
    return false;
  }

  property Item dragIconItem: appicon

  z: Drag.active ? 4 : 1

  function openActionMenu(visualParent, x, y) {
    if (typeof root !== "undefined" && root && root.launcherContextMenu) {
        root.launcherContextMenu.open(visualParent, Qt.point(x, y), {
            appName: favItem.appNameStr,
            launcherUrlStr: favItem.launcherUrlStr,
            storageId: ("storageId" in model && model.storageId) ? model.storageId : "",
            isPinnedToDock: favItem.isPinnedToDock,
            isHidden: favItem.isHiddenApp,
            onPinRequested: function(url) {
                if (typeof kicker !== "undefined" && kicker.tasksModel) {
                    kicker.tasksModel.requestAddLauncher(url);
                }
            },
            onToggleHideRequested: function(url, currentlyHidden) {
                if (typeof combinedRoot !== "undefined" && combinedRoot) {
                    if (currentlyHidden && typeof combinedRoot.unhideApp === "function") {
                        combinedRoot.unhideApp(url, favItem.appNameStr);
                        return;
                    } else if (!currentlyHidden && typeof combinedRoot.hideApp === "function") {
                        combinedRoot.hideApp(url, favItem.appNameStr);
                        return;
                    }
                }
                var config = (typeof root !== "undefined" && root && root.plasmoidConfiguration) ? root.plasmoidConfiguration : (typeof Plasmoid !== "undefined" ? Plasmoid.configuration : null);
                if (!config) return;
                var list = config.hiddenApps ? Array.from(config.hiddenApps) : [];
                var norm = (url || "").toString();
                if (currentlyHidden) {
                    list = list.filter(function(item) {
                        return item !== norm && !norm.endsWith("/" + item) && !item.endsWith("/" + norm);
                    });
                } else {
                    if (list.indexOf(norm) === -1) {
                        list.push(norm);
                    }
                }
                config.hiddenApps = list;
                if (typeof config.writeConfig === "function") {
                    config.writeConfig();
                }
            }
        });
    }
  }

  function trigger() {
    triggerModel.trigger(index, "", null);
    root.toggle();
  }

  function performDrag(handler) {
    // Dragging towards the desktop makes the pointer leave the launcher popup, which used to
    // close and destroy the window hosting the drag source: on Wayland that crashes
    // plasmashell (KDE bug 449426/488515). Keep it alive while dragging, then close it the way
    // hideOnWindowDeactivate would have once the gesture ends.
    if (typeof kicker !== "undefined" && kicker && typeof kicker.setDragInProgress === "function") {
      kicker.setDragInProgress(handler.active);
    }

    if (!handler.active) {
      kicker.dragSource.Drag.active = false;
      kicker.dragSource.Drag.imageSource = "";
      kicker.dragSource.sourceItem = null;
      return;
    }
    favItem.dragIconItem.grabToImage(result => {
      if (!handler.active) {
        return;
      }
      kicker.dragSource.sourceItem = favItem;
      kicker.dragSource.Drag.imageSource = result.url;
      // Qt serializes this to the compositor; a QUrl object instead of a string can break
      // the Wayland data transfer, so normalize it.
      var dragUrl = (favItem.launcherUrlStr || favItem.url || "").toString();
      kicker.dragSource.Drag.mimeData = {
        "text/uri-list" : [dragUrl]
      };
      kicker.dragSource.Drag.active = handler.active;
    });
  }

  readonly property bool isCurrent: {
    var isCurr = (typeof GridView.isCurrentItem !== "undefined") && Boolean(GridView.isCurrentItem);
    var isSrch = (typeof main !== "undefined") && Boolean(main.searching);
    var isKbd = (typeof GridView.view !== "undefined") && GridView.view && Boolean(GridView.view.movedWithKeyboard);
    return isCurr && (isSrch || isKbd);
  }
  readonly property bool isHovered: ma.containsMouse

  readonly property bool usePlasmaTheme: Boolean(typeof root !== "undefined" && root && root.plasmoidConfiguration ? root.plasmoidConfiguration.usePlasmaTheme : true)

  Rectangle {
    id: highlightCard
    anchors.fill: parent
    anchors.margins: 4
    radius: 16
    visible: favItem.isCurrent
    color: favItem.usePlasmaTheme
      ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.30)
      : (main.isDarkTheme ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.08))
    border.color: favItem.usePlasmaTheme
      ? Kirigami.Theme.highlightColor
      : (main.isDarkTheme ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(0, 0, 0, 0.15))
    border.width: 1.5
    z: 0
  }

  Item {
    id: appicon
    anchors.top: parent.top
    anchors.topMargin: Kirigami.Units.smallSpacing * 1.5
    anchors.horizontalCenter: parent.horizontalCenter
    width: root.iconSize
    height: width

    scale: favItem.isHovered ? 1.08 : 1.0
    transformOrigin: Item.Center

    Behavior on scale {
      NumberAnimation {
        duration: 80
        easing.type: Easing.OutQuad
      }
    }

    Kirigami.Icon {
      id: rawIcon
      anchors.fill: parent
      implicitWidth: parent.width
      implicitHeight: parent.height
      roundToIconSize: false
      source: model.decoration
      visible: true
    }
  }

  PlasmaComponents.Label {
    id: appname
    text: ("name" in model ? model.name : model.display)
    font.family: "Google Sans Flex"
    font.pixelSize: 11
    font.weight: Font.Medium
    color: main.textColor
    anchors {
      top: appicon.bottom
      left: parent.left
      right: parent.right
      topMargin: Kirigami.Units.smallSpacing + 2
      leftMargin: Kirigami.Units.smallSpacing
      rightMargin: Kirigami.Units.smallSpacing
    }
    textFormat: Text.PlainText
    elide: Text.ElideMiddle
    horizontalAlignment: Text.AlignHCenter
    maximumLineCount: 2
    wrapMode: Text.Wrap
  }

  MouseArea {
      id: ma
      anchors.fill: parent
      z: parent.z + 1
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      hoverEnabled: true
      onClicked: (mouse) => {
          if (mouse.button === Qt.RightButton) {
              favItem.openActionMenu(favItem, mouse.x, mouse.y);
          } else {
              trigger();
          }
      }
      onEntered: {
        var currentView = GridView.view;
        if (currentView && currentView.movedWithKeyboard) {
          return;
        }

        if (currentView && !currentView.activeFocus) {
          currentView.forceActiveFocus(Qt.MouseFocusReason);
        }
      }
  }

  DragHandler {
      id: dragHandler
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
      enabled: favItem.dragIconItem !== null
      target: null
      onActiveChanged: favItem.performDrag(this)
  }
}
