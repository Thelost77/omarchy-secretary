# OmaSecretary

OmaSecretary is an Omarchy bar widget for GitLab merge requests. It shows the merge requests that wait for you. It also starts a Claude Code session for a merge request with one key. The session reviews the merge request, or it fixes one of your merge requests.

The panel has two groups:

| Group | Content |
| --- | --- |
| To review | The open merge requests where you are a reviewer, with the replies to your notes. |
| My merge requests | Your open merge requests, with the news from other persons. |

A reply is in a thread where you wrote a note and another person wrote the last note. A row with replies opens the newest reply.

The bar shows the number of unseen rows. The number is red when an unseen row reports a failed pipeline, a conflict, or requested changes. A desktop notification tells you about each row that becomes unseen. Click the notification to open the merge request.

## Statuses

Each row shows its statuses as colored labels. The colors come from the current Omarchy theme.

| Color | Meaning | Statuses |
| --- | --- | --- |
| Red | Something blocks the merge request. | pipeline failed, conflicts, changes requested, requested changes |
| Yellow | The merge request waits for you. | to review, review re-requested, new commits, replies, comments |
| Green | The merge request is approved. | approved, ready to merge |
| Blue | The work continues. | reviewed, review started, 1/3 reviewed, reviewing, fixing |
| Gray | Information of low priority | draft, no reviewers, hidden |

A dot before the name shows an unseen row. The label "reviewing" or "fixing" shows an open session of the merge request.

An icon before the time shows the state of the last pipeline:

- A check mark: the pipeline passed.
- A cross: the pipeline failed.
- A clock: the pipeline runs or waits.
- A crossed circle: the pipeline was canceled or skipped, or it waits for a manual job.

## Requirements

- Omarchy 4 with Omarchy Shell
- `glab`, `jq`, `git`, `tmux`, and Claude Code (`claude`)
- A GitLab token that `glab` can use in a login shell

The plugin starts its helpers in a login shell. Use this command to make sure that `glab` works in a login shell:

```bash
bash -lc 'glab api user'
```

If the command fails, use `glab auth login`. As an alternative, export `GITLAB_HOST` and `GITLAB_TOKEN` in your login profile.

## Install

```bash
omarchy plugin add https://github.com/Thelost77/omarchy-secretary.git --enable
```

## Controls

- Click on the bar icon: open or close the panel
- Middle click on the bar icon: refresh
- `j`/`k` or the arrow keys: move the cursor
- `Enter`, `Space`, `o`, or a click on a row: open the row in the browser
- `l` or the right arrow: open the [detail page](#detail-page) of the row
- `c`: start the review session of the row
- `f`: start the fix session of one of your merge requests
- The buttons of the row under the cursor: **Fix** (`f`), **Review** (`c`), **Seen** (`x`), and **›** (`l`). **Fix** shows only on your merge requests. **Seen** shows only on an unseen row.
- `x`: mark the row as seen
- `A`: mark all rows as seen
- `H`: hide the row, or show a hidden row again
- `a`: show the hidden rows, or stop showing them
- `r`: refresh
- `Tab`: go to the next bar panel
- `Esc`: close the panel

## Detail page

The detail page shows one merge request: its title, branches, reviewers, statuses, and activity. The activity has the comments, the pushes, the changes of commented lines, the approvals, and the review requests.

The items that came after you last saw the row are under NEW. The other items are under EARLIER. When you leave the page, the plugin marks the row as seen.

On the detail page, use these keys:

- `j`/`k` or the arrow keys: move the cursor
- `Enter`, `l`, or a click on an item: open the item in the browser. A push opens its diff. A changed line opens the line in the diff.
- `o`: open the merge request in the browser
- `d`: open the new commits as one diff. This key works only when NEW has a push.
- `c`: start the review session
- `f`: start the fix session of one of your merge requests
- `x`: mark the row as seen
- `h`, the left arrow, `Esc`, or the **‹** button: go back to the list

## Review session

**Warning:** A review session publishes its notes on GitLab with your account. It does not ask you first. Start a session only when you want a published review.

When you start a review session, the plugin does these steps:

1. It opens a terminal with the tmux session `mr-<project>-<number>`.
2. It finds a clone of the project. Refer to [Settings](#settings).
3. It fetches the head of the merge request and checks it out in a git worktree. The worktree is in `~/.local/state/omasecretary/worktrees/`.
4. It starts `claude --permission-mode auto --effort xhigh` in the worktree with the prompt `prompts/review.md`.

Claude Code then reviews the change and publishes one summary note. The summary has a score from 0 to 100, a verdict from Approve to Block, and numbered findings that are grouped by severity: Critical, High, Medium, and Low. A finding states the problem. It does not prescribe a fix.

You can also review one of your merge requests. GitLab ignores the review state of the author, so Claude Code does not set it.

The publish step publishes all of your draft notes on the merge request. If you have draft notes that Claude Code did not write, Claude Code stops and asks you.

The session continues when you close the terminal. To stop a review, stop Claude Code in the session or kill the tmux session.

The plugin saves the Claude Code session of each merge request. When you start the session again, Claude Code resumes it with the prompt `prompts/follow-up.md`. Claude Code then checks each earlier finding against the new replies and the new commits, reviews the new code, and publishes a new summary with the status of each earlier finding. Use this, for example, when a row shows "new commits" or replies.

You can also start a review session from a merge request link:

```bash
~/.config/omarchy/plugins/io.github.thelost77.omasecretary/bin/omasecretary-review open <link>
```

## Fix session

A fix session works on the source branch of one of your merge requests. Its task list is the open findings of the review summaries, the open threads, the failed jobs of the pipeline, and the conflicts with the target branch. Low findings are tasks only when you ask for them.

When you start a fix session, the plugin does these steps:

1. It opens a terminal with the tmux session `fix-<project>-<number>`.
2. It finds a clone of the project. Refer to [Settings](#settings).
3. It fetches the source branch and checks it out in a separate git worktree. If the worktree has local work from an earlier session, the plugin keeps that work.
4. It starts `claude --permission-mode auto --effort xhigh` in the worktree with the prompt `prompts/fix.md`.

Claude Code then does these steps:

1. It sorts the tasks, Critical and High first. It fixes a clear point. It writes a reply to a debatable point. It asks you about an unclear point.
2. It fixes the failed jobs.
3. It merges the target branch to resolve the conflicts. It does not rebase.
4. It commits the changes and asks you before it pushes. It does not push with force.
5. After the push, it replies to each review summary with the status of each finding, and it replies in the threads. It resolves a thread only when the commits resolve the point without doubt.

The plugin does not start a fix session for a merge request from a fork.

## Settings

The plugin has one setting, the environment variable `OMASECRETARY_PROJECTS`. Set it to a folder that contains your clones. The plugin then makes the worktree from the clone whose `origin` is the project. Export the variable in your login profile, for example in `~/.bash_profile`:

```bash
export OMASECRETARY_PROJECTS="$HOME/Projects"
```

When the variable is not set, or when no clone has the project as its `origin`, the plugin makes its own clone in `~/.local/state/omasecretary/repos/`.

A session has these effects on a clone of yours:

- `git fetch` updates the remote-tracking branch of the target branch. A fix session also updates the remote-tracking branch of the source branch.
- `git worktree list` shows the worktree of the session.

The plugin does not change your branches or your working tree.

## Data

The plugin reads GitLab every 5 minutes. The helper `bin/omasecretary-inbox` only reads. It gets your open merge requests, their comments, and the system notes of GitLab, such as "added 2 commits". The panel computes the rows and the detail pages from them.

The first refresh marks each row as seen. After that, these events make a row unseen:

- A new review request
- A new request for a review that you gave before
- A reply in a thread where you wrote a note
- New commits after your review
- On your merge requests: a comment, an approval, a review, requested changes, a failed pipeline, or a conflict

The plugin keeps its data in `~/.local/state/omasecretary/`. The file `cache.json` holds the last result and the seen and hidden rows. The file `reviews.json` holds the Claude Code session, the worktree, and the commit of each review session and each fix session.

After each refresh, the plugin removes the worktree and the saved session of each merged or closed merge request. It keeps them while the tmux session of the merge request is open.

## Known limits

- The plugin finds replies only on merge requests where you are a reviewer or the author.
- After a review session of the plugin, the status "new commits" shows until the next review session. After a review in GitLab, the status shows only until you see the row.
- When `glab` cannot reach GitLab, the panel shows the saved rows. Its footer shows the error and the last error line of the helper.
- Claude Code removes old session transcripts. Without the transcript, the plugin starts the review again in a new conversation.

## Remove

Do these steps:

1. Use this command to remove the plugin:

   ```bash
   omarchy plugin remove io.github.thelost77.omasecretary
   ```

2. Use this command to remove the saved data and the worktrees of the sessions:

   ```bash
   rm -rf ~/.local/state/omasecretary
   ```

3. In each clone that had a worktree of a session, use this command to remove the stale worktree entries:

   ```bash
   git worktree prune
   ```

## Test

```bash
./test/secretary-test.sh
./test/review-test.sh
./test/qml-test.sh
omarchy plugin validate .
```

## License

[MIT](LICENSE)
