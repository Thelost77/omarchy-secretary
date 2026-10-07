#!/bin/bash

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
tool="$root/bin/omasecretary-review"
bash -n "$tool"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home" "$tmp/projects" "$tmp/remotes/group" "$tmp/tmux"

export HOME="$tmp/home"
unset CLAUDE_CONFIG_DIR
export XDG_STATE_HOME="$tmp/state"
export OMASECRETARY_PROJECTS="$tmp/projects"
state="$tmp/state/omasecretary"
worktree="$state/worktrees/group--app--5"

# Git reads no user config, and the GitLab host is a folder on this machine.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$tmp/remotes/.insteadOf" GIT_CONFIG_VALUE_0="https://gitlab.example.com/"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

cat >"$tmp/bin/glab" <<'SH'
#!/bin/bash
set -euo pipefail
[[ $# -eq 2 && $1 == api && $2 =~ ^projects/(group%2F[a-z]+)/merge_requests/5$ ]] || {
  printf 'Unexpected glab invocation: %s\n' "$*" >&2
  exit 1
}
# A file GLAB_FORK makes the merge request come from a fork.
printf '{"state":"%s","web_url":"https://gitlab.example.com/%s/-/merge_requests/5","target_branch":"main","source_branch":"feature&fix","source_project_id":%s,"target_project_id":1}\n' \
  "$(cat "$GLAB_STATE")" "${BASH_REMATCH[1]//%2F//}" "$([[ -e $GLAB_FORK ]] && echo 2 || echo 1)"
SH

cat >"$tmp/bin/claude" <<'SH'
#!/bin/bash
{
  printf 'cwd=%s\n' "$PWD"
  printf 'arg=%s\n' "$@"
} >"$CLAUDE_LOG"
SH

cat >"$tmp/bin/tmux" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$TMUX_LOG"
case "$1" in
has-session) [[ -e $TMUX_STATE/session ]] ;;
show-options) cat "$TMUX_STATE/marker" 2>/dev/null || true ;;
kill-session) rm -f "$TMUX_STATE/session" "$TMUX_STATE/marker" ;;
new-session) touch "$TMUX_STATE/session" ;;
set-option) printf '%s\n' "${@: -1}" >"$TMUX_STATE/marker" ;;
esac
SH

cat >"$tmp/bin/omarchy-launch-terminal" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$TERMINAL_LOG"
SH
chmod +x "$tmp/bin/"*

export GLAB_STATE="$tmp/glab-state" GLAB_FORK="$tmp/glab-fork" CLAUDE_LOG="$tmp/claude.log"
export TMUX_STATE="$tmp/tmux" TMUX_LOG="$tmp/tmux.log" TERMINAL_LOG="$tmp/terminal.log"
export PATH="$tmp/bin:$PATH"
printf 'opened' >"$GLAB_STATE"

# Each remote has the branch main, the source branch, and the head of merge request 5.
for name in app lib; do
  git init -q -b main "$tmp/seed"
  printf 'one\n' >"$tmp/seed/file"
  git -C "$tmp/seed" add file
  git -C "$tmp/seed" commit -q -m one
  printf 'two\n' >>"$tmp/seed/file"
  git -C "$tmp/seed" commit -q -a -m two
  git init -q --bare -b main "$tmp/remotes/group/$name.git"
  git -C "$tmp/seed" push -q "$tmp/remotes/group/$name.git" HEAD~1:refs/heads/main 'HEAD:refs/heads/feature&fix' HEAD:refs/merge-requests/5/head
  rm -rf "$tmp/seed"
done

# The folder name of the clone is not the project name.
git clone -q https://gitlab.example.com/group/app.git "$tmp/projects/other-name"
head_of() {
  git -C "$tmp/remotes/group/app.git" rev-parse refs/merge-requests/5/head
}
first=$(head_of)

review_of() {
  jq -r --arg field "$1" '.reviews["group/app!5"][$field] // ""' "$state/reviews.json"
}

"$tool" run group/app 5 </dev/null >/dev/null
session=$(review_of sessionId)
[[ $(git -C "$worktree" rev-parse HEAD) == "$first" ]] || fail "run checks out the merge request head in a worktree"
git -C "$tmp/projects/other-name" worktree list | grep -F "$worktree" >/dev/null || fail "run finds the clone by its origin"
[[ ! -e $state/repos ]] || fail "run makes no second clone of a project that has a clone"
pass "run checks out the merge request head in a worktree of the clone with that origin"

[[ -n $session && $(review_of sha) == "$first" && $(review_of worktree) == "$worktree" ]] || fail "run saves the session of the merge request"
grep -Fx "cwd=$worktree" "$CLAUDE_LOG" >/dev/null || fail "Claude Code starts in the worktree"
[[ $(sed -n '2,7p' "$CLAUDE_LOG" | tr '\n' ' ') == "arg=--permission-mode arg=auto arg=--effort arg=xhigh arg=--session-id arg=$session " ]] || fail "the first run starts a new session in auto mode with extra high effort"
grep -F "arg=Review merge request !5 of the GitLab project group/app" "$CLAUDE_LOG" >/dev/null || fail "the first run sends the review prompt"
grep -F "$first" "$CLAUDE_LOG" >/dev/null || fail "the prompt names the head"
if grep -F '{{' "$CLAUDE_LOG" >/dev/null; then
  fail "the prompt has no empty placeholder"
fi
pass "the first run saves the session and starts Claude Code with the review prompt"

# The author adds a commit, and Claude Code has a transcript of the session.
git clone -q "$tmp/remotes/group/app.git" "$tmp/author"
git -C "$tmp/author" fetch -q origin refs/merge-requests/5/head
git -C "$tmp/author" checkout -q FETCH_HEAD
printf 'three\n' >>"$tmp/author/file"
git -C "$tmp/author" commit -q -a -m three
git -C "$tmp/author" push -q origin HEAD:refs/merge-requests/5/head
second=$(head_of)
mkdir -p "$HOME/.claude/projects/some-folder"
touch "$HOME/.claude/projects/some-folder/$session.jsonl"
printf 'a change that the review session left\n' >>"$worktree/file"

"$tool" run group/app 5 </dev/null >/dev/null
[[ $second != "$first" && $(git -C "$worktree" rev-parse HEAD) == "$second" ]] || fail "a later run moves the worktree to the new head"
[[ $(review_of sessionId) == "$session" && $(review_of sha) == "$second" ]] || fail "a later run keeps the session and saves the new head"
[[ $(sed -n '2,7p' "$CLAUDE_LOG" | tr '\n' ' ') == "arg=--permission-mode arg=auto arg=--effort arg=xhigh arg=--resume arg=$session " ]] || fail "a later run resumes the session"
grep -F "the head was $first. The head is now $second" "$CLAUDE_LOG" >/dev/null || fail "the follow-up prompt names the two heads"
pass "a later run resumes the same session with the follow-up prompt on the new head"

rm "$HOME/.claude/projects/some-folder/$session.jsonl"
"$tool" run group/app 5 </dev/null >/dev/null
[[ $(sed -n '6,7p' "$CLAUDE_LOG" | tr '\n' ' ') == "arg=--session-id arg=$session " ]] || fail "a run without a transcript starts the session again"
pass "a run without a transcript starts the session again with the same ID"

"$tool" run group/lib 5 </dev/null >/dev/null 2>&1
[[ $(git -C "$state/repos/group/lib" config --get remote.origin.url) == "https://gitlab.example.com/group/lib.git" ]] || fail "run clones a project that has no clone"
[[ $(git -C "$state/worktrees/group--lib--5" rev-parse HEAD) == "$(git -C "$tmp/remotes/group/lib.git" rev-parse refs/merge-requests/5/head)" ]] || fail "run uses its own clone"
pass "run clones a project that has no clone"

fix_worktree="$state/worktrees/group--app--5--fix"
fix_of() {
  jq -r --arg field "$1" '.fixes["group/app!5"][$field] // ""' "$state/reviews.json"
}
feature_of() {
  git -C "$tmp/remotes/group/app.git" rev-parse 'refs/heads/feature&fix'
}

"$tool" run --fix group/app 5 </dev/null >/dev/null
[[ $(git -C "$fix_worktree" rev-parse HEAD) == "$(feature_of)" ]] || fail "a fix run checks out the source branch"
[[ -n $(fix_of sessionId) && $(fix_of sessionId) != "$(review_of sessionId)" && $(fix_of worktree) == "$fix_worktree" ]] || fail "a fix run saves its own session"
[[ $(sed -n '6p' "$CLAUDE_LOG") == "arg=--session-id" ]] || fail "the first fix run starts a new session"
grep -F "arg=Work on my merge request !5 of the GitLab project group/app" "$CLAUDE_LOG" >/dev/null || fail "the first fix run sends the fix prompt"
grep -F 'git push origin HEAD:refs/heads/feature&fix' "$CLAUDE_LOG" >/dev/null || fail "the prompt keeps an & of a branch name"
pass "a fix run checks out the source branch in its own worktree and sends the fix prompt"

touch "$HOME/.claude/projects/some-folder/$(fix_of sessionId).jsonl"
git -C "$fix_worktree" commit -q --allow-empty -m local
local_head=$(git -C "$fix_worktree" rev-parse HEAD)
"$tool" run --fix group/app 5 </dev/null >"$tmp/fix.out"
[[ $(git -C "$fix_worktree" rev-parse HEAD) == "$local_head" ]] || fail "a fix run keeps the local work of an earlier session"
grep -F "keeps its local work" "$tmp/fix.out" >/dev/null || fail "a fix run tells that it keeps the local work"
[[ $(sed -n '6,7p' "$CLAUDE_LOG" | tr '\n' ' ') == "arg=--resume arg=$(fix_of sessionId) " ]] || fail "a later fix run resumes the session"
pass "a later fix run resumes the session and keeps the local work of an earlier session"

git -C "$fix_worktree" checkout -q --detach "$(feature_of)"
git -C "$tmp/author" fetch -q origin 'refs/heads/feature&fix'
git -C "$tmp/author" checkout -q FETCH_HEAD
git -C "$tmp/author" commit -q --allow-empty -m four
git -C "$tmp/author" push -q origin 'HEAD:refs/heads/feature&fix'
"$tool" run --fix group/app 5 </dev/null >/dev/null
[[ $(git -C "$fix_worktree" rev-parse HEAD) == "$(feature_of)" ]] || fail "a fix run moves a clean worktree to the new head of the branch"
pass "a fix run moves a clean worktree to the new head of the branch"

touch "$GLAB_FORK"
rm -f "$CLAUDE_LOG"
if "$tool" run --fix group/app 5 </dev/null >/dev/null 2>&1 || [[ -e $CLAUDE_LOG ]]; then
  fail "a fix run rejects a merge request from a fork"
fi
rm "$GLAB_FORK"
pass "a fix run rejects a merge request from a fork"

"$tool" prune
[[ -d $worktree && -n $(review_of sessionId) && -d $fix_worktree ]] || fail "prune keeps an open merge request"
printf 'merged' >"$GLAB_STATE"
rm -f "$CLAUDE_LOG"
if "$tool" run group/app 5 </dev/null >/dev/null 2>&1 || [[ -e $CLAUDE_LOG ]]; then
  fail "run does not start a review of a merged merge request"
fi
pass "run does not start a review of a merged merge request"

touch "$TMUX_STATE/session"
"$tool" prune
[[ -d $worktree ]] || fail "prune keeps a merge request with an open tmux session"
rm "$TMUX_STATE/session"
"$tool" prune
[[ ! -e $worktree && ! -e $fix_worktree && ! -e $state/worktrees/group--lib--5 ]] || fail "prune removes the worktrees"
[[ $(jq -c '[.reviews, .fixes]' "$state/reviews.json") == "[{},{}]" ]] || fail "prune removes the entries"
if git -C "$tmp/projects/other-name" worktree list | grep -F "$worktree" >/dev/null; then
  fail "prune removes the worktree from the clone"
fi
[[ -z $(git -C "$tmp/projects/other-name" status --porcelain) ]] || fail "prune leaves the clone clean"
pass "prune keeps open work and removes the data of a merged merge request"

: >"$TMUX_LOG"
"$tool" open "https://gitlab.example.com/group/app/-/merge_requests/5/diffs"
grep -F "new-session -d -s mr-app-5 " "$TMUX_LOG" | grep -F "env -u CLAUDE_CONFIG_DIR bash -lc" |
  grep -F "run \"\$@\" $tool group/app 5" >/dev/null || fail "open starts the run command in a tmux session"
[[ $(cat "$TMUX_STATE/marker") == "review:group/app!5" ]] || fail "open marks the tmux session"
[[ $(tail -n 1 "$TERMINAL_LOG") == "tmux attach-session -t =mr-app-5" ]] || fail "open shows the session in a terminal"
pass "open starts a marked tmux session from a merge request link and shows it"

"$tool" open group/app 5
[[ $(grep -c "^new-session" "$TMUX_LOG") == 1 && $(wc -l <"$TERMINAL_LOG") == 2 ]] || fail "a second open shows the same session"
pass "a second open shows the same session"

rm "$TMUX_STATE/marker"
"$tool" open group/app 5
[[ $(grep -c "^kill-session" "$TMUX_LOG") == 1 && $(grep -c "^new-session" "$TMUX_LOG") == 2 ]] || fail "open replaces a restored session that has no marker"
pass "open replaces a restored session that has no marker"

printf 'review:other/app!5\n' >"$TMUX_STATE/marker"
terminals=$(wc -l <"$TERMINAL_LOG")
for args in "group/app 5" "group/app 0" "app 5" "group/app;id 5" "https://gitlab.example.com/group/app"; do
  # shellcheck disable=SC2086
  if "$tool" open $args >/dev/null 2>&1; then
    fail "open rejects: $args"
  fi
done
[[ $(wc -l <"$TERMINAL_LOG") == "$terminals" ]] || fail "a rejected open shows no terminal"
pass "open rejects a session of another merge request and invalid arguments"

rm -f "$TMUX_STATE/session" "$TMUX_STATE/marker"
"$tool" open --fix "https://gitlab.example.com/group/app/-/merge_requests/5"
grep -F "new-session -d -s fix-app-5 " "$TMUX_LOG" | grep -F "run \"\$@\" $tool --fix group/app 5" >/dev/null || fail "open --fix starts a fix session"
[[ $(cat "$TMUX_STATE/marker") == "fix:group/app!5" ]] || fail "open --fix marks the tmux session as a fix session"
pass "open --fix starts a marked fix session"

rm -f "$TMUX_STATE/session" "$TMUX_STATE/marker"
"$tool" open group/my.app 7
grep -F "new-session -d -s mr-my_app-7 " "$TMUX_LOG" >/dev/null || fail "the session name has no character that tmux rejects"
pass "the session name has no character that tmux rejects"

# The same flow with the real tmux, on its own server and without the user's config.
rm "$tmp/bin/tmux"
if ! command -v tmux >/dev/null; then
  pass "open starts the review in a real tmux session # SKIP no tmux"
  exit 0
fi
unset TMUX
export TMUX_TMPDIR="$tmp/socket"
mkdir -p "$TMUX_TMPDIR"
trap 'tmux kill-server 2>/dev/null || true; rm -rf "$tmp"' EXIT
# The login shell of the session must find the fake commands.
printf 'export PATH=%q:$PATH\n' "$tmp/bin" >"$HOME/.bash_profile"
cat >"$tmp/bin/claude" <<'CLAUDE'
#!/bin/bash
{
  printf 'cwd=%s\n' "$PWD"
  printf 'config=%s\n' "${CLAUDE_CONFIG_DIR:-unset}"
} >"$CLAUDE_LOG"
sleep 30
CLAUDE
printf 'opened' >"$GLAB_STATE"
rm -f "$CLAUDE_LOG"

CLAUDE_CONFIG_DIR="$tmp/other-profile" "$tool" open group/app 5
for _ in $(seq 50); do
  [[ -s $CLAUDE_LOG ]] && break
  sleep 0.1
done
grep -Fx "cwd=$worktree" "$CLAUDE_LOG" >/dev/null || fail "the tmux session starts Claude Code in the worktree"
grep -Fx "config=unset" "$CLAUDE_LOG" >/dev/null || fail "the tmux session does not inherit the Claude Code profile of the caller"
[[ $(tmux show-options -t "=mr-app-5:" -qv @omasecretary) == "review:group/app!5" ]] || fail "the tmux session has the marker"
[[ $(tmux list-sessions -F '#{@omasecretary}') == "review:group/app!5" ]] || fail "list-sessions shows the marker"
"$tool" open group/app 5
[[ $(tmux list-sessions -F '#{session_name}') == "mr-app-5" ]] || fail "a second open makes no second session"
pass "open starts the review in a real tmux session"
