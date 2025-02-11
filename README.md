# Eventide

[![Flutter Tests](https://github.com/sncf-connect-tech/eventide/actions/workflows/flutter.yml/badge.svg)](https://github.com/sncf-connect-tech/eventide/actions/workflows/flutter.yml)
[![Android Tests](https://github.com/sncf-connect-tech/eventide/actions/workflows/android.yml/badge.svg)](https://github.com/sncf-connect-tech/eventide/actions/workflows/android.yml)
[![iOS Tests](https://github.com/sncf-connect-tech/eventide/actions/workflows/ios.yml/badge.svg)](https://github.com/sncf-connect-tech/eventide/actions/workflows/ios.yml)

Eventide provides a easy-to-use flutter interface to access & modify native device calendars (iOS & Android).

## Features
* Automatic permission handling (you can still ask for permissions manually if you want to request early at runtime)
* Add/retrieve/delete calendars
* Add/retrieve/delete events
    NOTE: Eventide handles timezones as UTC. It's up to the developer to make sure he sends the right data with a [timezone aware DateTime class](https://pub.dev/packages/timezone).
* Add/delete reminders
* Custom exceptions

## Work in progress
* Recurring events
* Attendees

## Getting Started

### Android

Nothing to add on your side. All is already declared in eventide's AndroidManifest.xml

### iOS

To read/write calendar data, your app must include the following permissions in its info.plist file.

```xml
<key>NSCalendarsUsageDescription</key>
<string>We need access to your calendar to add information about your trip.</string>
<key>NSCalendarsFullAccessUsageDescription</key>
<string>We need access to your calendar to add information about your trip.</string>
<key>NSCalendarsWriteOnlyAccessUsageDescription</key>
<string>We need access to your calendar to add information about your trip.</string>
```

## Usage Example

```dart
import 'package:eventide/eventide.dart';

final eventide = Eventide();

final calendar = await eventide.createCalendar('Work', Colors.red);

final event = await eventide.createEvent(
    calendarId: calendar.id,
    title: 'Meeting',
    startDate: DateTime.now(),
    endDate: DateTime.now().add(Duration(hours: 1)),
);

final updatedEvent = await eventide.addReminder(
    durationBeforeEvent: Duration(minutes: 15),
    eventId: event.id,
);
```

## License

Copyright © 2025 SNCF Connect & Tech. This project is licensed under the MIT License - see the LICENSE file for details.
