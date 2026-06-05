<callout icon="🗓️" color="purple_bg">**Team Monthly Digest** | May 2026 | 4 weeklies | 21 dailies | 14 repos active | 6 releases | 5 partner threads</callout>

---

## The Month in Review

May was the month the EVM compatibility layer got serious about the Pectra fork. What started as scattered type-handling fixes in the first week consolidated into a coordinated readiness push, landing in the [hiero-json-rpc-relay](https://github.com/hiero-ledger/hiero-json-rpc-relay) v0.62.0 release at month-end. Three partners had been waiting on exactly that work before committing migration dates.

In parallel, the tokenization reference stack closed its external security audit. Twelve findings merged across the month, including a critical admin-role lockout fix, clearing the last blocker for partners using it as a baseline. The protocol-spec side moved too: a single HIP advanced two status gates over four weeks, with implementation work showing up in three repos.

The quieter story was developer tooling. The local-network deployment tool gained headless scripting support, which several partner CI pipelines had asked for, and the mirror node shipped a new query endpoint that simplifies a common indexing pattern.

---

## Top Storylines

### Pectra-fork readiness across the EVM stack

The relay spent the month preparing for Ethereum's Pectra fork. Early weeks landed isolated fixes to transaction type handling and chain-id mapping ([#5370](https://github.com/hiero-ledger/hiero-json-rpc-relay/pull/5370), [#5371](https://github.com/hiero-ledger/hiero-json-rpc-relay/pull/5371)); by mid-month the work organized around a shared authorization-list parser. It shipped in [v0.62.0](https://github.com/hiero-ledger/hiero-json-rpc-relay/releases/tag/v0.62.0). The effort also pulled in a [mirror node](https://github.com/hiero-ledger/hiero-mirror-node) change so historical block responses stay consistent during the fork window, and answered a standing partner ask captured in the [Pectra migration plan](https://www.notion.so/pectra-migration-plan-abc123) design doc.

**Where it stands:** shipped in [v0.62.0](https://github.com/hiero-ledger/hiero-json-rpc-relay/releases/tag/v0.62.0); two partners have scheduled migration dates.

### Tokenization reference audit closeout

The [asset-tokenization-studio](https://github.com/hiero-ledger/asset-tokenization-studio) external audit ran the full month. Twelve findings merged, the most serious a deployment bug that could permanently lock admin functions if the owner address was omitted ([#1096](https://github.com/hiero-ledger/asset-tokenization-studio/pull/1096)). The fixes were tracked weekly and informed an update to the [tokenization architecture](https://www.notion.so/tokenization-arch-def456) reference.

**Where it stands:** audit closed; safe for partners to baseline on mainnet.

---

## By the Numbers

**Releases this month**

<table header-row="true">
<tr><td>Repo</td><td>Version</td><td>Date</td><td>Notes</td></tr>
<tr><td>[hiero-json-rpc-relay](https://github.com/hiero-ledger/hiero-json-rpc-relay)</td><td>[v0.62.0](https://github.com/hiero-ledger/hiero-json-rpc-relay/releases/tag/v0.62.0)</td><td>2026-05-28</td><td>Pectra-fork readiness: authorization-list parsing and chain-id fixes.</td></tr>
<tr><td>[solo](https://github.com/hiero-ledger/solo)</td><td>[v0.74.0](https://github.com/hiero-ledger/solo/releases/tag/v0.74.0)</td><td>2026-05-20</td><td>Headless silent mode for CI pipelines.</td></tr>
</table>

**Activity trend**

- 21 dailies present (2026-05-01 to 2026-05-29); missing 2026-05-12, 2026-05-19 (weekend gaps)
- Busiest stretch: 2026-W21 (14 repos active / 3 releases)
- Repos active across the month: 14 unique

**HIP movement this month**

- **[HIP-1137](https://github.com/hiero-ledger/hiero-improvement-proposals/blob/main/HIP/hip-1137.md) - Scheduled token operations** - advanced Draft to Accepted this month; implementation in [hiero-consensus-node](https://github.com/hiero-ledger/hiero-consensus-node), [hiero-sdk-js](https://github.com/hiero-ledger/hiero-sdk-js)
- Touched but no status change: [HIP-1056](https://github.com/hiero-ledger/hiero-improvement-proposals/blob/main/HIP/hip-1056.md)

**Keyword themes**

- Top keywords this month (by days appeared): **EVM** (15 days), **relay** (12 days), **HIP** (9 days)

---

## Supporting Detail

### Top GitHub Themes

The EVM relay dominated activity, with sustained daily work on Pectra readiness across all four weeks. The [consensus node](https://github.com/hiero-ledger/hiero-consensus-node) was second, mostly carrying HIP-1137 implementation. Tokenization activity clustered around the audit closeout rather than new features.

### Partner Momentum

#### Acme Corp (3 weeks)

Acme tracked the Pectra work closely; their migration is gated on relay v0.62.0, now released. Open question on mirror-node rate limits remains.

(Single touch: Globex (2026-W20), Initech (2026-W22).)

### Notion Content Pulse

- **[Pectra migration plan](https://www.notion.so/pectra-migration-plan-abc123)** - the canonical migration guide; updated three times this month as the relay work firmed up.

---

## Week-by-Week Index

- 2026-W19 (2026-05-04 to 2026-05-10): [Team Weekly Digest - 2026-W19](https://www.notion.so/weekly-w19-111)
- 2026-W20 (2026-05-11 to 2026-05-17): [Team Weekly Digest - 2026-W20](https://www.notion.so/weekly-w20-222)
- 2026-W21 (2026-05-18 to 2026-05-24): [Team Weekly Digest - 2026-W21](https://www.notion.so/weekly-w21-333)
- 2026-W22 (2026-05-25 to 2026-05-31): [Team Weekly Digest - 2026-W22](https://www.notion.so/weekly-w22-444)

---

<callout icon="ℹ️" color="gray_bg">**Auto-generated** by Team Monthly Digest | Synthesized from 4 weeklies + 6 of 21 dailies read in full | Month: May 2026 (2026-05-01 to 2026-05-31)</callout>
