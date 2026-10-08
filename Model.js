var GROUPS = ["review", "mine"]
var REVIEW_NEWS = { requested_changes: "changes requested", reviewed: "reviewed" }
// A tone names the meaning of a status. The panel gives each tone a theme color.
var REVIEW_TONES = { review_started: "info", reviewed: "info", requested_changes: "danger", approved: "success", unapproved: "muted" }
var DONE_STATES = { reviewed: true, requested_changes: true, approved: true }
var PIPELINE_TONES = {
  success: "success",
  failed: "danger",
  created: "warning",
  waiting_for_resource: "warning",
  preparing: "warning",
  waiting_for_callback: "warning",
  pending: "warning",
  running: "warning",
  scheduled: "warning",
  canceled: "muted",
  canceling: "muted",
  skipped: "muted",
  manual: "muted"
}

function list(value) {
  return value && typeof value.length === "number" ? value : []
}

function text(value, limit) {
  return (typeof value === "string" ? value : "").slice(0, limit)
}

function texts(values, limit) {
  var result = []
  var raw = list(values)
  for (var i = 0; i < raw.length; i++) {
    var value = text(raw[i], limit)
    if (value) result.push(value)
  }
  return result
}

function ms(value) {
  var time = Date.parse(String(value || ""))
  return isFinite(time) ? time : 0
}

function safeUrl(value) {
  var url = text(value, 2048)
  return /^https:\/\/[^\s\u0000-\u001f\u007f]+$/.test(url) ? url : ""
}

function normalizeThread(value) {
  var notes = []
  var raw = list(value && value.notes)
  for (var i = 0; i < raw.length; i++) {
    var author = text(raw[i] && raw[i].author, 255)
    var id = Number(raw[i] && raw[i].id)
    if (!author || !(id > 0)) continue
    notes.push({
      id: id,
      author: author,
      at: text(raw[i].at, 40),
      body: text(raw[i].body, 400),
      path: text(raw[i].path, 512),
      line: Math.max(0, Math.floor(Number(raw[i].line) || 0))
    })
  }
  return notes.length === 0 ? null : { resolved: value.resolved === true, notes: notes }
}

// System notes of GitLab, such as "added 2 commits".
function normalizeEvents(values) {
  var events = []
  var raw = list(values)
  for (var i = 0; i < raw.length; i++) {
    var author = text(raw[i] && raw[i].author, 255)
    var id = Number(raw[i] && raw[i].id)
    if (!author || !(id > 0)) continue
    events.push({ id: id, author: author, at: text(raw[i].at, 40), body: text(raw[i].body, 800) })
  }
  return events
}

function normalizeMergeRequest(value) {
  if (!value || typeof value !== "object") return null
  var project = text(value.project, 512)
  var iid = Number(value.iid)
  var url = safeUrl(value.url)
  if (!project || !(iid > 0) || !url) return null
  if (value.role !== "author" && value.role !== "reviewer") return null

  var reviewers = []
  var rawReviewers = list(value.reviewers)
  for (var i = 0; i < rawReviewers.length; i++) {
    var username = text(rawReviewers[i] && rawReviewers[i].username, 255)
    if (username) reviewers.push({ username: username, state: text(rawReviewers[i].state, 40) })
  }

  var threads = []
  var rawThreads = list(value.threads)
  for (var j = 0; j < rawThreads.length; j++) {
    var thread = normalizeThread(rawThreads[j])
    if (thread) threads.push(thread)
  }

  return {
    key: project + "!" + iid,
    role: value.role,
    project: project,
    iid: iid,
    title: text(value.title, 300),
    url: url,
    author: text(value.author, 255),
    draft: value.draft === true,
    sha: text(value.sha, 64),
    sourceBranch: text(value.sourceBranch, 255),
    targetBranch: text(value.targetBranch, 255),
    updatedAt: text(value.updatedAt, 40),
    pipeline: text(value.pipeline, 40),
    mergeStatus: text(value.mergeStatus, 40),
    approvedBy: texts(value.approvedBy, 255),
    reviewers: reviewers,
    threads: threads,
    events: normalizeEvents(value.events)
  }
}

function normalizeInbox(value) {
  if (!value || value.version !== 1) return null
  var me = text(value.me, 255)
  if (!me || !value.mergeRequests || typeof value.mergeRequests.length !== "number") return null

  var mergeRequests = []
  var known = {}
  for (var i = 0; i < value.mergeRequests.length; i++) {
    var mr = normalizeMergeRequest(value.mergeRequests[i])
    if (!mr || known["$" + mr.key]) continue
    known["$" + mr.key] = true
    mergeRequests.push(mr)
  }
  return { version: 1, me: me, mergeRequests: mergeRequests }
}

function parseInbox(raw) {
  try {
    return normalizeInbox(JSON.parse(String(raw || "")))
  } catch (e) {
    return null
  }
}

function wroteIn(notes, username) {
  for (var i = 0; i < notes.length; i++) if (notes[i].author === username) return true
  return false
}

// The time of each note that another person wrote.
function otherNoteTimes(mr, me) {
  var times = []
  for (var i = 0; i < mr.threads.length; i++) {
    var notes = mr.threads[i].notes
    for (var j = 0; j < notes.length; j++) if (notes[j].author !== me) times.push(ms(notes[j].at))
  }
  return times
}

// The state of a merge request at the time the user last saw its row.
// All values come from GitLab, so the local clock has no effect.
function snapshot(mr, me) {
  var reviews = []
  for (var i = 0; i < mr.reviewers.length; i++) {
    reviews.push(mr.reviewers[i].username + ":" + mr.reviewers[i].state)
  }
  var eventTimes = []
  for (var j = 0; j < mr.events.length; j++) if (mr.events[j].author !== me) eventTimes.push(ms(mr.events[j].at))
  var noteTimes = otherNoteTimes(mr, me)
  return {
    at: Math.max.apply(null, [0].concat(noteTimes)),
    // The newest note or event of another person. The detail page marks newer items as new.
    activityAt: Math.max.apply(null, [0].concat(noteTimes, eventTimes)),
    sha: mr.sha,
    approvedBy: mr.approvedBy.slice(),
    reviews: reviews,
    failedSha: mr.pipeline === "failed" ? mr.sha : "",
    conflict: mr.mergeStatus === "conflict"
  }
}

function normalizeSnapshot(value) {
  if (!value || typeof value !== "object") return null
  return {
    at: Math.max(0, Number(value.at) || 0),
    activityAt: Math.max(0, Number(value.activityAt) || 0),
    sha: text(value.sha, 64),
    approvedBy: texts(value.approvedBy, 255),
    reviews: texts(value.reviews, 300),
    failedSha: text(value.failedSha, 64),
    conflict: value.conflict === true
  }
}

function rowKinds(mr) {
  return mr.role === "author" ? ["mine"] : ["review"]
}

function badge(text, tone) {
  return { text: text, tone: tone }
}

function addBadge(badges, text, tone) {
  for (var i = 0; i < badges.length; i++) if (badges[i].text === text) return
  badges.push(badge(text, tone))
}

function row(mr, group, values) {
  var texts = []
  for (var i = 0; i < values.badges.length; i++) texts.push(values.badges[i].text)
  return {
    key: group + ":" + mr.key,
    group: group,
    project: mr.project,
    name: mr.project.slice(mr.project.lastIndexOf("/") + 1),
    iid: mr.iid,
    title: mr.title,
    author: mr.author,
    draft: mr.draft,
    url: values.url || mr.url,
    status: texts.join(" · "),
    badges: values.badges,
    pipeline: mr.pipeline,
    pipelineTone: PIPELINE_TONES.hasOwnProperty(mr.pipeline) ? PIPELINE_TONES[mr.pipeline] : "",
    unseen: values.unseen,
    hidden: false,
    timeMs: values.timeMs
  }
}

function reviewerState(mr, me) {
  for (var i = 0; i < mr.reviewers.length; i++) {
    if (mr.reviewers[i].username === me) return mr.reviewers[i].state
  }
  return ""
}

// The review state of the user in a snapshot.
function snapshotState(seen, me) {
  for (var i = 0; i < seen.reviews.length; i++) {
    if (seen.reviews[i].indexOf(me + ":") === 0) return seen.reviews[i].slice(me.length + 1)
  }
  return ""
}

// reviewedSha is the head that the last review session read, or "".
// reviewedHead is the head when GitLab first showed a review of the user, or "".
function reviewRow(mr, me, seen, reviewedSha, reviewedHead) {
  var state = reviewerState(mr, me)
  var moved = !!seen && seen.sha !== mr.sha
  var sessionCommits = reviewedSha !== "" && reviewedSha !== mr.sha
  // Commits after a review by hand stay in the status only until the user sees them.
  var handCommits = moved && DONE_STATES[state] === true && reviewedHead !== "" && reviewedHead !== mr.sha
  // GitLab sets the state back to unreviewed when the author requests a new review.
  var reRequested = !!seen && (!state || state === "unreviewed") && DONE_STATES[snapshotState(seen, me)] === true
  var replies = waitingReplies(mr, me, seen ? seen.at : 0)

  var badges = [sessionCommits || handCommits ? badge("new commits", "warning")
    : reRequested ? badge("review re-requested", "warning")
    : !state || state === "unreviewed" ? badge("to review", "warning")
    : badge(state.replace(/_/g, " "), REVIEW_TONES[state] || "info")]
  if (replies.count > 0) badges.push(badge(replies.count + (replies.count === 1 ? " reply" : " replies"), "warning"))
  if (mr.draft) badges.push(badge("draft", "muted"))

  return row(mr, "review", {
    // A row with replies opens the newest reply.
    url: replies.count > 0 ? mr.url + "#note_" + replies.newest.id : "",
    badges: badges,
    unseen: !seen || (sessionCommits && moved) || handCommits || reRequested || replies.unseen,
    timeMs: ms(mr.updatedAt)
  })
}

// A thread waits for the user when the user wrote in it and another person wrote last.
// A resolved thread waits only until the user sees the reply. seenAt is the time
// of the newest note of another person when the user last saw the row.
function waitingReplies(mr, me, seenAt) {
  var result = { count: 0, unseen: false, newest: null }
  var newestMs = 0

  for (var i = 0; i < mr.threads.length; i++) {
    var notes = mr.threads[i].notes
    var last = notes[notes.length - 1]
    if (last.author === me || !wroteIn(notes, me)) continue
    var at = ms(last.at)
    if (at <= seenAt && mr.threads[i].resolved) continue
    result.count++
    if (at > seenAt) result.unseen = true
    if (!result.newest || at > newestMs) {
      result.newest = last
      newestMs = at
    }
  }
  return result
}

function steadyBadge(mr) {
  if (mr.pipeline === "failed") return badge("pipeline failed", "danger")
  if (mr.mergeStatus === "conflict") return badge("conflicts", "danger")
  if (mr.draft) return badge("draft", "muted")
  if (mr.mergeStatus === "mergeable" && mr.approvedBy.length > 0) return badge("ready to merge", "success")
  if (mr.reviewers.length === 0) return badge("no reviewers", "muted")

  var done = 0
  for (var i = 0; i < mr.reviewers.length; i++) {
    var state = mr.reviewers[i].state
    if (state && state !== "unreviewed" && state !== "review_started") done++
  }
  return badge(done + "/" + mr.reviewers.length + " reviewed", "info")
}

function mineRow(mr, me, seen) {
  var now = snapshot(mr, me)
  var was = seen || now
  var news = []

  var times = otherNoteTimes(mr, me)
  var comments = 0
  for (var i = 0; i < times.length; i++) if (times[i] > was.at) comments++
  if (comments > 0) addBadge(news, comments + (comments === 1 ? " comment" : " comments"), "warning")

  for (var j = 0; j < now.approvedBy.length; j++) {
    if (was.approvedBy.indexOf(now.approvedBy[j]) === -1) addBadge(news, "approved", "success")
  }

  for (var k = 0; k < mr.reviewers.length; k++) {
    var state = mr.reviewers[k].state
    var label = REVIEW_NEWS.hasOwnProperty(state) ? REVIEW_NEWS[state] : ""
    if (label && was.reviews.indexOf(now.reviews[k]) === -1) addBadge(news, label, REVIEW_TONES[state])
  }

  if (now.failedSha && now.failedSha !== was.failedSha) addBadge(news, "pipeline failed", "danger")
  if (now.conflict && !was.conflict) addBadge(news, "conflicts", "danger")

  return row(mr, "mine", {
    badges: news.length > 0 ? news : [steadyBadge(mr)],
    unseen: news.length > 0,
    timeMs: now.at || ms(mr.updatedAt)
  })
}

// A hidden row is in the result only when showHidden is true.
// reviews is the result of parseReviews.
function rows(state, showHidden, reviews) {
  var inbox = state && state.inbox
  if (!inbox) return []

  var result = []
  for (var i = 0; i < inbox.mergeRequests.length; i++) {
    var mr = inbox.mergeRequests[i]
    var kinds = rowKinds(mr)
    for (var j = 0; j < kinds.length; j++) {
      var key = kinds[j] + ":" + mr.key
      var hidden = state.hidden[key] === true
      if (hidden && showHidden !== true) continue
      var seen = state.seen[key]
      var built = kinds[j] === "mine" ? mineRow(mr, inbox.me, seen)
        : reviewRow(mr, inbox.me, seen, text(reviews && reviews[mr.key], 64), text(state.reviewedHeads[mr.key], 64))
      built.hidden = hidden
      result.push(built)
    }
  }

  return result.sort(function(a, b) {
    if (a.group !== b.group) return GROUPS.indexOf(a.group) - GROUPS.indexOf(b.group)
    if (a.unseen !== b.unseen) return a.unseen ? -1 : 1
    if (a.timeMs !== b.timeMs) return b.timeMs - a.timeMs
    return a.key.localeCompare(b.key)
  })
}

// The rows of "after" that are unseen and were not unseen in "before".
function freshRows(before, after) {
  var known = {}
  var old = list(before)
  for (var i = 0; i < old.length; i++) if (old[i].unseen) known[old[i].key] = true

  var fresh = []
  var all = list(after)
  for (var j = 0; j < all.length; j++) if (all[j].unseen && known[all[j].key] !== true) fresh.push(all[j])
  return fresh
}

function unreadCount(values) {
  var count = 0
  var all = list(values)
  for (var i = 0; i < all.length; i++) if (all[i] && all[i].unseen === true) count++
  return count
}

function rowByKey(state, key) {
  var all = rows(state, true)
  for (var i = 0; i < all.length; i++) if (all[i].key === key) return all[i]
  return null
}

function emptyState() {
  return { initialized: false, lastRefreshMs: 0, inbox: null, seen: {}, hidden: {}, reviewedHeads: {} }
}

function withChanges(state, seen, hidden) {
  return {
    initialized: state.initialized,
    lastRefreshMs: state.lastRefreshMs,
    inbox: state.inbox,
    seen: seen,
    hidden: hidden,
    reviewedHeads: state.reviewedHeads
  }
}

// Accepts the result of a refresh. The first refresh marks each row as seen.
// Later, a new review request is unseen, and a new merge request of the user is seen.
// The state of a merge request that left the inbox is removed.
// reviewedHeads keeps the head of the first refresh that shows a review of the user.
function reconcile(state, inbox, nowMs) {
  var seen = {}
  var hidden = {}
  var reviewedHeads = {}

  for (var i = 0; i < inbox.mergeRequests.length; i++) {
    var mr = inbox.mergeRequests[i]
    var kinds = rowKinds(mr)
    for (var j = 0; j < kinds.length; j++) {
      var key = kinds[j] + ":" + mr.key
      if (state.seen[key]) seen[key] = state.seen[key]
      else if (!state.initialized || kinds[j] === "mine") seen[key] = snapshot(mr, inbox.me)
      if (state.hidden[key]) hidden[key] = true
    }
    if (mr.role === "reviewer" && DONE_STATES[reviewerState(mr, inbox.me)] === true) {
      reviewedHeads[mr.key] = state.reviewedHeads[mr.key] || mr.sha
    }
  }

  return {
    initialized: true,
    lastRefreshMs: Number(nowMs) || 0,
    inbox: inbox,
    seen: seen,
    hidden: hidden,
    reviewedHeads: reviewedHeads
  }
}

function mergeRequestForRow(inbox, key) {
  var mrKey = String(key || "").replace(/^[a-z]+:/, "")
  for (var i = 0; inbox && i < inbox.mergeRequests.length; i++) {
    if (inbox.mergeRequests[i].key === mrKey) return inbox.mergeRequests[i]
  }
  return null
}

function withSeen(state, keys) {
  var seen = {}
  for (var known in state.seen) seen[known] = state.seen[known]
  for (var i = 0; i < keys.length; i++) {
    var mr = mergeRequestForRow(state.inbox, keys[i])
    if (mr) seen[keys[i]] = snapshot(mr, state.inbox.me)
  }
  return withChanges(state, seen, state.hidden)
}

function markSeen(state, key) {
  return withSeen(state, [key])
}

function markAllSeen(state) {
  var keys = []
  var all = rows(state)
  for (var i = 0; i < all.length; i++) keys.push(all[i].key)
  return withSeen(state, keys)
}

function setHidden(state, key, hide) {
  if (!mergeRequestForRow(state.inbox, key)) return state
  var hidden = {}
  for (var known in state.hidden) if (known !== key) hidden[known] = true
  if (hide === true) hidden[key] = true
  return withChanges(state, state.seen, hidden)
}

function serialize(state) {
  return JSON.stringify({
    version: 1,
    initialized: state.initialized,
    lastRefreshMs: state.lastRefreshMs,
    inbox: state.inbox,
    seen: state.seen,
    hidden: state.hidden,
    reviewedHeads: state.reviewedHeads
  }) + "\n"
}

function loadState(raw) {
  try {
    var saved = JSON.parse(String(raw || ""))
    if (!saved || saved.version !== 1) throw new Error("unsupported state")
    var inbox = normalizeInbox(saved.inbox)
    if (!inbox) throw new Error("no inbox")

    var state = {
      initialized: saved.initialized === true,
      lastRefreshMs: Math.max(0, Number(saved.lastRefreshMs) || 0),
      inbox: inbox,
      seen: {},
      hidden: {},
      reviewedHeads: {}
    }
    for (var i = 0; i < inbox.mergeRequests.length; i++) {
      var head = text(saved.reviewedHeads && saved.reviewedHeads[inbox.mergeRequests[i].key], 64)
      if (head) state.reviewedHeads[inbox.mergeRequests[i].key] = head
      var kinds = rowKinds(inbox.mergeRequests[i])
      for (var j = 0; j < kinds.length; j++) {
        var key = kinds[j] + ":" + inbox.mergeRequests[i].key
        var seen = normalizeSnapshot(saved.seen && saved.seen[key])
        if (seen) state.seen[key] = seen
        if (saved.hidden && saved.hidden[key] === true) state.hidden[key] = true
      }
    }
    return state
  } catch (e) {
    return emptyState()
  }
}

// Reads the file of the review launcher. The result maps each merge request
// to the head that its last review session read.
function parseReviews(raw) {
  var result = {}
  try {
    var saved = JSON.parse(String(raw || ""))
    if (!saved || saved.version !== 1 || !saved.reviews || typeof saved.reviews !== "object") return result
    for (var key in saved.reviews) {
      var sha = text(saved.reviews[key] && saved.reviews[key].sha, 64)
      if (key.indexOf("!") > 0 && sha) result[key] = sha
    }
  } catch (e) {
    return {}
  }
  return result
}

// Reads the sessions that the review launcher saved. Like parseSessions, the
// result maps each "<kind>:<project>!<iid>" to true.
function parseSavedSessions(raw) {
  var result = {}
  try {
    var saved = JSON.parse(String(raw || ""))
    if (!saved || saved.version !== 1) return result
    var sections = { review: saved.reviews, fix: saved.fixes }
    for (var kind in sections) {
      var entries = sections[kind]
      if (!entries || typeof entries !== "object") continue
      for (var key in entries) {
        if (key.indexOf("!") > 0 && text(entries[key] && entries[key].sessionId, 64)) result[kind + ":" + key] = true
      }
    }
  } catch (e) {
    return {}
  }
  return result
}

// Reads the tmux markers of the open sessions, one "<kind>:<project>!<iid>" on each line.
// The result maps each marker to true.
function parseSessions(raw) {
  var result = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    if (/^(review|fix):[^\s!]+![1-9][0-9]*$/.test(lines[i])) result[lines[i]] = true
  }
  return result
}

// Reads the colors of the tones from the colors.toml file of the Omarchy theme.
// A tone that the theme does not define has the value "".
function parsePalette(raw) {
  var names = {
    danger: ["red", "color1"],
    warning: ["yellow", "color3"],
    success: ["green", "color2"],
    info: ["blue", "color4"]
  }
  var values = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var match = lines[i].match(/^\s*([A-Za-z0-9_]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})\b/)
    if (match) values[match[1]] = match[2]
  }

  var palette = {}
  for (var tone in names) palette[tone] = values[names[tone][0]] || values[names[tone][1]] || ""
  return palette
}

// True when an unseen row has a status with the tone "danger".
function hasUnseenDanger(values) {
  var all = list(values)
  for (var i = 0; i < all.length; i++) {
    if (!all[i] || all[i].unseen !== true) continue
    for (var j = 0; j < list(all[i].badges).length; j++) if (all[i].badges[j].tone === "danger") return true
  }
  return false
}

// GitLab links a system note to a version of the diff, and sometimes to a line in it.
var VERSION_LINK = /diff_id=([0-9]+)&start_sha=([0-9a-f]{40})(#[0-9a-f]+_[0-9]+_[0-9]+)?/
var EVENT_KINDS = [
  [/^approved this merge request/, "approved"],
  [/^unapproved this merge request/, "unapproved"],
  [/^requested review from/, "review-request"],
  [/^changed the description/, "description"],
  [/^marked this merge request as/, "status"],
  [/^resolved all threads/, "resolved"]
]

// Markdown and HTML as one line of plain text.
function plain(value, limit) {
  return String(value || "")
    .replace(/<[^>]*>/g, " ")
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/[*`]/g, "")
    .replace(/&#39;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&amp;/g, "&")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, limit)
}

function versionUrl(mr, link) {
  return mr.url + "/diffs?diff_id=" + link[1] + "&start_sha=" + link[2] + (link[3] || "")
}

// The comments and the events of a merge request as items. A reply is a note
// of another person in a thread where the user wrote before.
function activity(mr, me) {
  var items = []
  for (var i = 0; i < mr.threads.length; i++) {
    var notes = mr.threads[i].notes
    var path = ""
    var line = 0
    var wrote = false
    for (var j = 0; j < notes.length; j++) {
      if (!path && notes[j].path) {
        path = notes[j].path
        line = notes[j].line
      }
      items.push({
        kind: notes[j].author === me ? "own" : wrote ? "reply" : "comment",
        author: notes[j].author,
        atMs: ms(notes[j].at),
        verb: notes[j].author === me ? "commented" : wrote ? "replied" : "commented",
        body: plain(notes[j].body, 240),
        lines: [],
        path: path,
        line: line,
        url: mr.url + "#note_" + notes[j].id
      })
      if (notes[j].author === me) wrote = true
    }
  }

  var events = mr.events.slice().sort(function(a, b) { return ms(a.at) - ms(b.at) })
  var changed = null
  for (var k = 0; k < events.length; k++) {
    var event = events[k]
    var first = String(event.body.split("\n")[0])
    var link = event.body.match(VERSION_LINK)
    var item = { kind: "event", author: event.author, atMs: ms(event.at), verb: "", body: "", lines: [], path: "", line: 0, url: link ? versionUrl(mr, link) : mr.url }

    var commits = first.match(/^added ([0-9]+) commits?/)
    if (commits) {
      var titles = event.body.match(/<li>[0-9a-f.]+ - .*?<\/li>|^\* [0-9a-f.]+ - .*$/gm) || []
      item.kind = "commits"
      item.verb = "pushed " + commits[1] + (commits[1] === "1" ? " commit" : " commits")
      for (var t = 0; t < titles.length && t < 5; t++) item.lines.push(plain(titles[t].replace(/^(<li>|\* )[0-9a-f.]+ - /, ""), 120))
      if (titles.length > 5) item.lines.push("and " + (titles.length - 5) + " more")
      item.diffId = link ? Number(link[1]) : 0
      item.startSha = link ? link[2] : ""
    } else if (/^changed this line in/.test(first)) {
      // A push changes many commented lines at once. They make one item.
      if (changed && changed.author === event.author && item.atMs - changed.atMs < 120000) {
        changed.count++
        changed.verb = "changed " + changed.count + " commented lines"
        continue
      }
      item.kind = "changed"
      item.count = 1
      item.verb = "changed a commented line"
      changed = item
    } else if (/^mentioned in /.test(first)) {
      continue
    } else {
      for (var e = 0; e < EVENT_KINDS.length; e++) if (EVENT_KINDS[e][0].test(first)) item.kind = EVENT_KINDS[e][1]
      item.verb = plain(first, 160)
      if (!item.verb) continue
    }
    items.push(item)
  }

  return items.sort(function(a, b) { return b.atMs - a.atMs })
}

// The detail page of a row: the row, the merge request, and its activity.
// An item of another person is new when it is newer than the activity that the user saw.
// diffUrl shows the commits that are new, as one diff of GitLab.
function detail(state, key, reviews) {
  var mr = mergeRequestForRow(state && state.inbox, key)
  var row = null
  var all = rows(state, true, reviews)
  for (var i = 0; i < all.length; i++) if (all[i].key === key) row = all[i]
  if (!mr || !row) return null

  var me = state.inbox.me
  var seen = state.seen[key]
  var since = seen ? seen.activityAt || seen.at : 0
  var items = activity(mr, me)
  var newCount = 0
  var diffId = 0
  var startSha = ""
  var oldestMs = Infinity
  for (var j = 0; j < items.length; j++) {
    items[j].isNew = items[j].author !== me && items[j].atMs > since
    if (!items[j].isNew) continue
    newCount++
    if (items[j].kind !== "commits" || !items[j].diffId) continue
    diffId = Math.max(diffId, items[j].diffId)
    if (items[j].atMs < oldestMs) {
      oldestMs = items[j].atMs
      startSha = items[j].startSha
    }
  }

  // The new items come first. Each part is newest first.
  items.sort(function(a, b) { return a.isNew !== b.isNew ? (a.isNew ? -1 : 1) : b.atMs - a.atMs })

  return {
    row: row,
    me: me,
    sourceBranch: mr.sourceBranch,
    targetBranch: mr.targetBranch,
    reviewers: mr.reviewers,
    items: items,
    newCount: newCount,
    diffUrl: diffId > 0 && startSha ? mr.url + "/diffs?diff_id=" + diffId + "&start_sha=" + startSha : ""
  }
}

function relativeTime(timestamp, currentTime) {
  var time = Number(timestamp)
  var now = Number(currentTime)
  if (!isFinite(time) || time <= 0) return ""
  if (!isFinite(now) || now <= 0) now = Date.now()

  var seconds = Math.max(0, Math.floor((now - time) / 1000))
  if (seconds < 60) return "now"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + "m"
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h"
  var days = Math.floor(hours / 24)
  if (days < 7) return days + "d"

  var date = new Date(time)
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return date.getDate() + " " + months[date.getMonth()]
}

if (typeof module !== "undefined") {
  module.exports = {
    parseInbox: parseInbox,
    parseReviews: parseReviews,
    parseSessions: parseSessions,
    parseSavedSessions: parseSavedSessions,
    parsePalette: parsePalette,
    hasUnseenDanger: hasUnseenDanger,
    loadState: loadState,
    serialize: serialize,
    emptyState: emptyState,
    reconcile: reconcile,
    rows: rows,
    rowByKey: rowByKey,
    detail: detail,
    freshRows: freshRows,
    unreadCount: unreadCount,
    markSeen: markSeen,
    markAllSeen: markAllSeen,
    setHidden: setHidden,
    relativeTime: relativeTime
  }
}
