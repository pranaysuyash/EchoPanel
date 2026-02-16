# EchoPanel Screen Capture (OCR) User Guide

**Version:** 1.0  
**Last Updated:** 2026-02-14  
**Feature:** Screen Content Capture & OCR

---

## What is Screen Capture?

EchoPanel can capture text from your screen during meetings - presentation slides, documents, web pages - and make it searchable alongside your meeting transcript.

**Example:**
```
Alice says: "As shown on the slide..."

EchoPanel captures the slide:
"Q3 2026 Financial Results
Revenue: $5.2M (+23% YoY)"

Later you search: "What was Q3 revenue?"
EchoPanel answers: "$5.2M" (from the slide)
```

---

## Getting Started

### 1. Enable Screen Capture

1. Open **EchoPanel Settings** (Cmd + ,)
2. Go to **Screen Capture** tab
3. Toggle **Enable Screen Content Capture**
4. Select capture interval (30 seconds recommended)

### 2. Grant Permissions

When prompted, grant **Screen Recording** permission:
- System Preferences → Security & Privacy → Screen Recording
- Check "EchoPanel"
- Restart EchoPanel

### 3. Start a Meeting

Screen capture runs automatically during recording when enabled.

---

## Settings Explained

### Capture Interval

| Interval | Best For | Note |
|----------|----------|------|
| 10 seconds | Rapid slide decks | Higher bandwidth |
| **30 seconds** | **Most presentations** | **Recommended** |
| 1 minute | Slow-paced reviews | Lower bandwidth |
| 5 minutes | Long documents | May miss slides |

### Menu Bar Indicator

When enabled, shows a small camera icon in your menu bar during capture:
- 📷 Solid = Capture active
- 📷 Dimmed = Waiting for next interval
- No icon = Capture disabled

---

## Privacy & Security

### What We Capture
- ✅ Text from slides and documents
- ✅ Charts and tables (as text)
- ✅ URLs and code snippets

### What We Don't Capture
- ❌ Full resolution images (only text)
- ❌ Video content
- ❌ Content when disabled
- ❌ Content outside meetings

### How It Works
1. **Capture:** Frame grabbed every N seconds
2. **Process:** OCR extracts text locally
3. **Store:** Text indexed to your session
4. **Discard:** Original image deleted immediately

### Your Control
- **Opt-in:** Disabled by default
- **Per-session:** Can disable anytime
- **Delete:** Session content deleted when you delete the recording

---

## Using Captured Content

### Search
Search your meeting history includes slide content:
```
Search: "revenue forecast"
Results:
- Transcript: "Alice: The revenue forecast..."
- Slide: "2026 Revenue Forecast: $25M"
```

### Export
Exported transcripts include slide references:
```markdown
## Meeting: Q3 Review

### Slide Capture [10:15 AM]
Q3 2026 Financial Results
Revenue: $5.2M (+23% YoY)
New Customers: 1,240

### Transcript
[10:15] Alice: As you can see, revenue is up 23%
```

---

## Troubleshooting

### "Screen Capture Not Available"

**Cause:** Permission not granted

**Fix:**
1. System Preferences → Security & Privacy → Screen Recording
2. Remove EchoPanel, then add it back
3. Restart EchoPanel

### "OCR Disabled" Warning

**Cause:** Feature turned off or Tesseract not installed

**Fix:**
- Check Settings → Screen Capture → Enable
- Or reinstall EchoPanel (includes Tesseract)

### High CPU Usage

**Cause:** Too frequent captures

**Fix:**
- Increase interval (60 seconds or more)
- Disable for long meetings without slides

### Missed Slides

**Cause:** Slide changed between capture intervals

**Fix:**
- Decrease interval to 10 seconds
- Or manually capture with "Capture Now" button

---

## Tips for Best Results

### For Presenters
- **Pause** on key slides (2+ seconds)
- Use **large fonts** (18pt minimum)
- **High contrast** (dark text on light background)
- Avoid **busy backgrounds**

### For Attendees
- **Enable before** the meeting starts
- Keep slides **full screen** (not windowed)
- **Don't obscure** content with other windows

---

## FAQ

**Q: Does this work with video calls?**
A: Yes - captures your screen, not the call itself.

**Q: Can I capture just one window?**
A: Not yet - currently captures the entire screen.

**Q: Does it work with handwritten notes?**
A: Limited support - typed text works best.

**Q: Is content shared with anyone?**
A: No - all processing is local to your machine.

**Q: How much storage does this use?**
A: Very little - only text (~1KB per slide) is stored.

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| Cmd + Shift + O | Toggle screen capture |
| Cmd + Shift + C | Capture frame now |

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-14 | Initial release |

---

*For technical details, see: `docs/OCR_PIPELINE_TECHNICAL_SPEC.md`*
