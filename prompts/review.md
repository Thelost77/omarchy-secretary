Review merge request !{{iid}} of the GitLab project {{project}} as a professional programmer, then publish the review on GitLab.

- Merge request: {{url}}
- This folder is a checkout of the merge request head, {{sha}}. The change is `git diff origin/{{target}}...HEAD`.
- API path for `glab api`: `{{api}}`

Prepare a deep and comprehensive review. Be brutally honest, but professional and competent. Focus on correctness, security, maintainability, missing tests, and simplification. Ground every point in a concrete reason or an established practice. Prefer the smallest correct design.

## Understand the change

1. Read the description, the linked issue, the commit messages, and all threads, also the resolved ones. Know what the change must do and what it must not change before you judge the code. If the intent is unclear, review what the code does, and ask about the intent in the summary.
2. Read the rules of the repository: CLAUDE.md, AGENTS.md, CONTRIBUTING.md, REVIEW.md, and the linter configuration. A rule violation is a finding only when you can quote the rule.
3. Start with the most important part of the change. Decide whether the approach is right before you look at details. If the design is wrong, say so in one note, and do not polish code that a redesign will replace.
4. Read beyond the diff: the callers and callees of each changed function, the tests, the types, schemas, config, and migrations that the change touches, the code that it deletes and who relied on it, and how the repository solves the same problem elsewhere. Use `git log` and `git blame` when the reason for the old code matters.

## What to look for

- Correctness: Does the change do what the description says, on every path? Check empty, missing, malformed, duplicate, and boundary input, ordering, units and time zones, and the behavior that the change removes.
- Errors and state: Does a catch block, a fallback, or a default value hide a failure? Does a partial failure leave consistent state? Is a retry safe to repeat? Are resources released?
- Contracts and compatibility: public APIs, events, CLI flags, config keys, stored data, and migrations. Do existing callers, old data, and a rollback still work?
- Concurrency: shared state, races, async ordering, cancellation, and lifecycles.
- Security: Trace untrusted input to queries, shell commands, file paths, HTML, URLs, and deserialization. Check authentication, object-level authorization, tenant scope, and secrets in code and logs. Report a security problem only with a concrete path from the input to the harm. Do not report theoretical denial of service, missing hardening without an exploit path, or attacks that need control of environment variables or CLI flags.
- Tests: Is there a test that fails without the change and passes with it? Do the tests check behavior and contracts, not mocks and internals? Which risky path has no test?
- Simplification: What can be deleted without a change in behavior? Challenge each new abstraction, option, flag, layer, and wrapper: does it have a current second use? Find duplicated paths, new helpers that existing code already provides, hidden defaults, speculative flexibility, and complexity that only moved. Say what is unnecessary and what already does its job.
- Performance: only where the change adds real cost, such as queries in a loop, unbounded data, or repeated remote calls on a hot path.
- Documentation: comments, README, and CLAUDE.md that the change makes wrong.

## Prove each finding

Each note is published under my name, so it must hold up. Base each finding on evidence: the code path with file and line, a failing input, or the output of a command that you ran. A guess from a name is not evidence. Before you keep a finding, check whether a caller, the framework, or the type system already handles it, whether the description says that the behavior is intended, and whether the problem existed before this change.

This is trusted code of my team. You may install the dependencies, build the code, and run the tests, the linter, and small scripts. Run them when the result proves or disproves a finding, or when the pipeline of {{sha}} did not run them. Do not repeat checks that passed for this head. Do not commit or push, and remove the files that you create.

If you suspect a problem but cannot prove it, write a question, not a blocker.

For a large merge request with independent areas, you can give each area to a subagent. Give it the intent, its files, and the standards above, and ask for every candidate finding with its evidence and severity, unfiltered. Then check each candidate in the code yourself before you write a note. Review a small merge request yourself.

## Write the notes

Write a note for each problem that can cause wrong behavior, a failing build or test, a security hole, a broken contract, or complexity that a simpler design avoids. Leave out pure taste, formatting that a tool controls, generated and vendored files, and points that a thread already makes. A problem in code that the change does not touch is not a note; mention it in the summary only if it matters for this change.

There is no quota. Do not search for something to say: a review with no findings is a good result for a good change.

Start each note with a label:

- `blocker:` must change before the merge. A demonstrated bug, security hole, data loss, or broken contract; risky new behavior without a test; or a design that makes the code clearly harder to maintain when a simpler design does the same job.
- `suggestion:` a weakness with a real cost that the merge does not require to fix.
- `question:` you need the author's intent, or you suspect a problem that you could not prove.
- `nit:` polish that the author may ignore. Write one only when it clearly helps the author.

Then state the problem: what is wrong, where, and why it matters (the input, the path, or the consequence). Do not prescribe a fix. The author or a fix session decides how to solve the problem, and a ready-made fix makes them stop looking for a better one. Mention a direction only when the problem is hard to understand without it, and call it one option. Do not use GitLab `suggestion` blocks. Keep it to a few sentences, and quote the code when that makes the problem clearer. Write one note per problem; when the same problem occurs in several places, write one note and list the other places. Comment on the code, not on the person. Do not hedge or pad. Write in English.

## Publish

- Before you write a draft note, list my pending draft notes with `GET {{api}}/draft_notes`. If any exist, stop and ask me what to do with them. The publish call sends all of my draft notes, also the ones that I wrote by hand.
- Check that `.diff_refs.head_sha` of the merge request is {{sha}}. If it is not, the author pushed during your review. Tell me before you publish.
- Create each note with `POST {{api}}/draft_notes`. Its `position` has `position_type: "text"`, the `base_sha`, `start_sha`, and `head_sha` from `.diff_refs`, `old_path`, `new_path`, and `new_line` for an added line, `old_line` for a removed line, or both for an unchanged line. Send the body as JSON: `glab api --input - -H 'Content-Type: application/json'`. If GitLab rejects a position, write the note without one, and name the file and the line in the text.
- Publish with `POST {{api}}/draft_notes/bulk_publish`. Set `note` to the summary. Set `reviewer_state` to `requested_changes` when you wrote a blocker, and to `reviewed` otherwise. Leave out `reviewer_state` when I am the author of the merge request, because GitLab ignores it for the author. `glab api user` gives my username.

The summary has two to five sentences. Start with the verdict: ready to merge, ready after the blockers are fixed, or needs a different approach. Then name the main risks, and say what you ran and what you could not verify. If you found no problem, say so, and say what you checked.

Then tell me in the terminal what you published.
