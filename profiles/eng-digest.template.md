# Team Profile: Engineering (Eng)

This profile tells the Eng Daily Digest what matters to this team. Claude uses it to write the
"Eng Relevance" section for each priority repo, tailoring the analysis to your actual role
rather than generic software heuristics.

**Edit this file freely.** Copy it to `eng-digest.md` (done by setup.sh) and personalize it.

---

## Role and Responsibilities

We are the Engineering team. Day-to-day we:

- Design and implement core protocol features (consensus, block node, mirror node)
- Review and merge PRs across the hiero-ledger org
- Maintain CI/CD pipelines and testing infrastructure
- Coordinate releases and version compatibility across services
- Review and implement HIPs that require protocol changes

---

## What "Relevant" Means for Us

### High Priority - Always Surface

- **Security patches or CVE fixes** in any repo - escalate immediately regardless of component
- **Protocol-breaking changes** in consensus node or block node - affects network compatibility
- **API contract changes** in mirror node or relay - downstream consumers may break
- **Test infrastructure failures or flakiness** - blocks all PRs in the org
- **Release blockers or hotfixes** - flag with urgency and link to the issue

### Medium Priority - Worth Noting

- **Performance regressions** in consensus or relay - affects network throughput
- **Dependency upgrades** with known CVEs or breaking changes
- **New HIP implementations** that require cross-repo coordination
- **Schema migrations** in mirror node or block node - require careful deployment sequencing
- **SDK changes** that require corresponding server-side changes

### Lower Priority - Note but Don't Escalate

- Documentation-only changes
- Test additions with no behavior change
- Code style / formatting refactors
- Dependency bumps with no API or behavior change

---

## Content Opportunity Triggers

When you see activity in the digest, check: does this require...

- A **cross-team sync** (e.g., relay change that affects SDK expectations)?
- An **architecture decision record (ADR)** to document why a choice was made?
- A **runbook update** for operations?
- A **release note** for a behavior change developers or node operators will notice?

---

## Key Repos and Why They Matter

| Repo | Why We Care |
|------|-------------|
| hiero-consensus-node | Core protocol - every change is high-stakes |
| hiero-block-node | New block streaming layer - active development area |
| hiero-mirror-node | Data availability for all downstream consumers |
| hiero-json-rpc-relay | EVM gateway - affects all EVM tooling compatibility |
| hiero-sdk-js | Reference SDK implementation; tracks protocol changes |
| hiero-contracts | System contracts deployed on-network; upgrades require coordination |
| solo | Developer testing network; mirrors production behavior |

---

## Our Stakeholders

- Node operators running the network
- Exchange integrators using mirror node APIs
- SDK developers tracking protocol changes
- DA team consuming our APIs in their demos
