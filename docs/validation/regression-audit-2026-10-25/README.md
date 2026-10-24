# Follow-up regression audit

**22 additional focused runs passed: 5,135 assertions, zero failed assertions or
game/script errors.** The tested older behaviors below remain intact. This is
separate from the [initial 25 runs / 3,446 assertions](../issues-109-112-2026-10-24/checks/results.json),
the [attack/snow/tutorial checks](../attack-path-snow-ui-2026-10-25/README.md), and
the [D3D12 load/cursor checks](../load-crashes-cursor-2026-10-25/README.md).
Repeated runs are not added to this coverage count.

The [machine-readable results](results.json), [compact coverage list](coverage.tsv),
and [retained logs](checks/) record each scenario, script hash, campaign and renderer.
Retained text normalizes line endings and trailing whitespace; `retained_log_sha256`
identifies these copies, while raw runtime hashes refer to the original local logs.
The [complete issue inventory](../issues-109-112-2026-10-24/issue-review.md) still
distinguishes reading all 110 reports from independently reproducing them.

## What was checked

| Behavior protected | Runs / assertions | Scope |
|---|---:|---|
| Shop filters, Shift stacks, wear/charge identity, quest-item protection, co-op repair/swap and spell-construction transactions | 3 / 221 | Real camp controls, authority transactions and ENet peers with private purses. |
| Repeat casting | 1 / 371 | Same-target recasts through classic mouse, direct keyboard and controller input. |
| Dialogue clock and held-Space skip | 2 / 18 | Host/guest clock ownership; final phrase remains until a fresh press. |
| Scrolling, journal states and translated controls | 1 / 198 | Hovered lists, endpoints, cancellation and EN/RU/DE strings. |
| Hidden replica presentation and original dialogue mouths | 2 / 159 | Current placement at reveal, animation clocks, body/portrait atlases and speaker lifecycle. |
| Character selection and training | 1 / 71 | Every offered spell in one original multiplayer kit; selection, disk reload, host admission, View, pending Accept/Cancel and immediate training. Inactive ability rows are excluded. |
| LiA smith dialogue | 1 / 16 | Authored offer list, Back, reopening, highlighting and reward names. |
| Saved clocks, travel, actor references, prison alarms and side quests | 4 / 709 | Base-campaign return state; independent saved actor identities; prepared original prison script continuations; all installed side-quest archive lifecycle checks. |
| Shop art, spell filtering and travel previews | 2 / 170 | Rendered OpenGL; actual EN/RU/DE text archives; distinct healer field/cave clicks. |
| Character/item fit and option layout | 3 / 3,165 | OpenGL EN/RU/DE remake controls; original heads/items stay in their cells while turning. Geometry assertions account for most of this count. |
| Original ground marks | 2 / 37 | OpenGL footprints on actual slopes and raised floors; blood/scorch visibility, fading, teardown and animated pigment versus an independent CPU projection. |

Selected [screenshots](layout/) were inspected. Original archive labels remain in
the installed edition's language when only the remake language is switched.
Audio checks inspect routing/events with all sound muted; no audible-fidelity
claim is made. Prepared actors and quest states do not constitute a full playthrough.

## Coverage gaps found and repaired

The [#85 history](../attack-path-snow-ui-2026-10-25/README.md) explains the recurring
path report: the October 23 patch repaired the pursuit speed sign but did not
repair the live preview. The closing claim was broader than the tested change.
The new path check fails 12 assertions against the previous production PCK and
passes against the correction, including an actual moving peasant and the older
hidden-position behavior.

The repository already had a broad gameplay runner, but **14 of the focused
scripts inspected here were absent from its catalog**. Eleven headless scripts
are now registered there; the multilingual rendered cases live in the
[focused manifest](../../../tools/regressions.json), along with tutorial and
ground-mark checks. The full catalog now has 403 available configurations across
314 scripts. This audit did **not** run all 403.

The eleven new catalog entries were also run through the full runner, including
its staged source, isolated profile and campaign confirmation: **11/11 programs,
755 assertions, zero failures/errors**. [Full metadata](main-catalog-results.json).
This is an integration replay, with overlapping assertions, not additional unique
coverage. Its metadata points to the retained compact logs.

The [focused command](../../regression-checks.md) reuses the existing summary
parser and gameplay bootstrap. Missing/duplicate completion, reduced assertion
counts, wrong campaign/profile/display, failed assertions, process failure and
script/game errors fail the run. An actual negative control supplied LiA archives
to the base-character case; the bootstrap rejected it before the test ran.
[Expected rejection](expected-wrong-campaign.json). Seven focused-runner unit
controls and 31 existing gameplay-runner checks pass. The latter initially found
three side-quest wrappers whose dynamically built marker was invisible to catalog
validation; each wrapper now declares its unchanged marker explicitly.

Two first attempts in this audit accidentally mapped base Suslanger/prison tests
to LiA archives. Their failures were not accepted as results. The mapping was
corrected, then the unchanged gameplay tests passed (35 and 70 assertions). The
shared startup check now gives a direct wrong-campaign error for that mistake.
The GPU Lab virtual-monitor EDID diagnostic is kept separately in results; the
exception is limited to its exact X11 refresh-rate call, not arbitrary errors.

## Remaining limits

No additional gameplay defect was demonstrated by these older-behavior checks.
That is narrower than a guarantee of no regressions. Native Windows driver and
DLSS/frame-generation qualification, Android freeze reports, internet co-op,
all character kits, every save/mod combination, and uninterrupted campaigns were
not rerun. The supplied crash failure chain was reproduced and its allocation
errors removed under the Windows executable through Wine/VKD3D; the final native
device hang and persistent black-ground image were not reproduced.

The commands are checked in for repeat use. No scheduler, remote CI run, issue
closure or release publication was created by this audit.
