var SYNCING_STATUSES = {
  "scanning": true,
  "waiting-for-rescan": true,
  "reconciling": true,
  "staging-alpha": true,
  "staging-beta": true,
  "transitioning": true,
  "saving": true,
  "connecting-alpha": true,
  "connecting-beta": true
}

var STATUS_LABELS = {
  "watching": "Watching",
  "scanning": "Scanning",
  "waiting-for-rescan": "Rescanning",
  "reconciling": "Reconciling",
  "staging-alpha": "Staging α",
  "staging-beta": "Staging β",
  "transitioning": "Applying",
  "saving": "Saving",
  "connecting-alpha": "Connecting α",
  "connecting-beta": "Connecting β",
  "disconnected": "Disconnected",
  "halted-on-root-emptied": "Halted (emptied)",
  "halted-on-root-deletion": "Halted (deleted)",
  "halted-on-root-type-change": "Halted (type)"
}

var MODE_SHORT = {
  "two-way-safe": "2-way",
  "two-way-resolved": "2-way*",
  "one-way-safe": "1-way",
  "one-way-replica": "replica"
}

function defaultStatus() {
  return {
    ok: true,
    installed: false,
    daemonRunning: false,
    version: "",
    syncs: [],
    forwards: [],
    error: ""
  }
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return defaultStatus()
  try {
    var parsed = JSON.parse(text)
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      var bad = defaultStatus()
      bad.ok = false
      bad.error = "Invalid Mutagen status payload"
      return bad
    }
    return {
      ok: true,
      installed: parsed.installed === true,
      daemonRunning: parsed.daemonRunning === true,
      version: String(parsed.version || ""),
      syncs: Array.isArray(parsed.syncs) ? parsed.syncs : [],
      forwards: Array.isArray(parsed.forwards) ? parsed.forwards : [],
      error: String(parsed.error || "")
    }
  } catch (e) {
    var failed = defaultStatus()
    failed.ok = false
    failed.error = "Failed to parse Mutagen status"
    return failed
  }
}

function formatBytes(bytes) {
  var value = Number(bytes || 0)
  if (!isFinite(value) || value <= 0) return "0 B"
  var units = ["B", "KB", "MB", "GB", "TB"]
  var index = 0
  while (value >= 1000 && index < units.length - 1) {
    value = value / 1000
    index++
  }
  var decimals = index === 0 ? 0 : (value >= 100 ? 0 : 1)
  return String(Number(value.toFixed(decimals))) + " " + units[index]
}

function formatRelativeTime(ms, nowMs) {
  var ts = Number(ms || 0)
  if (!isFinite(ts) || ts <= 0) return ""
  var now = (nowMs === undefined || nowMs === null) ? Date.now() : Number(nowMs)
  var diffSec = Math.max(0, Math.floor((now - ts) / 1000))
  if (diffSec < 60) return "just now"
  var minutes = Math.floor(diffSec / 60)
  if (minutes < 60) return minutes + "m ago"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  if (days < 30) return days + "d ago"
  if (days < 365) return Math.max(1, Math.floor(days / 30)) + "mo ago"
  return Math.max(1, Math.floor(days / 365)) + "y ago"
}

function compactHomePath(path, homeDir) {
  var p = String(path || "")
  var home = String(homeDir || "").replace(/\/+$/, "")
  if (home !== "" && (p === home || p.indexOf(home + "/") === 0)) {
    return "~" + p.slice(home.length)
  }
  return p
}

function compactPathSegments(path) {
  var trimmed = String(path || "").replace(/\/+$/, "")
  if (trimmed === "" || trimmed === "/" || trimmed === "~") {
    return { trimmed: trimmed || String(path || ""), depth: 0, leaf: trimmed || String(path || "") }
  }
  var hasTilde = trimmed.indexOf("~/") === 0
  var rest = hasTilde ? trimmed.slice(2) : trimmed.replace(/^\/+/, "")
  var parts = rest.split("/").filter(function(seg) { return seg !== "" })
  var leaf = parts.length > 0 ? parts[parts.length - 1] : trimmed
  return { trimmed: trimmed, depth: parts.length, leaf: leaf }
}

function compactLocalShortPath(path, homeDir) {
  var compacted = compactHomePath(path, homeDir)
  var info = compactPathSegments(compacted)
  if (info.depth > 2 || (info.depth > 1 && info.trimmed.length > 24)) {
    var candidate = "…/" + info.leaf
    if (candidate.length < info.trimmed.length) return candidate
  }
  return compacted
}

function compactRemoteShortPath(path, prefixLength) {
  var raw = String(path || "")
  var info = compactPathSegments(raw)
  var fullLen = (prefixLength > 0 ? (prefixLength + 1) : 0) + info.trimmed.length
  if (info.depth > 2 || (info.depth > 1 && fullLen > 24)) {
    var candidate = "…/" + info.leaf
    if (candidate.length < info.trimmed.length) return candidate
  }
  return raw
}

function shortIdentifier(id) {
  var value = String(id || "")
  if (value.length <= 14) return value || "session"
  return value.slice(0, 12) + "…"
}

function formatEndpoint(ep, homeDir) {
  var src = (ep && typeof ep === "object") ? ep : {}
  var protocol = String(src.protocol || "local").toLowerCase()
  var host = String(src.host || "")
  var user = String(src.user || "")
  var port = Number(src.port || 0)
  if (!isFinite(port) || port < 0) port = 0
  var path = String(src.path || "")
  var isLocal = protocol === "local" || (protocol === "" && host === "")
  var connected = src.connected === true
  var files = Number(src.files || 0)
  var directories = Number(src.directories || 0)
  var totalFileSize = Number(src.totalFileSize || 0)
  if (!isFinite(files) || files < 0) files = 0
  if (!isFinite(directories) || directories < 0) directories = 0
  if (!isFinite(totalFileSize) || totalFileSize < 0) totalFileSize = 0

  var url = ""
  var shortUrl = ""
  if (isLocal) {
    url = path
    shortUrl = compactLocalShortPath(path, homeDir)
  } else if (protocol === "ssh") {
    var sshPrefix = (user ? (user + "@") : "") + host + (port > 0 ? (":" + port) : "")
    url = sshPrefix ? (sshPrefix + ":" + path) : path
    var sshShortPath = compactRemoteShortPath(path, sshPrefix.length)
    shortUrl = sshPrefix ? (sshPrefix + ":" + sshShortPath) : sshShortPath
  } else if (protocol === "docker") {
    var dockerPrefix = (user ? (user + "@") : "") + host
    var dockerPath = path && path.charAt(0) !== "/" ? ("/" + path) : path
    url = "docker://" + dockerPrefix + dockerPath
    var dockerShortPrefix = "docker:" + host
    var dockerShortPath = path ? compactRemoteShortPath(path, dockerShortPrefix.length) : ""
    shortUrl = dockerShortPrefix + (dockerShortPath ? (":" + dockerShortPath) : "")
  } else {
    var protoPrefix = protocol + "://" + (user ? (user + "@") : "") + host + (port > 0 ? (":" + port) : "")
    url = protoPrefix + (path ? (":" + path) : "")
    var protoShortPath = path ? compactRemoteShortPath(path, protoPrefix.length) : ""
    shortUrl = protoPrefix + (protoShortPath ? (":" + protoShortPath) : "")
  }

  return {
    protocol: protocol,
    host: host,
    user: user,
    port: port,
    path: path,
    url: url,
    shortUrl: shortUrl,
    isLocal: isLocal,
    connected: connected,
    files: files,
    directories: directories,
    totalFileSize: totalFileSize,
    sizeText: formatBytes(totalFileSize)
  }
}

function describeChanges(changes) {
  if (!Array.isArray(changes) || changes.length === 0) return "no change"
  if (changes.length > 1) return changes.length + " changes"
  var ch = changes[0] || {}
  var oldEntry = ch.old || null
  var newEntry = ch.new || null
  var kind = (newEntry && newEntry.kind) || (oldEntry && oldEntry.kind) || "entry"
  if (!oldEntry && newEntry) return "created " + kind
  if (oldEntry && !newEntry) return "deleted " + kind
  if (oldEntry && newEntry) {
    if (oldEntry.kind && newEntry.kind && oldEntry.kind !== newEntry.kind) {
      return oldEntry.kind + " -> " + newEntry.kind
    }
    return "modified " + kind
  }
  return "changed"
}

function normalizeConflicts(rawConflicts) {
  var list = Array.isArray(rawConflicts) ? rawConflicts : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var c = list[i] || {}
    out.push({
      root: String(c.root || c.path || ""),
      alphaDesc: c.alphaDesc !== undefined ? String(c.alphaDesc) : describeChanges(c.alphaChanges),
      betaDesc: c.betaDesc !== undefined ? String(c.betaDesc) : describeChanges(c.betaChanges)
    })
  }
  return out
}

function collectScanProblems(raw) {
  var out = []
  var sources = [
    { side: "alpha", list: raw && raw.alpha && raw.alpha.scanProblems },
    { side: "beta", list: raw && raw.beta && raw.beta.scanProblems },
    { side: "", list: raw && raw.scanProblems }
  ]
  for (var s = 0; s < sources.length; s++) {
    var list = sources[s].list
    if (!Array.isArray(list)) continue
    for (var i = 0; i < list.length; i++) {
      var p = list[i] || {}
      out.push({
        side: String(sources[s].side || p.side || "sync"),
        path: String(p.path || ""),
        error: String(p.error || "")
      })
    }
  }
  return out
}

function extractStaging(raw, rawStatus) {
  var sp = null
  if (raw && raw.alpha && raw.alpha.stagingProgress && typeof raw.alpha.stagingProgress === "object") {
    sp = raw.alpha.stagingProgress
  } else if (raw && raw.beta && raw.beta.stagingProgress && typeof raw.beta.stagingProgress === "object") {
    sp = raw.beta.stagingProgress
  } else if (raw && raw.stagingProgress && typeof raw.stagingProgress === "object") {
    sp = raw.stagingProgress
  }

  var isStagingStatus = rawStatus === "staging-alpha" || rawStatus === "staging-beta"
  var expectedFiles = sp ? Number(sp.expectedFiles || 0) : 0
  var receivedFiles = sp ? Number(sp.receivedFiles || 0) : 0
  var expectedSize = sp ? Number(sp.expectedSize || 0) : 0
  var receivedSize = sp ? Number(sp.receivedSize !== undefined ? sp.receivedSize : (sp.totalReceivedSize || 0)) : 0
  var path = sp ? String(sp.path || "") : ""
  var active = isStagingStatus || (sp !== null && (expectedFiles > 0 || expectedSize > 0))

  if (!active) {
    return { active: false, progress: 0, text: "" }
  }

  var progress = 0
  if (expectedSize > 0) {
    progress = receivedSize / expectedSize
  } else if (expectedFiles > 0) {
    progress = receivedFiles / expectedFiles
  }
  if (!isFinite(progress) || progress < 0) progress = 0
  if (progress > 1) progress = 1

  var parts = []
  if (path !== "") {
    var base = path.split("/").pop() || path
    parts.push(base)
  }
  if (expectedFiles > 0) {
    parts.push(receivedFiles + "/" + expectedFiles + (expectedFiles === 1 ? " file" : " files"))
  }
  if (expectedSize > 0) {
    parts.push(formatBytes(receivedSize) + " / " + formatBytes(expectedSize))
  }
  var pct = Math.round(progress * 100)
  var text = parts.length > 0
    ? ("Staging " + pct + "% · " + parts.join(" · "))
    : (rawStatus === "staging-alpha" ? "Staging on alpha…" : "Staging on beta…")

  return {
    active: true,
    progress: progress,
    text: text
  }
}

function buildFilesSummary(alpha, beta) {
  var primary = (alpha.files > 0 || alpha.directories > 0 || alpha.totalFileSize > 0) ? alpha : beta
  if (!primary || (primary.files === 0 && primary.directories === 0 && primary.totalFileSize === 0)) {
    return ""
  }
  var fileLabel = primary.files + (primary.files === 1 ? " file" : " files")
  if (primary.totalFileSize > 0) {
    return fileLabel + " · " + primary.sizeText
  }
  return fileLabel
}

function buildIssueSummary(rawStatus, lastError, conflicts, scanProblems, paused, alpha, beta) {
  if (lastError !== "") return lastError
  if (rawStatus === "halted-on-root-emptied") return "Halted: root directory emptied"
  if (rawStatus === "halted-on-root-deletion") return "Halted: root directory deleted"
  if (rawStatus === "halted-on-root-type-change") return "Halted: root type changed"
  if (rawStatus.indexOf("halted-") === 0) return "Halted: " + rawStatus.slice(7).replace(/-/g, " ")
  if (conflicts.length > 0) {
    if (conflicts.length === 1 && conflicts[0].root !== "") {
      return "Conflict: " + conflicts[0].root
    }
    return conflicts.length + " conflicts need resolution"
  }
  if (scanProblems.length > 0) {
    var first = scanProblems[0]
    var loc = first.path ? (first.side + ":" + first.path) : first.side
    var msg = first.error ? (loc + " — " + first.error) : ("Scan problem on " + loc)
    if (scanProblems.length > 1) return msg + " (+" + (scanProblems.length - 1) + " more)"
    return msg
  }
  if (!paused) {
    if (!alpha.connected && !beta.connected) return "Both endpoints disconnected"
    if (!beta.connected) {
      return (beta.host ? ("Remote " + beta.host) : "Beta endpoint") + " disconnected"
    }
    if (!alpha.connected) {
      return (alpha.host ? ("Remote " + alpha.host) : "Alpha endpoint") + " disconnected"
    }
    if (rawStatus === "disconnected") return "Session disconnected"
  }
  return ""
}

function titleCaseStatus(status) {
  var s = String(status || "unknown").replace(/-/g, " ")
  return s.charAt(0).toUpperCase() + s.slice(1)
}

function normalizeSync(raw, cycleMap, nowMs, homeDir) {
  var src = (raw && typeof raw === "object") ? raw : {}
  var id = String(src.identifier || src.id || "")
  var name = String(src.name || "")
  var displayName = name !== "" ? name : shortIdentifier(id)
  var labels = (src.labels && typeof src.labels === "object") ? src.labels : {}
  var projectId = String(labels["io.mutagen.project"] || src.projectId || "")
  var mode = String(src.mode || "two-way-safe")
  var modeShort = MODE_SHORT[mode] || mode
  var paused = src.paused === true
  var rawStatus = String(src.status || (paused ? "paused" : "disconnected"))
  var alpha = formatEndpoint(src.alpha, homeDir)
  var beta = formatEndpoint(src.beta, homeDir)
  var conflicts = normalizeConflicts(src.conflicts)
  var scanProblems = collectScanProblems(src)
  var lastError = String(src.lastError || "").trim()
  var isHalted = rawStatus.indexOf("halted-") === 0
  var isDisconnectedIssue = !paused && (!alpha.connected || !beta.connected || rawStatus === "disconnected")
  var hasIssue = conflicts.length > 0 || lastError !== "" || isHalted || scanProblems.length > 0 || isDisconnectedIssue

  var health = "watching"
  if (hasIssue) {
    health = "issue"
  } else if (paused) {
    health = "paused"
  } else if (SYNCING_STATUSES[rawStatus] === true) {
    health = "syncing"
  } else {
    health = "watching"
  }

  var statusLabel = ""
  if (hasIssue) {
    if (conflicts.length > 0) {
      statusLabel = conflicts.length + (conflicts.length === 1 ? " conflict" : " conflicts")
    } else if (isHalted) {
      statusLabel = STATUS_LABELS[rawStatus] || "Halted"
    } else if (lastError !== "") {
      statusLabel = "Error"
    } else if (scanProblems.length > 0) {
      statusLabel = scanProblems.length + (scanProblems.length === 1 ? " scan issue" : " scan issues")
    } else {
      statusLabel = "Disconnected"
    }
  } else if (paused) {
    statusLabel = "Paused"
  } else {
    statusLabel = STATUS_LABELS[rawStatus] || titleCaseStatus(rawStatus)
  }

  var issueSummary = hasIssue
    ? buildIssueSummary(rawStatus, lastError, conflicts, scanProblems, paused, alpha, beta)
    : ""

  var successfulCycles = Number(src.successfulCycles || 0)
  if (!isFinite(successfulCycles) || successfulCycles < 0) successfulCycles = 0

  var lastSyncedText = ""
  if (cycleMap && id !== "" && cycleMap[id] && cycleMap[id].lastSyncMs > 0) {
    lastSyncedText = formatRelativeTime(cycleMap[id].lastSyncMs, nowMs)
  }

  var staging = extractStaging(src, rawStatus)

  var localPath = ""
  if (alpha.isLocal && alpha.path !== "") localPath = alpha.path
  else if (beta.isLocal && beta.path !== "") localPath = beta.path

  var sshEndpoint = null
  if (beta.protocol === "ssh" && beta.host !== "") {
    sshEndpoint = { host: beta.host, user: beta.user, port: beta.port, path: beta.path }
  } else if (alpha.protocol === "ssh" && alpha.host !== "") {
    sshEndpoint = { host: alpha.host, user: alpha.user, port: alpha.port, path: alpha.path }
  }

  return {
    id: id,
    name: name,
    displayName: displayName,
    projectId: projectId,
    mode: mode,
    modeShort: modeShort,
    paused: paused,
    rawStatus: rawStatus,
    statusLabel: statusLabel,
    health: health,
    hasIssue: hasIssue,
    issueSummary: issueSummary,
    conflicts: conflicts,
    scanProblems: scanProblems,
    lastError: lastError,
    successfulCycles: successfulCycles,
    lastSyncedText: lastSyncedText,
    stagingActive: staging.active,
    stagingProgress: staging.progress,
    stagingText: staging.text,
    alpha: alpha,
    beta: beta,
    localPath: localPath,
    sshEndpoint: sshEndpoint,
    filesSummary: buildFilesSummary(alpha, beta)
  }
}

function normalizeSyncs(rawList, cycleMap, nowMs, homeDir) {
  var list = Array.isArray(rawList) ? rawList : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    out.push(normalizeSync(list[i], cycleMap, nowMs, homeDir))
  }
  out.sort(function(a, b) {
    return String(a.displayName).localeCompare(String(b.displayName))
  })
  return out
}

function commonNamePrefix(sessions) {
  if (!Array.isArray(sessions) || sessions.length < 2) return ""
  var names = []
  for (var i = 0; i < sessions.length; i++) {
    var n = String((sessions[i] && sessions[i].name) || "").trim()
    if (n === "") return ""
    names.push(n)
  }
  names.sort(function(a, b) { return a.length - b.length })
  var shortest = names[0]
  var allMatchShortest = true
  for (var j = 1; j < names.length; j++) {
    if (names[j] !== shortest &&
        names[j].indexOf(shortest + "-") !== 0 &&
        names[j].indexOf(shortest + "_") !== 0 &&
        names[j].indexOf(shortest + ".") !== 0) {
      allMatchShortest = false
      break
    }
  }
  if (allMatchShortest && shortest.length >= 2) return shortest

  var firstTokens = names[0].split(/[-_./]+/)
  var shared = []
  for (var t = 0; t < firstTokens.length; t++) {
    var token = firstTokens[t]
    if (!token) break
    var ok = true
    for (var k = 1; k < names.length; k++) {
      var kTokens = names[k].split(/[-_./]+/)
      if (kTokens[t] !== token) {
        ok = false
        break
      }
    }
    if (!ok) break
    shared.push(token)
  }
  return shared.join("-")
}

function commonRemoteHost(sessions) {
  if (!Array.isArray(sessions) || sessions.length === 0) return ""
  var host = ""
  for (var i = 0; i < sessions.length; i++) {
    var s = sessions[i] || {}
    var candidate = ""
    if (s.beta && !s.beta.isLocal && s.beta.host) candidate = s.beta.host
    else if (s.alpha && !s.alpha.isLocal && s.alpha.host) candidate = s.alpha.host
    if (candidate === "") return ""
    if (host === "") host = candidate
    else if (host !== candidate) return ""
  }
  return host
}

function deriveProjectLabel(projectId, sessions) {
  var prefix = commonNamePrefix(sessions)
  var host = commonRemoteHost(sessions)
  if (prefix !== "" && host !== "") return prefix + " · " + host
  if (prefix !== "") return prefix
  if (host !== "") return host
  var stripped = String(projectId || "").replace(/^proj_/, "")
  return "Project " + (stripped.length > 8 ? stripped.slice(0, 8) : (stripped || "group"))
}

function groupSyncs(syncs) {
  var list = Array.isArray(syncs) ? syncs : []
  var projectMap = {}
  var projectIds = []
  var standalone = []

  for (var i = 0; i < list.length; i++) {
    var s = list[i]
    if (!s) continue
    var pid = String(s.projectId || "")
    if (pid !== "") {
      if (!projectMap[pid]) {
        projectMap[pid] = []
        projectIds.push(pid)
      }
      projectMap[pid].push(s)
    } else {
      standalone.push(s)
    }
  }

  var groups = []
  for (var p = 0; p < projectIds.length; p++) {
    var id = projectIds[p]
    var members = projectMap[id].slice().sort(function(a, b) {
      return String(a.displayName).localeCompare(String(b.displayName))
    })
    groups.push({
      key: "project:" + id,
      label: deriveProjectLabel(id, members),
      isProject: true,
      projectId: id,
      sessions: members
    })
  }

  groups.sort(function(a, b) {
    return String(a.label).localeCompare(String(b.label))
  })

  if (standalone.length > 0) {
    standalone.sort(function(a, b) {
      return String(a.displayName).localeCompare(String(b.displayName))
    })
    groups.push({
      key: "standalone",
      label: "",
      isProject: false,
      projectId: "",
      sessions: standalone
    })
  }

  return groups
}

function formatForwardEndpoint(ep) {
  if (typeof ep === "string") return ep
  if (!ep || typeof ep !== "object") return ""
  var protocol = String(ep.protocol || "local").toLowerCase()
  var host = String(ep.host || "")
  var user = String(ep.user || "")
  var port = Number(ep.port || 0)
  var path = String(ep.path || "")
  if (protocol === "local" || host === "") return path
  if (protocol === "ssh") {
    return (user ? (user + "@") : "") + host + (port > 0 ? (":" + port) : "") + (path ? (":" + path) : "")
  }
  if (protocol === "docker") {
    return "docker:" + host + (path ? (":" + path) : "")
  }
  return protocol + "://" + host + (path ? (":" + path) : "")
}

function normalizeForward(raw) {
  var src = (raw && typeof raw === "object") ? raw : {}
  var id = String(src.identifier || src.id || "")
  var name = String(src.name || "")
  var displayName = name !== "" ? name : shortIdentifier(id)
  var paused = src.paused === true
  var sourceObj = (src.source && typeof src.source === "object") ? src.source : null
  var destObj = (src.destination && typeof src.destination === "object") ? src.destination : null

  var sourceLabel = formatForwardEndpoint(src.source)
  var destinationLabel = formatForwardEndpoint(src.destination)

  var openConnections = Number(
    src.openConnections !== undefined
      ? src.openConnections
      : (sourceObj && sourceObj.openConnections !== undefined ? sourceObj.openConnections : 0)
  )
  var totalConnections = Number(
    src.totalConnections !== undefined
      ? src.totalConnections
      : (sourceObj && sourceObj.totalConnections !== undefined ? sourceObj.totalConnections : 0)
  )
  if (!isFinite(openConnections) || openConnections < 0) openConnections = 0
  if (!isFinite(totalConnections) || totalConnections < 0) totalConnections = 0

  var lastError = String(
    src.lastError ||
    (sourceObj && sourceObj.lastError) ||
    (destObj && destObj.lastError) ||
    ""
  ).trim()

  var rawStatus = String(src.status || "")
  var disconnected = !paused && (
    rawStatus === "disconnected" ||
    (sourceObj && sourceObj.connected === false) ||
    (destObj && destObj.connected === false)
  )

  var health = "active"
  var statusLabel = "Forwarding"
  if (lastError !== "" || disconnected) {
    health = "issue"
    statusLabel = lastError !== "" ? "Error" : "Disconnected"
  } else if (paused) {
    health = "paused"
    statusLabel = "Paused"
  } else if (openConnections > 0) {
    statusLabel = openConnections + " open"
  }

  return {
    id: id,
    name: name,
    displayName: displayName,
    paused: paused,
    health: health,
    statusLabel: statusLabel,
    sourceLabel: sourceLabel,
    destinationLabel: destinationLabel,
    openConnections: openConnections,
    totalConnections: totalConnections,
    lastError: lastError
  }
}

function normalizeForwards(rawList) {
  var list = Array.isArray(rawList) ? rawList : []
  var out = []
  for (var i = 0; i < list.length; i++) {
    out.push(normalizeForward(list[i]))
  }
  out.sort(function(a, b) {
    return String(a.displayName).localeCompare(String(b.displayName))
  })
  return out
}

function summarize(installed, daemonActive, syncs, forwards, showSessionCount) {
  var syncList = Array.isArray(syncs) ? syncs : []
  var fwdList = Array.isArray(forwards) ? forwards : []
  var showCount = showSessionCount !== false

  var totalSyncs = syncList.length
  var watchingCount = 0
  var syncingCount = 0
  var pausedCount = 0
  var issueCount = 0
  var conflictCount = 0

  for (var i = 0; i < syncList.length; i++) {
    var s = syncList[i] || {}
    if (s.health === "issue") issueCount++
    else if (s.health === "syncing") syncingCount++
    else if (s.health === "paused") pausedCount++
    else watchingCount++
    if (Array.isArray(s.conflicts)) conflictCount += s.conflicts.length
  }

  var totalForwards = fwdList.length
  var activeForwards = 0
  var forwardIssues = 0
  for (var j = 0; j < fwdList.length; j++) {
    var f = fwdList[j] || {}
    if (f.health === "active") activeForwards++
    else if (f.health === "issue") forwardIssues++
  }

  var totalIssues = issueCount + forwardIssues
  var state = "watching"
  if (!installed) {
    state = "not-installed"
  } else if (!daemonActive) {
    state = "stopped"
  } else if (totalSyncs === 0 && totalForwards === 0) {
    state = "empty"
  } else if (totalIssues > 0) {
    state = "issue"
  } else if (syncingCount > 0) {
    state = "syncing"
  } else if (totalSyncs > 0 && pausedCount === totalSyncs && activeForwards === 0) {
    state = "paused"
  } else {
    state = "watching"
  }

  var heroMeta = ""
  var statusText = ""
  var barLabel = ""

  if (state === "not-installed") {
    heroMeta = "Mutagen CLI not found in PATH"
    statusText = "Not installed"
  } else if (state === "stopped") {
    heroMeta = "Daemon stopped"
    statusText = "Daemon stopped"
  } else if (state === "empty") {
    heroMeta = "Daemon running · No sessions"
    statusText = "No sessions"
  } else {
    var parts = []
    if (issueCount > 0) {
      parts.push(issueCount + (issueCount === 1 ? " issue" : " issues"))
    }
    if (conflictCount > 0) {
      parts.push(conflictCount + (conflictCount === 1 ? " conflict" : " conflicts"))
    }
    if (syncingCount > 0) {
      parts.push(syncingCount + " syncing")
    }
    if (watchingCount > 0) {
      parts.push(watchingCount + " watching")
    }
    if (pausedCount > 0) {
      parts.push(pausedCount + " paused")
    }
    if (totalForwards > 0) {
      parts.push(activeForwards + "/" + totalForwards + (totalForwards === 1 ? " forward" : " forwards"))
    }
    heroMeta = parts.join(" · ")

    if (state === "issue") {
      statusText = conflictCount > 0
        ? (conflictCount + (conflictCount === 1 ? " conflict" : " conflicts"))
        : (totalIssues + (totalIssues === 1 ? " issue" : " issues"))
    } else if (state === "syncing") {
      statusText = syncingCount + " syncing"
    } else if (state === "paused") {
      statusText = "All paused"
    } else if (totalSyncs > 0) {
      statusText = pausedCount > 0
        ? (watchingCount + " watching, " + pausedCount + " paused")
        : (totalSyncs + " watching")
    } else {
      statusText = activeForwards + " forwarding"
    }

    if (showCount) {
      if (state === "issue") {
        barLabel = String(totalIssues)
      } else if (totalSyncs > 0) {
        barLabel = (pausedCount > 0 && pausedCount < totalSyncs)
          ? ((totalSyncs - pausedCount) + "/" + totalSyncs)
          : String(totalSyncs)
      } else if (totalForwards > 0) {
        barLabel = String(totalForwards)
      }
    }
  }

  var tooltipHint = "Left-click: Toggle panel · Middle-click: Refresh"
  var tooltipText = "Mutagen — " + heroMeta + "\n" + tooltipHint

  return {
    state: state,
    totalSyncs: totalSyncs,
    watchingCount: watchingCount,
    syncingCount: syncingCount,
    pausedCount: pausedCount,
    issueCount: issueCount,
    conflictCount: conflictCount,
    totalForwards: totalForwards,
    activeForwards: activeForwards,
    heroMeta: heroMeta,
    statusText: statusText,
    tooltipText: tooltipText,
    barLabel: barLabel
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    parseStatus: parseStatus,
    defaultStatus: defaultStatus,
    formatBytes: formatBytes,
    formatRelativeTime: formatRelativeTime,
    formatEndpoint: formatEndpoint,
    normalizeSync: normalizeSync,
    normalizeSyncs: normalizeSyncs,
    groupSyncs: groupSyncs,
    normalizeForward: normalizeForward,
    normalizeForwards: normalizeForwards,
    summarize: summarize
  }
}
