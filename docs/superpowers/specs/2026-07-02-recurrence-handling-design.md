# Recurrence Handling — Design Spec

**Date:** 2026-07-02  
**Status:** Approved  

---

## Context

Eventide is a Flutter plugin that bridges iOS and Android native calendars. Recurring events are listed as a planned feature in the README (`💡 Recurring events`) but no recurrence code exists anywhere in the codebase today.

This spec covers full recurrence support: creating recurring events, retrieving expanded instances, and deleting/updating individual instances or entire series.

---

## Goals

- Allow developers to create events with an RFC 5545 recurrence rule
- `retrieveEvents` returns expanded instances within the queried date range
- `deleteEvent` and `updateEvent` support three scopes: this instance, this and future, all events
- No new required dependencies on Eventide consumers — developers bring their own RRULE builder (e.g. the `rrule` pub package)

---

## Non-Goals

- Parsing or validating RRULE strings on the Dart side
- Providing a built-in RRULE builder
- Supporting exotic RFC 5545 properties not handled by EventKit (BYYEARDAY, BYWEEKNO, BYSETPOS)

---

## RFC 5545 Compliance Notes

The design passes RRULE values as opaque strings through the Dart/Pigeon layer. Compliance responsibilities are split:

| Concern | Status | Notes |
|---------|--------|-------|
| RRULE value format (no `RRULE:` prefix on wire) | Covered | Consistent with Android `CalendarContract.Events.RRULE` and iOS parsing |
| FREQ, INTERVAL, BYDAY, BYMONTHDAY, BYMONTH, COUNT, UNTIL | Covered | Supported on both platforms |
| BYYEARDAY, BYWEEKNO, BYSETPOS | Not supported | EventKit limitation; silently dropped on iOS, documented |
| WKST (week start day) | Not handled | Defaults to Monday per RFC 5545; acceptable for most use cases |
| COUNT + UNTIL mutual exclusivity | Not validated | Malformed RRULE passed through silently; caller's responsibility |
| UNTIL date serialization format | Implementation note | When patching RRULE for `thisAndFuture` on Android, `UNTIL` must be formatted as a UTC datetime string (`YYYYMMDDTHHMMSSZ`), not an epoch integer. The iOS `RRuleParser` must also handle both DATE (`YYYYMMDD`) and DATETIME (`YYYYMMDDTHHMMSSZ`) formats for UNTIL. |
| EXDATE in ICS generation | Known gap | `createEventInDefaultCalendar` / `createEventThroughNativePlatform` do not produce `EXDATE` lines for deleted instances. Acceptable since these are creation-only paths. |
| RECURRENCE-ID in ICS | Known gap | ICS generation does not produce `RECURRENCE-ID` for modified instances. Not relevant for the direct native API path. |

---

## Section 1: Dart API

### New type: `ETSpan`

```dart
enum ETSpan { thisEvent, thisAndFuture, allEvents }
```

Used on `deleteEvent` and `updateEvent` to specify the scope of the operation when acting on a recurring event instance.

### `ETEvent` — two new fields

```dart
final class ETEvent {
  // ... existing fields unchanged ...
  final String? recurrenceRule;        // RFC 5545 RRULE value, e.g. "FREQ=WEEKLY;BYDAY=MO,WE"
  final DateTime? originalInstanceTime; // populated for recurring instances only;
                                        // equals the scheduled start of this occurrence
                                        // as defined by the recurrence rule
}
```

`originalInstanceTime` is what makes a specific instance uniquely addressable across platforms. All instances of the same series share the same `id` (the master event ID); `originalInstanceTime` distinguishes them. For non-recurring events, `originalInstanceTime` is `null`.

Example — a weekly standup every Monday at 9am:

| Instance | `id`     | `startDate`    | `originalInstanceTime` |
|----------|----------|----------------|------------------------|
| Jul 7    | `abc123` | Jul 7, 09:00   | Jul 7, 09:00           |
| Jul 14   | `abc123` | Jul 14, 09:00  | Jul 14, 09:00          |
| Jul 21   | `abc123` | Jul 21, 09:00  | Jul 21, 09:00          |

If the Jul 14 instance were rescheduled to Jul 15, its `startDate` would be Jul 15 but `originalInstanceTime` would remain Jul 14.

### `createEvent` — one new optional parameter

```dart
Future<ETEvent> createEvent({
  required String calendarId,
  required String title,
  required DateTime startDate,
  required DateTime endDate,
  // ... existing optional params unchanged ...
  String? recurrenceRule, // RFC 5545 RRULE value
});
```

### `deleteEvent` — two new optional parameters

```dart
Future<void> deleteEvent({
  required String calendarId,
  required String eventId,
  ETSpan span = ETSpan.thisEvent,  // least-destructive default
  DateTime? originalInstanceTime,  // required when span != allEvents and event is recurring
});
```

Default is `ETSpan.thisEvent` — the least destructive option. Non-recurring events ignore `span` entirely, so this is backward compatible.

### `updateEvent` — three new optional parameters

```dart
Future<ETEvent> updateEvent({
  // ... existing params unchanged ...
  String? recurrenceRule,
  ETSpan span = ETSpan.thisEvent,  // least-destructive default
  DateTime? originalInstanceTime,  // required when span != allEvents and event is recurring
});
```

### `createEventInDefaultCalendar` and `createEventThroughNativePlatform` — one new optional parameter each

```dart
Future<void> createEventInDefaultCalendar({
  // ... existing params unchanged ...
  String? recurrenceRule,
});

Future<void> createEventThroughNativePlatform({
  // ... existing params unchanged ...
  String? recurrenceRule,
});
```

For `createEventThroughNativePlatform`, the recurrence rule is pre-populated on the event before the native UI opens. The user can still modify or clear it inside the native calendar UI.

### `retrieveEvents` — signature unchanged

Recurrence is transparent to callers. Each returned `ETEvent` instance already carries `recurrenceRule` and `originalInstanceTime`. No flag or extra parameter needed.

### Usage example

```dart
import 'package:rrule/rrule.dart';

// Create a recurring event
final rule = RecurrenceRule(
  frequency: Frequency.weekly,
  byWeekDays: {ByWeekDayEntry(DateTime.monday), ByWeekDayEntry(DateTime.wednesday)},
);

await eventide.createEvent(
  calendarId: calendar.id,
  title: 'Standup',
  startDate: DateTime(2026, 7, 7, 9, 0),
  endDate: DateTime(2026, 7, 7, 9, 30),
  recurrenceRule: rule.toString(), // "FREQ=WEEKLY;BYDAY=MO,WE"
);

// Retrieve instances within a range
final events = await eventide.retrieveEvents(
  calendarId: calendar.id,
  startDate: DateTime(2026, 7, 1),
  endDate: DateTime(2026, 7, 31),
);

// Delete just one instance
final instance = events.first;
await eventide.deleteEvent(
  calendarId: instance.calendarId,
  eventId: instance.id,
  span: ETSpan.thisEvent,
  originalInstanceTime: instance.originalInstanceTime,
);

// Delete this and all future
await eventide.deleteEvent(
  calendarId: instance.calendarId,
  eventId: instance.id,
  span: ETSpan.thisAndFuture,
  originalInstanceTime: instance.originalInstanceTime,
);

// Delete the whole series
await eventide.deleteEvent(
  calendarId: instance.calendarId,
  eventId: instance.id,
  span: ETSpan.allEvents,
);
```

---

## Section 2: Wire Protocol (Pigeon)

Changes are minimal. All RRULE logic lives in the Dart and native layers; the wire carries plain strings and integers.

### `Event` class — two new fields

```dart
final class Event {
  // ... existing fields unchanged ...
  final String? recurrenceRule;      // RFC 5545 RRULE value
  final int? originalInstanceTime;   // epoch ms UTC; populated for recurring instances only
}
```

### `createEvent` — one new parameter

```dart
Event createEvent(
  // ... existing params unchanged ...
  String? recurrenceRule,
);
```

### `createEventInDefaultCalendar` and `createEventThroughNativePlatform` — one new parameter each

```dart
void createEventInDefaultCalendar(
  // ... existing params unchanged ...
  String? recurrenceRule,
);

void createEventThroughNativePlatform(
  // ... existing params unchanged ...
  String? recurrenceRule,
);
```

### `deleteEvent` — two new parameters

```dart
void deleteEvent(
  String calendarId,
  String eventId,
  String span,               // "thisEvent" | "thisAndFuture" | "allEvents"
  int? originalInstanceTime, // epoch ms UTC
);
```

`span` is a plain string rather than a Pigeon enum to avoid additional codegen wiring.

### `updateEvent` — three new parameters

```dart
Event updateEvent(
  // ... existing params unchanged ...
  String? recurrenceRule,
  String span,
  int? originalInstanceTime,
);
```

`retrieveEvents` Pigeon signature is **unchanged**.

---

## Section 3: Android Implementation

### `createEvent`

Add one line to the existing `ContentValues` insert block:

```kotlin
if (recurrenceRule != null) {
    values.put(CalendarContract.Events.RRULE, recurrenceRule)
}
```

### `retrieveEvents`

Switch from `CalendarContract.Events` to `CalendarContract.Instances.CONTENT_URI`. The platform automatically expands recurring events into individual occurrences within the queried date range:

```kotlin
CalendarContract.Instances.query(contentResolver, projection, startMs, endMs)
```

Each row provides `EVENT_ID` (master id), `BEGIN`/`END` (instance start/end), `RRULE`, and all event columns. Mapping:

- `Event.id = EVENT_ID`
- `Event.startDate = BEGIN`, `Event.endDate = END`
- `Event.recurrenceRule` from `RRULE` column
- `Event.originalInstanceTime = BEGIN`

### `deleteEvent`

| Span | Behavior |
|------|----------|
| `allEvents` | Delete master event row directly (current behavior) |
| `thisEvent` | Insert exception row: `ORIGINAL_ID=eventId`, `ORIGINAL_INSTANCE_TIME=originalInstanceTime`, `DTSTART=originalInstanceTime`, `STATUS=STATUS_CANCELED` |
| `thisAndFuture` | Fetch master RRULE, append `UNTIL=<originalInstanceTime - 1ms>`, update master event row with patched RRULE |

### `updateEvent`

| Span | Behavior |
|------|----------|
| `allEvents` | Update master event row directly (current behavior, + RRULE field) |
| `thisEvent` | Insert exception row with new field values: `ORIGINAL_ID=eventId`, `ORIGINAL_INSTANCE_TIME=originalInstanceTime`, new DTSTART/DTEND, TITLE, etc. |
| `thisAndFuture` | Patch master RRULE with `UNTIL=<originalInstanceTime - 1ms>`; insert new master event row starting at `originalInstanceTime` with new field values and `recurrenceRule` |

### ICS generator (`IcsEventManager`)

Used by `createEventInDefaultCalendar` / `createEventThroughNativePlatform` on Android. Add one line to the generated VEVENT block:

```
RRULE:<recurrenceRule>
```

---

## Section 4: iOS Implementation

### `createEvent` and `createEventInDefaultCalendar`

Both use the EKEventStore path. Same recurrence handling applies to both:

```swift
if let rrule = recurrenceRule {
    let rule = RRuleParser.parse(rrule)
    ekEvent.recurrenceRules = [rule]
}
```

Supported RRULE properties: `FREQ`, `INTERVAL`, `BYDAY`, `BYMONTHDAY`, `BYMONTH`, `COUNT`, `UNTIL`. Unsupported properties (not handled by EventKit: `BYYEARDAY`, `BYWEEKNO`, `BYSETPOS`) are silently dropped and documented.

### `createEventThroughNativePlatform`

Same `RRuleParser` call as above, applied to the EKEvent before `EKEventEditViewController` is presented. The user can modify or clear the pre-populated recurrence rule inside the native UI.

### `retrieveEvents`

The existing `events(matching:)` query already returns individual occurrences. Two additions to `toEvent()`:

```swift
// Serialize EKRecurrenceRule → RRULE string
event.recurrenceRule = ekEvent.recurrenceRules?.first.map { RRuleSerializer.serialize($0) }

// Populate originalInstanceTime from the occurrence date
event.originalInstanceTime = ekEvent.occurrenceDate.map { Int($0.timeIntervalSince1970 * 1000) }
```

A new internal `RRuleSerializer` handles the reverse direction.

### `deleteEvent`

| Span | Behavior |
|------|----------|
| `allEvents` | Fetch master via `event(withIdentifier:)` — this returns the non-occurrence master EKEvent. Remove with `.thisEvent` on the master EKEvent removes the entire series (not a single occurrence). |
| `thisEvent` | Fetch specific occurrence: `events(matching:)` over `originalInstanceTime` date range, find occurrence where `occurrenceDate == originalInstanceTime`, remove with `.thisEvent` |
| `thisAndFuture` | Fetch specific occurrence (same as above), remove with `.futureEvents` |

### `updateEvent`

| Span | Behavior |
|------|----------|
| `allEvents` | Fetch master, update fields + `recurrenceRules`, save with `.thisEvent` |
| `thisEvent` | Fetch specific occurrence, update fields, save with `.thisEvent` |
| `thisAndFuture` | Fetch specific occurrence, update fields + `recurrenceRules`, save with `.futureEvents` |

### `RRuleParser` / `RRuleSerializer`

A small internal Swift utility (not exposed publicly). Designed for round-trip fidelity: `serialize(parse(rrule)) == rrule` for all supported properties. Unit-testable in isolation.

---

## Section 5: Testing

### Dart (`test/`)

- **`recurrence_test.dart`** — `createEvent` with `recurrenceRule` forwards correct args to `CalendarApi` mock; `deleteEvent` with each `ETSpan` value; `updateEvent` with each `ETSpan` value
- **`event_test.dart`** — extend: `ETEvent` equality/hashCode with new fields; `toETEvent()` conversion with `recurrenceRule` and `originalInstanceTime`

### Android (`android/src/test/kotlin/`)

- **`RecurrenceTests.kt`** — `createEvent` inserts `RRULE` into `ContentValues`; `deleteEvent` with `thisEvent` inserts a `STATUS_CANCELED` exception row; `deleteEvent` with `thisAndFuture` patches RRULE with `UNTIL`; `updateEvent` with each span behaves correctly
- **`IcsEventManagerTest.kt`** — extend: generated ICS contains `RRULE:` line when recurrence rule is present

### iOS

- **`RRuleParserTests.swift`** — round-trip for each FREQ (DAILY, WEEKLY, MONTHLY, YEARLY); INTERVAL, BYDAY, COUNT, UNTIL properties; unsupported property is dropped without error
- **`EasyEventStoreTests.swift`** — extend: create sets `recurrenceRules`; retrieve populates `recurrenceRule` and `originalInstanceTime`; delete/update with each span fetches the correct occurrence and calls `remove`/`save` with the correct `EKSpan`

---

## Open Questions

None — all design decisions resolved during brainstorming session.
