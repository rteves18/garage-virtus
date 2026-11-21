# Autonomous app progress (Ryan away, 2026-11-21)

Ryan's request: "get the rest of the app done: navigate my garage, cars, parts, database (local for now)", plus "an AI chat
where I can ask what parts I need for a section, e.g. 'what hardware do I need for the rear suspension?', and it builds a
list with a total. Later Amayama data gives availability, price, links and quantities."

Ryan opted out of questions for this run. The calls below are Claude's, recorded so he can override them.

## Working arrangement
- Worktree `~/Documents/dev/personal/garage-virtus-worktrees/app-progress`, branch `app-progress` (from `garage-tracking`).
  The main checkout belongs to Ryan's scraping agent: don't touch it. Merge when Ryan is back.
- Only quit app processes under this worktree's `build/` path.

## 1. AI parts assistant (Claude API)
- **Model:** `claude-opus-5-5` over raw HTTP `POST https://api.anthropic.com/v1/messages` (no official Swift SDK),
  `anthropic-version: 2026-10-21`, adaptive thinking (default), `output_config.effort: "medium"`, `max_tokens: 16000`,
  server-side refusal fallback (`anthropic-beta: server-side-fallback-2026-07-01`, `fallbacks: "default"`).
- **Key:** Ryan's Anthropic API key, entered once in Settings (⌘,) and stored in the Keychain. Never in files or git.
  Sandbox gains `com.apple.security.network.client`.
- **Context:** the open schema group (the schemas in the selected year window): every callout with its parts (OEM number,
  name, applies, period, qty per car, price/status) plus My garage coverage (have / need) per part number. Sent as the
  system prompt with prompt caching, so follow-up questions are cheap.
- **Tool:** `build_parts_list(title, items[{oem, quantity, reason}])`. The app resolves each part number against the
  section (name, unit price, availability), computes line totals and a grand total, and shows a list card. The model gets
  the computed totals back, so totals are never invented by the model. The card has "Add all to Need".
- **Conversation:** assistant content (including thinking blocks) is stored and sent back unchanged. The tool loop runs
  at most 6 rounds. `stop_reason` is handled for refusal, max_tokens and tool_use.
- **UI:** an "Ask AI" toolbar toggle in a group swaps the right-hand panel (fixed 380 pt, like the parts panel) to the
  chat. A new chat starts per group.

## 2. Garage navigation, cars, database
- Cars: list and edit Ryan's cars (the 180SX plus add/rename/delete). Parts belong to the selected car. Sidebar shows the
  car switcher.
- Garage overview: a "My garage" home with counts per status, total spent, and the most-short needs.
- A store-open failure shows a visible warning instead of silently using memory (deferred item from the garage review).

## Progress ledger
(appended as work lands)
- AI assistant done: Kit client, tool loop, list builder, context (40 Kit tests); Keychain key store; Settings; Ask AI panel. Launch check: group 101 with panel idle, network.client present. No live API call made (needs Ryan's key).
