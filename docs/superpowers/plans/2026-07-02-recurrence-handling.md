# Recurrence Handling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add full RFC 5545 recurrence support — create recurring events, retrieve expanded instances, and delete/update instances by scope (thisEvent / thisAndFuture / allEvents).

**Architecture:** RRULE strings flow opaque through the Dart/Pigeon wire. Android stores them directly in `CalendarContract.Events.RRULE`. iOS parses them via a new internal `RRuleParser` Swift utility into `EKRecurrenceRule`. Instance scope is a new `ETSpan` enum serialized as a plain string on the wire.

**Tech Stack:** Flutter/Dart, Pigeon v26.1.0 (codegen), Kotlin (Android CalendarContract), Swift (iOS EventKit), MockK + JUnit 5 (Android tests), mocktail (Dart tests), XCTest (iOS tests)

## Global Constraints

- Dart SDK `^3.7`, Flutter `≥3.29`
- Pigeon `^26.1.0`; codegen command from project root: `dart pub run pigeon --input ./pigeons/calendar_api.dart`
- Android package: `sncf.connect.tech.eventide`
- iOS source path: `ios/eventide/Sources/eventide/`; test path: `ios/eventide/Tests/eventide/`
- RRULE on wire: RFC 5545 **value only** (no `RRULE:` prefix), e.g. `FREQ=WEEKLY;BYDAY=MO,WE`
- `UNTIL` in patched RRULEs must be a UTC datetime string: `YYYYMMDDTHHMMSSZ`
- `ETSpan` defaults to `ETSpan.thisEvent` (least destructive) on both `deleteEvent` and `updateEvent`
- `originalInstanceTime` is `null` for non-recurring events
- Supported RRULE properties on iOS: `FREQ`, `INTERVAL`, `BYDAY`, `BYMONTHDAY`, `BYMONTH`, `COUNT`, `UNTIL`. Unsupported properties are silently dropped.

---

## File Map

### New files
| File | Purpose |
|------|---------|
| `lib/src/et_span.dart` | `ETSpan` enum |
| `android/src/main/kotlin/sncf/connect/tech/eventide/RecurrenceHelper.kt` | RRULE patch helpers (patchWithUntil, getMasterEventDuration) |
| `android/src/test/kotlin/sncf/connect/tech/eventide/RecurrenceTests.kt` | Android recurrence tests |
| `ios/eventide/Sources/eventide/RRuleParser.swift` | RRULE string → `EKRecurrenceRule` |
| `ios/eventide/Sources/eventide/RRuleSerializer.swift` | `EKRecurrenceRule` → RRULE string |
| `ios/eventide/Tests/eventide/RRuleParserTests.swift` | Round-trip parser/serializer tests |
| `test/recurrence_test.dart` | Dart-level recurrence API tests |

### Modified files
| File | Changes |
|------|---------|
| `pigeons/calendar_api.dart` | Add `recurrenceRule`/`originalInstanceTime` to `Event`; new params on `createEvent`, `createEventInDefaultCalendar`, `createEventThroughNativePlatform`, `deleteEvent`, `updateEvent` |
| `lib/src/calendar_api.g.dart` | Regenerated — do not hand-edit |
| `android/.../CalendarApi.g.kt` | Regenerated — do not hand-edit |
| `ios/.../CalendarApi.g.swift` | Regenerated — do not hand-edit |
| `lib/src/eventide_platform_interface.dart` | `ETEvent`: add `recurrenceRule`, `originalInstanceTime`; update abstract method signatures |
| `lib/src/eventide.dart` | Update `createEvent`, `createEventInDefaultCalendar`, `createEventThroughNativePlatform`, `deleteEvent`, `updateEvent` |
| `lib/src/extensions/event_extensions.dart` | `toETEvent()`: map two new wire fields |
| `lib/eventide.dart` | Export `ETSpan` |
| `android/.../CalendarImplem.kt` | `createEvent`, `retrieveEvents`, `deleteEvent`, `updateEvent` |
| `android/.../handler/IcsEventManager.kt` | Add `RRULE:` line to VEVENT block |
| `android/.../IcsEventManagerTest.kt` | Extend: RRULE present in ICS output |
| `ios/.../EasyEventStore/EasyEventStore.swift` | `createEvent`, `createDefaultEvent`, `presentEventCreationViewController`, `retrieveEvents`, `deleteEvent`, `updateEvent` |
| `ios/.../CalendarImplem.swift` | Pass new params to EasyEventStore |
| `test/event_test.dart` | Extend `ETEvent` equality and `toETEvent()` tests |

---

## Task 1: Pigeon Contract Update + Codegen

**Files:**
- Modify: `pigeons/calendar_api.dart`
- Regenerated: `lib/src/calendar_api.g.dart`, `android/src/main/kotlin/sncf/connect/tech/eventide/CalendarApi.g.kt`, `ios/eventide/Sources/eventide/CalendarApi.g.swift`

**Interfaces:**
- Produces: updated Pigeon stubs used by all subsequent tasks

- [ ] **Step 1: Update `pigeons/calendar_api.dart`**

Replace the `Event` class and all affected method signatures. The complete updated portions are:

```dart
// Event class — add two nullable fields and update constructor
final class Event {
  final String id;
  final String calendarId;
  final String title;
  final bool isAllDay;
  final int startDate;
  final int endDate;
  final List<int> reminders;
  final List<Attendee> attendees;
  final String? description;
  final String? url;
  final String? location;
  final String? recurrenceRule;       // RFC 5545 RRULE value; null for non-recurring
  final int? originalInstanceTime;    // epoch ms UTC; null for non-recurring

  const Event({
    required this.id,
    required this.title,
    required this.isAllDay,
    required this.startDate,
    required this.endDate,
    required this.calendarId,
    required this.reminders,
    required this.attendees,
    required this.description,
    required this.url,
    required this.location,
    required this.recurrenceRule,
    required this.originalInstanceTime,
  });
}
```

Update `createEvent` (add one param at the end):
```dart
@async
Event createEvent({
  required String calendarId,
  required String title,
  required int startDate,
  required int endDate,
  required bool isAllDay,
  required String? description,
  required String? url,
  required String? location,
  required List<int>? reminders,
  required String? recurrenceRule,
});
```

Update `createEventInDefaultCalendar` (add one param at the end):
```dart
@async
void createEventInDefaultCalendar({
  required String title,
  required int startDate,
  required int endDate,
  required bool isAllDay,
  required String? description,
  required String? url,
  required String? location,
  required List<int>? reminders,
  required String? recurrenceRule,
});
```

Update `createEventThroughNativePlatform` (add one optional param at the end):
```dart
@async
void createEventThroughNativePlatform({
  String? title,
  int? startDate,
  int? endDate,
  bool? isAllDay,
  String? description,
  String? url,
  String? location,
  List<int>? reminders,
  String? recurrenceRule,
});
```

Update `deleteEvent` (add span and originalInstanceTime; update `@SwiftFunction`):
```dart
@async
@SwiftFunction('deleteEvent(withId:span:originalInstanceTime:)')
void deleteEvent({
  required String eventId,
  required String span,
  required int? originalInstanceTime,
});
```

Update `updateEvent` (add three params at the end; update `@SwiftFunction`):
```dart
@async
@SwiftFunction('updateEvent(withId:calendarId:title:startDate:endDate:isAllDay:description:url:location:reminders:recurrenceRule:span:originalInstanceTime:)')
Event updateEvent({
  required String eventId,
  required String calendarId,
  required String title,
  required int startDate,
  required int endDate,
  required bool isAllDay,
  required String? description,
  required String? url,
  required String? location,
  required List<int>? reminders,
  required String? recurrenceRule,
  required String span,
  required int? originalInstanceTime,
});
```

- [ ] **Step 2: Run Pigeon codegen**

```bash
dart pub run pigeon --input ./pigeons/calendar_api.dart
```

Expected: no errors; three generated files updated (check timestamps on `lib/src/calendar_api.g.dart`, `android/.../CalendarApi.g.kt`, `ios/.../CalendarApi.g.swift`).

- [ ] **Step 3: Verify generated files compile**

```bash
flutter build apk --debug 2>&1 | head -40
```

Expected: compile errors about missing `recurrenceRule` and `originalInstanceTime` in `CalendarImplem` implementations — this is expected at this stage.

- [ ] **Step 4: Commit**

```bash
git add pigeons/calendar_api.dart lib/src/calendar_api.g.dart \
  android/src/main/kotlin/sncf/connect/tech/eventide/CalendarApi.g.kt \
  ios/eventide/Sources/eventide/CalendarApi.g.swift
git commit -m "chore: update Pigeon contract with recurrence fields and span params"
```

---

## Task 2: Dart Model — ETSpan + ETEvent

**Files:**
- Create: `lib/src/et_span.dart`
- Modify: `lib/src/eventide_platform_interface.dart`
- Modify: `lib/src/extensions/event_extensions.dart`
- Modify: `lib/eventide.dart`
- Modify (extend): `test/event_test.dart`

**Interfaces:**
- Produces: `ETSpan` enum; `ETEvent.recurrenceRule: String?`; `ETEvent.originalInstanceTime: DateTime?`

- [ ] **Step 1: Write failing tests for ETEvent new fields**

Add to `test/event_test.dart`:

```dart
group('ETEvent with recurrence', () {
  test('toETEvent maps recurrenceRule', () {
    final raw = Event(
      id: '1', title: 'T', isAllDay: false,
      startDate: 0, endDate: 3600000,
      calendarId: 'cal1', reminders: [], attendees: [],
      description: null, url: null, location: null,
      recurrenceRule: 'FREQ=WEEKLY;BYDAY=MO',
      originalInstanceTime: 1751788800000,
    );
    final etEvent = raw.toETEvent();
    expect(etEvent.recurrenceRule, equals('FREQ=WEEKLY;BYDAY=MO'));
  });

  test('toETEvent maps originalInstanceTime to DateTime', () {
    final raw = Event(
      id: '1', title: 'T', isAllDay: false,
      startDate: 0, endDate: 3600000,
      calendarId: 'cal1', reminders: [], attendees: [],
      description: null, url: null, location: null,
      recurrenceRule: 'FREQ=DAILY',
      originalInstanceTime: 1751788800000,
    );
    final etEvent = raw.toETEvent();
    expect(
      etEvent.originalInstanceTime,
      equals(DateTime.fromMillisecondsSinceEpoch(1751788800000, isUtc: true)),
    );
  });

  test('toETEvent sets originalInstanceTime to null for non-recurring', () {
    final raw = Event(
      id: '1', title: 'T', isAllDay: false,
      startDate: 0, endDate: 3600000,
      calendarId: 'cal1', reminders: [], attendees: [],
      description: null, url: null, location: null,
      recurrenceRule: null,
      originalInstanceTime: null,
    );
    final etEvent = raw.toETEvent();
    expect(etEvent.originalInstanceTime, isNull);
    expect(etEvent.recurrenceRule, isNull);
  });

  test('ETEvent equality includes recurrenceRule and originalInstanceTime', () {
    final dt = DateTime.fromMillisecondsSinceEpoch(1751788800000, isUtc: true);
    final a = ETEvent(
      id: '1', title: 'T', isAllDay: false,
      startDate: DateTime(2026, 7, 7), endDate: DateTime(2026, 7, 7, 1),
      calendarId: 'cal1', reminders: [], attendees: [],
      description: null, url: null, location: null,
      recurrenceRule: 'FREQ=DAILY',
      originalInstanceTime: dt,
    );
    final b = ETEvent(
      id: '1', title: 'T', isAllDay: false,
      startDate: DateTime(2026, 7, 7), endDate: DateTime(2026, 7, 7, 1),
      calendarId: 'cal1', reminders: [], attendees: [],
      description: null, url: null, location: null,
      recurrenceRule: 'FREQ=DAILY',
      originalInstanceTime: dt,
    );
    expect(a, equals(b));
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/event_test.dart
```

Expected: compilation errors — `recurrenceRule` and `originalInstanceTime` don't exist yet on `ETEvent`.

- [ ] **Step 3: Create `lib/src/et_span.dart`**

```dart
/// The scope of a delete or update operation on a recurring event instance.
enum ETSpan {
  /// Affects only this specific occurrence.
  thisEvent,

  /// Affects this occurrence and all future occurrences in the series.
  thisAndFuture,

  /// Affects every occurrence in the series (modifies the master event).
  allEvents,
}
```

- [ ] **Step 4: Add `recurrenceRule` and `originalInstanceTime` to `ETEvent`**

In `lib/src/eventide_platform_interface.dart`, find the `ETEvent` class and add two fields. Follow the exact pattern of existing nullable fields (`description`, `url`, `location`). Add to the field list:

```dart
final String? recurrenceRule;
final DateTime? originalInstanceTime;
```

Add to the constructor:
```dart
this.recurrenceRule,
this.originalInstanceTime,
```

Add to `==` operator (follow existing pattern, e.g. `&& recurrenceRule == other.recurrenceRule && originalInstanceTime == other.originalInstanceTime`).

Add to `hashCode` (follow existing `Object.hash` or `^` pattern already in the class).

Add to `toString` if it exists.

- [ ] **Step 5: Update `toETEvent()` in `lib/src/extensions/event_extensions.dart`**

Add two mappings inside `toETEvent()`:

```dart
recurrenceRule: event.recurrenceRule,
originalInstanceTime: event.originalInstanceTime != null
    ? DateTime.fromMillisecondsSinceEpoch(
        event.originalInstanceTime!,
        isUtc: true,
      )
    : null,
```

- [ ] **Step 6: Export `ETSpan` from `lib/eventide.dart`**

Add to the barrel file:
```dart
export 'src/et_span.dart';
```

- [ ] **Step 7: Run tests to verify they pass**

```bash
flutter test test/event_test.dart
```

Expected: all new tests pass; no existing tests broken.

- [ ] **Step 8: Commit**

```bash
git add lib/src/et_span.dart lib/src/eventide_platform_interface.dart \
  lib/src/extensions/event_extensions.dart lib/eventide.dart test/event_test.dart
git commit -m "feat: add ETSpan enum and recurrence fields to ETEvent"
```

---

## Task 3: Dart API — Method Signatures + Tests

**Files:**
- Modify: `lib/src/eventide_platform_interface.dart` (abstract method signatures)
- Modify: `lib/src/eventide.dart` (concrete implementations)
- Create: `test/recurrence_test.dart`

**Interfaces:**
- Consumes: `ETSpan` from Task 2; updated Pigeon stubs from Task 1
- Produces: updated public API; `_spanToString` helper

- [ ] **Step 1: Write failing tests**

Create `test/recurrence_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:eventide/eventide.dart';
import 'package:eventide/src/calendar_api.g.dart';

class _MockCalendarApi extends Mock implements CalendarApi {}

void main() {
  late _MockCalendarApi mockCalendarApi;
  late Eventide eventide;

  final startDate = DateTime(2026, 7, 7, 9, 0);
  final endDate = DateTime(2026, 7, 7, 9, 30);

  final baseEvent = Event(
    id: 'master1',
    title: 'Standup',
    isAllDay: false,
    startDate: startDate.toUtc().millisecondsSinceEpoch,
    endDate: endDate.toUtc().millisecondsSinceEpoch,
    calendarId: 'cal1',
    reminders: [],
    attendees: [],
    description: null,
    url: null,
    location: null,
    recurrenceRule: 'FREQ=WEEKLY;BYDAY=MO',
    originalInstanceTime: startDate.toUtc().millisecondsSinceEpoch,
  );

  setUp(() {
    mockCalendarApi = _MockCalendarApi();
    eventide = Eventide(calendarApi: mockCalendarApi);
    registerFallbackValue(baseEvent);
  });

  group('createEvent with recurrenceRule', () {
    test('forwards recurrenceRule to CalendarApi', () async {
      when(
        () => mockCalendarApi.createEvent(
          calendarId: any(named: 'calendarId'),
          title: any(named: 'title'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          isAllDay: any(named: 'isAllDay'),
          description: any(named: 'description'),
          url: any(named: 'url'),
          location: any(named: 'location'),
          reminders: any(named: 'reminders'),
          recurrenceRule: any(named: 'recurrenceRule'),
        ),
      ).thenAnswer((_) async => baseEvent);

      await eventide.createEvent(
        calendarId: 'cal1',
        title: 'Standup',
        startDate: startDate,
        endDate: endDate,
        recurrenceRule: 'FREQ=WEEKLY;BYDAY=MO',
      );

      verify(
        () => mockCalendarApi.createEvent(
          calendarId: 'cal1',
          title: 'Standup',
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          isAllDay: false,
          description: null,
          url: null,
          location: null,
          reminders: null,
          recurrenceRule: 'FREQ=WEEKLY;BYDAY=MO',
        ),
      ).called(1);
    });
  });

  group('deleteEvent with span', () {
    test('forwards thisEvent span and originalInstanceTime', () async {
      when(
        () => mockCalendarApi.deleteEvent(
          eventId: any(named: 'eventId'),
          span: any(named: 'span'),
          originalInstanceTime: any(named: 'originalInstanceTime'),
        ),
      ).thenAnswer((_) async {});

      await eventide.deleteEvent(
        eventId: 'master1',
        span: ETSpan.thisEvent,
        originalInstanceTime: startDate,
      );

      verify(
        () => mockCalendarApi.deleteEvent(
          eventId: 'master1',
          span: 'thisEvent',
          originalInstanceTime: startDate.toUtc().millisecondsSinceEpoch,
        ),
      ).called(1);
    });

    test('forwards allEvents span with null originalInstanceTime', () async {
      when(
        () => mockCalendarApi.deleteEvent(
          eventId: any(named: 'eventId'),
          span: any(named: 'span'),
          originalInstanceTime: any(named: 'originalInstanceTime'),
        ),
      ).thenAnswer((_) async {});

      await eventide.deleteEvent(eventId: 'master1', span: ETSpan.allEvents);

      verify(
        () => mockCalendarApi.deleteEvent(
          eventId: 'master1',
          span: 'allEvents',
          originalInstanceTime: null,
        ),
      ).called(1);
    });

    test('forwards thisAndFuture span', () async {
      when(
        () => mockCalendarApi.deleteEvent(
          eventId: any(named: 'eventId'),
          span: any(named: 'span'),
          originalInstanceTime: any(named: 'originalInstanceTime'),
        ),
      ).thenAnswer((_) async {});

      await eventide.deleteEvent(
        eventId: 'master1',
        span: ETSpan.thisAndFuture,
        originalInstanceTime: startDate,
      );

      verify(
        () => mockCalendarApi.deleteEvent(
          eventId: 'master1',
          span: 'thisAndFuture',
          originalInstanceTime: startDate.toUtc().millisecondsSinceEpoch,
        ),
      ).called(1);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/recurrence_test.dart
```

Expected: compile errors — new params not yet on `Eventide` methods.

- [ ] **Step 3: Update abstract signatures in `lib/src/eventide_platform_interface.dart`**

Update each method signature to add the new params:

```dart
Future<ETEvent> createEvent({
  required String calendarId,
  required String title,
  required DateTime startDate,
  required DateTime endDate,
  bool isAllDay = false,
  String? description,
  String? url,
  String? location,
  Iterable<Duration>? reminders,
  String? recurrenceRule,          // new
});

Future<void> createEventInDefaultCalendar({
  required String title,
  required DateTime startDate,
  required DateTime endDate,
  bool isAllDay = false,
  String? description,
  String? url,
  String? location,
  Iterable<Duration>? reminders,
  String? recurrenceRule,          // new
});

Future<void> createEventThroughNativePlatform({
  String? title,
  DateTime? startDate,
  DateTime? endDate,
  bool? isAllDay,
  String? description,
  String? url,
  String? location,
  Iterable<Duration>? reminders,
  String? recurrenceRule,          // new
});

Future<void> deleteEvent({
  required String eventId,
  ETSpan span = ETSpan.thisEvent,       // new
  DateTime? originalInstanceTime,       // new
});

Future<ETEvent> updateEvent(
  ETEvent event, {
  String? calendarId,
  String? title,
  DateTime? startDate,
  DateTime? endDate,
  bool? isAllDay,
  String? description,
  String? url,
  String? location,
  Iterable<Duration>? reminders,
  String? recurrenceRule,               // new
  ETSpan span = ETSpan.thisEvent,       // new
  DateTime? originalInstanceTime,       // new
});
```

- [ ] **Step 4: Update concrete implementations in `lib/src/eventide.dart`**

Add a private helper:
```dart
String _spanToString(ETSpan span) => switch (span) {
  ETSpan.thisEvent => 'thisEvent',
  ETSpan.thisAndFuture => 'thisAndFuture',
  ETSpan.allEvents => 'allEvents',
};
```

Update `createEvent` — add `recurrenceRule` param and pass it to Pigeon:
```dart
Future<ETEvent> createEvent({
  ...,
  String? recurrenceRule,
}) async {
  // existing body unchanged, add to the _calendarApi.createEvent call:
  recurrenceRule: recurrenceRule,
}
```

Update `createEventInDefaultCalendar` — same pattern, add `recurrenceRule`.

Update `createEventThroughNativePlatform` — same pattern, add `recurrenceRule`.

Update `deleteEvent`:
```dart
Future<void> deleteEvent({
  required String eventId,
  ETSpan span = ETSpan.thisEvent,
  DateTime? originalInstanceTime,
}) async {
  try {
    await _calendarApi.deleteEvent(
      eventId: eventId,
      span: _spanToString(span),
      originalInstanceTime: originalInstanceTime?.toUtc().millisecondsSinceEpoch,
    );
  } on PlatformException catch (e) {
    throw e.toETException();
  }
}
```

Update `updateEvent` — add the three new params and pass them to Pigeon:
```dart
Future<ETEvent> updateEvent(
  ETEvent event, {
  ...,
  String? recurrenceRule,
  ETSpan span = ETSpan.thisEvent,
  DateTime? originalInstanceTime,
}) async {
  // In the _calendarApi.updateEvent call, add:
  recurrenceRule: recurrenceRule ?? event.recurrenceRule,
  span: _spanToString(span),
  originalInstanceTime: originalInstanceTime?.toUtc().millisecondsSinceEpoch
      ?? event.originalInstanceTime?.toUtc().millisecondsSinceEpoch,
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
flutter test test/recurrence_test.dart
```

Expected: all tests pass.

- [ ] **Step 6: Run full Dart test suite to check no regressions**

```bash
flutter test
```

Expected: all existing tests pass (may need to add `recurrenceRule: null, originalInstanceTime: null` to any `Event(...)` constructors in existing tests).

- [ ] **Step 7: Commit**

```bash
git add lib/src/eventide_platform_interface.dart lib/src/eventide.dart \
  test/recurrence_test.dart
git commit -m "feat: add recurrence params to Dart API methods"
```

---

## Task 4: Android — createEvent with RRULE

**Files:**
- Modify: `android/src/main/kotlin/sncf/connect/tech/eventide/CalendarImplem.kt`
- Create: `android/src/test/kotlin/sncf/connect/tech/eventide/RecurrenceTests.kt`

**Interfaces:**
- Consumes: updated `CalendarApi.g.kt` from Task 1
- Produces: `createEvent` stores RRULE in `CalendarContract.Events`

- [ ] **Step 1: Write failing test**

Create `android/src/test/kotlin/sncf/connect/tech/eventide/RecurrenceTests.kt`:

```kotlin
package sncf.connect.tech.eventide

import android.content.ContentValues
import android.provider.CalendarContract
import io.mockk.slot
import io.mockk.verify
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import sncf.connect.tech.eventide.Mocks.Companion.mockPermissionGranted
import sncf.connect.tech.eventide.Mocks.Companion.mockWritableCalendar

// Reuse the same setup pattern as EventTests.kt
class RecurrenceTests {
    // (copy the full @BeforeEach setup from EventTests.kt — same fields and calendarImplem construction)

    @Test
    fun `createEvent inserts RRULE into ContentValues when recurrenceRule is provided`() = runTest {
        mockPermissionGranted(permissionHandler)
        mockWritableCalendar(contentResolver, calendarContentUri)

        val insertedValues = slot<ContentValues>()
        // mock contentResolver.insert to capture the values
        every { contentResolver.insert(eventContentUri, capture(insertedValues)) } returns
            android.net.Uri.parse("content://com.android.calendar/events/42")
        // mock reminder insert
        every { contentResolver.insert(remindersContentUri, any()) } returns null

        val callback = mockk<(Result<sncf.connect.tech.eventide.Event>) -> Unit>(relaxed = true)
        calendarImplem.createEvent(
            calendarId = "1",
            title = "Standup",
            startDate = 1751880000000L,
            endDate = 1751883600000L,
            isAllDay = false,
            description = null,
            url = null,
            location = null,
            reminders = null,
            recurrenceRule = "FREQ=WEEKLY;BYDAY=MO",
            callback = callback,
        )

        assertEquals("FREQ=WEEKLY;BYDAY=MO", insertedValues.captured.getAsString(CalendarContract.Events.RRULE))
    }

    @Test
    fun `createEvent does not insert RRULE when recurrenceRule is null`() = runTest {
        mockPermissionGranted(permissionHandler)
        mockWritableCalendar(contentResolver, calendarContentUri)

        val insertedValues = slot<ContentValues>()
        every { contentResolver.insert(eventContentUri, capture(insertedValues)) } returns
            android.net.Uri.parse("content://com.android.calendar/events/43")
        every { contentResolver.insert(remindersContentUri, any()) } returns null

        val callback = mockk<(Result<sncf.connect.tech.eventide.Event>) -> Unit>(relaxed = true)
        calendarImplem.createEvent(
            calendarId = "1",
            title = "Standup",
            startDate = 1751880000000L,
            endDate = 1751883600000L,
            isAllDay = false,
            description = null, url = null, location = null, reminders = null,
            recurrenceRule = null,
            callback = callback,
        )

        assert(!insertedValues.captured.containsKey(CalendarContract.Events.RRULE))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
./gradlew :eventide:test
```

Expected: compilation error — `recurrenceRule` not yet accepted by `CalendarImplem.createEvent`.

- [ ] **Step 3: Update `CalendarImplem.createEvent`**

The Pigeon-generated `CalendarApi.g.kt` interface now includes `recurrenceRule: String?`. Update the `createEvent` implementation in `CalendarImplem.kt` to accept and use it.

In the `ContentValues` block, after the existing fields, add:

```kotlin
if (recurrenceRule != null) {
    values.put(CalendarContract.Events.RRULE, recurrenceRule)
}
```

Also update the returned `Event` object at the end of `createEvent` to include the new fields:

```kotlin
Event(
    // ... existing fields ...
    recurrenceRule = recurrenceRule,
    originalInstanceTime = null, // create returns the master; not an instance
)
```

- [ ] **Step 4: Run test to verify it passes**

```bash
./gradlew :eventide:test --tests "sncf.connect.tech.eventide.RecurrenceTests"
```

Expected: both tests pass.

- [ ] **Step 5: Commit**

```bash
git add android/src/main/kotlin/sncf/connect/tech/eventide/CalendarImplem.kt \
  android/src/test/kotlin/sncf/connect/tech/eventide/RecurrenceTests.kt
git commit -m "feat(android): store RRULE on createEvent"
```

---

## Task 5: Android — retrieveEvents via CalendarContract.Instances

**Files:**
- Modify: `android/src/main/kotlin/sncf/connect/tech/eventide/CalendarImplem.kt`
- Modify: `android/src/test/kotlin/sncf/connect/tech/eventide/RecurrenceTests.kt`

**Interfaces:**
- Produces: `retrieveEvents` returns expanded instances; each has `originalInstanceTime = BEGIN`

- [ ] **Step 1: Write failing test**

Add to `RecurrenceTests.kt`:

```kotlin
@Test
fun `retrieveEvents returns originalInstanceTime from instance BEGIN`() = runTest {
    mockPermissionGranted(permissionHandler)

    val instanceStart = 1751880000000L
    val instanceEnd = 1751883600000L

    // Mock the Instances cursor (same pattern as Mocks.mockRetrieveEvents but for Instances)
    val cursor = mockk<android.database.Cursor>(relaxed = true)
    var rowIndex = -1
    every { cursor.moveToNext() } answers { rowIndex++; rowIndex < 1 }
    // EVENT_ID column
    every { cursor.getColumnIndex(CalendarContract.Instances.EVENT_ID) } returns 0
    every { cursor.getString(0) } returns "42"
    // TITLE column
    every { cursor.getColumnIndex(CalendarContract.Instances.TITLE) } returns 1
    every { cursor.getString(1) } returns "Standup"
    // BEGIN column
    every { cursor.getColumnIndex(CalendarContract.Instances.BEGIN) } returns 2
    every { cursor.getLong(2) } returns instanceStart
    // END column
    every { cursor.getColumnIndex(CalendarContract.Instances.END) } returns 3
    every { cursor.getLong(3) } returns instanceEnd
    // RRULE column
    every { cursor.getColumnIndex(CalendarContract.Instances.RRULE) } returns 4
    every { cursor.getString(4) } returns "FREQ=WEEKLY;BYDAY=MO"
    // ALL_DAY
    every { cursor.getColumnIndex(CalendarContract.Instances.ALL_DAY) } returns 5
    every { cursor.getInt(5) } returns 0
    // DESCRIPTION, LOCATION, etc. return null
    every { cursor.getColumnIndex(CalendarContract.Events.DESCRIPTION) } returns 6
    every { cursor.getString(6) } returns null
    every { cursor.getColumnIndex(CalendarContract.Events.EVENT_LOCATION) } returns 7
    every { cursor.getString(7) } returns null
    every { cursor.getColumnIndex(CalendarContract.Events.CALENDAR_ID) } returns 8
    every { cursor.getString(8) } returns "1"

    // The actual query URI pattern: Instances URI with date range
    every { contentResolver.query(any(), any(), any(), any(), any()) } returns cursor

    // Mock empty reminders and attendees queries
    val emptyCursor = mockk<android.database.Cursor>(relaxed = true)
    every { emptyCursor.moveToNext() } returns false
    every { contentResolver.query(remindersContentUri, any(), any(), any(), any()) } returns emptyCursor
    every { contentResolver.query(attendeesContentUri, any(), any(), any(), any()) } returns emptyCursor

    var result: List<sncf.connect.tech.eventide.Event>? = null
    calendarImplem.retrieveEvents(
        calendarId = "1",
        startDate = instanceStart,
        endDate = instanceEnd + 86400000L,
    ) { result = it.getOrNull() }

    val event = result?.firstOrNull()
    assertEquals("42", event?.id)
    assertEquals("FREQ=WEEKLY;BYDAY=MO", event?.recurrenceRule)
    assertEquals(instanceStart, event?.originalInstanceTime)
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
./gradlew :eventide:test --tests "sncf.connect.tech.eventide.RecurrenceTests.retrieveEvents*"
```

Expected: FAIL — `originalInstanceTime` not yet populated.

- [ ] **Step 3: Update `retrieveEvents` in `CalendarImplem.kt`**

Switch the query from `CalendarContract.Events` to `CalendarContract.Instances`. Replace the existing query URI construction with:

```kotlin
val instancesUri = CalendarContract.Instances.CONTENT_URI.buildUpon()
    .appendPath(startDate.toString())
    .appendPath(endDate.toString())
    .build()

val cursor = contentResolver.query(
    instancesUri,
    arrayOf(
        CalendarContract.Instances.EVENT_ID,        // use as event id
        CalendarContract.Instances.TITLE,
        CalendarContract.Instances.BEGIN,            // instance start
        CalendarContract.Instances.END,              // instance end
        CalendarContract.Instances.RRULE,
        CalendarContract.Instances.ALL_DAY,
        CalendarContract.Events.DESCRIPTION,
        CalendarContract.Events.EVENT_LOCATION,
        CalendarContract.Instances.CALENDAR_ID,
    ),
    "${CalendarContract.Instances.CALENDAR_ID} = ?",
    arrayOf(calendarId),
    null,
)
```

When building each `Event` from the cursor, map:
- `id = cursor.getString(EVENT_ID index)`
- `startDate = cursor.getLong(BEGIN index)`
- `endDate = cursor.getLong(END index)`
- `recurrenceRule = cursor.getString(RRULE index)` (null if absent)
- `originalInstanceTime = cursor.getLong(BEGIN index)` (same as startDate for non-modified instances; still correct for modified ones where BEGIN = originalInstanceTime)

Reminders and attendees are still fetched by a secondary query using the `EVENT_ID` (unchanged).

- [ ] **Step 4: Run test to verify it passes**

```bash
./gradlew :eventide:test --tests "sncf.connect.tech.eventide.RecurrenceTests"
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add android/src/main/kotlin/sncf/connect/tech/eventide/CalendarImplem.kt \
  android/src/test/kotlin/sncf/connect/tech/eventide/RecurrenceTests.kt
git commit -m "feat(android): expand recurring events via CalendarContract.Instances"
```

---

## Task 6: Android — RecurrenceHelper + deleteEvent Span Logic

**Files:**
- Create: `android/src/main/kotlin/sncf/connect/tech/eventide/RecurrenceHelper.kt`
- Modify: `android/src/main/kotlin/sncf/connect/tech/eventide/CalendarImplem.kt`
- Modify: `android/src/test/kotlin/sncf/connect/tech/eventide/RecurrenceTests.kt`

**Interfaces:**
- Produces: `RecurrenceHelper.patchWithUntil(rrule, untilMs)` and `getEventDuration(eventId)`; `deleteEvent` supports all three spans

- [ ] **Step 1: Write failing tests**

Add to `RecurrenceTests.kt`:

```kotlin
@Test
fun `deleteEvent with allEvents deletes master event row`() = runTest {
    mockPermissionGranted(permissionHandler)
    mockWritableCalendar(contentResolver, calendarContentUri)

    every { contentResolver.delete(eventContentUri, "_id = ?", arrayOf("42")) } returns 1

    val callback = mockk<(Result<Unit>) -> Unit>(relaxed = true)
    calendarImplem.deleteEvent(
        eventId = "42",
        span = "allEvents",
        originalInstanceTime = null,
        callback = callback,
    )

    verify { contentResolver.delete(eventContentUri, "_id = ?", arrayOf("42")) }
}

@Test
fun `deleteEvent with thisEvent inserts STATUS_CANCELED exception row`() = runTest {
    mockPermissionGranted(permissionHandler)
    mockWritableCalendar(contentResolver, calendarContentUri)

    // mock getCalendarId and getEventDuration queries
    val calendarCursor = mockk<android.database.Cursor>(relaxed = true)
    every { calendarCursor.moveToFirst() } returns true
    every { calendarCursor.getString(0) } returns "1"  // calendarId
    every { contentResolver.query(eventContentUri, arrayOf(CalendarContract.Events.CALENDAR_ID), "_id = ?", arrayOf("42"), null) } returns calendarCursor

    val durationCursor = mockk<android.database.Cursor>(relaxed = true)
    every { durationCursor.moveToFirst() } returns true
    every { durationCursor.getLong(0) } returns 1751880000000L // DTSTART
    every { durationCursor.getLong(1) } returns 1751883600000L // DTEND
    every { contentResolver.query(eventContentUri, arrayOf(CalendarContract.Events.DTSTART, CalendarContract.Events.DTEND), "_id = ?", arrayOf("42"), null) } returns durationCursor

    val insertedValues = slot<ContentValues>()
    every { contentResolver.insert(eventContentUri, capture(insertedValues)) } returns
        android.net.Uri.parse("content://com.android.calendar/events/99")

    val callback = mockk<(Result<Unit>) -> Unit>(relaxed = true)
    calendarImplem.deleteEvent(
        eventId = "42",
        span = "thisEvent",
        originalInstanceTime = 1751880000000L,
        callback = callback,
    )

    assertEquals(42L, insertedValues.captured.getAsLong(CalendarContract.Events.ORIGINAL_ID))
    assertEquals(1751880000000L, insertedValues.captured.getAsLong(CalendarContract.Events.ORIGINAL_INSTANCE_TIME))
    assertEquals(CalendarContract.Events.STATUS_CANCELED, insertedValues.captured.getAsInteger(CalendarContract.Events.STATUS))
}

@Test
fun `deleteEvent with thisAndFuture patches master RRULE with UNTIL`() = runTest {
    mockPermissionGranted(permissionHandler)
    mockWritableCalendar(contentResolver, calendarContentUri)

    // mock fetch of master event RRULE
    val rruleCursor = mockk<android.database.Cursor>(relaxed = true)
    every { rruleCursor.moveToFirst() } returns true
    every { rruleCursor.getString(0) } returns "FREQ=WEEKLY;BYDAY=MO"
    every { contentResolver.query(eventContentUri, arrayOf(CalendarContract.Events.RRULE), "_id = ?", arrayOf("42"), null) } returns rruleCursor

    val updatedValues = slot<ContentValues>()
    every { contentResolver.update(eventContentUri, capture(updatedValues), "_id = ?", arrayOf("42")) } returns 1

    val callback = mockk<(Result<Unit>) -> Unit>(relaxed = true)
    calendarImplem.deleteEvent(
        eventId = "42",
        span = "thisAndFuture",
        originalInstanceTime = 1751880000000L,
        callback = callback,
    )

    val patchedRrule = updatedValues.captured.getAsString(CalendarContract.Events.RRULE)
    assert(patchedRrule.contains("UNTIL=")) { "Expected UNTIL in patched RRULE, got: $patchedRrule" }
    assert(!patchedRrule.contains("FREQ=WEEKLY;BYDAY=MO;UNTIL=").not()) // RRULE has expected prefix
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
./gradlew :eventide:test --tests "sncf.connect.tech.eventide.RecurrenceTests.deleteEvent*"
```

Expected: FAIL — span param not yet handled.

- [ ] **Step 3: Create `RecurrenceHelper.kt`**

```kotlin
package sncf.connect.tech.eventide

import android.content.ContentResolver
import android.net.Uri
import android.provider.CalendarContract
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

object RecurrenceHelper {

    private val untilFormatter = DateTimeFormatter
        .ofPattern("yyyyMMdd'T'HHmmss'Z'")
        .withZone(ZoneOffset.UTC)

    /**
     * Appends or replaces UNTIL in an RRULE string. Removes COUNT if present
     * (COUNT and UNTIL are mutually exclusive per RFC 5545).
     * [untilMs] is the exclusive upper bound in epoch milliseconds — the UNTIL
     * value is set to [untilMs] - 1ms so this instant is excluded from the series.
     */
    fun patchWithUntil(rrule: String, untilMs: Long): String {
        val untilInstant = Instant.ofEpochMilli(untilMs - 1)
        val untilStr = untilFormatter.format(untilInstant)
        val parts = rrule.split(";")
            .filter { !it.startsWith("UNTIL=") && !it.startsWith("COUNT=") }
        return (parts + "UNTIL=$untilStr").joinToString(";")
    }

    /**
     * Fetches the RRULE string of a master event from CalendarContract.Events.
     * Returns null if the event has no RRULE or is not found.
     */
    fun getMasterRrule(
        contentResolver: ContentResolver,
        eventContentUri: Uri,
        eventId: String,
    ): String? {
        contentResolver.query(
            eventContentUri,
            arrayOf(CalendarContract.Events.RRULE),
            "${CalendarContract.Events._ID} = ?",
            arrayOf(eventId),
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0)
        }
        return null
    }

    /**
     * Returns the duration (endDate - startDate) of a master event in milliseconds.
     */
    fun getMasterEventDurationMs(
        contentResolver: ContentResolver,
        eventContentUri: Uri,
        eventId: String,
    ): Long {
        contentResolver.query(
            eventContentUri,
            arrayOf(CalendarContract.Events.DTSTART, CalendarContract.Events.DTEND),
            "${CalendarContract.Events._ID} = ?",
            arrayOf(eventId),
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                return cursor.getLong(1) - cursor.getLong(0)
            }
        }
        return 3_600_000L // default 1h if not found
    }
}
```

- [ ] **Step 4: Update `deleteEvent` in `CalendarImplem.kt`**

The Pigeon interface now provides `span: String` and `originalInstanceTime: Long?`. Replace the current delete implementation with span-aware logic:

```kotlin
override fun deleteEvent(
    eventId: String,
    span: String,
    originalInstanceTime: Long?,
    callback: (Result<Unit>) -> Unit,
) {
    permissionHandler.checkCalendarAccessThenExecute(Permission.WRITE) {
        when (span) {
            "allEvents" -> deleteAllEvents(eventId, callback)
            "thisEvent" -> deleteThisEvent(eventId, originalInstanceTime!!, callback)
            "thisAndFuture" -> deleteThisAndFutureEvents(eventId, originalInstanceTime!!, callback)
            else -> deleteAllEvents(eventId, callback) // safe fallback
        }
    }
}

private fun deleteAllEvents(eventId: String, callback: (Result<Unit>) -> Unit) {
    // existing delete logic: contentResolver.delete by _id
    val deleted = contentResolver.delete(eventContentUri, "${CalendarContract.Events._ID} = ?", arrayOf(eventId))
    if (deleted == 0) callback(Result.failure(Exception("NOT_FOUND")))
    else callback(Result.success(Unit))
}

private fun deleteThisEvent(eventId: String, originalInstanceTime: Long, callback: (Result<Unit>) -> Unit) {
    val calendarId = getCalendarId(eventId) ?: run {
        callback(Result.failure(Exception("NOT_FOUND"))); return
    }
    val durationMs = RecurrenceHelper.getMasterEventDurationMs(contentResolver, eventContentUri, eventId)
    val values = ContentValues().apply {
        put(CalendarContract.Events.ORIGINAL_ID, eventId.toLong())
        put(CalendarContract.Events.ORIGINAL_INSTANCE_TIME, originalInstanceTime)
        put(CalendarContract.Events.DTSTART, originalInstanceTime)
        put(CalendarContract.Events.DTEND, originalInstanceTime + durationMs)
        put(CalendarContract.Events.STATUS, CalendarContract.Events.STATUS_CANCELED)
        put(CalendarContract.Events.CALENDAR_ID, calendarId.toLong())
        put(CalendarContract.Events.EVENT_TIMEZONE, "UTC")
    }
    contentResolver.insert(eventContentUri, values)
    callback(Result.success(Unit))
}

private fun deleteThisAndFutureEvents(eventId: String, originalInstanceTime: Long, callback: (Result<Unit>) -> Unit) {
    val rrule = RecurrenceHelper.getMasterRrule(contentResolver, eventContentUri, eventId) ?: run {
        // Non-recurring event: just delete it
        deleteAllEvents(eventId, callback); return
    }
    val patched = RecurrenceHelper.patchWithUntil(rrule, originalInstanceTime)
    val values = ContentValues().apply { put(CalendarContract.Events.RRULE, patched) }
    contentResolver.update(eventContentUri, values, "${CalendarContract.Events._ID} = ?", arrayOf(eventId))
    callback(Result.success(Unit))
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
./gradlew :eventide:test --tests "sncf.connect.tech.eventide.RecurrenceTests"
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add android/src/main/kotlin/sncf/connect/tech/eventide/RecurrenceHelper.kt \
  android/src/main/kotlin/sncf/connect/tech/eventide/CalendarImplem.kt \
  android/src/test/kotlin/sncf/connect/tech/eventide/RecurrenceTests.kt
git commit -m "feat(android): span-aware deleteEvent with RecurrenceHelper"
```

---

## Task 7: Android — updateEvent Span Logic

**Files:**
- Modify: `android/src/main/kotlin/sncf/connect/tech/eventide/CalendarImplem.kt`
- Modify: `android/src/test/kotlin/sncf/connect/tech/eventide/RecurrenceTests.kt`

**Interfaces:**
- Consumes: `RecurrenceHelper` from Task 6
- Produces: `updateEvent` supports all three spans

- [ ] **Step 1: Write failing tests**

Add to `RecurrenceTests.kt`:

```kotlin
@Test
fun `updateEvent with allEvents updates master event row`() = runTest {
    mockPermissionGranted(permissionHandler)
    mockWritableCalendar(contentResolver, calendarContentUri)

    val updatedValues = slot<ContentValues>()
    every {
        contentResolver.update(eventContentUri, capture(updatedValues), "_id = ?", arrayOf("42"))
    } returns 1

    // mock re-query after update (CalendarImplem re-fetches the event)
    Mocks.mockRetrieveEvents(contentResolver, eventContentUri, remindersContentUri, attendeesContentUri)

    val callback = mockk<(Result<sncf.connect.tech.eventide.Event>) -> Unit>(relaxed = true)
    calendarImplem.updateEvent(
        eventId = "42", calendarId = "1", title = "Updated Standup",
        startDate = 1751880000000L, endDate = 1751883600000L,
        isAllDay = false, description = null, url = null, location = null,
        reminders = null, recurrenceRule = "FREQ=WEEKLY;BYDAY=MO,WE",
        span = "allEvents", originalInstanceTime = null,
        callback = callback,
    )

    assertEquals("Updated Standup", updatedValues.captured.getAsString(CalendarContract.Events.TITLE))
    assertEquals("FREQ=WEEKLY;BYDAY=MO,WE", updatedValues.captured.getAsString(CalendarContract.Events.RRULE))
}

@Test
fun `updateEvent with thisAndFuture splits series at originalInstanceTime`() = runTest {
    mockPermissionGranted(permissionHandler)
    mockWritableCalendar(contentResolver, calendarContentUri)

    // mock fetch of master RRULE
    val rruleCursor = mockk<android.database.Cursor>(relaxed = true)
    every { rruleCursor.moveToFirst() } returns true
    every { rruleCursor.getString(0) } returns "FREQ=WEEKLY;BYDAY=MO"
    every { contentResolver.query(eventContentUri, arrayOf(CalendarContract.Events.RRULE), "_id = ?", arrayOf("42"), null) } returns rruleCursor

    val updateValues = slot<ContentValues>()
    every { contentResolver.update(eventContentUri, capture(updateValues), "_id = ?", arrayOf("42")) } returns 1

    val insertValues = slot<ContentValues>()
    every { contentResolver.insert(eventContentUri, capture(insertValues)) } returns
        android.net.Uri.parse("content://com.android.calendar/events/99")
    every { contentResolver.insert(remindersContentUri, any()) } returns null

    Mocks.mockRetrieveEvents(contentResolver, eventContentUri, remindersContentUri, attendeesContentUri)

    val callback = mockk<(Result<sncf.connect.tech.eventide.Event>) -> Unit>(relaxed = true)
    calendarImplem.updateEvent(
        eventId = "42", calendarId = "1", title = "Updated Standup",
        startDate = 1751880000000L, endDate = 1751883600000L,
        isAllDay = false, description = null, url = null, location = null,
        reminders = null, recurrenceRule = "FREQ=WEEKLY;BYDAY=MO,WE",
        span = "thisAndFuture", originalInstanceTime = 1751880000000L,
        callback = callback,
    )

    // Master event should be truncated with UNTIL
    assert(updateValues.captured.getAsString(CalendarContract.Events.RRULE).contains("UNTIL="))
    // New series should have the new RRULE
    assertEquals("FREQ=WEEKLY;BYDAY=MO,WE", insertValues.captured.getAsString(CalendarContract.Events.RRULE))
    assertEquals(1751880000000L, insertValues.captured.getAsLong(CalendarContract.Events.DTSTART))
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
./gradlew :eventide:test --tests "sncf.connect.tech.eventide.RecurrenceTests.updateEvent*"
```

Expected: FAIL.

- [ ] **Step 3: Update `updateEvent` in `CalendarImplem.kt`**

The Pigeon interface now provides `recurrenceRule: String?`, `span: String`, `originalInstanceTime: Long?`. Add span-based branching:

```kotlin
override fun updateEvent(
    eventId: String, calendarId: String, title: String,
    startDate: Long, endDate: Long, isAllDay: Boolean,
    description: String?, url: String?, location: String?,
    reminders: List<Long>?, recurrenceRule: String?,
    span: String, originalInstanceTime: Long?,
    callback: (Result<Event>) -> Unit,
) {
    permissionHandler.checkCalendarAccessThenExecute(Permission.WRITE) {
        when (span) {
            "thisEvent" -> updateThisEvent(
                eventId, calendarId, title, startDate, endDate, isAllDay,
                description, url, location, reminders, recurrenceRule,
                originalInstanceTime!!, callback,
            )
            "thisAndFuture" -> updateThisAndFutureEvents(
                eventId, calendarId, title, startDate, endDate, isAllDay,
                description, url, location, reminders, recurrenceRule,
                originalInstanceTime!!, callback,
            )
            else -> updateAllEvents( // "allEvents" and fallback
                eventId, calendarId, title, startDate, endDate, isAllDay,
                description, url, location, reminders, recurrenceRule, callback,
            )
        }
    }
}

private fun updateAllEvents(
    eventId: String, calendarId: String, title: String,
    startDate: Long, endDate: Long, isAllDay: Boolean,
    description: String?, url: String?, location: String?,
    reminders: List<Long>?, recurrenceRule: String?,
    callback: (Result<Event>) -> Unit,
) {
    // existing updateEvent logic + add RRULE to ContentValues
    val mergedDescription = DescriptionUrlHelper.mergeDescriptionAndUrl(description, null)
    val values = ContentValues().apply {
        put(CalendarContract.Events.TITLE, title)
        put(CalendarContract.Events.DTSTART, startDate)
        put(CalendarContract.Events.DTEND, endDate)
        put(CalendarContract.Events.ALL_DAY, if (isAllDay) 1 else 0)
        put(CalendarContract.Events.DESCRIPTION, mergedDescription)
        put(CalendarContract.Events.EVENT_LOCATION, location)
        if (recurrenceRule != null) put(CalendarContract.Events.RRULE, recurrenceRule)
    }
    contentResolver.update(eventContentUri, values, "${CalendarContract.Events._ID} = ?", arrayOf(eventId))
    // re-fetch and return event (existing pattern)
    retrieveUpdatedEvent(eventId, callback)
}

private fun updateThisEvent(
    eventId: String, calendarId: String, title: String,
    startDate: Long, endDate: Long, isAllDay: Boolean,
    description: String?, url: String?, location: String?,
    reminders: List<Long>?, recurrenceRule: String?,
    originalInstanceTime: Long, callback: (Result<Event>) -> Unit,
) {
    val mergedDescription = DescriptionUrlHelper.mergeDescriptionAndUrl(description, null)
    val values = ContentValues().apply {
        put(CalendarContract.Events.ORIGINAL_ID, eventId.toLong())
        put(CalendarContract.Events.ORIGINAL_INSTANCE_TIME, originalInstanceTime)
        put(CalendarContract.Events.DTSTART, startDate)
        put(CalendarContract.Events.DTEND, endDate)
        put(CalendarContract.Events.ALL_DAY, if (isAllDay) 1 else 0)
        put(CalendarContract.Events.TITLE, title)
        put(CalendarContract.Events.DESCRIPTION, mergedDescription)
        put(CalendarContract.Events.EVENT_LOCATION, location)
        put(CalendarContract.Events.CALENDAR_ID, calendarId.toLong())
        put(CalendarContract.Events.EVENT_TIMEZONE, "UTC")
        put(CalendarContract.Events.STATUS, CalendarContract.Events.STATUS_CONFIRMED)
    }
    val uri = contentResolver.insert(eventContentUri, values)
    val newId = uri?.lastPathSegment ?: eventId
    retrieveUpdatedEvent(newId, callback)
}

private fun updateThisAndFutureEvents(
    eventId: String, calendarId: String, title: String,
    startDate: Long, endDate: Long, isAllDay: Boolean,
    description: String?, url: String?, location: String?,
    reminders: List<Long>?, recurrenceRule: String?,
    originalInstanceTime: Long, callback: (Result<Event>) -> Unit,
) {
    // 1. Truncate master series with UNTIL
    val existingRrule = RecurrenceHelper.getMasterRrule(contentResolver, eventContentUri, eventId)
    if (existingRrule != null) {
        val patchedRrule = RecurrenceHelper.patchWithUntil(existingRrule, originalInstanceTime)
        val truncateValues = ContentValues().apply { put(CalendarContract.Events.RRULE, patchedRrule) }
        contentResolver.update(eventContentUri, truncateValues, "${CalendarContract.Events._ID} = ?", arrayOf(eventId))
    }
    // 2. Insert new series starting at originalInstanceTime
    val newRrule = recurrenceRule
        ?: existingRrule?.split(";")
            ?.filter { !it.startsWith("UNTIL=") && !it.startsWith("COUNT=") }
            ?.joinToString(";")
    val duration = endDate - startDate
    val mergedDescription = DescriptionUrlHelper.mergeDescriptionAndUrl(description, null)
    val insertValues = ContentValues().apply {
        put(CalendarContract.Events.CALENDAR_ID, calendarId.toLong())
        put(CalendarContract.Events.TITLE, title)
        put(CalendarContract.Events.DTSTART, originalInstanceTime)
        put(CalendarContract.Events.DTEND, originalInstanceTime + duration)
        put(CalendarContract.Events.ALL_DAY, if (isAllDay) 1 else 0)
        put(CalendarContract.Events.DESCRIPTION, mergedDescription)
        put(CalendarContract.Events.EVENT_LOCATION, location)
        put(CalendarContract.Events.EVENT_TIMEZONE, "UTC")
        if (newRrule != null) put(CalendarContract.Events.RRULE, newRrule)
    }
    val uri = contentResolver.insert(eventContentUri, insertValues)
    val newId = uri?.lastPathSegment ?: eventId
    insertReminders(newId, reminders)
    retrieveUpdatedEvent(newId, callback)
}
```

Note: `retrieveUpdatedEvent` is a private helper that re-fetches the event by ID and calls the callback (implement following the existing pattern in CalendarImplem).

- [ ] **Step 4: Run all Android tests**

```bash
./gradlew :eventide:test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add android/src/main/kotlin/sncf/connect/tech/eventide/CalendarImplem.kt \
  android/src/test/kotlin/sncf/connect/tech/eventide/RecurrenceTests.kt
git commit -m "feat(android): span-aware updateEvent"
```

---

## Task 8: Android — ICS Generator RRULE

**Files:**
- Modify: `android/src/main/kotlin/sncf/connect/tech/eventide/handler/IcsEventManager.kt`
- Modify: `android/src/test/kotlin/sncf/connect/tech/eventide/IcsEventManagerTest.kt`

**Interfaces:**
- Produces: `generateIcsContent(...)` includes `RRULE:` line when recurrenceRule is non-null

- [ ] **Step 1: Write failing test**

Add to `IcsEventManagerTest.kt`:

```kotlin
@Test
fun `generateIcsContent includes RRULE line when recurrenceRule is provided`() {
    val ics = IcsEventManager.generateIcsContent(
        title = "Standup",
        startDate = 1751880000000L,
        endDate = 1751883600000L,
        isAllDay = false,
        description = null,
        location = null,
        reminders = emptyList(),
        recurrenceRule = "FREQ=WEEKLY;BYDAY=MO",
    )
    assert(ics.contains("RRULE:FREQ=WEEKLY;BYDAY=MO")) { "Expected RRULE line, got:\n$ics" }
}

@Test
fun `generateIcsContent omits RRULE line when recurrenceRule is null`() {
    val ics = IcsEventManager.generateIcsContent(
        title = "Standup",
        startDate = 1751880000000L,
        endDate = 1751883600000L,
        isAllDay = false,
        description = null,
        location = null,
        reminders = emptyList(),
        recurrenceRule = null,
    )
    assert(!ics.contains("RRULE:")) { "Expected no RRULE line, got:\n$ics" }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
./gradlew :eventide:test --tests "sncf.connect.tech.eventide.IcsEventManagerTest"
```

Expected: compile error — `recurrenceRule` param not yet on `generateIcsContent`.

- [ ] **Step 3: Update `IcsEventManager.generateIcsContent`**

Add `recurrenceRule: String?` to the function signature and insert the RRULE line inside the VEVENT block, after `DTEND`:

```kotlin
if (recurrenceRule != null) {
    append("RRULE:${recurrenceRule}\r\n")
}
```

Also update all call sites in `CalendarImplem.kt` (the two methods that call `icsEventManager.generateIcsContent(...)`) to pass `recurrenceRule`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
./gradlew :eventide:test
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add android/src/main/kotlin/sncf/connect/tech/eventide/handler/IcsEventManager.kt \
  android/src/main/kotlin/sncf/connect/tech/eventide/CalendarImplem.kt \
  android/src/test/kotlin/sncf/connect/tech/eventide/IcsEventManagerTest.kt
git commit -m "feat(android): add RRULE to ICS generator"
```

---

## Task 9: iOS — RRuleParser + RRuleSerializer

**Files:**
- Create: `ios/eventide/Sources/eventide/RRuleParser.swift`
- Create: `ios/eventide/Sources/eventide/RRuleSerializer.swift`
- Create: `ios/eventide/Tests/eventide/RRuleParserTests.swift`

**Interfaces:**
- Produces: `RRuleParser.parse(_ rrule: String) -> EKRecurrenceRule?`; `RRuleSerializer.serialize(_ rule: EKRecurrenceRule) -> String`

- [ ] **Step 1: Write failing tests**

Create `ios/eventide/Tests/eventide/RRuleParserTests.swift`:

```swift
import XCTest
import EventKit
@testable import eventide

final class RRuleParserTests: XCTestCase {

    // MARK: - Parser tests

    func testParseDailyFreq() {
        let rule = RRuleParser.parse("FREQ=DAILY")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.frequency, .daily)
        XCTAssertEqual(rule?.interval, 1)
    }

    func testParseWeeklyWithByday() {
        let rule = RRuleParser.parse("FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.frequency, .weekly)
        XCTAssertEqual(rule?.interval, 2)
        let days = rule?.daysOfTheWeek?.map { $0.dayOfTheWeek } ?? []
        XCTAssertTrue(days.contains(.monday))
        XCTAssertTrue(days.contains(.wednesday))
        XCTAssertTrue(days.contains(.friday))
    }

    func testParseMonthly() {
        let rule = RRuleParser.parse("FREQ=MONTHLY;INTERVAL=1")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.frequency, .monthly)
    }

    func testParseYearly() {
        let rule = RRuleParser.parse("FREQ=YEARLY")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.frequency, .yearly)
    }

    func testParseCount() {
        let rule = RRuleParser.parse("FREQ=DAILY;COUNT=10")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.recurrenceEnd?.occurrenceCount, 10)
    }

    func testParseUntilDatetime() {
        let rule = RRuleParser.parse("FREQ=DAILY;UNTIL=20261231T235959Z")
        XCTAssertNotNil(rule)
        XCTAssertNotNil(rule?.recurrenceEnd?.endDate)
    }

    func testParseUntilDate() {
        let rule = RRuleParser.parse("FREQ=DAILY;UNTIL=20261231")
        XCTAssertNotNil(rule)
        XCTAssertNotNil(rule?.recurrenceEnd?.endDate)
    }

    func testUnsupportedPropertySilentlyDropped() {
        // BYYEARDAY is unsupported; parser should still return a rule for the supported parts
        let rule = RRuleParser.parse("FREQ=YEARLY;BYYEARDAY=100")
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.frequency, .yearly)
    }

    func testInvalidFreqReturnsNil() {
        let rule = RRuleParser.parse("FREQ=HOURLY")
        XCTAssertNil(rule)
    }

    // MARK: - Serializer tests

    func testSerializeDaily() {
        let rule = EKRecurrenceRule(
            recurrenceWith: .daily, interval: 1,
            daysOfTheWeek: nil, daysOfTheMonth: nil,
            monthsOfTheYear: nil, weeksOfTheYear: nil,
            daysOfTheYear: nil, setPositions: nil, end: nil
        )
        let rrule = RRuleSerializer.serialize(rule)
        XCTAssertEqual(rrule, "FREQ=DAILY")
    }

    func testSerializeWeeklyWithDays() {
        let rule = EKRecurrenceRule(
            recurrenceWith: .weekly, interval: 1,
            daysOfTheWeek: [
                EKRecurrenceDayOfWeek(.monday),
                EKRecurrenceDayOfWeek(.wednesday),
            ],
            daysOfTheMonth: nil, monthsOfTheYear: nil,
            weeksOfTheYear: nil, daysOfTheYear: nil,
            setPositions: nil, end: nil
        )
        let rrule = RRuleSerializer.serialize(rule)
        XCTAssertTrue(rrule.contains("FREQ=WEEKLY"))
        XCTAssertTrue(rrule.contains("BYDAY="))
        XCTAssertTrue(rrule.contains("MO"))
        XCTAssertTrue(rrule.contains("WE"))
    }

    func testSerializeWithCount() {
        let rule = EKRecurrenceRule(
            recurrenceWith: .daily, interval: 1,
            daysOfTheWeek: nil, daysOfTheMonth: nil,
            monthsOfTheYear: nil, weeksOfTheYear: nil,
            daysOfTheYear: nil, setPositions: nil,
            end: EKRecurrenceEnd(occurrenceCount: 5)
        )
        let rrule = RRuleSerializer.serialize(rule)
        XCTAssertTrue(rrule.contains("COUNT=5"))
    }

    // MARK: - Round-trip tests

    func testRoundTripWeekly() {
        let original = "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,FR"
        guard let rule = RRuleParser.parse(original) else {
            return XCTFail("Parse returned nil")
        }
        let serialized = RRuleSerializer.serialize(rule)
        // Re-parse to verify the round-trip is semantically equivalent
        let reparsed = RRuleParser.parse(serialized)
        XCTAssertEqual(reparsed?.frequency, rule.frequency)
        XCTAssertEqual(reparsed?.interval, rule.interval)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test \
  -workspace ios/eventide.xcworkspace \
  -scheme eventide \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  2>&1 | tail -20
```

Expected: compile error — `RRuleParser` and `RRuleSerializer` don't exist yet.

- [ ] **Step 3: Create `RRuleParser.swift`**

```swift
// ios/eventide/Sources/eventide/RRuleParser.swift

import EventKit

struct RRuleParser {
    static func parse(_ rrule: String) -> EKRecurrenceRule? {
        var frequency: EKRecurrenceFrequency?
        var interval = 1
        var daysOfWeek: [EKRecurrenceDayOfWeek]?
        var daysOfMonth: [NSNumber]?
        var monthsOfYear: [NSNumber]?
        var end: EKRecurrenceEnd?

        for component in rrule.components(separatedBy: ";") {
            let parts = component.components(separatedBy: "=")
            guard parts.count == 2 else { continue }
            let key = parts[0].uppercased()
            let value = parts[1]

            switch key {
            case "FREQ":
                frequency = parseFrequency(value)
            case "INTERVAL":
                interval = Int(value) ?? 1
            case "BYDAY":
                daysOfWeek = parseDaysOfWeek(value)
            case "BYMONTHDAY":
                daysOfMonth = value.components(separatedBy: ",")
                    .compactMap { Int($0) as NSNumber? }
            case "BYMONTH":
                monthsOfYear = value.components(separatedBy: ",")
                    .compactMap { Int($0) as NSNumber? }
            case "COUNT":
                if let count = Int(value) {
                    end = EKRecurrenceEnd(occurrenceCount: count)
                }
            case "UNTIL":
                if let date = parseUntilDate(value) {
                    end = EKRecurrenceEnd(end: date)
                }
            default:
                break // unsupported property silently dropped
            }
        }

        guard let freq = frequency else { return nil }

        return EKRecurrenceRule(
            recurrenceWith: freq,
            interval: interval,
            daysOfTheWeek: daysOfWeek,
            daysOfTheMonth: daysOfMonth,
            monthsOfTheYear: monthsOfYear,
            weeksOfTheYear: nil,
            daysOfTheYear: nil,
            setPositions: nil,
            end: end
        )
    }

    private static func parseFrequency(_ value: String) -> EKRecurrenceFrequency? {
        switch value.uppercased() {
        case "DAILY":   return .daily
        case "WEEKLY":  return .weekly
        case "MONTHLY": return .monthly
        case "YEARLY":  return .yearly
        default:        return nil
        }
    }

    private static func parseDaysOfWeek(_ value: String) -> [EKRecurrenceDayOfWeek] {
        let dayMap: [String: EKWeekday] = [
            "SU": .sunday, "MO": .monday, "TU": .tuesday,
            "WE": .wednesday, "TH": .thursday, "FR": .friday, "SA": .saturday,
        ]
        return value.components(separatedBy: ",").compactMap { token in
            guard token.count >= 2 else { return nil }
            let dayKey = String(token.suffix(2)).uppercased()
            let prefix = String(token.dropLast(2))
            let weekNumber = Int(prefix) ?? 0
            guard let weekday = dayMap[dayKey] else { return nil }
            return EKRecurrenceDayOfWeek(weekday, weekNumber: weekNumber)
        }
    }

    private static func parseUntilDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        if let date = formatter.date(from: value) { return date }
        formatter.dateFormat = "yyyyMMdd"
        return formatter.date(from: value)
    }
}
```

- [ ] **Step 4: Create `RRuleSerializer.swift`**

```swift
// ios/eventide/Sources/eventide/RRuleSerializer.swift

import EventKit

struct RRuleSerializer {
    static func serialize(_ rule: EKRecurrenceRule) -> String {
        var parts: [String] = ["FREQ=\(serializeFrequency(rule.frequency))"]

        if rule.interval > 1 {
            parts.append("INTERVAL=\(rule.interval)")
        }

        if let days = rule.daysOfTheWeek, !days.isEmpty {
            let dayStrings = days.map { day -> String in
                let abbr = serializeWeekday(day.dayOfTheWeek)
                return day.weekNumber != 0 ? "\(day.weekNumber)\(abbr)" : abbr
            }.sorted() // deterministic output
            parts.append("BYDAY=\(dayStrings.joined(separator: ","))")
        }

        if let days = rule.daysOfTheMonth, !days.isEmpty {
            parts.append("BYMONTHDAY=\(days.map { "\($0)" }.joined(separator: ","))")
        }

        if let months = rule.monthsOfTheYear, !months.isEmpty {
            parts.append("BYMONTH=\(months.map { "\($0)" }.joined(separator: ","))")
        }

        if let recEnd = rule.recurrenceEnd {
            if recEnd.occurrenceCount > 0 {
                parts.append("COUNT=\(recEnd.occurrenceCount)")
            } else if let endDate = recEnd.endDate {
                let formatter = DateFormatter()
                formatter.timeZone = TimeZone(identifier: "UTC")
                formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
                parts.append("UNTIL=\(formatter.string(from: endDate))")
            }
        }

        return parts.joined(separator: ";")
    }

    private static func serializeFrequency(_ freq: EKRecurrenceFrequency) -> String {
        switch freq {
        case .daily:   return "DAILY"
        case .weekly:  return "WEEKLY"
        case .monthly: return "MONTHLY"
        case .yearly:  return "YEARLY"
        @unknown default: return "DAILY"
        }
    }

    private static func serializeWeekday(_ weekday: EKWeekday) -> String {
        switch weekday {
        case .sunday:    return "SU"
        case .monday:    return "MO"
        case .tuesday:   return "TU"
        case .wednesday: return "WE"
        case .thursday:  return "TH"
        case .friday:    return "FR"
        case .saturday:  return "SA"
        @unknown default: return "MO"
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild test \
  -workspace ios/eventide.xcworkspace \
  -scheme eventide \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:eventideTests/RRuleParserTests \
  2>&1 | tail -20
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add ios/eventide/Sources/eventide/RRuleParser.swift \
  ios/eventide/Sources/eventide/RRuleSerializer.swift \
  ios/eventide/Tests/eventide/RRuleParserTests.swift
git commit -m "feat(ios): add RRuleParser and RRuleSerializer"
```

---

## Task 10: iOS — createEvent, createEventInDefaultCalendar, createEventThroughNativePlatform

**Files:**
- Modify: `ios/eventide/Sources/eventide/EasyEventStore/EasyEventStore.swift`
- Modify: `ios/eventide/Sources/eventide/CalendarImplem.swift`

**Interfaces:**
- Consumes: `RRuleParser` from Task 9; updated `CalendarApi.g.swift` from Task 1

- [ ] **Step 1: Update `EasyEventStore.swift` — `createEvent(calendarId:...)`**

In the method that creates a specific-calendar event, add after the existing field assignments and before `eventStore.save(...)`:

```swift
if let rrule = recurrenceRule,
   let ekRule = RRuleParser.parse(rrule) {
    ekEvent.recurrenceRules = [ekRule]
}
```

Update the method signature to accept `recurrenceRule: String?`.

- [ ] **Step 2: Update `EasyEventStore.swift` — `createEvent(title:...)` (default calendar)**

Same change — add `recurrenceRule: String?` param and apply the same `RRuleParser.parse` block.

- [ ] **Step 3: Update `EasyEventStore.swift` — `presentEventCreationViewController`**

Add `recurrenceRule: String?` param. Apply the same `RRuleParser.parse` block to the EKEvent **before** it is passed to `EventEditViewControllerManager`. The user will see the recurrence pre-populated in the native UI and can modify or clear it.

- [ ] **Step 4: Update `CalendarImplem.swift`**

`CalendarImplem` delegates to `EasyEventStore`. The Pigeon-generated `CalendarApi.g.swift` already passes `recurrenceRule` through. Update all three `CalendarImplem` methods that call `EasyEventStore` to forward the `recurrenceRule` param.

- [ ] **Step 5: Verify compilation**

```bash
xcodebuild build \
  -workspace ios/eventide.xcworkspace \
  -scheme eventide \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  2>&1 | tail -20
```

Expected: builds cleanly.

- [ ] **Step 6: Commit**

```bash
git add ios/eventide/Sources/eventide/EasyEventStore/EasyEventStore.swift \
  ios/eventide/Sources/eventide/CalendarImplem.swift
git commit -m "feat(ios): set recurrenceRules on createEvent, createDefaultEvent, presentEventCreationVC"
```

---

## Task 11: iOS — retrieveEvents

**Files:**
- Modify: `ios/eventide/Sources/eventide/EasyEventStore/EasyEventStore.swift`

**Interfaces:**
- Produces: returned `Event` objects include `recurrenceRule` and `originalInstanceTime`

- [ ] **Step 1: Update `EKEvent.toEvent()` extension in `EasyEventStore.swift`**

Find the `extension EKEvent` block containing `toEvent()`. Add two new field mappings:

```swift
// Serialize the first recurrence rule back to an RRULE string
let recurrenceRule: String? = self.recurrenceRules?.first.map { RRuleSerializer.serialize($0) }

// originalInstanceTime: the occurrence date of this specific instance (nil for master/non-recurring)
let originalInstanceTime: Int64? = self.occurrenceDate.map { Int64($0.timeIntervalSince1970 * 1000) }
```

Add these to the `Event(...)` constructor call:
```swift
Event(
    // ... existing fields ...
    recurrenceRule: recurrenceRule,
    originalInstanceTime: originalInstanceTime,
)
```

The `Event` constructor now requires these two fields (from the regenerated Pigeon stub in Task 1).

- [ ] **Step 2: Verify compilation and existing tests pass**

```bash
xcodebuild test \
  -workspace ios/eventide.xcworkspace \
  -scheme eventide \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  2>&1 | tail -30
```

Expected: all tests pass. Verify `recurrenceRule` and `originalInstanceTime` fields are populated in the test output if running against a device with recurring events.

- [ ] **Step 3: Commit**

```bash
git add ios/eventide/Sources/eventide/EasyEventStore/EasyEventStore.swift
git commit -m "feat(ios): populate recurrenceRule and originalInstanceTime on retrieved events"
```

---

## Task 12: iOS — deleteEvent + updateEvent Span Logic

**Files:**
- Modify: `ios/eventide/Sources/eventide/EasyEventStore/EasyEventStore.swift`
- Modify: `ios/eventide/Sources/eventide/CalendarImplem.swift`

**Interfaces:**
- Consumes: `ETSpan` string values `"thisEvent"`, `"thisAndFuture"`, `"allEvents"`
- Produces: `deleteEvent` and `updateEvent` respect span and originalInstanceTime

- [ ] **Step 1: Add a private occurrence-fetching helper in `EasyEventStore.swift`**

```swift
/// Fetches the specific EKEvent occurrence for [eventId] whose occurrenceDate
/// matches [originalInstanceTime] (within a 1-second tolerance).
private func findOccurrence(eventId: String, originalInstanceTimeMs: Int64) -> EKEvent? {
    let targetDate = Date(timeIntervalSince1970: Double(originalInstanceTimeMs) / 1000.0)
    let predicate = eventStore.predicateForEvents(
        withStart: targetDate.addingTimeInterval(-1),
        end: targetDate.addingTimeInterval(86401), // search 1 day window
        calendars: nil
    )
    return eventStore.events(matching: predicate).first {
        $0.eventIdentifier == eventId &&
        abs($0.occurrenceDate.timeIntervalSince(targetDate)) < 1.0
    }
}
```

- [ ] **Step 2: Update `deleteEvent` in `EasyEventStore.swift`**

Current signature: `func deleteEvent(eventId: String) throws`. Update to:
```swift
func deleteEvent(eventId: String, span: String, originalInstanceTime: Int64?) throws
```

Implementation:
```swift
func deleteEvent(eventId: String, span: String, originalInstanceTime: Int64?) throws {
    switch span {
    case "allEvents":
        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw EventideError.notFound
        }
        try eventStore.remove(event, span: .thisEvent, commit: true)

    case "thisEvent":
        guard let instanceTime = originalInstanceTime,
              let occurrence = findOccurrence(eventId: eventId, originalInstanceTimeMs: instanceTime)
        else { throw EventideError.notFound }
        try eventStore.remove(occurrence, span: .thisEvent, commit: true)

    case "thisAndFuture":
        guard let instanceTime = originalInstanceTime,
              let occurrence = findOccurrence(eventId: eventId, originalInstanceTimeMs: instanceTime)
        else { throw EventideError.notFound }
        try eventStore.remove(occurrence, span: .futureEvents, commit: true)

    default: // treat unknown spans as allEvents
        guard let event = eventStore.event(withIdentifier: eventId) else {
            throw EventideError.notFound
        }
        try eventStore.remove(event, span: .thisEvent, commit: true)
    }
}
```

- [ ] **Step 3: Update `updateEvent` in `EasyEventStore.swift`**

Add `recurrenceRule: String?`, `span: String`, and `originalInstanceTime: Int64?` parameters. Add span branching:

```swift
func updateEvent(
    eventId: String, calendarId: String?, title: String?,
    startDate: Date?, endDate: Date?, isAllDay: Bool?,
    notes: String?, url: URL?, location: String?,
    alarms: [TimeInterval]?, recurrenceRule: String?,
    span: String, originalInstanceTime: Int64?
) throws -> EKEvent {
    let ekEvent: EKEvent
    switch span {
    case "thisEvent", "thisAndFuture":
        guard let instanceTime = originalInstanceTime,
              let occurrence = findOccurrence(eventId: eventId, originalInstanceTimeMs: instanceTime)
        else { throw EventideError.notFound }
        ekEvent = occurrence

    default: // "allEvents"
        guard let master = eventStore.event(withIdentifier: eventId) else {
            throw EventideError.notFound
        }
        ekEvent = master
    }

    // Apply field updates (existing pattern)
    if let title = title { ekEvent.title = title }
    if let startDate = startDate { ekEvent.startDate = startDate }
    if let endDate = endDate { ekEvent.endDate = endDate }
    if let isAllDay = isAllDay { ekEvent.isAllDay = isAllDay }
    if let notes = notes { ekEvent.notes = notes }
    if let url = url { ekEvent.url = url }
    if let location = location { ekEvent.location = location }
    if let alarms = alarms { ekEvent.alarms = alarms.map { EKAlarm(relativeOffset: $0) } }
    if let rrule = recurrenceRule, let ekRule = RRuleParser.parse(rrule) {
        ekEvent.recurrenceRules = [ekRule]
    }

    let ekSpan: EKSpan = span == "thisAndFuture" ? .futureEvents : .thisEvent
    try eventStore.save(ekEvent, span: ekSpan, commit: true)
    return ekEvent
}
```

- [ ] **Step 4: Update `CalendarImplem.swift`**

Forward the new `span` and `originalInstanceTime` params from the Pigeon method implementations to the `EasyEventStore` calls for `deleteEvent` and `updateEvent`.

- [ ] **Step 5: Run full iOS test suite**

```bash
xcodebuild test \
  -workspace ios/eventide.xcworkspace \
  -scheme eventide \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  2>&1 | tail -30
```

Expected: all tests pass.

- [ ] **Step 6: Run full Dart test suite one final time**

```bash
flutter test
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add ios/eventide/Sources/eventide/EasyEventStore/EasyEventStore.swift \
  ios/eventide/Sources/eventide/CalendarImplem.swift
git commit -m "feat(ios): span-aware deleteEvent and updateEvent"
```

---

## Self-Review Checklist

All spec requirements are covered:

| Spec requirement | Task |
|-----------------|------|
| `createEvent` accepts `recurrenceRule` | Tasks 1, 3, 4, 10 |
| `createEventInDefaultCalendar` accepts `recurrenceRule` | Tasks 1, 3, 8, 10 |
| `createEventThroughNativePlatform` accepts `recurrenceRule` | Tasks 1, 3, 10 |
| `retrieveEvents` returns expanded instances with `recurrenceRule` + `originalInstanceTime` | Tasks 5, 11 |
| `deleteEvent` supports `ETSpan.thisEvent` | Tasks 6, 12 |
| `deleteEvent` supports `ETSpan.thisAndFuture` | Tasks 6, 12 |
| `deleteEvent` supports `ETSpan.allEvents` | Tasks 6, 12 |
| `updateEvent` supports all three spans | Tasks 7, 12 |
| `ETSpan` default is `thisEvent` | Task 3 |
| ICS generator includes RRULE | Task 8 |
| iOS RRuleParser handles FREQ/INTERVAL/BYDAY/BYMONTHDAY/BYMONTH/COUNT/UNTIL | Task 9 |
| UNTIL formatted as `YYYYMMDDTHHMMSSZ` when patching RRULE | Task 6 (`RecurrenceHelper`) |
| iOS `createEventThroughNativePlatform` pre-populates recurrence | Task 10 |
