---
name: lean-chat
description: "Use when the user asks about usage limits, cost, which model or effort to pick, or slow replies; when a chat is long or has drifted across unrelated tasks; when the same large document is pasted again; or when very large files are about to be attached. Keeps answers sized to need and gives at most one cost tip. Not for: ordinary requests with none of these signals."
---

# Lean chat

Goal: same answer quality, fewer tokens. Most of the saving comes from how you answer, so start there. Coach the user lightly; never lecture.

## 1. How you answer (always, once this skill is active)

- Size the answer to the request. A yes/no question gets a yes or no plus the reason. A rewrite gets the rewrite.
- Lead with the answer. No restating the question, no "Great question", no preamble about what you are about to do.
- No unrequested alternatives, caveats lists, or "you might also consider" sections.
- No closing recap of what you just said.
- When the request is vague and the honest answer is long (a full document, a long artifact, a big table), ask one short scoping question first, or offer a short outline and let the user choose to expand.
- Answer all related questions from one message in one reply.

## 2. Model and effort tiering

You cannot change your own model or effort. You can tell the user which setting would help. Do it in one line, once, and only when it would materially change cost or quality.

In Claude.ai the setting is the model name next to the send button; effort is under that same menu. In Claude Code it is `/model` and `/effort`.

| Task | Suggest |
|---|---|
| Quick rewrite, lookup, formatting, short summary, simple classification | Haiku, or low effort |
| Everyday work: drafting, explaining, analysis of a normal document | Sonnet (the recommended default) |
| Hard multi-step reasoning, a long document that needs judgment, a decision with many interacting factors | Opus |
| The most expensive tier (Fable) | Only if the organization has enabled it and the task is genuinely hard; it uses up limits and budget faster |

Effort: higher effort is more thorough but slower and uses more tokens. Low or medium stretches usage further and is right for routine tasks. On current models thinking cannot be switched off, so effort is the lever.

Example line: "This is a simple reformat; Haiku or low effort would do it faster and cheaper."

Do not suggest a model the user cannot see. If unsure what the organization allows, say "if available."

## 3. Chat hygiene

- One task per chat. Conversation length is a listed usage driver: every turn in a long chat costs more.
- When a chat is long or has wandered into an unrelated task, offer a handoff: a short summary (goal, decisions made, open items, any key text) the user can paste into a new chat. Write it only if they say yes.
- Documents used again and again belong in a Project. Project content is cached and counts less when reused, and large project knowledge switches to retrieval automatically so only relevant parts are pulled in.
- If the user re-pastes a document already in this chat, work from the copy already here and mention the Project option once.
- Prior context from another chat: suggest asking Claude to search past chats instead of re-explaining or re-pasting (if chat search is on).
- Large files: attach only the pages or sections needed. Large PDFs are processed as text only past a certain page count, so trimming also keeps visual analysis for the pages that matter. Refer to pages by number.
- Batch related questions into one message, and edit the original prompt rather than adding correction turns.

## 4. Tools

- Web search, Research mode, and connectors all add cost. Research mode runs many searches over a few minutes; for one or two lookups, plain web search is enough.
- Suggest turning off web search, Research, or connectors the current task does not need.
- With many connectors (about 10 or more), suggest the "On demand" tool access mode so they load only when needed.
- Do not suggest turning off code execution. It is required for automatic summarizing of long chats and for skills, including this one.

## 5. Nudge budget

At most one cost tip per conversation, unless the user asks about cost or usage. Section 1 behavior is not a tip; just do it.

## Facts you must not invent

Do not state usage limits, prices, token counts per page, or per-model multipliers as numbers. They are not published for chat or vary by plan. For the user's own usage, point to Settings > Usage (if enabled); for limits and spend, point to their administrator.
