Work on my merge request !{{iid}} of the GitLab project {{project}}. Address its review threads, its failed pipeline jobs, and its conflicts with the target branch.

- Merge request: {{url}}
- This folder is a detached checkout of the source branch `{{source}}`. When the session started, `origin/{{source}}` was at {{sha}}.
- Target branch: `origin/{{target}}`
- API path: `{{api}}`

## Start

1. If `git status` shows changes, or if HEAD is not {{sha}}, an earlier session left work in this folder. If this conversation made that work, continue from it. Otherwise tell me what you found, and ask me how to continue.
2. Read the merge request, all of its threads (paginated), my username (`glab api user`), and my pending draft notes (`GET {{api}}/draft_notes`). If I have pending draft notes, stop and ask me what to do with them. The publish call sends all of my draft notes.
3. Make the task list:
   - Each unresolved thread, also the threads that I started, such as the findings of my own review. Skip a thread that another person started when I wrote its last note: I answered it, and it waits for that person. Also skip a thread of mine that asks another person a question.
   - Each failed job of the head pipeline: `projects/<id>/pipelines/<pipeline id>/jobs?scope[]=failed`, with `<id>` from `.target_project_id` and the pipeline ID from `.head_pipeline.id`. The log is at `projects/<id>/jobs/<job id>/trace`. A failed job with `allow_failure` does not block the merge; fix it only when this merge request caused the failure.
   - The conflicts with the target branch, when `.has_conflicts` is true.

   If the task list is empty, tell me and stop.

## Conflicts

Do this task first, so that the other fixes build on the current target branch. Merge `origin/{{target}}` into this checkout. Do not rebase. For each conflict, read what both sides changed and why (`git log --merge -p` helps), and keep the intent of both sides. If a conflict needs a product decision, ask me. Run the tests that the conflicting files touch, and commit the merge.

## Threads

For each thread, find what the reviewer wants and why: the problem behind the words, not only the literal proposal. Read the whole thread and the code that it is about. The position can be outdated, so find where that code is now. Check whether the point is correct: trace the code, or reproduce the problem.

Then sort the thread:

- Clear: you know what to change, and the change clearly resolves the point. Make the change.
- Debatable or needs input: the point is wrong, it is a trade-off, or it needs more input from the reviewer. Do not change the code. Write a reply later.
- Unclear: you do not know what the reviewer wants. Ask me before you do anything for this thread.

Apply the same rules to my own threads. They often come from an automated review and can be wrong, so check them as strictly as the others.

Make the smallest change that resolves the point. Do not refactor nearby code or fix unrelated problems; tell me about them instead. If the same problem occurs elsewhere in this merge request, fix it there too. If a reviewer did not understand the code, make the code clearer instead of explaining it in the thread. When the point is about behavior, add or update a test that fails without the fix.

## Failed jobs

Find the first real error in the log, not the last line. Decide the cause: this merge request, the target branch (the same job fails there too), or the infrastructure (a runner, a network, or a timeout problem). Fix only what this merge request caused. For the other causes, tell me and do not change the code. Run the command of the job here to prove the fix. Do not skip tests, weaken assertions, or disable checks to make a job pass. If a test itself is wrong, fix it, and say why in the commit message.

## Commit and push

Run the tests, the linter, and the build that the changes touch, and fix what fails. Make one commit for each logical change, in the style of `git log`. Do not amend or rewrite commits that are on the remote branch. Then show me the commits and the check results, and ask me before you push. Push without force:

```
git push origin HEAD:refs/heads/{{source}}
```

If the push fails because the branch moved, fetch `origin/{{source}}`, merge it, run the checks again, and ask me again. Never force-push.

## Reply

After the push, write a draft reply with `POST {{api}}/draft_notes` in each thread from the task list. Use `in_reply_to_discussion_id` and `resolve_discussion` (a boolean). Skip an unclear thread that I did not decide.

- Clear: say in one or two sentences what changed, and name the commit. Resolve the thread. In my own threads, a short "Fixed in <commit>: …" is enough.
- Debatable or needs input: give your reasons with evidence, or ask your question. Name the trade-off, and ask whether the reviewer still prefers the other way. Do not resolve the thread.
- My own finding that you reject: give the evidence in one or two sentences, and resolve the thread.

Write in English. Agree plainly when the reviewer is right, and disagree with reasons, not defensively. If I did not allow the push, ask me before you write a reply. Publish the replies with `POST {{api}}/draft_notes/bulk_publish`.

Then tell me in the terminal what you changed, what you pushed, what you wrote in the threads, and what is still open.
