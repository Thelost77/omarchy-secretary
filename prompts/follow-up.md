There is new activity on merge request !{{iid}} of {{project}} since your review. Answer it, review the new code, then publish.

- Merge request: {{url}}
- At your last review, the head was {{previous}}. The head is now {{sha}}, and this folder is a checkout of it.
- Target branch: `origin/{{target}}`
- API path: `{{api}}`

Use the standards and the publish rules of your first review.

## Read

1. Make sure that you published your review in this conversation. If you did not, do your first review on the current head, and then stop.
2. List my pending draft notes with `GET {{api}}/draft_notes`. If one exists that you did not write in this conversation, stop and ask me what to do with it. The publish call sends all of my draft notes.
3. Read all threads again (`{{api}}/discussions`, paginated). Your threads are the ones that you started in this conversation. Your notes carry my username, and so do my own notes and the replies of my fix sessions. So find new activity by note ID and time, not by author: each note after your last note in a thread is new.
4. Read the new code with `git diff {{previous}} HEAD`. If the author rebased or merged the target branch, this diff also contains changes from the target branch. Then compare the old and the new merge request diff instead; `git range-diff` helps.

## Your threads

For each of your threads with a new note, or with new code at its position, check the code itself, not only the reply:

- Fixed: reply in one sentence, name the commit, and resolve the thread. If it is already resolved, write nothing.
- Partly fixed, or the fix adds a problem: say exactly what is still missing.
- The author disagrees: judge the reasons on their merits; the author often knows the code better. If the reasons hold, say so and resolve the thread. If they do not, answer with new evidence, not the same argument again. For a suggestion or a nit, accept the author's decision and resolve the thread.
- Your question is answered: resolve the thread if the answer removes the concern. If the answer shows a bug, say so and start the reply with `blocker:`.
- Resolved, but not fixed: reply and say what is missing.
- No new note and no change at its position: write nothing.

## New code

Review the new commits with the standards of your first review. Do not add suggestions or nits on code that you reviewed before and that did not change. If you missed a real blocker in your first review, report it now, and say that it is new.

## Publish

Publish all draft notes in one `bulk_publish` call. The summary has one to three sentences: the verdict first, then which blockers are fixed and which are still open. Set `reviewer_state` to `requested_changes` while one of your blockers is open, and to `reviewed` otherwise. Leave it out when I am the author. If no thread needs an answer and the new code has no finding, publish only the summary, and only when your verdict changed, so that the reviewer state is current.

Then tell me in the terminal what you published, or why you published nothing.
