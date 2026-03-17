# RAG Operations — PDF Ingestion, Retrieval, and Quality

How to prepare, upload, manage, and validate course PDFs in Open WebUI for the medique-hostedui chatbot.

---

## How RAG works in this project

```
Admin uploads PDF
       │
       ▼
Open WebUI extracts text (built-in parser, not OCR)
       │
       ▼
Text split into chunks (configurable size + overlap)
       │
       ▼
Each chunk embedded via OpenAI text-embedding-3-small
       │
       ▼
Embeddings stored (ChromaDB in dev, pgvector in prod)
       │
       ▼
Student asks question → query embedded → top-k similar chunks retrieved
       │
       ▼
System prompt + retrieved chunks + question → sent to GPT-4o-mini
       │
       ▼
Model answers from the retrieved context (grounding constraint)
```

**Critical understanding**: Open WebUI's text extraction is rule-based, not OCR. It reads the text layer embedded in the PDF. If a PDF is a scanned image with no text layer, extraction produces nothing or garbage. See "Scanned vs. text PDFs" below.

---

## PDF Preparation (before upload)

### Text PDFs vs. scanned PDFs

| Type | How to identify | Extraction quality | Action |
|------|----------------|-------------------|--------|
| **Text PDF** (born-digital) | You can select and copy text in a PDF reader | Good — full text extracted | Upload directly |
| **Scanned PDF with OCR layer** | You can select text, but it may have typos | Variable — depends on OCR quality | Upload, then verify with test queries |
| **Scanned PDF without text layer** | You cannot select any text; it's a flat image | **Zero** — no text extracted | Must be OCR'd before upload (see below) |

### How to check if a PDF has a text layer

1. Open the PDF in any reader (Preview, Acrobat, Chrome).
2. Try to select a paragraph of text with your cursor.
3. If you can select and copy text → it has a text layer.
4. If clicking just selects the whole page as an image → no text layer.

### Handling scanned PDFs (no text layer)

Open WebUI cannot OCR images. You must pre-process:

**Option A — Adobe Acrobat Pro**
1. Open the scanned PDF.
2. Go to Tools → Scan & OCR → Recognize Text.
3. Run OCR. Save the result.
4. Upload the OCR'd PDF to Open WebUI.

**Option B — Free tools**
- `ocrmypdf` (command line, open source):
  ```bash
  # Install
  pip install ocrmypdf
  # or: brew install ocrmypdf (macOS)
  # or: apt install ocrmypdf (Ubuntu)

  # Run OCR on a scanned PDF
  ocrmypdf input-scanned.pdf output-text.pdf --language por
  ```
- Online OCR services (privacy concern with medical content — use offline tools when possible).

**Option C — Manual text extraction**
If the PDF is short or OCR quality is poor, manually extract the text into a `.txt` or `.md` file and upload that instead. Open WebUI accepts text files in Knowledge collections.

### Structural issues that hurt extraction

| Problem | Impact | Mitigation |
|---------|--------|-----------|
| Multi-column layouts | Columns may merge into garbled text | Convert to single-column before upload, or test and accept if readable |
| Tables | Cell boundaries lost; data becomes a text stream | Verify table content retrieval with test queries; consider recreating critical tables as text |
| Headers/footers repeated on every page | Appear in many chunks, diluting relevance | Acceptable if content is still retrievable; not fixable without pre-processing |
| Embedded images with text | Image text not extracted (not OCR) | If critical, transcribe image text manually into a supplementary file |
| Watermarks | May appear in extracted text as noise | Remove watermarks before upload if possible |
| Password-protected PDFs | Cannot be parsed at all | Remove password protection before upload |
| Very large PDFs (500+ pages) | Upload may time out; many chunks reduce precision | Split into chapter-sized files (50–100 pages each) |

### PDF naming convention

Name files descriptively so admins can manage them later. The filename is visible in the Knowledge collection UI.

**Recommended format**: `[course-code]-[module]-[topic].pdf`

Examples:
```
cardio-mod01-insuficiencia-cardiaca.pdf
cardio-mod02-hipertensao-arterial.pdf
cardio-mod03-arritmias.pdf
farmaco-mod01-anti-hipertensivos.pdf
farmaco-mod02-anticoagulantes.pdf
```

**Avoid**:
- Generic names: `aula1.pdf`, `material.pdf`, `scan20260315.pdf`
- Very long names: keep under 80 characters
- Special characters: avoid accents, spaces (use hyphens)
- Version numbers in filenames: `v2`, `final`, `final-final` — use the collection as the version control, not the filename

---

## Knowledge Collection Strategy

### Option A: One collection per course (recommended)

```
Collection: "Cardiologia 2026"
  ├── cardio-mod01-insuficiencia-cardiaca.pdf
  ├── cardio-mod02-hipertensao-arterial.pdf
  ├── cardio-mod03-arritmias.pdf
  └── cardio-mod04-valvopatias.pdf

Collection: "Farmacologia 2026"
  ├── farmaco-mod01-anti-hipertensivos.pdf
  ├── farmaco-mod02-anticoagulantes.pdf
  └── farmaco-mod03-analgesicos.pdf
```

**Pros**: Clean separation. Each course can have its own model configuration. Students in course A don't get results from course B.

**Cons**: More admin work. If courses share foundational content, it must be duplicated.

**How to implement**: Create separate models in Admin → Workspace → Models, each bound to its own collection.

### Option B: Single unified collection

```
Collection: "Curso de Medicina 2026"
  ├── cardio-mod01-insuficiencia-cardiaca.pdf
  ├── cardio-mod02-hipertensao-arterial.pdf
  ├── farmaco-mod01-anti-hipertensivos.pdf
  └── ... all PDFs together
```

**Pros**: Simple. Cross-module answers possible (e.g., connecting pathophysiology to pharmacology).

**Cons**: Less precise retrieval. A pharmacology question might retrieve cardiology chunks.

**When to use**: Single course with interconnected modules. Or early-stage setup when you have few PDFs.

### Option C: Cohort-based collections (future)

```
Collection: "Turma 2026.1 — Cardiologia"
Collection: "Turma 2026.2 — Cardiologia" (updated materials)
```

Use when course materials change between cohorts and you need to keep old cohorts' content stable while updating for new ones.

### Recommendation

Start with **Option A** (one collection per course). Migrate to Option C only if cohort-specific content becomes necessary. See `docs/integration.md` for the full multi-course strategy.

---

## Creating a Knowledge Collection — Step by Step

### 1. Create the collection

1. Log in as Admin.
2. Go to **Admin → Knowledge** (or **Workspace → Knowledge** depending on version).
3. Click **+ New Knowledge** (or **Add Knowledge Base**).
4. Enter a name: `Cardiologia 2026`
5. Optionally enter a description: `Módulos 1–4 do curso de cardiologia`
6. Click **Create**.

### 2. Upload PDFs

1. Open the newly created collection.
2. Click **Upload** or drag files into the upload area.
3. Select your prepared PDF files.
4. Wait for processing to complete. Open WebUI will:
   - Extract text from each PDF
   - Split text into chunks
   - Embed each chunk via OpenAI API
   - Store embeddings in the vector database
5. Processing time depends on PDF size and API speed. A 100-page PDF typically takes 30–120 seconds.

### 3. Verify upload

After processing completes:
- The collection should show the uploaded files with their names.
- If a file shows an error, check if it's a scanned PDF without a text layer.

### 4. Bind collection to model

1. Go to **Admin → Workspace → Models**.
2. Find `gpt-4o-mini` (or your configured model) and click the edit/pencil icon.
3. Under **Knowledge**, click **Add** and select your collection.
4. Under **Advanced Params**:
   - Set **Temperature**: `0.3`
5. Click **Save**.

### 5. Verify retrieval

Open a new chat and test with a question you know the PDF answers. See "Retrieval Quality Validation" below.

---

## RAG Settings Reference

Configure at **Admin → Settings → Documents**.

| Setting | Recommended value | Rationale |
|---------|-------------------|-----------|
| **Chunk Size** | 1000 (tokens) | Balances granularity with context. Too small → fragments lose meaning. Too large → retrieval is imprecise. |
| **Chunk Overlap** | 200 (tokens) | Prevents important content from being split across chunk boundaries. |
| **Top-K** | 5 | Number of chunks retrieved per query. 5 gives good recall without overwhelming the prompt. Increase to 8–10 if answers seem incomplete; decrease to 3 if answers include irrelevant content. |
| **Relevance Threshold** | 0.3 (if available) | Minimum similarity score. Chunks below this are not included. Adjust based on testing. |
| **Embedding Model** | `text-embedding-3-small` | Set via `.env`. Do not change in the UI independently. |

### When to adjust

| Symptom | Try |
|---------|-----|
| Answers miss relevant content | Increase top-k (5 → 8). Decrease chunk size (1000 → 750). |
| Answers include irrelevant content | Decrease top-k (5 → 3). Increase relevance threshold. |
| Answers truncate mid-thought | Increase chunk size (1000 → 1500). Increase overlap (200 → 300). |
| Tables/lists retrieved as fragments | Increase chunk size to keep tables in one chunk. |

---

## Managing Files in a Collection

### Adding new files

1. Open the collection.
2. Upload new files.
3. They are embedded and added to the existing collection.
4. Test retrieval for the new content.

### Removing a file

1. Open the collection.
2. Find the file and click the delete/remove icon.
3. The file and its embeddings are removed.
4. **Warning**: if students have ongoing chats that referenced this content, those older answers remain in chat history but future questions will not retrieve the removed content.

### Updating a file (new version)

There is no "replace" feature. You must:

1. Remove the old file from the collection.
2. Upload the new version.
3. Wait for re-embedding.
4. Test retrieval for changed content.

**Important**: do both steps in sequence. If you upload the new file without removing the old one, both versions will be indexed, and the bot may retrieve contradictory information.

### Bulk operations

Open WebUI does not currently support bulk delete or bulk re-upload via the UI. For large-scale content changes:

1. Delete the entire collection.
2. Create a new collection with the same name.
3. Upload all files (new versions).
4. Re-bind the collection to the model.
5. Re-test.

---

## Retrieval Quality Validation

### The 5-question test

After uploading PDFs or changing RAG settings, run this minimal validation:

| # | Test type | What to do | Pass criteria |
|---|----------|-----------|---------------|
| 1 | **Direct match** | Ask a question with the answer verbatim in a PDF | Answer matches PDF content. No fabrication. |
| 2 | **Paraphrase match** | Ask the same concept in different words | Same content retrieved; answer is substantively correct. |
| 3 | **Cross-section** | Ask something that spans two sections of the PDF | Answer combines information from both sections. |
| 4 | **Not in material** | Ask about a topic definitely NOT in the PDFs | Bot says "Não encontrei essa informação no material do curso." |
| 5 | **Near-miss** | Ask about a topic related to but not exactly in the PDFs | Bot answers what IS available and clearly indicates the gap. |

### Extraction quality check

After uploading a PDF, verify the text was extracted correctly:

1. Pick a specific passage from the PDF (a paragraph, a table, a list).
2. Ask the bot to explain or quote that specific content.
3. If the answer is garbled, has missing words, or is completely wrong → extraction failed.
4. Compare against the original PDF to check for OCR errors or layout issues.

**Common extraction problems you'll see in bot responses**:
- Merged columns: "The heartpumps blood to" (space missing between column text)
- Table data as prose: "Age Risk Factor 45+ High 30-45 Medium" (no structure)
- Header/footer noise: responses include "Page 47" or "Copyright 2026" as content
- Missing content: the bot can't find information that's clearly in the PDF (usually means it's in an image)

### Ongoing quality monitoring

Periodically review chats (Admin → Chats) for:

| Signal | What it means | Action |
|--------|---------------|--------|
| Bot says "não encontrei" for content that IS in the PDFs | Retrieval failure — embedding mismatch or chunk too small | Re-test with different phrasing; consider adjusting chunk size or top-k |
| Bot gives a correct answer but doesn't attribute to course materials | Possible parametric leakage (answering from training data) | Check if the topic is in the PDFs; if not, the system prompt grounding is being bypassed |
| Bot gives an answer with wrong details (dates, doses, names) | Extraction error or hallucination | Compare answer against source PDF; re-upload if extraction is faulty |
| Bot mixes content from different courses/modules inappropriately | Collection too broad or top-k too high | Consider splitting into per-course collections; reduce top-k |

---

## Scanned PDFs — Detailed Handling

### Detection

```bash
# Quick check with pdffonts (from poppler-utils)
pdffonts document.pdf

# If output shows fonts → text-based PDF
# If output is empty → scanned image, no text layer
```

On macOS:
```bash
brew install poppler
pdffonts document.pdf
```

On Ubuntu:
```bash
apt install poppler-utils
pdffonts document.pdf
```

### OCR workflow with ocrmypdf

```bash
# Install
pip install ocrmypdf
# or: brew install ocrmypdf (macOS)
# or: apt install ocrmypdf (Ubuntu)

# Basic OCR (Portuguese)
ocrmypdf --language por input.pdf output.pdf

# Force OCR even if text layer exists (if existing layer is bad)
ocrmypdf --language por --force-ocr input.pdf output.pdf

# Skip pages that already have text (hybrid PDFs)
ocrmypdf --language por --skip-text input.pdf output.pdf

# Optimize output file size
ocrmypdf --language por --optimize 2 input.pdf output.pdf
```

### OCR quality verification

After running OCR:
1. Open the output PDF in a reader.
2. Try to select and copy a paragraph.
3. Paste into a text editor.
4. Compare against the visible text — look for:
   - Missing characters
   - Wrong characters (0 vs O, l vs 1)
   - Merged or split words
   - Missing accents (common in Portuguese OCR)

If OCR quality is poor and the document is short, consider manual transcription to `.txt`.

---

## Grounding Strategy

The bot must answer from course PDFs, not from its parametric knowledge. This is enforced through four independent layers:

| Layer | Mechanism | Where configured | Failure mode |
|-------|-----------|-----------------|-------------|
| 1. **System prompt** | Instructs model to answer only from provided context | Admin → System Prompt | Model ignores instruction (adversarial prompting or weak phrasing) |
| 2. **Knowledge binding** | Attaches PDF collection to model for RAG retrieval | Admin → Models → Knowledge | Collection not bound, or bound to wrong model |
| 3. **Environment flags** | `ENABLE_RAG_WEB_SEARCH=false`, `ENABLE_SEARCH_QUERY=false` | `.env` | Someone changes the value |
| 4. **No tools** | No external tools enabled in Open WebUI | Admin → Tools (empty) | Someone enables a tool |

### What this does NOT guarantee

- **Parametric leakage is not fully preventable.** GPT-4o has extensive medical knowledge. Even with strong prompting, the model may "fill in" when retrieved context is partially relevant. This is a fundamental limitation of prompt-based control.
- **Chunk relevance is not perfect.** The embedding model may retrieve topically similar but factually different chunks, leading the model to synthesize incorrect answers.
- **Extraction fidelity is not guaranteed.** If the PDF parser misreads content, the bot will confidently answer with wrong information sourced from garbled text.

### Mitigation for each gap

| Gap | Mitigation |
|-----|-----------|
| Parametric leakage | Low temperature (0.3). Strong prompt wording. Periodic chat review. |
| Irrelevant chunk retrieval | Tune top-k and chunk size. Use descriptive PDF filenames. Consider per-course collections. |
| Extraction errors | Verify extraction after upload. Use text-based PDFs. OCR scanned PDFs before upload. |

---

## Hallucination Debugging

When the bot gives an answer that seems wrong:

### Step 1: Check if the content is in the PDF

Open the source PDF and search for the relevant terms. Is the information actually there?

- **Yes, it's there**: the bot retrieved and interpreted it correctly → not a hallucination
- **Yes, but different**: extraction error → re-upload or fix the PDF
- **No, it's not there**: the model answered from parametric knowledge → grounding failure

### Step 2: Check if the chunk was retrieved

Ask the same question again. Some Open WebUI versions show source documents in the response. If not:

- Rephrase the question — does the answer change significantly? If yes, retrieval is inconsistent.
- Ask a very specific question using exact terms from the PDF — if the bot now answers correctly, the original phrasing didn't match the embedding.

### Step 3: Check RAG settings

- Is the Knowledge collection actually bound to the model? (Admin → Models → Knowledge)
- Is top-k set appropriately? (too low = misses content; too high = noise)
- Was the embedding model changed since upload? (invalidates all embeddings)

### Step 4: Check the PDF itself

- Open the PDF and try to copy-paste the relevant section.
- If the pasted text is garbled → extraction problem. Re-upload or OCR.
- If the content is in an image → not extractable. Create a text supplement.

---

## Multi-Course / Multi-Cohort Strategy

### Current setup

Single model (`gpt-4o-mini`) with one or more Knowledge collections.

### Scaling to multiple courses

**Approach A: Multiple collections on one model**

Bind multiple collections to `gpt-4o-mini`. All content is searchable in one chat.

```
Model: gpt-4o-mini
  └── Knowledge: [Cardiologia 2026] + [Farmacologia 2026]
```

Pros: Simple. Students can ask cross-course questions.
Cons: Retrieval noise. Cardiology query may pull pharmacology chunks.

**Approach B: One model configuration per course**

Create named model configurations in Open WebUI, each bound to its own collection.

```
Model: "Tutor — Cardiologia"     → Knowledge: [Cardiologia 2026]
Model: "Tutor — Farmacologia"    → Knowledge: [Farmacologia 2026]
```

In Open WebUI: Admin → Workspace → Models → **Create a Model** (not the same as a connection — this is a model config/alias that wraps `gpt-4o-mini` with specific Knowledge and system prompt settings).

Pros: Clean separation. Students select the right tutor for their course.
Cons: More admin work. Students must know which model to pick.

**Recommended**: Start with Approach A. Move to Approach B when retrieval noise becomes a real problem.

### Cohort versioning

When course materials change between cohorts:

1. Create a new collection: `Cardiologia 2026.2`
2. Upload updated PDFs.
3. Bind the new collection to the model.
4. Unbind the old collection (or leave it if old cohort students still need access).
5. Optionally: create a separate model config for the new cohort.

**Do not** delete old collections while students from that cohort may still need access to their chat history and materials.

---

## Embedding Model Considerations

### Current: text-embedding-3-small

- Cost: $0.02 / 1M tokens
- Dimensions: 1536
- Quality: good for educational text retrieval
- Speed: fast

### Upgrade path: text-embedding-3-large

- Cost: $0.13 / 1M tokens (6.5x more expensive)
- Dimensions: 3072
- Quality: better for nuanced medical terminology
- When to upgrade: if retrieval quality tests consistently show that `small` misses relevant content despite tuning chunk size and top-k

### Changing the embedding model

**IMPORTANT**: Changing the embedding model invalidates ALL existing embeddings. You must:

1. Change `RAG_EMBEDDING_MODEL` in `.env`.
2. Restart the container.
3. Delete ALL Knowledge collections.
4. Re-create collections and re-upload ALL PDFs.
5. Re-bind collections to models.
6. Re-run retrieval quality tests.

This costs embedding API calls for every document. Plan accordingly.
