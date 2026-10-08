There is new activity on merge request !{{iid}} of {{project}} since your review. Check it, review the new code, then publish a new summary.

- Merge request: {{url}}
- At your last review, the head was {{previous}}. The head is now {{sha}}, and this folder is a checkout of it.
- Target branch: `origin/{{target}}`
- API path: `{{api}}`

Use the standards, the summary structure, and the publish rules of your first review.

## Read

1. Make sure that you published your review in this conversation. If you did not, do your first review on the current head, and then stop.
2. List my pending draft notes with `GET {{api}}/draft_notes`. If one exists that you did not write in this conversation, stop and ask me what to do with it. The publish call sends all of my draft notes.
3. Read all notes and threads again (`{{api}}/discussions`, paginated), especially the replies in the discussion of your summary. My own notes and the replies of my fix sessions carry my username, like your notes. So find new activity by note ID and time, not by author.
4. Read the new code with `git diff {{previous}} HEAD`. If the author rebased or merged the target branch, this diff also contains changes from the target branch. Then compare the old and the new merge request diff instead; `git range-diff` helps.

## Earlier findings

Check each open finding of your earlier summaries in the code itself, not only in the replies, and give it a status:

- Fixed: the code resolves the problem. Name the commit.
- Still open: say what is still missing. A fix that adds a problem is still open.
- Accepted: the author declined a suggestion or a Low finding. Accept that.
- Withdrawn: the author showed with reasons that the finding was wrong. Judge the reasons on their merits; the author often knows the code better. If the reasons do not hold, keep the finding open, and answer with new evidence, not the same argument again.

If a reply asks you a question, answer it in the status of its finding.

## New code

Review the new commits with the standards of your first review. Do not add Medium or Low findings on code that you reviewed before and that did not change. If you missed a Critical or High problem in your first review, report it now, and say that it is new. Number new findings after the earlier ones, and keep the numbers of the earlier findings.

## Publish

Publish one new summary note in the structure of your first review, for the current state. Add a section `### Earlier findings` after the severity table: a table with the number, the title, and the status of each earlier finding, with one sentence for each status other than Fixed. The severity table and the finding sections show only the findings that are still open and the new findings. Choose the score and the verdict as in your first review.

If nothing changed since your last summary, publish nothing.

Then tell me in the terminal what you published, or why you published nothing.
