# EchoPanel Documentation

> **Quick Start**: New to the project? Start with [FEATURES.md](./FEATURES.md) and [LIVE_LISTENER_SPEC.md](./LIVE_LISTENER_SPEC.md).

---

## 🔴 Critical Path Documentation

Start here for understanding the core system.

| Doc | Purpose | Read Time |
|-----|---------|-----------|
| [LIVE_LISTENER_SPEC.md](./LIVE_LISTENER_SPEC.md) | Core product spec for live listening | 15 min |
| [WS_CONTRACT.md](./WS_CONTRACT.md) | WebSocket protocol between client/server | 10 min |
| [ARCHITECTURE.md](./ARCHITECTURE.md) | High-level system architecture | 5 min |
| [DUAL_PIPELINE_ARCHITECTURE.md](./DUAL_PIPELINE_ARCHITECTURE.md) | Real-time + offline pipeline design | 20 min |
| [DATA_MODEL.md](./DATA_MODEL.md) | Core data models and relationships | 5 min |

---

## 🔧 Engineering Guides

### For Implementers

| Doc | Purpose |
|-----|---------|
| [IMPLEMENTATION_PLAN_STREAMING_FIX.md](./IMPLEMENTATION_PLAN_STREAMING_FIX.md) | Current streaming improvements |
| [FULL_PIPELINE_DATA_FLOW.md](./FULL_PIPELINE_DATA_FLOW.md) | Data flow through entire system |
| [PIPELINE_EVOLUTION_2026-02.md](./PIPELINE_EVOLUTION_2026-02.md) | Architecture evolution roadmap |
| [WS_CONTRACT.md](./WS_CONTRACT.md) | WebSocket message schemas |
| [STORAGE_AND_EXPORTS.md](./STORAGE_AND_EXPORTS.md) | Data persistence |

### For Debuggers

| Doc | Purpose |
|-----|---------|
| [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) | Common issues and fixes |
| [OBSERVABILITY.md](./OBSERVABILITY.md) | Metrics, logs, monitoring |
| [TESTING.md](./TESTING.md) | Test strategy and commands |
| [WORKLOG_TICKETS.md](./WORKLOG_TICKETS.md) | Active work log |

### For Operators

| Doc | Purpose |
|-----|---------|
| [DEPLOY_RUNBOOK_2026-02-06.md](./DEPLOY_RUNBOOK_2026-02-06.md) | Deployment procedures |
| [DISTRIBUTION_PLAN_v0.2.md](./DISTRIBUTION_PLAN_v0.2.md) | Release distribution |
| [HARDWARE_AND_PERFORMANCE.md](./HARDWARE_AND_PERFORMANCE.md) | Performance benchmarks |

---

## 📊 Audits and Analysis

**30+ technical audits** in [`docs/audit/`](./audit/):

### Most Recent & Critical
- **[Phase 0A: System Contracts](./audit/PHASE_0A_SYSTEM_CONTRACTS_AUDIT.md)** - State machines, protocol truth, race conditions
- **[Streaming Reliability](./audit/streaming-reliability-dual-pipeline-20260210.md)** - End-to-end streaming analysis
- **[UI/UX Audit](./audit/UI_UX_AUDIT_2026-02-09.md)** - Interface design review

### All Audits
See [audit/README.md](./audit/README.md) for complete index organized by:
- Priority (P0/P1/P2)
- Date
- Category

---

## 🎨 Product & Design

| Doc | Purpose |
|-----|---------|
| [FEATURES.md](./FEATURES.md) | Feature overview |
| [UI.md](./UI.md) | UI guidelines |
| [UX.md](./UX.md) | UX principles |
| [VISUAL_TESTING.md](./VISUAL_TESTING.md) | Visual regression testing |

---

## 🏗️ Architecture Decision Records

See [`docs/adr/`](./adr/) for architectural decisions:
- Why WebSocket instead of gRPC
- Why faster-whisper as default ASR
- Why dual-pipeline architecture

---

## 📋 Process & Planning

| Doc | Purpose |
|-----|---------|
| [WORKLOG_TICKETS.md](./WORKLOG_TICKETS.md) | Active and completed work |
| [DECISIONS.md](./DECISIONS.md) | Key product/technical decisions |
| [PROJECT_MANAGEMENT.md](./PROJECT_MANAGEMENT.md) | Project organization |
| [QA_CHECKLIST.md](./QA_CHECKLIST.md) | Release QA checklist |
| [CHANGELOG.md](./CHANGELOG.md) | Version history |

---

## 🔒 Security & Compliance

| Doc | Purpose |
|-----|---------|
| [SECURITY.md](./SECURITY.md) | Security practices |
| [ONBOARDING_COPY.md](./ONBOARDING_COPY.md) | Privacy messaging |
| [LICENSING.md](./LICENSING.md) | License information |

---

## 🚀 Release & GTM

| Doc | Purpose |
|-----|---------|
| [RELEASE_DISTRIBUTION.md](./RELEASE_DISTRIBUTION.md) | Release process |
| [LAUNCH_PLANNING.md](./LAUNCH_PLANNING.md) | Launch coordination |
| [GTM.md](./GTM.md) | Go-to-market strategy |
| [MARKETING.md](./MARKETING.md) | Marketing materials |
| [PRICING.md](./PRICING.md) | Pricing strategy |

---

## 🔍 Research

| Doc | Purpose |
|-----|---------|
| [ASR_MODEL_RESEARCH_2026-02.md](./ASR_MODEL_RESEARCH_2026-02.md) | ASR provider research |
| [VOXTRAL_RESEARCH_2026-02.md](./VOXTRAL_RESEARCH_2026-02.md) | Voxtral analysis |
| [VOXTRAL_LATENCY_ANALYSIS_2026-02.md](./VOXTRAL_LATENCY_ANALYSIS_2026-02.md) | Latency deep-dive |
| [RAG_PIPELINE_ARCHITECTURE.md](./RAG_PIPELINE_ARCHITECTURE.md) | RAG implementation |
| [NER_PIPELINE_ARCHITECTURE.md](./NER_PIPELINE_ARCHITECTURE.md) | NER pipeline |

---

## 📚 Reference

| Doc | Purpose |
|-----|---------|
| [GLOSSARY.md](./GLOSSARY.md) | Terminology |
| [VERSIONING.md](./VERSIONING.md) | Version scheme |
| [CLAIMS.md](./CLAIMS.md) | Feature claims validation |
| [RISK_REGISTER.md](./RISK_REGISTER.md) | Known risks |

---

## Stats

- **Total Documentation**: 50+ files
- **Audit Documents**: 30+ files
- **Lines of Docs**: 45,000+
- **Last Updated**: 2026-02-11

---

## Contributing

When adding new documentation:
1. Place audits in `docs/audit/` following naming convention
2. Update this README with link
3. Update `audit/README.md` index
4. Link from relevant implementation plans
