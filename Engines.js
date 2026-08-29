// Search engines offered by the settings selector, and the URL/query
// resolution helpers shared by the overlay.

var ENGINES = [
  { id: "duckduckgo", label: "DuckDuckGo", url: "https://duckduckgo.com/?q=%s", favicon: "https://duckduckgo.com/favicon.ico" },
  { id: "google", label: "Google", url: "https://www.google.com/search?q=%s", favicon: "https://www.google.com/favicon.ico" },
  { id: "bing", label: "Bing", url: "https://www.bing.com/search?q=%s", favicon: "https://www.bing.com/favicon.ico" },
  { id: "startpage", label: "Startpage", url: "https://www.startpage.com/sp/search?query=%s", favicon: "https://www.startpage.com/favicon.ico" }
]

function engineById(id) {
  for (var i = 0; i < ENGINES.length; i++) {
    if (ENGINES[i].id === id) return ENGINES[i]
  }
  return ENGINES[0]
}

// True when the input reads as a destination to navigate to directly
// (has a scheme, is localhost, or looks like a bare domain) rather than
// free text to hand to the search engine.
function looksLikeUrl(input) {
  var s = (input || "").trim()
  if (!s || /\s/.test(s)) return false
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(s)) return true
  if (/^localhost(:\d+)?(\/\S*)?$/i.test(s)) return true
  return /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+(:\d+)?(\/\S*)?$/i.test(s)
}

// Adds a scheme (defaulting to https) when the input had none.
function resolveUrl(input) {
  var s = (input || "").trim()
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(s)) return s
  return "https://" + s
}

function searchUrl(engineId, query) {
  var engine = engineById(engineId)
  return engine.url.replace("%s", encodeURIComponent(query))
}

// The single suggestion row shown under the search field: what Enter will do.
function previewFor(engineId, input) {
  var s = (input || "").trim()
  if (!s) return null
  if (looksLikeUrl(s)) return { kind: "url", label: "Open " + resolveUrl(s), target: resolveUrl(s) }
  var engine = engineById(engineId)
  return { kind: "search", label: "Search " + engine.label + " for “" + s + "”", target: searchUrl(engineId, s) }
}
