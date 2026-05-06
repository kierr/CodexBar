# Plan: Add Time-Range Selection to Subscription Utilization Chart

## Context

ZAI's "Subscription Utilization" chart shows only 1 bar (today) because:
1. ZAI was just enabled for plan utilization history — only ~1 hour of samples exist
2. The chart shows **one bar per billing period** (reset-boundary aligned). For session (5h window) that's 1 bar per 5 hours; for weekly it's 1 bar per week.
3. There is **no time-range selection** — no way to zoom to "last 24h" or "last 30 days"

**User wants:**
- **Hourly view**: Last 24 hours, one bar per hour, local timezone
- **Daily view**: Last 30 days, one bar per day, local timezone
- Past history visible immediately (not waiting weeks for bars to accumulate)

## Current Architecture (what exists)

**File:** `Sources/CodexBar/PlanUtilizationHistoryChartMenuView.swift` (799 lines)

- `seriesPoints()` (line 288): Maps entries → **period-boundary-aligned** points using `ResetBoundaryLattice`. Each bar = one billing period (5h for session, 7d for weekly).
- `Layout.maxPoints = 30`: Shows last 30 periods whatever they are.
- `makeModel()` (line 235): Calls `seriesPoints()`, truncates to 30, builds chart model.
- Series picker (line 99-114): Segmented picker to switch between session/weekly/opus series.
- **No** time-range picker exists.

**Data model is sufficient:** `PlanUtilizationHistoryEntry` has `capturedAt` (Date), `usedPercent` (Double). Entries are recorded roughly hourly (deduped to peak per hour). This gives us enough resolution for hourly/daily bucketing.

## Changes

### File: `Sources/CodexBar/PlanUtilizationHistoryChartMenuView.swift`

#### 1. Add `ChartTimeRange` enum and state

```swift
private enum ChartTimeRange: String, CaseIterable {
    case last24Hours = "24h"
    case last7Days = "7d"
    case last30Days = "30d"
}
```

Add `@State private var selectedTimeRange: ChartTimeRange = .last30Days` to the view.

#### 2. Add time-range Picker UI (alongside series picker)

Add a second segmented Picker below (or above) the existing series picker:
```
[24h] [7d] [30d]
```

#### 3. New method: `calendarTimeRangePoints()` 

When a time range is selected, bucket entries by calendar time in local timezone instead of by reset boundary:

**For `.last24Hours`:**
- Take entries where `capturedAt >= now - 24h`
- Bucket into hourly slots using `Calendar.current.startOfDay(for:) + hourOffset`
- One bar per hour (up to 24 bars)
- X-axis labels at 6h intervals or day-boundary changes

**For `.last7Days` / `.last30Days`:**
- Take entries where `capturedAt >= now - range`
- Bucket into daily slots using `Calendar.current.startOfDay(for:)`
- One bar per day (up to 7 or 30 bars)
- X-axis labels every few days, always showing last label

Each bucket keeps the **peak `usedPercent`** observed in that slot (same pattern as existing peak-per-period logic).

#### 4. Modify `makeModel()` to dispatch based on time range

```swift
if selectedTimeRange != nil {  // new mode
    points = self.calendarTimeRangePoints(history: history, range: selectedTimeRange, referenceDate: referenceDate)
} else {  // legacy period-boundary mode (default when no time range picker)
    points = self.seriesPoints(history: history, referenceDate: referenceDate)
}
```

Actually simpler: **always use calendar-time bucketing** when time-range picker is present. The period-boundary mode becomes unnecessary since calendar-time gives better granularity.

#### 5. Update axis label logic

- **24h**: Show "6am", "12pm", "6pm", "now" style labels using hour-minute format
- **7d/30d**: Keep existing "May 6" style labels (already uses `.dateTime.month(.abbreviated).day()`)

#### 6. Update detail line

For hourly view, show `"May 6, 3:05 pm: 57% used"` format (already exists via `detailDateLabel`). For daily, show same.

## Files Modified

| File | Change |
|------|--------|
| `Sources/CodexBar/PlanUtilizationHistoryChartMenuView.swift` | Add ChartTimeRange enum, time-range picker, `calendarTimeRangePoints()` method, update `makeModel()` and axis label logic |

## Verification

1. Build with clean: `CODEXBAR_FORCE_CLEAN=1 DEVELOPER_DIR=/Volumes/Applications/Xcode-26.3.0.app/Contents/Developer CODEXBAR_SIGNING=adhoc bash Scripts/package_app.sh release`
2. Kill: `bash kill_codexbar.sh`
3. Trash+copy+verify timestamp+launch
4. Open ZAI menu → Subscription Utilization:
   - Default shows **30d** tab with daily bars (1 bar so far = today, more will appear over time)
   - Switch to **24h** tab → shows hourly bars for today (bars appear as data accumulates each hour)
   - All times in **local timezone**
   - Axis labels readable, not overlapping
