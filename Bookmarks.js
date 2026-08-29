// Parses the plain-text bookmarks file:
//
//   # decorative comment lines are ignored
//   [Category/Subcategory]
//   Name (padding is cosmetic) | https://example.com
//
// Blank lines and "#" lines are ignored. Entries before any "[...]"
// header fall under the empty category.

function parseBookmarks(raw) {
  var lines = String(raw || "").split("\n")
  var category = ""
  var items = []
  for (var i = 0; i < lines.length; i++) {
    var trimmed = lines[i].trim()
    if (!trimmed || trimmed.charAt(0) === "#") continue

    var catMatch = trimmed.match(/^\[(.+)\]$/)
    if (catMatch) {
      category = catMatch[1].trim()
      continue
    }

    var sep = trimmed.indexOf("|")
    if (sep === -1) continue
    var name = trimmed.slice(0, sep).trim()
    var url = trimmed.slice(sep + 1).trim()
    if (!name || !url) continue

    items.push({
      category: category,
      name: name,
      url: url,
      path: category ? category + " ▸ " + name : name
    })
  }
  return items
}

function filterBookmarks(items, filterText, limit) {
  var q = String(filterText || "").toLowerCase().trim()
  var out = []
  for (var i = 0; i < items.length; i++) {
    var it = items[i]
    if (!q || it.path.toLowerCase().indexOf(q) !== -1) {
      out.push(it)
      if (out.length >= limit) break
    }
  }
  return out
}

// Builds a folder tree from "Category/Subcategory/..." paths so browsing
// can drill down one segment at a time instead of showing one flat list.
// A node's own bookmarks are the entries whose category is exactly that
// node's path (mixed folders + bookmarks at the same level are both kept).
function buildTree(items) {
  var root = { children: {}, bookmarks: [] }
  for (var i = 0; i < items.length; i++) {
    var it = items[i]
    var segments = it.category
      ? it.category.split("/").map(function(s) { return s.trim() }).filter(function(s) { return s.length > 0 })
      : []
    var node = root
    for (var s = 0; s < segments.length; s++) {
      var seg = segments[s]
      if (!node.children[seg]) node.children[seg] = { children: {}, bookmarks: [] }
      node = node.children[seg]
    }
    node.bookmarks.push(it)
  }
  return root
}

// Walks the tree along pathSegments; returns null if the path no longer
// exists (e.g. the file changed underneath an open drill-down).
function nodeAtPath(root, pathSegments) {
  var node = root
  for (var i = 0; i < pathSegments.length; i++) {
    if (!node || !node.children[pathSegments[i]]) return null
    node = node.children[pathSegments[i]]
  }
  return node
}

// Alphabetically sorted subfolder names directly under a node — used to
// power the "existing categories" suggestion lists in the add-bookmark
// form (so a typo doesn't silently create a near-duplicate category).
function folderNames(node) {
  if (!node) return []
  return Object.keys(node.children).sort(function(a, b) {
    return a.localeCompare(b, undefined, { sensitivity: "base" })
  })
}

// Alphabetical: subfolders first, then this node's own bookmarks — each
// normalized to { type: "folder"|"bookmark", name, node|url }.
function childrenOf(node) {
  if (!node) return []
  var folderNames = Object.keys(node.children).sort(function(a, b) {
    return a.localeCompare(b, undefined, { sensitivity: "base" })
  })
  var folders = folderNames.map(function(name) {
    return { type: "folder", name: name, node: node.children[name] }
  })
  var bookmarks = node.bookmarks.slice().sort(function(a, b) {
    return a.name.localeCompare(b.name, undefined, { sensitivity: "base" })
  }).map(function(b) {
    return { type: "bookmark", name: b.name, url: b.url }
  })
  return folders.concat(bookmarks)
}
