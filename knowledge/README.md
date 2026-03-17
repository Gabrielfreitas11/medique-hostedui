# Knowledge Base — Course PDFs

PDF files are **not** stored in this git repository.
They are uploaded and managed through Open WebUI's Knowledge interface.

Full documentation: [docs/rag-operations.md](../docs/rag-operations.md)
Checklists: [docs/checklists.md](../docs/checklists.md)

## Quick reference

### Adding a PDF

1. **Prepare**: Verify it has a text layer (can you select text?). If scanned, run OCR first.
2. **Name**: Use `[course]-[module]-[topic].pdf` format.
3. **Upload**: Admin → Knowledge → select collection → Upload.
4. **Bind**: Admin → Workspace → Models → select model → Knowledge → add collection.
5. **Test**: New chat → ask a question the PDF answers → verify accuracy.

### Updating a PDF

1. Remove the old version from the collection.
2. Upload the new version.
3. Test retrieval for changed content.

### OCR for scanned PDFs

```bash
ocrmypdf --language por input-scanned.pdf output-text.pdf
```

### Backup

Keep original PDFs in a separate secure location (cloud storage, NAS).
Embeddings can be re-created by re-uploading, but this costs API calls.

### Recommended RAG settings

| Setting | Value |
|---------|-------|
| Chunk Size | 1000 |
| Chunk Overlap | 200 |
| Top-K | 5 |
| Temperature | 0.3 |
| Embedding Model | text-embedding-3-small |
