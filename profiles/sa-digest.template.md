# Team Profile: team

This profile tells the Team Daily Digest what matters to this team. Claude uses it to write the
"Relevance" section for each priority repo, tailoring the analysis to your actual role
rather than generic software heuristics.

**Edit this file freely.** The more specific you are, the more useful the Relevance sections become.
Copy it to `team-digest.md` (already done by setup.sh) and personalize it.

---

## Role and Responsibilities

We are the team. Our job is to design, validate, and guide
technical solutions for developers and partners building on the Hedera network. Day-to-day we:

- Design reference architectures and integration patterns for partners and enterprise customers
- Provide technical advisory during partner onboarding - helping teams choose the right APIs,
  SDKs, and network features for their use case
- Write tutorials, demos, and code examples that demonstrate best practices
- Maintain and contribute to hedera-docs and developer documentation
- Build conference talks, workshops, and live demo content
- Evaluate new protocol features (HIPs, EVM changes, token service updates) for partner impact
- Conduct technical deep-dives with partner engineering teams to unblock integrations
- Track ecosystem developments and translate them into actionable technical guidance
- Review and recommend architecture decisions for DeFi, tokenization, NFT, and AI agent use cases
- Bridge the gap between protocol engineering and external developer experience

---

## What "Relevant" Means for Us

### High Priority - Always Surface

- **SDK breaking changes** (hiero-sdk-js, other language SDKs) - we support partners using
  these SDKs; breaking changes require immediate advisory and migration guidance
- **New APIs or features in mirror node or JSON-RPC relay** - these open new integration
  patterns; flag the specific new endpoint or capability so we can advise partners
- **EVM compatibility changes** - we maintain Solidity examples and advise on EVM migration
  strategies; any change to how the relay handles opcodes, precompiles, or gas affects our
  reference architectures and partner integrations
- **New or approved HIPs** - we evaluate HIPs for partner impact and prepare technical
  guidance; flag the HIP number and what it enables
- **Deprecations or removals in any public API or SDK** - we need to proactively notify
  partners and update integration guides before they hit errors; flag with urgency
- **Architecture changes in core services** (consensus node, block node, mirror node) -
  component splits, service restructuring, or data flow changes affect our reference
  architectures and capacity planning advice

### Medium Priority - Worth Noting

- **Performance improvements in relay or mirror node** - faster APIs improve partner
  experience; worth noting in architecture recommendations
- **New SDK releases** - we write release highlights and advise partners on upgrade timing
- **Partner conversations about developer friction** - directly informs our solution design
  and content roadmap; flag the specific friction mentioned
- **Smart contract / HTS changes** - affects our DeFi, tokenization, and NFT reference
  architectures and partner solutions
- **hiero-improvement-proposals activity** - early signal on what features to prepare
  technical guidance for
- **Security-related changes** - affects our security recommendations for partner architectures

### Lower Priority - Note but Don't Escalate

- Internal infrastructure refactors with no API surface change
- Test coverage improvements with no behavior change
- CI/CD pipeline changes with no developer-facing impact
- Performance work inside consensus node (not relay/mirror node)

---

## Content and Advisory Triggers

When you see activity in the digest, check: could this become...

- A **reference architecture** update or new design pattern?
- A **partner advisory** about migration, upgrade timing, or breaking changes?
- A **tutorial or guide** update on hedera-docs?
- A **new demo repo** or code example showing best practices?
- A **workshop module** or conference talk segment?
- A **technical blog post** on hedera.com/blog or dev.to?
- A **social thread** (tweet, LinkedIn) about what the ecosystem is building?
- A **release highlight** that we should communicate to developers and partners?
- An **integration pattern** that simplifies a common partner use case?

Flag these opportunities explicitly in the Relevance section.

---

## Our Key Repos and Why They Matter

| Repo | Why We Care |
|------|-------------|
| hedera-docs | Our primary content output - any PR here is directly relevant |
| hiero-sdk-js | JS/TS SDK used in most of our demos, tutorials, and partner integrations |
| hiero-json-rpc-relay | EVM compat layer; changes affect all Solidity/EVM reference architectures |
| hiero-mirror-node | REST/GraphQL APIs used in every indexing, explorer, and analytics integration |
| hiero-consensus-node | Core protocol; architecture changes affect capacity planning and network behavior advice |
| hiero-block-node | Block streaming; relevant for partners building indexers and analytics tools |
| hiero-improvement-proposals | Future features we need to evaluate for partner impact in advance |
| hiero-contracts | System contracts and precompiles used in HTS/DeFi reference architectures |
| solo | Local dev network; changes affect developer getting-started experience |
| hedera-agent-kit-js | AI agent integration - emerging area for partner solutions |
| stablecoin-studio | Token use-case reference; changes affect tokenization guidance |
| asset-tokenization-studio | RWA use-case reference; we track ERC-3643 / HIP-206 changes here |

---

## Our Audience

The developers and partners we serve are typically:
- EVM-native developers migrating from Ethereum to Hedera
- Enterprise architects designing tokenization, payment, or supply chain solutions
- DeFi builders exploring Hedera's EVM compatibility and native token service
- Partner engineering teams integrating Hedera into existing platforms
- Hackathon participants getting started quickly
- AI/ML teams exploring on-chain agent capabilities

When assessing relevance, ask: "Does this change affect how a developer or partner would
design, build, integrate, or operate a solution on Hedera?"
