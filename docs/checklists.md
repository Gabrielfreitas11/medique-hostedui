# Operational Checklists

Print-and-use checklists for content ingestion, retrieval quality, hallucination debugging, and re-upload decisions.

---

## Checklist 1: Content Ingestion

Run this checklist for every PDF before and after uploading to Open WebUI.

### Before upload

| # | Check | How | Pass? |
|---|-------|-----|-------|
| 1 | PDF has a text layer | Open in reader → try to select/copy text | ☐ |
| 2 | If scanned: OCR has been applied | Run `pdffonts file.pdf` — should show fonts | ☐ |
| 3 | Text is readable when copied | Copy a paragraph → paste in text editor → readable? | ☐ |
| 4 | No password protection | PDF opens without password prompt | ☐ |
| 5 | File size is reasonable | Under 50MB per file; split if larger | ☐ |
| 6 | File is named descriptively | Format: `[course]-[module]-[topic].pdf` | ☐ |
| 7 | No sensitive data beyond course content | No student PII, no instructor personal data | ☐ |
| 8 | Original PDF backed up externally | Copy stored in cloud/NAS separate from Open WebUI | ☐ |

### Upload

| # | Step | Status |
|---|------|--------|
| 9 | Collection exists (or created) | ☐ |
| 10 | File uploaded to correct collection | ☐ |
| 11 | Processing completed without error | ☐ |
| 12 | Collection is bound to the model | ☐ |

### After upload

| # | Verification | How | Pass? |
|---|-------------|-----|-------|
| 13 | Direct question test | Ask something the PDF clearly answers | ☐ |
| 14 | Answer matches PDF content | Compare bot's answer against source PDF | ☐ |
| 15 | No fabricated page numbers or citations | Bot doesn't invent references | ☐ |
| 16 | Table/list content retrievable | Ask about a specific table or list in the PDF | ☐ |
| 17 | Not-in-material test | Ask something NOT in this PDF → bot declines | ☐ |

If any check fails, see `docs/rag-operations.md` for troubleshooting.

---

## Checklist 2: Retrieval Quality

Run this after changing RAG settings, adding/removing significant content, or on a monthly schedule.

| # | Test | Input (adapt to your content) | Expected | Pass? |
|---|------|------------------------------|----------|-------|
| 1 | **Exact term match** | Use a specific term from a PDF heading | Retrieves correct section | ☐ |
| 2 | **Synonym/paraphrase** | Ask the same concept using different words | Same content retrieved | ☐ |
| 3 | **Cross-section retrieval** | Ask something that requires combining two sections | Answer draws from both | ☐ |
| 4 | **Specific detail** | Ask for a specific number, name, or date from the PDF | Correct detail returned, not fabricated | ☐ |
| 5 | **Negative test** | Ask about a topic definitively not in the PDFs | Bot says "não encontrei" | ☐ |
| 6 | **Near-miss test** | Ask about a related but uncovered topic | Bot answers available content, identifies gap | ☐ |
| 7 | **Table retrieval** | Ask about data in a table | Correct data returned (or acknowledge extraction issue) | ☐ |
| 8 | **Long passage** | Ask the bot to explain a topic covered in 2+ pages | Comprehensive answer, not truncated | ☐ |

### Scoring

- **8/8 pass**: Retrieval quality is good. No changes needed.
- **6–7/8 pass**: Minor tuning needed. Adjust chunk size or top-k.
- **5 or fewer pass**: Significant issue. Check PDF extraction, RAG settings, and collection binding.

### Common fixes

| Failure pattern | Likely cause | Fix |
|----------------|-------------|-----|
| Tests 1–3 fail | Collection not bound to model | Admin → Models → Knowledge → add collection |
| Test 2 fails but 1 passes | Embedding model mismatch between query and doc | Verify RAG_EMBEDDING_MODEL hasn't changed since upload |
| Test 4 fails (invents details) | Chunk doesn't contain the detail; model fills in | Increase top-k; verify PDF extraction quality |
| Test 5 fails (answers anyway) | Parametric leakage | Strengthen system prompt; lower temperature |
| Test 7 fails | Table extraction issue | Re-upload or create a text summary of the table |
| Test 8 fails (truncated) | Chunk size too small; top-k too low | Increase chunk size and/or top-k |

---

## Checklist 3: Hallucination Debugging

Use when a bot response contains information that seems wrong or unsourced.

| # | Step | Action | Finding |
|---|------|--------|---------|
| 1 | **Identify the claim** | Write down the specific fact the bot stated | Claim: _____________ |
| 2 | **Search the source PDF** | Open the PDF, Ctrl+F for key terms | Found in PDF? ☐ Yes ☐ No |
| 3a | If YES in PDF: **Compare** | Does the bot's statement match the PDF? | ☐ Matches (not a hallucination) |
| 3b | If YES but different: **Extraction error** | The text was garbled during extraction | ☐ Re-upload PDF or fix source |
| 3c | If NO in PDF: **Parametric leak** | Model answered from training data | ☐ Grounding failure — see step 4 |
| 4 | **Check collection binding** | Admin → Models → is collection attached? | ☐ Bound correctly |
| 5 | **Check RAG settings** | Admin → Settings → Documents → chunk/top-k | ☐ Settings correct |
| 6 | **Re-test with exact PDF wording** | Use terms directly from the PDF | ☐ Correct answer now? |
| 7 | **Re-test with original phrasing** | Repeat the original question | ☐ Still hallucinating? |
| 8 | **Decision** | Based on findings: | ☐ PDF issue → fix PDF ☐ RAG settings → tune ☐ Prompt weakness → strengthen prompt ☐ Unavoidable parametric leak → document and monitor |

### Root cause summary

| Root cause | Frequency | Fixable? |
|-----------|-----------|----------|
| PDF extraction error | Common with scanned/complex PDFs | Yes — fix PDF, re-upload |
| Chunk boundary splits relevant content | Common | Yes — adjust chunk size/overlap |
| Query phrasing doesn't match embedding | Occasional | Partially — test with different wordings |
| Low top-k misses relevant chunks | Occasional | Yes — increase top-k |
| Parametric knowledge leakage | Occasional | Partially — prompt + temperature only |
| Model confident confabulation | Rare | No — fundamental LLM limitation |

---

## Checklist 4: When to Re-Upload / Re-Process Documents

Use this decision tree when considering whether documents need to be re-processed.

| # | Trigger | Re-upload needed? | Action |
|---|---------|-------------------|--------|
| 1 | Course materials updated (new edition) | **Yes** | Remove old file, upload new version |
| 2 | OCR quality was poor on initial upload | **Yes** | Re-run OCR with better settings, re-upload |
| 3 | RAG chunk size/overlap changed | **No** — existing embeddings use old settings, but new queries may retrieve differently | Re-upload only if retrieval quality degrades |
| 4 | Embedding model changed (e.g., `small` → `large`) | **Yes — all documents** | Delete all collections, re-create, re-upload everything |
| 5 | Open WebUI upgraded to new version | **Maybe** | Test retrieval quality first. Re-upload only if it degrades. |
| 6 | Bot giving wrong answers for known content | **Maybe** | Run hallucination checklist first. Re-upload only if extraction is the cause. |
| 7 | New module added to course | **Upload new files only** | Add to existing collection |
| 8 | Module removed from course | **Delete file from collection** | Students won't get removed content in future queries |
| 9 | Multiple versions of same content exist | **Yes — clean up** | Remove duplicates; keep only current version |
| 10 | Moved from dev to production | **Yes — re-upload in prod** | Dev and prod have separate databases; embeddings don't transfer |

### Re-upload procedure

```
1. Note which collection and files are affected.
2. Back up current state (./scripts/backup.sh).
3. Remove the old file(s) from the collection.
4. Upload the new file(s).
5. Wait for processing to complete.
6. Run the 5-question retrieval test (Checklist 2, tests 1–5).
7. If bound to a model, verify the binding is still active.
```

---

## Checklist 5: Pre-Launch Content Review

Run before opening the chatbot to students.

| # | Check | Status |
|---|-------|--------|
| 1 | All course PDFs uploaded to correct collections | ☐ |
| 2 | All collections bound to the correct model | ☐ |
| 3 | System prompt pasted and saved | ☐ |
| 4 | RAG settings configured (chunk 1000, overlap 200, top-k 5) | ☐ |
| 5 | Web search disabled (Admin + `.env`) | ☐ |
| 6 | No tools/functions enabled | ☐ |
| 7 | Temperature set to 0.3 | ☐ |
| 8 | Signup disabled | ☐ |
| 9 | Student accounts created | ☐ |
| 10 | Retrieval quality checklist passed (6+ / 8) | ☐ |
| 11 | Bot behavior test matrix passed (all A–F, I groups) | ☐ |
| 12 | At least one jailbreak test run (Group G) | ☐ |
| 13 | Original PDFs backed up externally | ☐ |
| 14 | Database backup tested (./scripts/backup.sh) | ☐ |
| 15 | OpenAI spending limit set | ☐ |
