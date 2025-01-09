# Flutter Calendar Connect ⚠️ work in progress ⚠️

A Flutter plugin to access & modify native calendars on user's device (iOS & Android).

This plugin allows you to create, read and delete calendars, events and reminders. It handles timezones as UTC.

## Getting Started

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

### Android

To read/write calendar data, your app must include the READ_CALENDAR permission in its manifest file. It must include the WRITE_CALENDAR permission to delete, insert or update calendar data:

```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"...>
    <uses-sdk android:minSdkVersion="14" />
    <uses-permission android:name="android.permission.READ_CALENDAR" />
    <uses-permission android:name="android.permission.WRITE_CALENDAR" />
    ...
</manifest>
```

## Contribute

### Build with pigeon

We use [pigeon](https://pub.dev/packages/pigeon) to make communication between Flutter and host platforms easier.

Run the following command from project root to build boilerplate code with pigeon:

```sh
fvm dart pub run pigeon --input ./lib/src/pigeon/calendar_api.dart
```

## License

Copyright © 2025 SNCF Connect & Tech. This project is licensed under the MIT License - see the LICENSE file for details.
