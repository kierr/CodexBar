---
summary: "z.ai provider: API token, quota + subscription endpoints, 3-tier limit mapping."
read_when:
  - Debugging z.ai token storage or quota parsing
  - Updating z.ai API endpoints
---

# z.ai provider

z.ai is API-token based. Fetches quota limits and subscription info in parallel.

## Token sources (fallback order)

1) Config token (`~/.codexbar/config.json` → `providers[].apiKey`).
2) Environment variable `Z_AI_API_KEY`.

### Config location
- `~/.codexbar/config.json`

## API endpoints (all use Bearer token auth)

### Quota
- `GET https://api.z.ai/api/monitor/usage/quota/limit`
- BigModel (China mainland) host: `https://open.bigmodel.cn`
- Override host via Providers → z.ai → *API region* or `Z_AI_API_HOST=open.bigmodel.cn`.
- Override the full quota URL via `Z_AI_QUOTA_URL=...`.
- Headers: `authorization: Bearer <token>`, `accept: application/json`

### Subscription
- `GET https://api.z.ai/api/biz/subscription/list`
- Returns plan name (e.g. "GLM Coding Max"), status, billing cycle, renewal dates.
- Fetched in parallel with quota on each refresh.

## Parsing + mapping

- Quota response fields:
  - `data.limits[]` → each limit entry.
  - `data.planName` (or `plan`, `plan_type`, `packageName`) → plan label.
  - `data.level` → plan tier (e.g. "max") used as fallback identity.
- Limit types (up to 3 per account, stable slot assignment):
  - `TOKENS_LIMIT` + 5-hour window → primary ("5-hour") — everyone has this.
  - `TIME_LIMIT` + monthly → secondary ("Tools") — everyone has this.
  - `TOKENS_LIMIT` + 7-day window → tertiary ("Weekly") — some accounts only.
- Identity priority: subscription.productName → planName → level.
- Window duration: unit (1=days, 3=hours, 5=minutes) + number → minutes.
- Reset: `nextResetTime` (epoch ms) → date.
- Usage details: `usageDetails[]` per model (tool usage breakdown).
- Menu bar metric: defaults to Automatic (most constrained window). Configurable in Preferences.

## Submenu display

The z.ai details submenu shows:
- **Subscription**: plan name, status, billing cycle, renewal date.
- **Tool usage**: per-tool breakdown (search-prime, web-reader, zread) + reset time.

## Known limitations

- Widget does not surface the new subscription or 3-tier data.

## Key files
- `Sources/CodexBarCore/Providers/Zai/ZaiUsageStats.swift` — models + quota parsing
- `Sources/CodexBarCore/Providers/Zai/ZaiProviderDescriptor.swift` — provider registration + fetch strategy
- `Sources/CodexBarCore/Providers/Zai/ZaiSubscriptionFetcher.swift` — subscription API
- `Sources/CodexBarCore/Providers/Zai/ZaiSettingsReader.swift` — env var + config reading
- `Sources/CodexBarCore/Providers/Zai/ZaiAPIRegion.swift` — region URLs
- `Sources/CodexBar/ZaiTokenStore.swift` — legacy migration helper
