import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Bookmarks.js" as Bookmarks
import "Engines.js" as Engines

// Slide-down launcher: SUPER+B opens it in "search" mode (web search /
// direct URL, via xdg-open so it honors whatever the user's default
// browser is), SUPER+SHIFT+B opens it in "bookmarks" mode (browse/add
// entries from a plain-text bookmarks file). Both modes share one panel;
// the tabs in the header switch between them without a new keybind.
Item {
  id: root

  property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/weblauncher"
  property var shell: null
  property var manifest: null

  property bool opened: false
  // The wlr layer-shell surface itself; kept mapped slightly longer than
  // `opened` so the slide-up close animation has time to actually play
  // before the window disappears (unlike mapping, unmapping is instant).
  property bool surfaceVisible: false
  property string mode: "search" // "search" | "bookmarks"
  property bool adding: false

  property string engine: "duckduckgo"
  property string bookmarksFile: "~/Documents/bookmarks/bookmarks.txt"
  readonly property string bookmarksAbsolutePath: root.bookmarksFile.indexOf("~/") === 0
    ? (Quickshell.env("HOME") + root.bookmarksFile.slice(1))
    : root.bookmarksFile

  property string query: ""
  property var bookmarkItems: []
  property var bookmarkTree: ({ children: ({}), bookmarks: [] })
  property var pathStack: []
  property var displayEntries: []
  property int selectedIndex: 0
  property var categorySuggestions: []
  property var subcategorySuggestions: []
  property int categorySuggestionIndex: -1
  property int subcategorySuggestionIndex: -1

  readonly property var currentPreview: Engines.previewFor(root.engine, root.query)

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int cardWidth: Math.min(Style.space(700), panel.width - Style.space(80))
  property int rowHeight: Math.max(Style.space(30), Style.font.subtitle + Style.spacing.md * 2)

  function open(payloadJson) {
    var requestedMode = "search"
    try {
      var payload = JSON.parse(payloadJson || "{}")
      if (payload && (payload.mode === "search" || payload.mode === "bookmarks")) requestedMode = payload.mode
    } catch (e) {}

    if (root.opened && root.mode === requestedMode && !root.adding) {
      root.dismiss()
      return
    }

    root.mode = requestedMode
    root.adding = false
    root.surfaceVisible = true
    root.opened = true
    root.pathStack = []
    if (searchField) searchField.text = ""
    if (requestedMode === "bookmarks") bookmarksFileView.reload()
    root.focusPrimaryField()
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "weblauncher")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function focusPrimaryField() {
    Qt.callLater(function() {
      if (root.adding) { if (categoryField) categoryField.forceActiveFocus() }
      else if (searchField) searchField.forceActiveFocus()
    })
  }

  function switchMode(nextMode) {
    if (root.mode === nextMode && !root.adding) return
    root.mode = nextMode
    root.adding = false
    root.query = ""
    root.selectedIndex = 0
    root.pathStack = []
    if (searchField) searchField.text = ""
    if (nextMode === "bookmarks") bookmarksFileView.reload()
    root.focusPrimaryField()
  }

  function loadBookmarks(raw) {
    root.bookmarkItems = Bookmarks.parseBookmarks(raw)
    root.bookmarkTree = Bookmarks.buildTree(root.bookmarkItems)
    root.rebuildBookmarks()
  }

  // Empty query: browse the folder tree at the current pathStack depth,
  // subfolders alphabetically first, then this level's own bookmarks.
  // Non-empty query: ignore the tree and flat-search every bookmark,
  // same as before — typing always searches everything.
  function rebuildBookmarks() {
    var entries
    if (root.query) {
      entries = Bookmarks.filterBookmarks(root.bookmarkItems, root.query, 300).map(function(it) {
        return { type: "bookmark", name: it.path, url: it.url }
      })
    } else {
      var node = Bookmarks.nodeAtPath(root.bookmarkTree, root.pathStack)
      if (!node) {
        root.pathStack = []
        node = root.bookmarkTree
      }
      entries = Bookmarks.childrenOf(node)
    }
    root.displayEntries = entries
    if (root.selectedIndex >= entries.length) root.selectedIndex = Math.max(0, entries.length - 1)
  }

  function moveSelection(delta) {
    if (root.displayEntries.length === 0) return
    root.selectedIndex = (root.selectedIndex + delta + root.displayEntries.length) % root.displayEntries.length
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function openTarget(url) {
    root.dismiss()
    Quickshell.execDetached(["xdg-open", url])
  }

  function submitSearch() {
    if (!root.currentPreview) return
    root.openTarget(root.currentPreview.target)
  }

  function activateEntry(index) {
    if (index < 0 || index >= root.displayEntries.length) return
    var entry = root.displayEntries[index]
    if (entry.type === "folder") root.drillInto(entry.name)
    else root.openTarget(Engines.resolveUrl(entry.url))
  }

  function drillInto(name) {
    root.pathStack = root.pathStack.concat([name])
    root.selectedIndex = 0
    if (searchField) searchField.text = ""
    root.rebuildBookmarks()
  }

  function drillUp() {
    if (root.pathStack.length === 0) return
    root.pathStack = root.pathStack.slice(0, -1)
    root.selectedIndex = 0
    root.rebuildBookmarks()
  }

  function setEngine(id) {
    root.engine = id
    saveSettingsProc.command = [root.pluginDir + "/bin/save-settings", id, root.bookmarksFile]
    saveSettingsProc.running = true
  }

  function editBookmarksFile() {
    root.dismiss()
    // Omarchy's own "open the user's configured default editor" wrapper —
    // it already handles TUI-in-a-terminal vs GUI editors correctly, so
    // there's no need to read $EDITOR (which is meant for inline shell use,
    // e.g. "omarchy-launch-editor --inline", and can't just be exec'd as-is)
    // or wrap xdg-terminal-exec ourselves.
    Quickshell.execDetached(["omarchy-launch-editor", root.bookmarksAbsolutePath])
  }

  function startAdd() {
    root.adding = true
    if (categoryField) categoryField.text = ""
    if (subcategoryField) subcategoryField.text = ""
    if (nameField) nameField.text = ""
    if (urlField) urlField.text = ""
    root.updateCategorySuggestions()
    root.updateSubcategorySuggestions()
    root.focusPrimaryField()
  }

  function cancelAdd() {
    root.adding = false
    root.focusPrimaryField()
  }

  // Filters existing top-level category names as the user types; an
  // empty field shows all of them so they can be browsed, not just
  // searched — the point is picking an existing one without retyping it.
  // Suggestions changing invalidates whatever row was arrow-highlighted.
  function updateCategorySuggestions() {
    var all = Bookmarks.folderNames(root.bookmarkTree)
    var q = categoryField.text.trim().toLowerCase()
    root.categorySuggestions = q ? all.filter(function(n) { return n.toLowerCase().indexOf(q) !== -1 }) : all
    root.categorySuggestionIndex = -1
  }

  function updateSubcategorySuggestions() {
    var parent = categoryField.text.trim() ? Bookmarks.nodeAtPath(root.bookmarkTree, [categoryField.text.trim()]) : null
    var all = Bookmarks.folderNames(parent)
    var q = subcategoryField.text.trim().toLowerCase()
    root.subcategorySuggestions = q ? all.filter(function(n) { return n.toLowerCase().indexOf(q) !== -1 }) : all
    root.subcategorySuggestionIndex = -1
  }

  function selectCategorySuggestion(index) {
    if (index < 0 || index >= root.categorySuggestions.length) return
    categoryField.text = root.categorySuggestions[index]
    root.updateSubcategorySuggestions()
    subcategoryField.forceActiveFocus()
  }

  function selectSubcategorySuggestion(index) {
    if (index < 0 || index >= root.subcategorySuggestions.length) return
    subcategoryField.text = root.subcategorySuggestions[index]
    nameField.forceActiveFocus()
  }

  function submitAdd() {
    var name = nameField.text.trim()
    var url = urlField.text.trim()
    if (!name || !url) return
    var category = categoryField.text.trim()
    var subcategory = subcategoryField.text.trim()
    var fullCategory = category && subcategory ? category + "/" + subcategory : category
    addBookmarkProc.command = [root.pluginDir + "/bin/add-bookmark", root.bookmarksAbsolutePath, fullCategory, name, url]
    addBookmarkProc.running = true
  }

  FileView {
    id: settingsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weblauncher.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(text())
        if (data && data.engine) root.engine = data.engine
        if (data && data.bookmarksFile) root.bookmarksFile = data.bookmarksFile
      } catch (e) {}
    }
  }

  FileView {
    id: bookmarksFileView
    path: root.bookmarksAbsolutePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadBookmarks(text())
    onLoadFailed: root.loadBookmarks("")
  }

  Process { id: saveSettingsProc }

  Process {
    id: addBookmarkProc
    onExited: {
      root.adding = false
      bookmarksFileView.reload()
      root.focusPrimaryField()
    }
  }

  ListModel { id: bookmarkModel }

  onDisplayEntriesChanged: {
    bookmarkModel.clear()
    for (var i = 0; i < displayEntries.length; i++)
      bookmarkModel.append({
        entryType: displayEntries[i].type,
        entryName: displayEntries[i].name,
        entryUrl: displayEntries[i].url || ""
      })
  }

  PanelWindow {
    id: panel
    visible: root.surfaceVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "weblauncher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: cardColumn.implicitHeight + root.contentMargin * 2
      radius: root.cornerRadius
      anchors.top: parent.top
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.topMargin: root.opened ? Style.space(96) : -(height + Style.space(160))
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      Behavior on anchors.topMargin {
        NumberAnimation {
          duration: 180
          easing.type: Easing.OutCubic
          onRunningChanged: if (!running && !root.opened) root.surfaceVisible = false
        }
      }

      MouseArea { anchors.fill: parent; onClicked: {} }

      Column {
        id: cardColumn
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.spacing.md

        // ------------------------------------------------------- mode tabs
        Row {
          visible: !root.adding
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.spacing.xs

          Repeater {
            model: [ { key: "search", label: "Web Search" }, { key: "bookmarks", label: "Bookmarks" } ]
            delegate: Rectangle {
              required property var modelData
              width: tabLabel.implicitWidth + Style.spacing.md * 2
              height: Style.spacing.controlHeight
              radius: root.cornerRadius
              color: root.mode === modelData.key ? root.selectedBackground : "transparent"

              Text {
                id: tabLabel
                anchors.centerIn: parent
                text: modelData.label
                color: root.mode === modelData.key ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.switchMode(modelData.key)
              }
            }
          }
        }

        // ---------------------------------------------------- search header
        RowLayout {
          width: parent.width
          visible: !root.adding
          spacing: Style.spacing.md

          Text {
            text: root.mode === "search" ? "" : ""
            color: root.foreground
            font.pixelSize: Style.font.heading
            Layout.alignment: Qt.AlignVCenter
          }

          TextField {
            id: searchField
            Layout.fillWidth: true
            foreground: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            placeholderText: root.mode === "search" ? "Search the web or paste a URL…" : "Search bookmarks…"
            onTextChanged: {
              root.query = text
              if (root.mode === "bookmarks") root.rebuildBookmarks()
            }
            onAccepted: {
              if (root.mode === "search") root.submitSearch()
              else root.activateEntry(root.selectedIndex)
            }
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                if (searchField.text.length > 0) searchField.text = ""
                else root.dismiss()
                event.accepted = true
              } else if (root.mode === "bookmarks" && event.key === Qt.Key_Down) {
                root.moveSelection(1)
                event.accepted = true
              } else if (root.mode === "bookmarks" && event.key === Qt.Key_Up) {
                root.moveSelection(-1)
                event.accepted = true
              } else if (root.mode === "bookmarks" && event.key === Qt.Key_Backspace
                         && searchField.text.length === 0 && root.pathStack.length > 0) {
                root.drillUp()
                event.accepted = true
              } else if (root.mode === "bookmarks" && searchField.text.length === 0
                         && event.key === Qt.Key_Right) {
                var entry = root.displayEntries[root.selectedIndex]
                if (entry && entry.type === "folder") root.drillInto(entry.name)
                event.accepted = true
              } else if (root.mode === "bookmarks" && searchField.text.length === 0
                         && event.key === Qt.Key_Left && root.pathStack.length > 0) {
                root.drillUp()
                event.accepted = true
              } else if (root.mode === "bookmarks" && event.key === Qt.Key_Tab
                         && !(event.modifiers & Qt.ShiftModifier)) {
                root.startAdd()
                event.accepted = true
              } else if (root.mode === "bookmarks" && (event.key === Qt.Key_Backtab
                         || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier)))) {
                root.editBookmarksFile()
                event.accepted = true
              }
            }
          }
        }

        // ------------------------------------------------------- add header
        RowLayout {
          width: parent.width
          visible: root.adding
          spacing: Style.spacing.md

          Text {
            text: "Add bookmark"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            Layout.fillWidth: true
          }

          Text {
            text: "Cancel"
            color: root.selectedText
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.cancelAdd() }
          }
        }

        // ----------------------------------------------------- engine chips
        Row {
          visible: root.mode === "search" && !root.adding
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.spacing.sm

          Repeater {
            model: Engines.ENGINES
            delegate: Rectangle {
              required property var modelData
              width: engineRow.implicitWidth + Style.spacing.md * 2
              height: Style.spacing.controlHeight
              radius: root.cornerRadius
              color: root.engine === modelData.id ? root.selectedBackground : "transparent"
              border.color: root.border
              border.width: root.engine === modelData.id ? 0 : 1

              Row {
                id: engineRow
                anchors.centerIn: parent
                spacing: Style.spacing.xs

                Image {
                  width: Style.font.body
                  height: Style.font.body
                  anchors.verticalCenter: parent.verticalCenter
                  source: modelData.favicon
                  asynchronous: true
                  cache: true
                  fillMode: Image.PreserveAspectFit
                  visible: status === Image.Ready
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.label
                  color: root.engine === modelData.id ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setEngine(modelData.id)
              }
            }
          }
        }

        // ------------------------------------------------------ preview row
        Rectangle {
          visible: root.mode === "search" && !root.adding && !!root.currentPreview
          width: parent.width
          height: root.rowHeight
          radius: root.cornerRadius
          color: root.selectedBackground

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.md
            anchors.rightMargin: Style.spacing.md
            text: root.currentPreview ? root.currentPreview.label : ""
            color: root.selectedText
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            elide: Text.ElideMiddle
          }

          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.submitSearch() }
        }

        // ------------------------------------------------------- bookmark links
        Item {
          visible: root.mode === "bookmarks" && !root.adding
          width: parent.width
          height: addBookmarkLink.implicitHeight

          Text {
            id: addBookmarkLink
            anchors.left: parent.left
            text: "+ Add bookmark (Tab)"
            color: root.selectedText
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle

            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.startAdd() }
          }

          Item {
            anchors.right: parent.right
            width: editRow.implicitWidth
            height: editRow.implicitHeight

            Row {
              id: editRow
              spacing: Style.spacing.xs

              Text {
                text: "\uf040"
                color: root.selectedText
                font.pixelSize: Style.font.subtitle
                anchors.verticalCenter: parent.verticalCenter
              }

              Text {
                text: "Edit bookmarks (Shift+Tab)"
                color: root.selectedText
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.editBookmarksFile()
            }
          }
        }

        // ---------------------------------------------------------- breadcrumb
        Item {
          visible: root.mode === "bookmarks" && !root.adding && !root.query && root.pathStack.length > 0
          width: parent.width
          height: backLink.implicitHeight

          Row {
            id: backLink
            spacing: Style.spacing.xs

            Text {
              text: "‹ Back"
              color: root.selectedText
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.drillUp()
              }
            }

            Text {
              text: "—  " + root.pathStack.join(" ▸ ")
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
            }
          }
        }

        // -------------------------------------------------------- bookmarks list
        ListView {
          id: resultList
          visible: root.mode === "bookmarks" && !root.adding
          width: parent.width
          height: Math.min(Style.space(360), Math.max(1, bookmarkModel.count) * root.rowHeight)
          clip: true
          model: bookmarkModel

          delegate: Rectangle {
            required property int index
            required property string entryType
            required property string entryName
            required property string entryUrl
            width: resultList.width
            height: root.rowHeight
            radius: root.cornerRadius
            color: index === root.selectedIndex ? root.selectedBackground : "transparent"

            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.spacing.md
              anchors.rightMargin: Style.spacing.md
              text: (entryType === "folder" ? "  " : "") + entryName + (entryType === "folder" ? "  ›" : "")
              color: index === root.selectedIndex ? root.selectedText : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              elide: Text.ElideMiddle
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: { root.selectedIndex = index; root.activateEntry(index) }
            }
          }
        }

        Text {
          visible: root.mode === "bookmarks" && !root.adding && bookmarkModel.count === 0
          text: root.query
            ? "No bookmarks match."
            : (root.pathStack.length > 0 ? "Nothing in this category." : "No bookmarks yet — click “+ Add bookmark” to add one.")
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
        }

        // ------------------------------------------------------------ add form
        Column {
          visible: root.adding
          width: parent.width
          spacing: Style.spacing.sm

          TextField {
            id: categoryField
            width: parent.width
            foreground: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            placeholderText: "Category (optional) — type or pick below"
            KeyNavigation.tab: subcategoryField
            onTextChanged: { root.updateCategorySuggestions(); root.updateSubcategorySuggestions() }
            onAccepted: {
              if (root.categorySuggestionIndex >= 0) root.selectCategorySuggestion(root.categorySuggestionIndex)
              else root.submitAdd()
            }
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.cancelAdd()
                event.accepted = true
              } else if (event.key === Qt.Key_Down && root.categorySuggestions.length > 0) {
                root.categorySuggestionIndex = Math.min(root.categorySuggestionIndex + 1, root.categorySuggestions.length - 1)
                categorySuggestionList.positionViewAtIndex(root.categorySuggestionIndex, ListView.Contain)
                event.accepted = true
              } else if (event.key === Qt.Key_Up && root.categorySuggestionIndex >= 0) {
                root.categorySuggestionIndex = root.categorySuggestionIndex - 1
                if (root.categorySuggestionIndex >= 0)
                  categorySuggestionList.positionViewAtIndex(root.categorySuggestionIndex, ListView.Contain)
                event.accepted = true
              }
            }
          }

          ListView {
            id: categorySuggestionList
            visible: categoryField.activeFocus && root.categorySuggestions.length > 0
            width: parent.width
            height: Math.min(Style.space(150), root.categorySuggestions.length * root.rowHeight)
            clip: true
            model: root.categorySuggestions

            delegate: Rectangle {
              required property string modelData
              required property int index
              width: categorySuggestionList.width
              height: root.rowHeight
              color: index === root.categorySuggestionIndex ? root.selectedBackground : "transparent"
              radius: root.cornerRadius

              Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.spacing.md
                text: modelData
                color: index === root.categorySuggestionIndex ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                elide: Text.ElideMiddle
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectCategorySuggestion(index)
              }
            }
          }

          TextField {
            id: subcategoryField
            width: parent.width
            foreground: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            placeholderText: "Subcategory (optional) — type or pick below"
            KeyNavigation.tab: nameField
            onTextChanged: root.updateSubcategorySuggestions()
            onAccepted: {
              if (root.subcategorySuggestionIndex >= 0) root.selectSubcategorySuggestion(root.subcategorySuggestionIndex)
              else root.submitAdd()
            }
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) {
                root.cancelAdd()
                event.accepted = true
              } else if (event.key === Qt.Key_Down && root.subcategorySuggestions.length > 0) {
                root.subcategorySuggestionIndex = Math.min(root.subcategorySuggestionIndex + 1, root.subcategorySuggestions.length - 1)
                subcategorySuggestionList.positionViewAtIndex(root.subcategorySuggestionIndex, ListView.Contain)
                event.accepted = true
              } else if (event.key === Qt.Key_Up && root.subcategorySuggestionIndex >= 0) {
                root.subcategorySuggestionIndex = root.subcategorySuggestionIndex - 1
                if (root.subcategorySuggestionIndex >= 0)
                  subcategorySuggestionList.positionViewAtIndex(root.subcategorySuggestionIndex, ListView.Contain)
                event.accepted = true
              }
            }
          }

          ListView {
            id: subcategorySuggestionList
            visible: subcategoryField.activeFocus && root.subcategorySuggestions.length > 0
            width: parent.width
            height: Math.min(Style.space(150), root.subcategorySuggestions.length * root.rowHeight)
            clip: true
            model: root.subcategorySuggestions

            delegate: Rectangle {
              required property string modelData
              required property int index
              width: subcategorySuggestionList.width
              height: root.rowHeight
              color: index === root.subcategorySuggestionIndex ? root.selectedBackground : "transparent"
              radius: root.cornerRadius

              Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.spacing.md
                text: modelData
                color: index === root.subcategorySuggestionIndex ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                elide: Text.ElideMiddle
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectSubcategorySuggestion(index)
              }
            }
          }

          TextField {
            id: nameField
            width: parent.width
            foreground: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            placeholderText: "Name"
            KeyNavigation.tab: urlField
            onAccepted: root.submitAdd()
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) { root.cancelAdd(); event.accepted = true }
            }
          }

          TextField {
            id: urlField
            width: parent.width
            foreground: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            placeholderText: "https://…"
            KeyNavigation.tab: categoryField
            onAccepted: root.submitAdd()
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) { root.cancelAdd(); event.accepted = true }
            }
          }
        }
      }
    }
  }
}
