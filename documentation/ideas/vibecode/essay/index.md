# Vibecode efficiency — preliminary test

*Preliminary single-run comparison of an AI agent consuming the same content as English prose vs as vibecode JSON. Quick directional check, not a rigorous experiment.*

~~~vibecode
{"vibecode": {
	"doc": "vibecode_efficiency_preliminary",
	"role": "captures a preliminary single-run measurement of token cost and wall-clock time for an AI agent consuming the same source content as English prose vs as structured vibecode JSON; flags caveats and outlines what a rigorous follow-up would require",
	"status": "preliminary_finding_not_priority",
	"finding": "vibecode_used_21pct_fewer_tokens_and_40pct_less_wall_clock_at_equivalent_answer_quality",
	"sample_size": "n_equals_1_per_format",
	"related_issue": "https://github.com/mikosullivan/puck/issues/457"
}}
~~~

## Question

Is vibecode JSON measurably more efficient for an AI agent to consume than equivalent English prose? "Efficient" = fewer tokens and/or less wall-clock to reach the same comprehension. Filed as [issue #457](https://github.com/mikosullivan/puck/issues/457).

## Source material

The Wikipedia article on *A Midsummer Night's Dream*, pulled as plain text via the Wikipedia API:

- [midsummer.txt](https://puck.uno/documentation/ideas/vibecode/essay/midsummer.txt) — 74,558 chars of prose
- [midsummer.json](https://puck.uno/documentation/ideas/vibecode/essay/midsummer.json) — 33,817 chars of vibecode (45% the size on disk) covering the same content

The vibecode is hand-translated: structured outer keys, tokenized values where natural (character names, dates, places, roles), prose only where compression would lose meaning. Same scope as the .txt — characters, full plot by act/scene, sources, dating, themes, critical history, performance history, adaptations.

## Method

Two cold agents (spawned in parallel under identical conditions), each given one file and the same four-question task:

1. Trade of each mechanical.
2. Flower in Oberon's potion and its color-change origin.
3. Year and venue of first court performance.
4. Three film adaptations from the 2010s, with year and director.

Each agent was told to read the full file, answer the questions, and report a subjective "fast / medium / slow" feel for the read.

## Result

| | Prose (.txt) | Vibecode (.json) | Vibecode advantage |
|---|---|---|---|
| Source chars | 74,558 | 33,817 | 45% the size |
| Tokens consumed | 51,257 | 40,479 | -21% |
| Wall-clock | 13.9 s | 8.3 s | -40% |
| Read tool calls | 2 (paged) | 1 (one shot) | — |
| Answer correctness | equivalent | equivalent | — |

Both agents answered questions 1–3 correctly. Both were equally shaky on question 4 — the source itself thins out for 2010s films, so the gap is in the source, not the format.

## What this suggests

Token cost goes down meaningfully (~20%) and wall-clock goes down more (~40%). The wall-clock drop is bigger than the token drop because the vibecode fit in one Read tool call while the prose required two — single-shot reads avoid round-trip overhead. Worth noting that this overhead is a property of the tooling, not the format; in a setting where the prose also fits in one read, the gap would narrow toward the token ratio.

The answer-quality match is the load-bearing finding. If vibecode cost half the tokens but lost half the comprehension, it'd be a bad trade. The fact that the four-question correctness was equivalent means the compression was lossless at this depth.

## What this doesn't establish

- **Training contamination.** *Midsummer* is in every LLM's training corpus. Questions 1–3 could plausibly be answered from memory without reading either file. A rigorous repeat needs content the model demonstrably hasn't seen — a post-cutoff Wikipedia article, an obscure topic, or original writing.
- **Sample size of one per format.** Single-run measurements are anecdote, not signal. A real test wants ~10 cold runs per format, ideally across multiple agent backbones, with cross-condition randomization.
- **Question depth.** Four-fact retrieval is the shallowest comprehension test. Genuine equivalence checking wants synthesis ("what's the central conflict between Oberon and Titania"), inference ("which critic would most strongly agree with X"), and cross-reference ("does the plot summary support the gender-roles thematic reading").
- **Vibecode quality varies.** This particular vibecode was hand-tuned by an AI (me) under direct human feedback to push structure as deep as possible. A naïve translation would have looser structure and a smaller win. A more aggressive minified format might gain more.

## Rough next steps for a real test

1. Pick a source the model can't recall — a 2026 article, an obscure topic, or write something new.
2. Generate both formats from the same source.
3. Design ~20 questions covering surface facts, structured detail, and inference. Answers grounded in the source only.
4. Run N cold agents per format (~10 each), randomize question order, score blindly.
5. Report token cost, wall-clock, and answer correctness as distributions, not single numbers.
6. If the finding holds, repeat across at least one more agent backbone to check format-specific tokenization effects.

## Status

Not a priority. This page exists as a directional finding and a placeholder for the rigorous follow-up whenever it becomes useful to run. [Issue #457](https://github.com/mikosullivan/puck/issues/457) stays open as the trigger.
