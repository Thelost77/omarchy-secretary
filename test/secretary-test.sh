#!/bin/bash

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
helper="$root/bin/omasecretary-inbox"
command -v node >/dev/null
bash -n "$helper"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/fixtures"

# The fake accepts only the read requests that the helper is allowed to send.
cat >"$tmp/bin/glab" <<'SH'
#!/bin/bash
set -euo pipefail
case "$*" in
"api graphql --paginate -f query="*authoredMergeRequests*)
  cat "$GLAB_FIXTURES/author.json"
  ;;
"api graphql --paginate -f query="*reviewRequestedMergeRequests*)
  cat "$GLAB_FIXTURES/reviewer.json"
  ;;
"api --paginate projects/"*"/discussions?per_page=100")
  name=${3#projects/}
  name=${name%/discussions*}
  cat "$GLAB_FIXTURES/${name/\/merge_requests\//!}.json"
  ;;
*)
  printf 'Unexpected glab invocation: %s\n' "$*" >&2
  exit 1
  ;;
esac
SH
chmod +x "$tmp/bin/glab"

merge_request() {
  # <project> <iid> <updatedAt> <pipeline> <reviewers>
  printf '{"iid":"%s","title":"Change %s","webUrl":"https://gitlab.example.com/%s/-/merge_requests/%s","draft":false,"diffHeadSha":"aaa111","sourceBranch":"feature","targetBranch":"main","updatedAt":"%s","detailedMergeStatus":"NOT_APPROVED","project":{"fullPath":"%s"},"author":{"name":"Ann Example"},"headPipeline":%s,"approvedBy":{"nodes":[]},"reviewers":{"nodes":[%s]}}' \
    "$2" "$2" "$1" "$2" "$3" "$1" "$4" "$5"
}

page() {
  printf '{"data":{"currentUser":{"username":"me","mergeRequests":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[%s]}}}}\n' "$1"
}

reviewer() {
  printf '{"username":"%s","mergeRequestInteraction":{"reviewState":"%s"}}' "$1" "$2"
}

note() {
  # <id> <author> <time> [system] [resolved]
  printf '{"id":%s,"system":%s,"author":{"username":"%s"},"created_at":"2026-10-01T%s:00.000+02:00","resolvable":%s,"resolved":%s}' \
    "$1" "${4:-false}" "$2" "$3" "$([[ ${4:-false} == true ]] && echo false || echo true)" "${5:-false}"
}

# A note with a text and an optional position, for the detail page.
rich() {
  # <id> <author> <time> <system> <body> [path line]
  jq -nc --argjson id "$1" --arg author "$2" --arg at "2026-10-01T$3:00.000+02:00" --argjson system "$4" \
    --arg body "$5" --arg path "${6:-}" --argjson line "${7:-0}" '
    {id: $id, system: $system, author: {username: $author}, created_at: $at, resolvable: ($system | not), resolved: false, body: $body}
    + (if $path == "" then {} else {position: {new_path: $path, new_line: $line}} end)'
}
sha40=0123456789abcdef0123456789abcdef01234567
version="/group/api/-/merge_requests/12/diffs?diff_id=7&start_sha=$sha40"

app=$(merge_request group/app 7 2026-10-01T09:30:00+02:00 '{"status":"SUCCESS"}' "$(reviewer ann UNREVIEWED)")
lib=$(merge_request group/lib 3 2026-09-20T09:30:00+02:00 null "")
api=$(merge_request group/api 12 2026-10-01T12:00:00+02:00 '{"status":"SUCCESS"}' "$(reviewer me UNREVIEWED),$(reviewer bob REVIEWED)")

# glab prints each page as one JSON document.
{ page "$app"; page "$lib"; } >"$tmp/fixtures/author.json"
page "$api,$lib" >"$tmp/fixtures/reviewer.json"

{
  printf '[{"notes":[%s]},' "$(note 100 ann 08:00 true)"
  printf '{"notes":[%s,%s]},' "$(rich 101 me 10:00 false 'Why?' src/a.ts 7)" "$(rich 102 ann 11:00 false 'Fixed in **abc**, see [docs](https://x)')"
  printf '{"notes":[%s,%s,%s]},' "$(note 103 me 10:05)" "$(note 104 ann 10:30)" "$(note 105 me 10:40)"
  printf '{"notes":[%s]}]\n' "$(note 106 bob 10:10)"
  printf '[{"notes":[%s,%s]},' "$(note 107 me 09:00 false true)" "$(note 108 ann 12:00 false true)"
  printf '{"notes":[%s]},' "$(rich 120 ann 10:20 true $'added 2 commits\n\n<ul><li>abc1234 - first title</li><li>def5678 - second &#39;quoted&#39;</li></ul>\n\n'"[Compare with previous version]($version)")"
  printf '{"notes":[%s]},' "$(rich 121 ann 10:21 true "changed this line in [version 2 of the diff]($version#${sha40}_10_12)")"
  printf '{"notes":[%s]},' "$(rich 122 ann 10:22 true "changed this line in [version 2 of the diff]($version#${sha40}_20_22)")"
  printf '{"notes":[%s]},' "$(rich 123 bob 10:25 true 'mentioned in merge request !99')"
  printf '{"notes":[%s]}]\n' "$(rich 124 bob 10:26 true 'approved this merge request')"
} >"$tmp/fixtures/group%2Fapi!12.json"
printf '[{"notes":[%s]}]\n' "$(note 201 ann 09:00)" >"$tmp/fixtures/group%2Fapp!7.json"
printf '[]\n' >"$tmp/fixtures/group%2Flib!3.json"

run_helper() {
  GLAB_FIXTURES="$tmp/fixtures" PATH="$tmp/bin:$PATH" "$helper"
}

run_helper >"$tmp/inbox.json" || fail "helper reads the merge requests and their threads"
pass "helper reads the merge requests and their threads"

mv "$tmp/fixtures/group%2Flib!3.json" "$tmp/lib.json"
if output=$(run_helper 2>/dev/null) || [[ -n $output ]]; then
  fail "helper prints nothing when one request fails"
fi
mv "$tmp/lib.json" "$tmp/fixtures/group%2Flib!3.json"
pass "helper prints nothing when one request fails"

cp "$tmp/fixtures/reviewer.json" "$tmp/reviewer.json"
printf '{"errors":[{"message":"denied"}]}\n' >"$tmp/fixtures/reviewer.json"
if output=$(run_helper 2>/dev/null) || [[ -n $output ]]; then
  fail "helper prints nothing when GitLab rejects a query"
fi
mv "$tmp/reviewer.json" "$tmp/fixtures/reviewer.json"
pass "helper prints nothing when GitLab rejects a query"

ROOT="$root" INBOX="$tmp/inbox.json" node <<'JS'
const fs = require('fs')
const path = require('path')
const model = require(path.join(process.env.ROOT, 'Model.js'))

function assert(condition, description) {
  if (!condition) {
    console.error(`not ok - ${description}`)
    process.exit(1)
  }
  console.log(`ok - ${description}`)
}

const clone = value => JSON.parse(JSON.stringify(value))
const find = (inbox, key) => inbox.mergeRequests.find(mr => mr.key === key)
const row = (state, key) => model.rows(state).find(r => r.key === key)
const unread = state => model.unreadCount(model.rows(state))
const note = (id, author, time) => ({ id, author, at: `2026-10-01T${time}:00.000+02:00` })
const copyOf = (mr, project, iid, values) => Object.assign(clone(mr), { key: `${project}!${iid}`, project, iid, threads: [] }, values)
// A refresh that brings the changed inbox.
const refresh = (state, inbox) => model.reconcile(state, model.parseInbox(JSON.stringify(inbox)), 42)

const raw = fs.readFileSync(process.env.INBOX, 'utf8')
const base = model.parseInbox(raw)
const api = find(base, 'group/api!12')
assert(base.me === 'me' && base.mergeRequests.length === 3, 'helper joins the pages of the two lists')
assert(find(base, 'group/lib!3').role === 'author', 'a merge request in the two lists keeps the author role')
assert(api.iid === 12 && api.pipeline === 'success' && api.reviewers[1].state === 'reviewed' && find(base, 'group/lib!3').pipeline === '', 'helper emits plain values')
assert(api.threads.length === 4 && api.threads.every(t => t.notes.every(n => n.id !== 100)), 'helper joins the pages of threads and drops system notes')
assert(api.threads[3].resolved && !api.threads[0].resolved, 'helper marks resolved threads')
assert(
  api.sourceBranch === 'feature' && api.events.length === 6 && api.threads[0].notes[0].path === 'src/a.ts'
    && api.threads[0].notes[0].line === 7 && api.threads[0].notes[1].body.startsWith('Fixed in'),
  'helper keeps the branches, the text and the position of notes, and the system notes as events'
)

let state = model.reconcile(model.emptyState(), base, 42)
assert(unread(state) === 0, 'first refresh leaves no row unseen')
assert(
  model.rows(state).map(r => r.key).join() === 'review:group/api!12,mine:group/app!7,mine:group/lib!3',
  'rows come in the order: to review, my merge requests'
)
assert(row(state, 'review:group/api!12').status === 'to review · 1 reply' && row(state, 'review:group/api!12').name === 'api', 'a review row shows the review state of the user')
assert(
  row(state, 'review:group/api!12').url.endsWith('/merge_requests/12#note_102'),
  'a review row counts the open threads that wait for the user and links to the newest reply'
)
assert(row(state, 'mine:group/app!7').status === '0/1 reviewed' && row(state, 'mine:group/lib!3').status === 'no reviewers', 'a row of the user shows the review progress')
const tones = r => r.badges.map(b => `${b.text}=${b.tone}`).join()
assert(
  tones(row(state, 'review:group/api!12')) === 'to review=warning,1 reply=warning'
    && tones(row(state, 'mine:group/app!7')) === '0/1 reviewed=info' && tones(row(state, 'mine:group/lib!3')) === 'no reviewers=muted',
  'each status has a tone'
)
assert(row(state, 'review:group/api!12').pipelineTone === 'success' && row(state, 'mine:group/lib!3').pipelineTone === '', 'a row has the tone of its pipeline')

let inbox = clone(base)
inbox.mergeRequests.push(copyOf(api, 'group/web', 5))
state = refresh(state, inbox)
assert(row(state, 'review:group/web!5').unseen && model.rows(state)[0].key === 'review:group/web!5' && unread(state) === 1, 'a later review request is unseen and comes first')
assert(
  row(state, 'review:group/web!5').status === 'to review' && !row(state, 'review:group/web!5').url.includes('#note_'),
  'a review row without replies links to the merge request'
)
assert(
  model.freshRows(model.rows(model.reconcile(model.emptyState(), base, 42)), model.rows(state)).map(r => r.key).join() === 'review:group/web!5'
    && model.freshRows(model.rows(state), model.rows(state)).length === 0,
  'a refresh reports each unseen row one time'
)
state = model.markSeen(state, 'review:group/web!5')
assert(unread(state) === 0, 'the user can mark a row as seen')

find(inbox, 'group/api!12').threads[1].notes.push(note(109, 'ann', '13:00'))
state = refresh(state, inbox)
assert(
  row(state, 'review:group/api!12').unseen && row(state, 'review:group/api!12').status === 'to review · 2 replies'
    && row(state, 'review:group/api!12').url.endsWith('#note_109') && unread(state) === 1,
  'a reply after a note of the user makes the review row unseen'
)
state = model.markSeen(state, 'review:group/api!12')
assert(!row(state, 'review:group/api!12').unseen && row(state, 'review:group/api!12').status === 'to review · 2 replies', 'a seen reply in an open thread stays in the row')

find(inbox, 'group/api!12').threads[0].notes.push(note(110, 'me', '14:00'))
state = refresh(state, inbox)
assert(row(state, 'review:group/api!12').status === 'to review · 1 reply' && unread(state) === 0, 'a thread leaves the row when the user answers')

find(inbox, 'group/api!12').threads[3].notes.push(note(111, 'ann', '15:00'))
state = refresh(state, inbox)
assert(row(state, 'review:group/api!12').unseen && row(state, 'review:group/api!12').status === 'to review · 2 replies', 'a reply in a resolved thread is unseen')
state = model.markSeen(state, 'review:group/api!12')
assert(row(state, 'review:group/api!12').status === 'to review · 1 reply', 'a resolved thread leaves the row when the user has seen the reply')

const app = find(inbox, 'group/app!7')
app.threads.push({ resolved: false, notes: [note(202, 'bob', '16:00'), note(203, 'me', '16:05')] })
state = refresh(state, inbox)
assert(row(state, 'mine:group/app!7').unseen && row(state, 'mine:group/app!7').status === '1 comment', 'a comment of another person on a merge request of the user is unseen')
state = model.markSeen(state, 'mine:group/app!7')
assert(!row(state, 'mine:group/app!7').unseen && row(state, 'mine:group/app!7').status === '0/1 reviewed', 'a seen row shows the review progress again')

app.approvedBy = ['ann']
app.reviewers[0].state = 'approved'
app.mergeStatus = 'mergeable'
state = refresh(state, inbox)
assert(row(state, 'mine:group/app!7').unseen && tones(row(state, 'mine:group/app!7')) === 'approved=success', 'an approval is unseen')
state = model.markSeen(state, 'mine:group/app!7')
assert(tones(row(state, 'mine:group/app!7')) === 'ready to merge=success', 'an approved, mergeable merge request is ready to merge')

app.approvedBy = []
app.reviewers[0].state = 'requested_changes'
app.mergeStatus = 'requested_changes'
app.pipeline = 'failed'
state = refresh(state, inbox)
assert(row(state, 'mine:group/app!7').status === 'changes requested · pipeline failed', 'a requested change and a failed pipeline are unseen')
assert(
  tones(row(state, 'mine:group/app!7')) === 'changes requested=danger,pipeline failed=danger' && row(state, 'mine:group/app!7').pipelineTone === 'danger'
    && model.hasUnseenDanger(model.rows(state)) && !model.hasUnseenDanger(model.rows(model.markSeen(state, 'mine:group/app!7'))),
  'an unseen requested change and failed pipeline have the tone danger'
)
state = refresh(model.markSeen(state, 'mine:group/app!7'), inbox)
assert(!row(state, 'mine:group/app!7').unseen && row(state, 'mine:group/app!7').status === 'pipeline failed', 'a failed pipeline is reported one time for each commit')
app.sha = 'bbb222'
state = refresh(state, inbox)
assert(row(state, 'mine:group/app!7').unseen && row(state, 'mine:group/app!7').status === 'pipeline failed', 'a failed pipeline of a new commit is unseen')

inbox.mergeRequests.push(copyOf(app, 'group/new', 1, { pipeline: 'success' }))
state = refresh(state, inbox)
assert(!row(state, 'mine:group/new!1').unseen && unread(state) === 1, 'a new merge request of the user is seen')
state = model.markAllSeen(state)
assert(unread(state) === 0, 'mark all seen clears the unread count')

const saved = model.loadState(model.serialize(state))
assert(JSON.stringify(model.rows(saved)) === JSON.stringify(model.rows(state)) && saved.lastRefreshMs === 42, 'the state survives a shell restart')
assert(!model.loadState('not json').initialized && model.rows(model.loadState('not json')).length === 0, 'an invalid saved state fails closed')

state = model.setHidden(state, 'review:group/api!12', true)
assert(!row(state, 'review:group/api!12') && row(state, 'mine:group/app!7'), 'the user can hide one row')
assert(!row(model.loadState(model.serialize(state)), 'review:group/api!12'), 'a hidden row stays hidden after a shell restart')
assert(model.rows(state, true).find(r => r.key === 'review:group/api!12').hidden && model.rowByKey(state, 'review:group/api!12').hidden, 'the list with hidden rows marks the hidden row')
assert(row(model.setHidden(state, 'review:group/api!12', false), 'review:group/api!12'), 'the user can show a hidden row again')
inbox.mergeRequests = inbox.mergeRequests.filter(mr => mr.key !== 'group/api!12')
state = refresh(state, inbox)
assert(
  !Object.keys(state.seen).concat(Object.keys(state.hidden)).some(key => key.endsWith('group/api!12')),
  'a merge request that left the inbox leaves no state'
)

const reviewKey = 'review:group/api!12'
const reviewOf = (state, sha) => model.rows(state, false, model.parseReviews(JSON.stringify({
  version: 1, reviews: { 'group/api!12': { sessionId: 'id', sha, worktree: '/tmp/w' } }
}))).find(r => r.key === reviewKey)
let reviewed = model.reconcile(model.emptyState(), base, 42)
assert(reviewOf(reviewed, 'aaa111').status === 'to review · 1 reply' && !reviewOf(reviewed, 'aaa111').unseen, 'a review of the current head adds no news')
const pushed = JSON.parse(raw)
pushed.mergeRequests.find(mr => mr.key === 'group/api!12').sha = 'bbb222'
reviewed = refresh(reviewed, pushed)
assert(reviewOf(reviewed, 'aaa111').status === 'new commits · 1 reply' && reviewOf(reviewed, 'aaa111').unseen, 'commits after the last review session are unseen')
reviewed = model.markSeen(reviewed, reviewKey)
assert(reviewOf(reviewed, 'aaa111').status === 'new commits · 1 reply' && !reviewOf(reviewed, 'aaa111').unseen, 'seen commits stay in the status until the next review')
assert(reviewOf(reviewed, 'bbb222').status === 'to review · 1 reply', 'a review of the new head removes the status')
assert(Object.keys(model.parseReviews('not json')).length === 0, 'an invalid review file adds no news')

// The user reviews in GitLab, not in a review session of the plugin.
const myReview = (state, sha) => {
  const inbox = JSON.parse(raw)
  Object.assign(inbox.mergeRequests.find(mr => mr.key === 'group/api!12'), { sha })
  inbox.mergeRequests.find(mr => mr.key === 'group/api!12').reviewers[0].state = state
  return inbox
}
let hand = refresh(model.reconcile(model.emptyState(), base, 42), myReview('unreviewed', 'bbb222'))
assert(!row(hand, reviewKey).unseen && row(hand, reviewKey).status === 'to review · 1 reply', 'commits before a review of the user add no news')
hand = refresh(hand, myReview('reviewed', 'bbb222'))
assert(!row(hand, reviewKey).unseen && tones(row(hand, reviewKey)) === 'reviewed=info,1 reply=warning', 'a review by hand adds no news')
hand = refresh(hand, myReview('reviewed', 'ccc333'))
assert(row(hand, reviewKey).unseen && tones(row(hand, reviewKey)) === 'new commits=warning,1 reply=warning', 'commits after a review by hand are unseen')
hand = model.markSeen(hand, reviewKey)
assert(!row(hand, reviewKey).unseen && row(hand, reviewKey).status === 'reviewed · 1 reply', 'seen commits after a review by hand leave the status')
assert(model.loadState(model.serialize(hand)).reviewedHeads['group/api!12'] === 'bbb222', 'the head of a review by hand survives a shell restart')
hand = refresh(hand, myReview('unreviewed', 'ccc333'))
assert(row(hand, reviewKey).unseen && tones(row(hand, reviewKey)) === 'review re-requested=warning,1 reply=warning', 'a new review request after a review is unseen')
hand = model.markSeen(hand, reviewKey)
assert(!row(hand, reviewKey).unseen && row(hand, reviewKey).status === 'to review · 1 reply' && !hand.reviewedHeads['group/api!12'], 'a seen new review request shows to review')

const drafted = JSON.parse(raw)
drafted.mergeRequests.find(mr => mr.key === 'group/api!12').draft = true
assert(tones(row(model.reconcile(model.emptyState(), model.parseInbox(JSON.stringify(drafted)), 42), reviewKey)) === 'to review=warning,1 reply=warning,draft=muted', 'a review row shows a draft')

const palette = model.parsePalette('red = "#e67e80"\nyellow = "#dbbc7f"\ncolor2 = "#a7c080"\n# blue = "#000000"\n')
assert(
  palette.danger === '#e67e80' && palette.warning === '#dbbc7f' && palette.success === '#a7c080' && palette.info === '',
  'the palette reads named theme colors and terminal colors as a fallback'
)
// The detail page
const sha40 = '0123456789abcdef0123456789abcdef01234567'
const kind = (page, name) => page.items.find(i => i.kind === name)
let page = model.detail(model.reconcile(model.emptyState(), base, 42), reviewKey, {})
assert(page.sourceBranch === 'feature' && page.targetBranch === 'main' && page.newCount === 0 && page.diffUrl === '', 'the detail page shows nothing new after the first refresh')
const ordered = page => page.items.every((i, n) => n === 0
  || (page.items[n - 1].isNew && !i.isNew) || (page.items[n - 1].isNew === i.isNew && page.items[n - 1].atMs >= i.atMs))
assert(ordered(page), 'the detail page lists the newest item first')
const reply = page.items.find(i => i.url.endsWith('#note_102'))
assert(
  reply.kind === 'reply' && reply.verb === 'replied' && reply.body === 'Fixed in abc, see docs' && reply.path === 'src/a.ts' && reply.line === 7,
  'a reply shows plain text and the line of its thread'
)
assert(kind(page, 'own') && kind(page, 'comment'), 'the detail page has the notes of the user and of other persons')
assert(
  kind(page, 'commits').verb === 'pushed 2 commits' && kind(page, 'commits').lines.join('|') === "first title|second 'quoted'"
    && kind(page, 'commits').url.endsWith(`/merge_requests/12/diffs?diff_id=7&start_sha=${sha40}`),
  'a push shows its commits and links to its diff'
)
assert(
  kind(page, 'changed').verb === 'changed 2 commented lines' && kind(page, 'changed').url.endsWith(`#${sha40}_10_12`),
  'the commented lines that one push changes make one item'
)
assert(
  kind(page, 'approved').author === 'bob' && !page.items.some(i => /mentioned/.test(i.verb)) && !page.items.some(i => i.verb === ''),
  'the detail page shows approvals and leaves out mentions and empty events'
)

const busy = JSON.parse(raw)
const busyApi = busy.mergeRequests.find(mr => mr.key === 'group/api!12')
busyApi.threads[2].notes.push({ id: 130, author: 'bob', at: '2026-10-01T13:00:00.000+02:00', body: 'One more thing', path: '', line: 0 })
busyApi.events.push({
  id: 131,
  author: 'ann',
  at: '2026-10-01T13:05:00.000+02:00',
  body: `added 1 commit\n\n<ul><li>aaa2222 - fix</li></ul>\n\n[Compare with previous version](/x/-/merge_requests/12/diffs?diff_id=9&start_sha=${'f'.repeat(40)})`
})
const watched = refresh(model.reconcile(model.emptyState(), base, 42), busy)
page = model.detail(watched, reviewKey, {})
assert(page.newCount === 2 && page.items[0].isNew && page.items[1].isNew && !page.items[2].isNew, 'the items after the last look are new')
busyApi.threads[0].notes.push({ id: 132, author: 'me', at: '2026-10-01T14:00:00.000+02:00', body: 'Thanks', path: '', line: 0 })
page = model.detail(refresh(watched, busy), reviewKey, {})
assert(page.items[0].isNew && page.items[2].url.endsWith('#note_132') && ordered(page), 'the new items come before a newer note of the user')
assert(page.diffUrl.endsWith(`/merge_requests/12/diffs?diff_id=9&start_sha=${'f'.repeat(40)}`), 'the diff since the last look starts at the first new push')
assert(model.detail(model.markSeen(watched, reviewKey), reviewKey, {}).newCount === 0, 'a seen row has no new items')

const sessions = model.parseSessions('review:group/app!5\nfix:group/app!5\nother:group/app!5\nreview:group/app!0\ngroup/app!5\n')
assert(Object.keys(sessions).join() === 'review:group/app!5,fix:group/app!5', 'only valid session markers are read')

const unsafe = JSON.parse(raw)
unsafe.mergeRequests[0].url = 'javascript:alert(1)'
assert(model.parseInbox(JSON.stringify(unsafe)).mergeRequests.length === 2, 'a merge request without an HTTPS link is dropped')
assert(model.parseInbox('') === null && model.parseInbox('{"version":2}') === null, 'an invalid helper result is rejected')
assert(model.relativeTime(1000, 61000) === '1m', 'relative timestamps use compact labels')
JS
