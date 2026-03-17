# CLAUDE.md — docs/bot-behavior/

## Responsibility

This directory defines how the chatbot **behaves** — its personality, constraints, refusal logic, response structure, and edge case handling. It is the specification that the system prompt implements.

## Files

| File | Purpose |
|------|---------|
| `system-prompt.md` | Production-ready system prompt (English and Portuguese), plus a compact fallback version. The Portuguese version is the one pasted into Open WebUI. |
| `refusal-rules.md` | Exhaustive list of what the bot must refuse, how it must refuse, and the exact phrasing. Covers diagnosis, prescriptions, emergencies, PII, jailbreak attempts. |
| `style-guide.md` | Response formatting, tone, language rules, structural patterns. How the bot should write, not what it should say. |
| `examples.md` | Concrete input→output examples for every behavior class: good answers, refusals, out-of-scope, not-found, boundary cases. |
| `test-matrix.md` | Validation test cases with inputs, expected behaviors, and pass/fail criteria. Run after every system prompt change. |

## How these files relate to the live system

```
docs/bot-behavior/          config/system-prompts/        Open WebUI
  (specification)              (deployable prompt)           (live system)
       │                            │                           │
       │   implements               │   paste into              │
       └──────────────►  medical-tutor.md  ──────────►  Admin → System Prompt
```

- `docs/bot-behavior/` is the **source of truth** for behavior design decisions.
- `config/system-prompts/medical-tutor.md` is the **deployable artifact** — the prompt you paste into Open WebUI.
- If the specification changes, update the system prompt to match, then re-paste into Open WebUI.

## Key constraint

The system prompt is the **only** mechanism that controls bot behavior at runtime. There is no code, no middleware, no filter between the LLM and the student. The prompt must be self-contained and robust against prompt injection. Every rule in the specification documents must be enforceable via the system prompt alone.

## Language decision

The system prompt is written in **Portuguese (brasileiro)** because:
- Students interact in Portuguese
- GPT-4o follows instructions in the same language it's asked to respond in more reliably
- The English version exists as a reference and for teams that prefer English design docs

An English-language version is maintained alongside for clarity and review, but the Portuguese version is the one deployed.
