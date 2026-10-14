# Filing issues

Use the same standard whether an issue comes from a person, a review, a skill, or a CLI.
The six [issue forms](../../.github/ISSUE_TEMPLATE/) supply the prompts. Each marks one main
answer required; the other fields help capture evidence and prepare the work. A small, clear
request can stay a sentence. Leave unknowns explicit instead of inventing a specification.

## Choose the deliverable

Choose the type by what completing this issue delivers, not by how much implementation
detail is already known.

| Type | Use when completion delivers… | Example |
|---|---|---|
| `type:bug` | A correction to intended behavior | Search became slower after a release. |
| `type:feature` | New or improved intended product behavior or capability | Users can search a larger catalog within an agreed response time. |
| `type:task` | An implementation, tooling, or maintenance improvement that preserves intended product behavior | Replace a storage library while preserving its existing contract. |
| `type:discovery` | Evidence or a recommendation answering a bounded question | Measure where search spends time and recommend the next step. |
| `type:decision` | A recorded choice, or an explicitly scoped authorization supported by evidence | Choose a caching approach after comparing its costs and behavior. |
| `type:epic` | A coordinated set of independently deliverable outcomes | Improve search across indexing, ranking, and presentation. |

A bug can have an unknown cause. A feature can have a known implementation. Investigation
inside a bug fix does not automatically need its own Discovery issue. Use a separate
Discovery when its result is itself the deliverable; link a subsequent implementation issue
when that work is distinct.

Performance, reliability, accessibility, data, documentation, security hardening, testing,
and integrations are topics. Put a useful topic or subsystem in **Area or topic**; it does
not select the template or automatically create a label. For performance work, capture the
workload, baseline and target when known. A short initial request need not know all three.
For data changes, identify reconciliation and safe-rerun expectations. Add compatibility,
rollout, or recovery details only where the change needs them.

## Capture, prepare, complete

- **Capture:** Use a concrete title and explain the problem, outcome, question, or choice.
  Include the evidence you have and distinguish observation from hypothesis. Search for
  an existing issue before filing another. Summarize essential requirements from links;
  another person's local scratch path is not a usable specification.
- **Prepare:** Before undertaking the work, make its scope and **Done when** clear. Resolve
  material contradictions and identify dependencies or outstanding decisions. Prefer
  observable examples to vague criteria such as "works correctly." A reporter does not
  need to supply a root cause, architecture, or test command.
- **Complete:** Link the result or verification that satisfies the completion criteria.
  For Discovery, record findings and remaining uncertainty; for Decision, record the
  choice, who made it, its scope, and supporting evidence. Link any distinct follow-up.

Keep coupled changes together when they need one coordinated implementation and proof.
Split work that can be completed, accepted, and landed independently. Use an Epic to link
those outcomes without copying each child's full specification. A review bundle can remain
one triage issue, typed by its deliverable, whose result gives each finding a disposition:
fix here, linked follow-up, needs evidence, or declined with a reason. Do not turn every
advisory into a new task.

For review follow-ups, include the source review and relevant commit, evidence and impact,
why the finding was deferred, and any dependency or revisit trigger. A proposed fix from a
review is a suggestion until selected as the issue's scope. The issue still gets its actual
work type, such as Bug or Engineering task.

## Existing permissions and restrictions

An issue's type, assignment, readiness, or parent does not grant permission or override
user instructions. Preserve any existing human-decision or joint-discovery restrictions,
including their labels and recorded scope. An assignee alone does not preserve a gate.
Where joint discovery prohibits autonomous research as well as implementation, both
restrictions remain in effect. Do not add a new approval step to routine authorized work.

Choosing an approach and authorizing its later execution are different outcomes. A decision
about a deployment design does not authorize a deployment. Keep any later approval beside
the execution work, with its required evidence and exact action. If an authorization itself
is the decision requested, record its limits explicitly before closing the issue.

Use synthetic examples and remove secrets or private user data from evidence. Sensitive
vulnerability details belong in the project's private security reporting channel.
If no private route is documented, ask a maintainer for one without posting those details.

## Labels

Every issue gets exactly one of the six `type:*` labels. Preserve applicable existing
restriction labels. Area, priority, source, and risk labels are optional per repository;
add them when someone uses them to filter or route work. Do not create a second status
system alongside a maintained project board. Scheduling priority and defect impact are
different judgments; a review's severity does not automatically set queue priority.

## Filing through agents and the CLI

Read the chosen form's field descriptions, then write a Markdown body that follows those
prompts. Use the same field labels as headings where helpful; omit empty optional sections.
Do not copy the YAML itself or unfilled placeholders into the issue. The browser's form
validation does not enforce CLI or API submissions, so skills and agents must apply this
standard themselves.

GitHub currently documents required-field submission enforcement for public repositories
only. Apply the same content standard in private repositories; required markers are not a
substitute for checking the issue body.

Write the exact body to a file and pass it without shell interpolation:

```sh
gh issue create --repo owner-example/repo-example \
  --title 'Allow replaying the tutorial without clearing saved progress' \
  --label 'type:feature' --body-file /path/to/issue-body.md
```

Include applicable existing restriction labels using additional `--label` arguments.
Use the repository's available labels; if the required type label is missing, report that
setup gap instead of silently dropping the type. Issue creation follows the user's existing
authorization. Creating missing labels requires the per-repository confirmation below.

After creation, inspect the issue's actual labels, for example with
`gh issue view <number> --repo owner-example/repo-example --json labels`. Confirm the
selected type and all applicable restriction labels are present. The REST API can silently
drop requested labels when the caller lacks push access. Report missing labels for a
maintainer to apply; preserve restrictions in the issue body and do not treat missing
labels as permission to proceed.

## Enabling the forms in a repository

The files under `.github/ISSUE_TEMPLATE/` must be on the repository's default branch.
The included `config.yml` sets `blank_issues_enabled: false`, steering contributors into
the forms. GitHub still offers blank issues to users with write access or higher, and
CLI/API clients can bypass the forms. Agent instructions apply the same filing standard
across those paths; this configuration is not a repository-wide submission gate. Stricter
automation would have to validate issues after creation or editing and flag missing content.

Create the six type labels in each destination repository: labels are repository metadata
and are not installed by copying template files. GitHub applies a
form's labels only when those labels already exist. Inspect existing labels first. Show the
target repository and the missing labels with their descriptions, then ask the user to
confirm before creating any. After confirmation, run only the creation commands for missing
labels; preserve existing labels. If all six already exist, no creation or confirmation is
needed. An approval applies to the named repository and labels, not every repository.

```sh
issue_repo=owner-example/repo-example
gh label list --repo "$issue_repo" --limit 1000
# After the user confirms this repository and its missing labels, run only those commands:
gh label create 'type:bug' --repo "$issue_repo" --color d73a4a \
  --description 'Correct unintended behavior or a regression'
gh label create 'type:feature' --repo "$issue_repo" --color a2eeef \
  --description 'Add or improve intended product behavior or capability'
gh label create 'type:task' --repo "$issue_repo" --color 5319e7 \
  --description 'Improve implementation, tooling, or maintenance'
gh label create 'type:discovery' --repo "$issue_repo" --color d4c5f9 \
  --description 'Answer a bounded question with evidence or a recommendation'
gh label create 'type:decision' --repo "$issue_repo" --color fbca04 \
  --description 'Record a choice or an explicitly scoped authorization'
gh label create 'type:epic' --repo "$issue_repo" --color 0052cc \
  --description 'Coordinate independently deliverable outcomes'
```

Before accepting reports, document a private security contact, such as in `SECURITY.md`,
or enable GitHub private vulnerability reporting where available. The forms do not create
a private reporting channel.

When adopting these forms in another repository, copy the filing guidance and make it
discoverable by that repository's agents. Confirm label provisioning for that repository
separately. No label
migration or automatic relabeling is implied.

See GitHub's [issue-form syntax](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-issue-forms),
[template chooser configuration](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/configuring-issue-templates-for-your-repository),
[field validation rules](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/syntax-for-githubs-form-schema),
the [GitHub CLI issue command](https://cli.github.com/manual/gh_issue_create),
and [REST issue creation permissions](https://docs.github.com/en/rest/issues/issues#create-an-issue).
