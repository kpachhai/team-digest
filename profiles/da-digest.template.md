# Team Profile: Developer Advocacy (DA)

This profile tells the DA Daily Digest what matters to this team. Claude uses it to write the
"DA Relevance" section for each priority repo, tailoring the analysis to your actual role
rather than generic software heuristics.

**Edit this file freely.** The more specific you are, the more useful the Relevance sections become.
Copy it to `da-digest.md` (already done by setup.sh) and personalize it.

---

## Role and Responsibilities

We are the Developer Advocacy team at Hedera/Hiero. Our job is to educate and enable developers
building on the Hedera network. Day-to-day we:

- Write tutorials, demos, and code examples for developers
- Maintain and contribute to hedera-docs and developer documentation
- Build conference talks, workshops, and live demo content
- Engage with partner developers, answer technical questions, and unblock integrations
- Track ecosystem developments and translate them into developer-facing content
- Run and maintain demo repos that demonstrate Hedera features end-to-end

---

## What "Relevant" Means for Us

### High Priority - Always Surface

- **SDK breaking changes** (hiero-sdk-js, other language SDKs) - we own code examples that use
  these SDKs; breaking changes require immediate doc and example updates
- **New APIs or features in mirror node or JSON-RPC relay** - these become blog posts, tutorials,
  and demo updates; flag the specific new endpoint or capability
- **EVM compatibility changes** - we maintain Solidity examples and EVM migration content;
  any change to how the relay handles opcodes, precompiles, or gas affects our demos
- **New or approved HIPs** - we write developer implementation guides for HIPs; flag the HIP number
  and what it enables
- **Deprecations or removals in any public API or SDK** - we need to update tutorials before
  developers hit errors; flag with urgency

### Medium Priority - Worth Noting

- **Performance improvements in relay or mirror node** - faster APIs = better developer experience;
  worth a note in release announcements
- **New SDK releases** - we write release highlights and update the changelog docs
- **Partner conversations about developer friction** - informs our content roadmap; flag the
  specific friction mentioned
- **Smart contract / HTS changes** - affects our DeFi, tokenization, and NFT demo content
- **hiero-improvement-proposals activity** - early signal on what features to prep content for

### Lower Priority - Note but Don't Escalate

- Internal infrastructure refactors with no API surface change
- Test coverage improvements with no behavior change
- CI/CD pipeline changes with no developer-facing impact
- Performance work inside consensus node (not relay/mirror node)

---

## Content Opportunity Triggers

When you see activity in the digest, check: could this become...

- A **blog post** on hedera.com/blog or dev.to?
- A **tutorial or guide** update on hedera-docs?
- A **new demo repo** or code example?
- A **workshop module** or conference talk segment?
- A **social thread** (tweet, LinkedIn) about what the ecosystem is building?
- A **release highlight** that we should communicate to developers?

Flag these opportunities explicitly in the Relevance section.

---

## Our Key Repos and Why They Matter

| Repo | Why We Care |
|------|-------------|
| hedera-docs | Our primary content output - any PR here is directly relevant |
| hiero-sdk-js | JS/TS SDK used in most of our demos and tutorials |
| hiero-json-rpc-relay | EVM compat layer; changes affect all our Solidity and EVM examples |
| hiero-mirror-node | REST/GraphQL APIs we use in every indexing and explorer demo |
| hiero-improvement-proposals | Future features we need to prepare content for in advance |
| hiero-contracts | System contracts and precompiles used in our HTS/DeFi demos |
| solo | Local dev network; changes affect our developer getting-started experience |
| hedera-agent-kit-js | AI agent integration - emerging content area |
| stablecoin-studio | Token use-case demo; changes affect our tokenization content |
| asset-tokenization-studio | RWA use-case demo; we track ERC-3643 / HIP-206 changes here |

---

## Our Audience

The developers we serve are typically:
- EVM-native developers migrating from Ethereum to Hedera
- Enterprise developers building tokenization or payment solutions
- DeFi builders exploring Hedera's EVM compatibility
- Hackathon participants getting started quickly

When assessing relevance, ask: "Does this change affect what a developer building on Hedera
would experience, learn, or need to update in their code?"
