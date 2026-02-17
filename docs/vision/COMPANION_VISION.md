# Product Vision: EchoPanel Companion

## 1. The Core Shift
Current EchoPanel is a **Review Tool** (best used after the meeting).
The new vision is a **Co-pilot Tool** (best used *during* and *collaboratively* with the meeting).

| Current State | Future State (Companion) |
| :--- | :--- |
| Landscape Window (920px+) | Adaptive Sidebar (300px - Full Screen) |
| Passive Transcription | Active Q&A ("What did actionable did Bob just say?") |
| Audio Context Only | Multi-modal Context (Audio + User Uploaded PDFs) |
| Post-Meeting Summary | Real-time Synthesis & Retrieval |

---

## 2. Feature: The "Sidebar" Experience
**User Problem**: "I need to see the meeting context alongside the Zoom/Meet window, not in a separate dashboard that covers my screen."

### UX Concept
*   **Default State:** A slim (300-400px width) vertical window pinned to the side of the screen.
*   **Adaptive Layout:**
    *   *Landscape (Current)*: 3 Columns [Transcript | Cards | Entities].
    *   *Sidebar (New)*: 1 Column with **Tabbed Views** or a **Unified Feed**.
*   **Unified Feed Approach (Recommended):**
    *   Instead of separate tabs, interleave content in a single timeline:
        *   `[09:05] Speaker A: "We need to fix the API."`
        *   `[09:05] ✨ AI Insight: Action Item detected - Fix API`
        *   `[09:06] Speaker B: "Agreed."`

### Technical Implication (SwiftUI)
*   **Refactor `SidePanelView`**: Move away from fixed `HStack`. Use `ViewThatFits` or `GeometryReader` to switch layout modes.
*   **Window Management**: Add "Always on Top" toggle. Use `NSPanel` with `.utilityWindow` style (already partially implemented) but ensure distinct "Mode Switching" UI.

---

## 3. Feature: Live Intelligence (LLM + RAG)
**User Problem**: "I want to ask questions like 'Does this align with the PDF I uploaded?' or 'Catch me up on the last 5 minutes'."

### Workflow
1.  **Context Injection (Pre-Meeting / Live)**:
    *   User drags & drops a PDF (e.g., "Project_Specs_v2.pdf") into EchoPanel.
    *   System indexes text chunks from the PDF.
2.  **Live Ingestion**:
    *   Transcript segments flow into the Context Window.
3.  **Interaction**:
    *   User types: *"Does the plan mentioned match the specs?"*
    *   LLM retrieves: Relevant chunks from "Project_Specs_v2.pdf" + Recent Transcript history.
    *   LLM answers: *"There is a conflict. The specs say 'SQL' but the speaker mentioned 'NoSQL'."*

### Architecture Requirements
*   **Vector Store**: Lightweight, local-first vector DB (e.g., `ChromaDB` or in-memory `FAISS`) to store document chunks.
*   **LLM Gateway**:
    *   *Cloud*: OpenAI/Anthropic API (Key required).
    *   *Local*: Integration with `Ollama` (Zero cost, privacy preserved, requires M-series chip).
*   **Context Manager Service**: A new Python service in `server/services/context_engine.py` to manage the "Sliding Window" of transcript + "Retrieved" static context.

---

## 4. Feature: Post-Call "Chat with Meeting"
**User Problem**: "I forgot what we decided about the budget. I don't want to read the whole transcript."

### UX Concept
*   **Chat Interface**: A standard chat UI (like ChatGPT) but scoped specifically to the meeting session.
*   **Citations**: When the LLM answers, it links to the specific timestamp in the transcript.
    *   *User*: "What was the budget?"
    *   *EchoPanel*: "$50k [Click to jump to 14:20]"

---

## 5. Development Roadmap (Phased)

### Phase 1: The UI Pivot (Sidebar)
*   [ ] Refactor `SidePanelView.swift` to support responsive layout.
*   [ ] Implement "Compact Mode" (Sidebar) with Tabbed navigation (Transcript / Highlights).

### Phase 2: The Brain (Context)
*   [ ] Build `DocumentIngestService` (Python) to parse PDFs.
*   [ ] Add "Upload" UI in Mac App.

### Phase 3: The Mouth (Chat)
*   [ ] Add `LLMService` (connect to OpenAI/Ollama).
*   [ ] Add Chat UI panel in Sidebar.
*   [ ] Implement "Chat with Transcript" logic.
