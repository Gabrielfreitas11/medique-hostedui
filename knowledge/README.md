# Knowledge Base — Course PDFs

PDF files are **not** stored in this git repository.
They are uploaded and managed through Open WebUI's Knowledge interface.

## How to add course PDFs

1. Log in as Admin.
2. Go to **Admin → Knowledge → New Collection** (or select existing).
3. Click **Upload** and select PDF files.
4. Wait for embedding to complete (progress shown in UI).
5. Go to **Admin → Workspace → Models → (select model) → Knowledge**.
6. Attach the collection to the model so RAG retrieval is active.

## PDF quality tips

- Use text-based PDFs, not scanned images. Scanned PDFs produce poor text extraction.
- Tables and multi-column layouts may not extract cleanly — verify with test queries.
- If a PDF is image-heavy, consider extracting text separately and uploading as a `.txt` file.
- After uploading, test retrieval by asking a question you know the PDF answers.

## Updating content

- Upload the new PDF version to the collection.
- Remove the old version to avoid duplicate or conflicting chunks.
- Re-test retrieval after updates.

## Backup

Keep original PDFs in a separate secure location (cloud storage, NAS).
The vector embeddings can be re-created by re-uploading, but this costs embedding API calls.
