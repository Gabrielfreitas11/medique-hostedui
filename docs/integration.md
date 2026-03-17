# Integration Strategy

How to integrate the medique chatbot into a course website so students access it as part of their learning experience.

---

## Integration Options — Overview

| Option | How students access | Complexity | Best for |
|--------|-------------------|------------|----------|
| **A. Direct link** | Click a link on the course site → opens Open WebUI in a new tab | Lowest | MVP / pilot |
| **B. Iframe embed** | Chatbot appears embedded inside a course page | Medium | Seamless UX |
| **C. Subdomain** | `tutor.yourdomain.com` with course site linking to it | Medium | Clean separation |
| **D. API proxy** | Custom frontend consumes Open WebUI's API | Highest | Full UI control (future) |

This document focuses on **A and B** — the two realistic options for this project. C is a variant of A with DNS. D requires custom development and is out of scope.

---

## Option A: Direct Link (Simplest — MVP)

### How it works

```
Course website                    Open WebUI
┌─────────────────┐              ┌──────────────────┐
│                 │   click      │                  │
│  "Abrir Tutor"  │─────────────→│  Login page      │
│   [button/link] │   new tab    │  → Chat UI       │
│                 │              │                  │
└─────────────────┘              └──────────────────┘
```

The course website has a button or link that opens `https://tutor.yourdomain.com` (or `https://yourdomain.com:443`) in a new browser tab. Students log in with credentials the admin created for them.

### Setup

1. Deploy Open WebUI in production (docs/deployment.md).
2. Create student accounts (Admin → Users).
3. Add a link/button to your course website:

```html
<a href="https://tutor.yourdomain.com" target="_blank" rel="noopener">
  Abrir Tutor do Curso
</a>
```

4. Share login credentials with students (email, course platform message, etc.).

### Pros

- Zero integration code.
- Open WebUI handles all auth, sessions, and UI.
- Works with any course platform (Hotmart, Kiwify, Teachable, WordPress, custom).
- Admin UI is fully separate from student experience.

### Cons

- Students see the full Open WebUI interface (sidebar, model selector, settings).
- Separate login — students must remember another set of credentials.
- No visual integration with the course site.
- Students could explore settings and model options (though they can't change admin settings).

### Mitigation: reduce UI clutter for students

Open WebUI's `User` role (not Admin) already hides admin panels. Students see:
- Chat interface
- Chat history sidebar
- Model selector (if multiple models are visible)

To reduce further:
- Set `DEFAULT_MODELS=gpt-4o-mini` so the model is pre-selected.
- If Open WebUI supports a "default user interface" mode in your version, enable it.
- Use `WEBUI_NAME` to brand the UI (e.g., `Medique - Tutor de Cardiologia`).

---

## Option B: Iframe Embed (Recommended)

### How it works

```
Course website page
┌──────────────────────────────────────┐
│  Módulo 3 — Arritmias Cardíacas     │
│                                      │
│  [Course content above]              │
│                                      │
│  ┌──────────────────────────────┐    │
│  │  ┌── Open WebUI (iframe) ──┐│    │
│  │  │                         ││    │
│  │  │   Chat interface        ││    │
│  │  │                         ││    │
│  │  └─────────────────────────┘│    │
│  └──────────────────────────────┘    │
└──────────────────────────────────────┘
```

Open WebUI is loaded inside an `<iframe>` on the course page. Students interact with the chatbot without leaving the course site.

### Setup

**Step 1 — Change Nginx X-Frame-Options**

The current Nginx config sets `X-Frame-Options: SAMEORIGIN`, which blocks iframes from other domains. You need to change this.

In `reverse-proxy/nginx.conf`, replace:

```nginx
add_header X-Frame-Options "SAMEORIGIN" always;
```

With one of these options:

```nginx
# Option 1: Allow only your course site domain (most secure)
add_header Content-Security-Policy "frame-ancestors 'self' https://yourcoursedomain.com" always;
# Remove the X-Frame-Options line — CSP frame-ancestors supersedes it

# Option 2: Allow any site to embed (less secure — use only for testing)
# Remove the X-Frame-Options line entirely
```

**Step 2 — Configure SameSite cookies**

For the iframe login to work across domains, Open WebUI's session cookies need `SameSite=None; Secure`. Check if Open WebUI supports configuring this via environment variables in your version. If not, the student must log in to Open WebUI directly first (in a new tab), and the session cookie will then work in the iframe within the same browser.

> **Note**: Cross-domain iframe authentication is a known pain point. If cookies don't work across domains, fall back to Option A (direct link) or host both the course site and Open WebUI on the same parent domain (e.g., `www.yourdomain.com` for the course and `tutor.yourdomain.com` for the chatbot).

**Step 3 — Add the iframe to your course page**

```html
<iframe
  src="https://tutor.yourdomain.com"
  width="100%"
  height="700"
  style="border: 1px solid #e0e0e0; border-radius: 8px;"
  allow="clipboard-write"
  loading="lazy"
  title="Tutor Educacional">
</iframe>
```

**Step 4 — Responsive version**

```html
<div style="position: relative; width: 100%; padding-bottom: 80%; min-height: 500px;">
  <iframe
    src="https://tutor.yourdomain.com"
    style="position: absolute; top: 0; left: 0; width: 100%; height: 100%; border: 1px solid #e0e0e0; border-radius: 8px;"
    allow="clipboard-write"
    loading="lazy"
    title="Tutor Educacional">
  </iframe>
</div>
```

### Pros

- Students stay on the course page.
- Feels like a native feature of the course platform.
- Admin UI is hidden (students never navigate directly to Open WebUI).

### Cons

- Cross-domain cookie issues may complicate authentication.
- Requires Nginx config change (X-Frame-Options).
- Iframe may not look perfect on all screen sizes.
- Some course platforms restrict custom HTML/iframes.

---

## Authentication Options

### What Open WebUI supports natively

| Method | How it works | Setup effort |
|--------|-------------|-------------|
| **Built-in email/password** | Admin creates accounts manually in the UI | Lowest — already set up |
| **OAuth/OIDC** | Delegate login to an external identity provider (Google, GitHub, custom) | Medium — requires OIDC provider |
| **LDAP** | Enterprise directory integration | High — requires LDAP server |

### Recommendation by scenario

| Scenario | Auth method | Why |
|----------|------------|-----|
| Small class (< 50 students) | Built-in email/password | Simple. Admin creates accounts. No integration needed. |
| Medium class (50–200) or multiple courses | OAuth/OIDC via Google | Students log in with Google accounts. No manual account creation. |
| Course platform has its own auth (Hotmart, Kiwify) | Built-in + manual provisioning | These platforms don't expose OIDC. Create accounts manually or with a script. |
| Enterprise / university | LDAP or institutional OIDC | Integrate with existing identity management. |

### OAuth/OIDC setup (optional — label: integration path)

If your course platform or identity provider supports OIDC, Open WebUI can consume it. The relevant environment variables (check your Open WebUI version for exact names):

```bash
# Example — Google OIDC (check Open WebUI docs for current variable names)
OAUTH_CLIENT_ID=your-google-client-id
OAUTH_CLIENT_SECRET=your-google-client-secret
OAUTH_PROVIDER_URL=https://accounts.google.com/.well-known/openid-configuration
ENABLE_OAUTH_SIGNUP=true   # auto-create accounts on first login
```

> **Important**: If you enable OAuth signup, any person with a valid Google account can create an account. You would need to restrict by email domain (e.g., `@yourschool.edu`) or disable auto-signup and pre-create accounts using the OAuth email.

### SSO with Hotmart/Kiwify (optional — label: future integration path)

These platforms do not expose standard OIDC endpoints. Integration options:

1. **Webhook on purchase**: Hotmart/Kiwify sends a webhook when a student buys the course → your server creates an Open WebUI account via Open WebUI's API → sends credentials to the student.
2. **Manual provisioning**: Admin creates accounts for enrolled students. Simple, but doesn't scale.
3. **Custom middleware**: Build a thin auth proxy that validates Hotmart/Kiwify session tokens and creates/logs in Open WebUI users. Requires custom development.

None of these are implemented in this project. They require application code outside the scope of "configure and deploy Open WebUI."

---

## Per-Course Segregation

### The problem

If you have multiple courses (e.g., Cardiologia, Farmacologia, Pediatria), students in one course should not get answers from another course's PDFs.

### Strategy: one model configuration per course

Open WebUI allows creating **model configurations** — aliases that wrap a base model (e.g., `gpt-4o-mini`) with specific Knowledge collections, system prompts, and parameters.

```
Model Config: "Tutor — Cardiologia"
  ├── Base model: gpt-4o-mini
  ├── Knowledge: [Cardiologia 2026] collection
  ├── System prompt: medical-tutor.md (same for all courses)
  └── Temperature: 0.3

Model Config: "Tutor — Farmacologia"
  ├── Base model: gpt-4o-mini
  ├── Knowledge: [Farmacologia 2026] collection
  ├── System prompt: medical-tutor.md
  └── Temperature: 0.3
```

**How to create**: Admin → Workspace → Models → Create a Model.

### How students select the right course

| Approach | How | Pros | Cons |
|----------|-----|------|------|
| **Students pick the model** | Model selector dropdown in chat | Zero config | Students might pick the wrong one |
| **Default model per link** | Use URL parameter if Open WebUI supports it (check version) | Seamless | Depends on URL parameter support |
| **One instance per course** | Deploy separate Open WebUI containers, each with one course | Full isolation | More infra, more cost, more admin |
| **Hide non-relevant models** | Open WebUI may support role-based model visibility (check version) | Clean UX | Depends on RBAC features |

### Recommendation

**Start with one shared instance + named model configs.** Use descriptive names like "Tutor — Cardiologia 2026" so students can identify the right one. This works for 2–5 courses.

If you need strict isolation (students must not even see other courses), deploy separate instances.

### Knowledge base structure by course

```
Knowledge Collections:
├── "Cardiologia 2026"
│   ├── cardio-mod01-insuficiencia-cardiaca.pdf
│   ├── cardio-mod02-hipertensao-arterial.pdf
│   └── cardio-mod03-arritmias.pdf
│
├── "Farmacologia 2026"
│   ├── farmaco-mod01-anti-hipertensivos.pdf
│   └── farmaco-mod02-anticoagulantes.pdf
│
└── "Pediatria 2026"
    ├── pedi-mod01-crescimento-desenvolvimento.pdf
    └── pedi-mod02-imunizacao.pdf

Model Configurations:
├── "Tutor — Cardiologia"     → bound to "Cardiologia 2026"
├── "Tutor — Farmacologia"    → bound to "Farmacologia 2026"
└── "Tutor — Pediatria"       → bound to "Pediatria 2026"
```

### Preventing students from accessing wrong materials

| Control | How | Strength |
|---------|-----|----------|
| Separate Knowledge collections | Each collection has only one course's PDFs | Strong — RAG only searches the bound collection |
| Named model configs | Each model config is bound to one collection | Strong — correct binding means correct retrieval |
| Student guidance | Clear labels ("Tutor — Cardiologia") + onboarding instructions | Moderate — depends on student compliance |
| Separate instances (if needed) | Each course gets its own Open WebUI deployment | Strongest — complete isolation |

**What you cannot prevent**: If multiple collections are bound to the same model config, RAG will search all of them. The solution is one collection per model config.

---

## Access Control

### What students CAN do (User role)

- Chat with available models
- View their own chat history
- Change their own password
- Select models from the model dropdown

### What students CANNOT do (User role)

- Access Admin panels
- Create/delete Knowledge collections
- Change system prompts
- Modify RAG settings
- Create other user accounts
- Enable tools, functions, or web search
- See other students' chats

### Residual exposure — what students CAN see

Even with the `User` role, students see the full Open WebUI chat interface. This means:

| What they see | Risk | Mitigation |
|---------------|------|-----------|
| Model selector dropdown | Might pick wrong model or try `gpt-4o` | Set `DEFAULT_MODELS` to pre-select; limit visible models if possible |
| Chat settings (temperature, etc.) per conversation | Could increase temperature, weakening grounding | Per-chat settings do NOT override model defaults for Knowledge binding; only affects generation params |
| Sidebar with chat history | Privacy — no risk (they see only their own) | None needed |
| "New Chat" button | Could start chats without Knowledge context if they select the base model instead of the model config | Name model configs clearly; set default model to the configured one |

### Hiding the admin UI from students

The Admin UI is only visible to users with the `Admin` role. Students with the `User` role never see:
- Admin → Settings
- Admin → Users
- Admin → Knowledge (management)
- Admin → Workspace

**Risk**: if a student somehow obtains admin credentials, they can change all settings. Mitigation:
- Use a strong, unique admin password.
- Never share admin credentials with students.
- Regularly check Admin → Users for unexpected admin accounts.

---

## Session and Privacy

### Session behavior

- Open WebUI uses JWT tokens for sessions.
- Session duration depends on `WEBUI_SECRET_KEY` — rotating the secret logs everyone out.
- Chat history is stored server-side in the database, tied to the user's account.

### Privacy considerations

| Data | Where stored | Who can see | Retention |
|------|-------------|------------|-----------|
| Chat messages | PostgreSQL (prod) / SQLite (dev) | The student + admin (via Admin → Chats) | Until deleted |
| User accounts (email, name) | Database | Admin only | Until account deleted |
| PDF content (embeddings) | Vector database | Returned to any user who queries the bound model | Until collection deleted |
| API requests | OpenAI servers (external) | OpenAI (subject to their data policy) | Per OpenAI data usage policy |

### LGPD considerations (Brazil)

If operating in Brazil, consider:

1. **Inform students** that their chat messages are stored and that queries are sent to OpenAI.
2. **Provide a way to delete chat history** — admin can delete individual chats or entire user accounts.
3. **Data processing agreement** with OpenAI — review their enterprise data processing terms.
4. **Minimize PII** — the system prompt already tells students not to share personal health info.
5. **Retention policy** — define how long chat history is kept; implement periodic deletion if required.

> This is not legal advice. Consult a lawyer for LGPD compliance specific to your situation.

---

## Branding and Customization

### What you can customize

| Element | How | Scope |
|---------|-----|-------|
| Application name | `WEBUI_NAME` env var | Appears in browser tab and header |
| Default model | `DEFAULT_MODELS` env var | Pre-selects model for new chats |
| System prompt | Admin UI → System Prompt | Controls bot personality and rules |
| Model config names | Admin → Models → Create a Model | Labels students see in the dropdown |

### What you CANNOT customize without custom code

| Element | Why |
|---------|-----|
| Login page appearance | Open WebUI's login page is not themeable via config |
| Chat UI layout, colors, fonts | Built into Open WebUI's frontend |
| Sidebar contents | Controlled by Open WebUI, not configurable |
| Welcome/onboarding message | Some versions support a "system banner" — check your version |
| Custom CSS injection | Not supported via env vars; would require forking Open WebUI |

### Branding recommendation

Set `WEBUI_NAME` to something students recognize:

```bash
# .env
WEBUI_NAME=Medique - Tutor de Cardiologia 2026
```

If running multiple courses, each instance (or model config) should have a clear name that matches the course.

---

## Risks of Exposing the Platform

### Risk matrix for public exposure

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Students explore UI settings (harmless) | High | None | `User` role limits what they can change |
| Students select wrong model | Medium | Low (wrong Knowledge base) | Use DEFAULT_MODELS; name model configs clearly |
| Students share login credentials | Medium | Low (educational content only) | Monitor active sessions; unique passwords |
| Someone finds the URL and probes it | Medium | Low–Medium | Auth required; rate limiting; no sensitive data exposed |
| Prompt injection / jailbreak attempts | Medium | Medium | System prompt + 4-layer grounding (see grounding-strategy.md) |
| DDoS on public endpoint | Low | Medium | Nginx rate limiting + cloud firewall |
| Admin credentials compromised | Low | High | Strong password; MFA if available; limit admin accounts |

### How to limit exposure

1. **Don't publicize the URL.** Share it only through the course platform, not on public pages.
2. **Disable signup** (`ENABLE_SIGNUP=false`). Only admin-created accounts can access.
3. **Rate limit** via Nginx (already configured: 10 req/s per IP).
4. **Monitor** active users: Admin → Users periodically.
5. **Review chats** periodically for abuse: Admin → Chats.

---

## Staged Rollout Plan

### Stage 1: Internal / Admin Only

**Duration**: 1–2 weeks.
**Audience**: Only the course admin/instructor.

| # | Task | Status |
|---|------|--------|
| 1 | Deploy Open WebUI (dev or prod) | ☐ |
| 2 | Create admin account | ☐ |
| 3 | Paste system prompt | ☐ |
| 4 | Upload course PDFs to Knowledge collection | ☐ |
| 5 | Bind collection to model | ☐ |
| 6 | Configure RAG settings (chunk 1000, overlap 200, top-k 5) | ☐ |
| 7 | Set temperature to 0.3 | ☐ |
| 8 | Disable signup | ☐ |
| 9 | Run admin restriction checklist (docs/grounding-strategy.md) | ☐ |
| 10 | Run full test matrix (docs/bot-behavior/test-matrix.md) | ☐ |
| 11 | Run grounding acceptance tests (docs/grounding-strategy.md) | ☐ |
| 12 | Test backup and restore (docs/runbook.md § 5–6) | ☐ |
| 13 | Set OpenAI spending limit | ☐ |

**Exit criteria**: All tests pass. Backup/restore verified. Admin is comfortable with the platform.

### Stage 2: Limited Student Pilot

**Duration**: 2–4 weeks.
**Audience**: 3–5 trusted students (TAs, monitor students, or volunteers).

| # | Task | Status |
|---|------|--------|
| 1 | Create pilot student accounts (role: User) | ☐ |
| 2 | Share access link and login credentials with pilot students | ☐ |
| 3 | Provide brief usage instructions (what to ask, what not to ask) | ☐ |
| 4 | Ask pilot students to test specific scenarios: | |
| | — Ask a question the PDF answers | ☐ |
| | — Ask a question NOT in the PDFs | ☐ |
| | — Ask something ambiguous / partially covered | ☐ |
| | — Try to get a diagnosis (should be refused) | ☐ |
| 5 | Collect pilot feedback: | |
| | — Was the answer helpful? | ☐ |
| | — Was the answer accurate? | ☐ |
| | — Was anything confusing about the UI? | ☐ |
| | — Did the bot ever answer something it shouldn't have? | ☐ |
| 6 | Review chat logs for pilot students (Admin → Chats) | ☐ |
| 7 | Fix any issues found (system prompt, RAG settings, PDFs) | ☐ |
| 8 | Re-run minimum regression tests after any fix | ☐ |
| 9 | Monitor OpenAI costs during pilot period | ☐ |

**Exit criteria**: Pilot students report positive experience. No grounding failures. No diagnosis outputs. Costs are within budget.

### Stage 3: Production Rollout

**Duration**: Ongoing.
**Audience**: All enrolled students.

| # | Task | Status |
|---|------|--------|
| 1 | Deploy in production if still on dev (docs/deployment.md) | ☐ |
| 2 | Pin Open WebUI to a specific version tag | ☐ |
| 3 | Set up automated daily backups (cron) | ☐ |
| 4 | Create all student accounts | ☐ |
| 5 | Add chatbot link/iframe to the course website | ☐ |
| 6 | Send students access instructions + brief usage guide | ☐ |
| 7 | Include disclaimer: "Este é um tutor educacional, não um médico" | ☐ |
| 8 | Set up health check monitoring (docs/runbook.md § 12) | ☐ |
| 9 | Schedule weekly chat log reviews | ☐ |
| 10 | Schedule monthly retrieval quality checks | ☐ |
| 11 | Document the rollback plan if issues arise | ☐ |

**Ongoing operations**: Follow docs/runbook.md for all procedures.

---

## Shared Bot vs. One Bot Per Course

### Decision framework

| Factor | Shared bot (one instance, multiple model configs) | Separate bots (one instance per course) |
|--------|--------------------------------------------------|----------------------------------------|
| **Setup effort** | Low — one deployment, model configs in UI | High — multiple Docker Compose deployments |
| **Admin overhead** | Low — one place to manage | High — duplicate settings across instances |
| **Cost** | Lower — one PostgreSQL, one server | Higher — more containers, more resources |
| **Student isolation** | Moderate — students see all model configs but each searches its own collection | Strong — students only see their course's bot |
| **Cross-course queries** | Possible if student picks wrong model | Impossible |
| **Scaling** | Good to 5–10 courses | Better for 10+ courses or strict isolation |

### Recommendation

**Use a shared instance with named model configs until you have a concrete reason not to.**

Switch to separate instances when:
- You have 10+ courses and the model selector is unwieldy.
- Different courses need different system prompts or embedding models.
- Strict regulatory or organizational isolation is required.
- Different courses have different admin teams who shouldn't see each other's settings.

---

## Knowledge Base Structure — Recommendation

### For one course

```
Collection: "Cardiologia 2026"
  └── All PDFs for this course

Model Config: "Tutor — Cardiologia"
  └── Bound to "Cardiologia 2026"
```

### For multiple courses (shared instance)

```
Collections:
├── "Cardiologia 2026"       → bound to "Tutor — Cardiologia"
├── "Farmacologia 2026"      → bound to "Tutor — Farmacologia"
└── "Pediatria 2026"         → bound to "Tutor — Pediatria"
```

**Rule**: one collection per course, one model config per collection. Never bind multiple course collections to the same model config.

### For course cohorts (material changes between terms)

```
Collections:
├── "Cardiologia 2026.1"     → bound to "Tutor — Cardio (Turma 2026.1)"
├── "Cardiologia 2026.2"     → bound to "Tutor — Cardio (Turma 2026.2)" (updated PDFs)
```

Old cohort students keep access to their version. New cohort gets the updated model config.

### For shared foundational + course-specific content

```
Collections:
├── "Fundamentos Médicos"    → shared material (anatomy, physiology)
├── "Cardiologia 2026"       → course-specific material

Model Config: "Tutor — Cardiologia"
  └── Bound to BOTH "Fundamentos Médicos" + "Cardiologia 2026"
```

Use only if cross-collection retrieval doesn't cause noise. Test before committing.

---

## Summary

### Recommended integration approach

**Iframe embed** (Option B) with:
- Open WebUI on a subdomain (`tutor.yourdomain.com`)
- Nginx `Content-Security-Policy: frame-ancestors` set to your course domain
- Built-in email/password auth (admin creates accounts)
- Named model configs per course (one collection per config)
- `DEFAULT_MODELS` set to the primary course model
- `WEBUI_NAME` branded with the course name

This gives students a seamless experience embedded in the course page without requiring custom application code.

### Simplest MVP approach

**Direct link** (Option A):
1. Deploy Open WebUI.
2. Create student accounts.
3. Add a link to your course website: `<a href="https://tutor.yourdomain.com" target="_blank">Abrir Tutor</a>`
4. Share login credentials.

Total integration effort: one HTML link. Everything else is Open WebUI configuration.

### Safest rollout plan

1. **Stage 1** (1–2 weeks): Admin-only testing. Upload PDFs, run all checklists, verify grounding.
2. **Stage 2** (2–4 weeks): 3–5 pilot students. Collect feedback. Fix issues. Review chat logs.
3. **Stage 3**: Full rollout. Automated backups. Monitoring schedule. Weekly log reviews.

Never skip Stage 1. Stage 2 can be shortened to 1 week if Stage 1 is thorough. Stage 3 is indefinite — the bot is now part of the course.
