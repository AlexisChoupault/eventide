import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart';

import 'package:eventide/eventide.dart';
import 'package:eventide/src/calendar_api.g.dart';
import 'package:eventide/src/extensions/event_extensions.dart';

class _MockCalendarApi extends Mock implements CalendarApi {}

// Helpers
Event _makeEvent({
  String id = '1',
  String title = 'Event',
  bool isAllDay = false,
  required int startDate,
  required int endDate,
  String calendarId = '1',
}) => Event(
  id: id,
  title: title,
  isAllDay: isAllDay,
  startDate: startDate,
  endDate: endDate,
  calendarId: calendarId,
  description: null,
  url: null,
  location: null,
  reminders: [],
  attendees: [],
);

void main() {
  tz.initializeTimeZones();

  late _MockCalendarApi mockCalendarApi;
  late Eventide eventide;

  setUp(() {
    mockCalendarApi = _MockCalendarApi();
    eventide = Eventide(calendarApi: mockCalendarApi);
  });

  // ─── Vols intercontinentaux ───────────────────────────────────────────────

  group('Vols intercontinentaux', () {
    test('Paris (UTC+2 CEST) → Montréal (UTC-4 EDT) : décalage de 6h', () async {
      // Départ 13h30 heure de Paris = 11h30 UTC
      // Arrivée 15h00 heure de Montréal = 19h00 UTC → durée vol ~7h30
      final parisDeparture = TZDateTime(getLocation('Europe/Paris'), 2025, 9, 8, 13, 30);
      final montrealArrival = TZDateTime(getLocation('America/Toronto'), 2025, 9, 8, 15, 0);

      final utcStart = parisDeparture.toUtc().millisecondsSinceEpoch;
      final utcEnd = montrealArrival.toUtc().millisecondsSinceEpoch;

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
        ),
      ).thenAnswer((_) async => _makeEvent(startDate: utcStart, endDate: utcEnd));

      await eventide.createEvent(
        title: 'Paris → Montréal',
        startDate: parisDeparture,
        endDate: montrealArrival,
        calendarId: '1',
      );

      verify(
        () => mockCalendarApi.createEvent(
          calendarId: '1',
          title: 'Paris → Montréal',
          startDate: utcStart,
          endDate: utcEnd,
          isAllDay: false,
          description: null,
          url: null,
          location: null,
          reminders: null,
        ),
      ).called(1);

      // L'heure UTC de départ doit être 11h30
      expect(DateTime.fromMillisecondsSinceEpoch(utcStart, isUtc: true).hour, 11);
      expect(DateTime.fromMillisecondsSinceEpoch(utcStart, isUtc: true).minute, 30);
    });

    test('Tokyo (UTC+9) → New York (UTC-4 EDT) : franchissement de la ligne de date', () async {
      // Départ Tokyo lundi 10h00 = lundi 01h00 UTC
      // Arrivée New York lundi 08h00 = lundi 12h00 UTC → vol ~11h
      final tokyoDeparture = TZDateTime(getLocation('Asia/Tokyo'), 2025, 6, 9, 10, 0);
      final newYorkArrival = TZDateTime(getLocation('America/New_York'), 2025, 6, 9, 8, 0);

      final utcStart = tokyoDeparture.toUtc().millisecondsSinceEpoch;
      final utcEnd = newYorkArrival.toUtc().millisecondsSinceEpoch;

      // Vérification : arrivée UTC est après départ UTC
      expect(utcEnd, greaterThan(utcStart));

      // Tokyo UTC+9 : 10h00 → UTC 01h00
      expect(tokyoDeparture.toUtc().hour, 1);
      // New York EDT UTC-4 : 08h00 → UTC 12h00
      expect(newYorkArrival.toUtc().hour, 12);

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
        ),
      ).thenAnswer((_) async => _makeEvent(startDate: utcStart, endDate: utcEnd));

      await eventide.createEvent(
        title: 'Tokyo → New York',
        startDate: tokyoDeparture,
        endDate: newYorkArrival,
        calendarId: '1',
      );

      verify(
        () => mockCalendarApi.createEvent(
          calendarId: '1',
          title: 'Tokyo → New York',
          startDate: utcStart,
          endDate: utcEnd,
          isAllDay: false,
          description: null,
          url: null,
          location: null,
          reminders: null,
        ),
      ).called(1);
    });

    test('Los Angeles (UTC-7 PDT) → Londres (UTC+1 BST) : 10h de vol', () async {
      // Départ LA dimanche 18h00 = dimanche 01h00 UTC lundi
      final laDeparture = TZDateTime(getLocation('America/Los_Angeles'), 2025, 8, 10, 18, 0);
      // Arrivée Londres lundi 12h00 = lundi 11h00 UTC
      final londonArrival = TZDateTime(getLocation('Europe/London'), 2025, 8, 11, 12, 0);

      final utcStart = laDeparture.toUtc().millisecondsSinceEpoch;
      final utcEnd = londonArrival.toUtc().millisecondsSinceEpoch;

      // LA PDT = UTC-7 : 18h00 → UTC 01h00 (lendemain)
      expect(laDeparture.toUtc().hour, 1);
      expect(laDeparture.toUtc().day, 11); // lendemain

      // Londres BST = UTC+1 : 12h00 → UTC 11h00
      expect(londonArrival.toUtc().hour, 11);

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
        ),
      ).thenAnswer((_) async => _makeEvent(startDate: utcStart, endDate: utcEnd));

      await eventide.createEvent(
        title: 'Los Angeles → Londres',
        startDate: laDeparture,
        endDate: londonArrival,
        calendarId: '1',
      );

      verify(
        () => mockCalendarApi.createEvent(
          calendarId: '1',
          title: 'Los Angeles → Londres',
          startDate: utcStart,
          endDate: utcEnd,
          isAllDay: false,
          description: null,
          url: null,
          location: null,
          reminders: null,
        ),
      ).called(1);
    });
  });

  // ─── Fuseaux à offset demi-heure ─────────────────────────────────────────

  group('Fuseaux à offset non-entier', () {
    test('Inde (UTC+5:30) : réunion à 09h30 IST = 04h00 UTC', () async {
      final indiaTime = TZDateTime(getLocation('Asia/Kolkata'), 2025, 3, 15, 9, 30);
      final indiaEnd = TZDateTime(getLocation('Asia/Kolkata'), 2025, 3, 15, 10, 30);

      // IST = UTC+5:30 → 09h30 - 5h30 = 04h00 UTC
      expect(indiaTime.toUtc().hour, 4);
      expect(indiaTime.toUtc().minute, 0);

      final utcStart = indiaTime.toUtc().millisecondsSinceEpoch;
      final utcEnd = indiaEnd.toUtc().millisecondsSinceEpoch;

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
        ),
      ).thenAnswer((_) async => _makeEvent(startDate: utcStart, endDate: utcEnd));

      await eventide.createEvent(title: 'Réunion Bangalore', startDate: indiaTime, endDate: indiaEnd, calendarId: '1');

      verify(
        () => mockCalendarApi.createEvent(
          calendarId: '1',
          title: 'Réunion Bangalore',
          startDate: utcStart,
          endDate: utcEnd,
          isAllDay: false,
          description: null,
          url: null,
          location: null,
          reminders: null,
        ),
      ).called(1);
    });

    test('Australie/Adelaide (UTC+9:30 ACST) : réunion à 14h00 = 04h30 UTC', () async {
      // ACST = UTC+9:30 (hiver australien, pas de DST en juillet)
      final adelaideTime = TZDateTime(getLocation('Australia/Adelaide'), 2025, 7, 20, 14, 0);
      final adelaideEnd = TZDateTime(getLocation('Australia/Adelaide'), 2025, 7, 20, 15, 0);

      // 14h00 ACST - 9h30 = 04h30 UTC
      expect(adelaideTime.toUtc().hour, 4);
      expect(adelaideTime.toUtc().minute, 30);

      final utcStart = adelaideTime.toUtc().millisecondsSinceEpoch;
      final utcEnd = adelaideEnd.toUtc().millisecondsSinceEpoch;

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
        ),
      ).thenAnswer((_) async => _makeEvent(startDate: utcStart, endDate: utcEnd));

      await eventide.createEvent(
        title: 'Réunion Adelaide',
        startDate: adelaideTime,
        endDate: adelaideEnd,
        calendarId: '1',
      );

      verify(
        () => mockCalendarApi.createEvent(
          calendarId: '1',
          title: 'Réunion Adelaide',
          startDate: utcStart,
          endDate: utcEnd,
          isAllDay: false,
          description: null,
          url: null,
          location: null,
          reminders: null,
        ),
      ).called(1);
    });

    test('Nepal (UTC+5:45) : offset unique de 45 minutes', () async {
      final nepalTime = TZDateTime(getLocation('Asia/Kathmandu'), 2025, 5, 10, 12, 0);

      // NPT = UTC+5:45 → 12h00 - 5h45 = 06h15 UTC
      expect(nepalTime.toUtc().hour, 6);
      expect(nepalTime.toUtc().minute, 15);
    });
  });

  // ─── Changements d'heure (DST) ───────────────────────────────────────────

  group('Changements d\'heure (DST)', () {
    test('Europe/Paris : passage heure d\'hiver → heure d\'été (dernier dimanche mars)', () async {
      // En 2025 : passage le 30 mars à 02h00 → 03h00
      // Événement juste avant : 01h30 CET (UTC+1) = 00h30 UTC
      final beforeDst = TZDateTime(getLocation('Europe/Paris'), 2025, 3, 30, 1, 30);
      // Événement juste après : 03h30 CEST (UTC+2) = 01h30 UTC
      final afterDst = TZDateTime(getLocation('Europe/Paris'), 2025, 3, 30, 3, 30);

      expect(beforeDst.toUtc().hour, 0);
      expect(beforeDst.toUtc().minute, 30);
      expect(afterDst.toUtc().hour, 1);
      expect(afterDst.toUtc().minute, 30);

      // La différence UTC est bien 1h malgré un écart apparent de 2h en heure locale
      final diffMs = afterDst.toUtc().millisecondsSinceEpoch - beforeDst.toUtc().millisecondsSinceEpoch;
      expect(diffMs, const Duration(hours: 1).inMilliseconds);
    });

    test('Europe/Paris : passage heure d\'été → heure d\'hiver (dernier dimanche octobre)', () async {
      // En 2025 : passage le 26 octobre à 03h00 → 02h00
      // Événement à 02h30 CEST (heure d\'été, UTC+2) = 00h30 UTC
      final summerTime = TZDateTime(getLocation('Europe/Paris'), 2025, 10, 26, 2, 30);
      // La même heure locale 02h30 existe deux fois ; tz la résout en heure d\'été par défaut

      // Événement à 03h30 CET (heure d\'hiver, UTC+1) = 02h30 UTC
      final winterTime = TZDateTime(getLocation('Europe/Paris'), 2025, 10, 26, 3, 30);

      // 03h30 CET = UTC+1 → 02h30 UTC
      expect(winterTime.toUtc().hour, 2);
      expect(winterTime.toUtc().minute, 30);

      // Vérification de la cohérence des timestamps
      expect(winterTime.toUtc().millisecondsSinceEpoch, greaterThan(summerTime.toUtc().millisecondsSinceEpoch));
    });

    test('America/New_York : DST spring forward — événement chevauche l\'heure manquante', () async {
      // Aux USA en 2025 : passage le 9 mars à 02h00 → 03h00
      // Événement débutant avant 02h00 ET se terminant après 03h00
      final before = TZDateTime(getLocation('America/New_York'), 2025, 3, 9, 1, 0);
      final after = TZDateTime(getLocation('America/New_York'), 2025, 3, 9, 3, 30);

      // 01h00 EST = UTC-5 → 06h00 UTC
      expect(before.toUtc().hour, 6);
      // 03h30 EDT = UTC-4 → 07h30 UTC
      expect(after.toUtc().hour, 7);
      expect(after.toUtc().minute, 30);

      // La durée UTC est 1h30 même si localement les heures 02h00–03h00 n'existent pas
      final diffMs = after.toUtc().millisecondsSinceEpoch - before.toUtc().millisecondsSinceEpoch;
      expect(diffMs, const Duration(hours: 1, minutes: 30).inMilliseconds);
    });

    test('createEvent préserve le timestamp UTC lors d\'un update après changement DST', () async {
      // Événement créé en heure d\'été, mis à jour en heure d\'hiver
      final summerDate = TZDateTime(getLocation('Europe/Paris'), 2025, 7, 15, 10, 0); // CEST UTC+2
      final winterDate = TZDateTime(getLocation('Europe/Paris'), 2025, 12, 10, 10, 0); // CET UTC+1

      // Même heure locale (10h00) mais UTC différent
      expect(summerDate.toUtc().hour, 8); // UTC+2 → 08h00 UTC
      expect(winterDate.toUtc().hour, 9); // UTC+1 → 09h00 UTC

      final originalEvent = Event(
        id: '42',
        title: 'Réunion récurrente',
        isAllDay: false,
        startDate: summerDate.toUtc().millisecondsSinceEpoch,
        endDate: summerDate.toUtc().add(const Duration(hours: 1)).millisecondsSinceEpoch,
        calendarId: '1',
        description: null,
        url: null,
        location: null,
        reminders: [],
        attendees: [],
      );

      when(
        () => mockCalendarApi.updateEvent(
          eventId: any(named: 'eventId'),
          calendarId: any(named: 'calendarId'),
          title: any(named: 'title'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          isAllDay: any(named: 'isAllDay'),
          description: any(named: 'description'),
          url: any(named: 'url'),
          location: any(named: 'location'),
          reminders: any(named: 'reminders'),
        ),
      ).thenAnswer((_) async => originalEvent);

      await eventide.updateEvent(
        originalEvent.toETEvent(),
        startDate: winterDate,
        endDate: winterDate.add(const Duration(hours: 1)),
      );

      verify(
        () => mockCalendarApi.updateEvent(
          eventId: '42',
          calendarId: '1',
          title: 'Réunion récurrente',
          startDate: winterDate.toUtc().millisecondsSinceEpoch,
          endDate: winterDate.toUtc().add(const Duration(hours: 1)).millisecondsSinceEpoch,
          isAllDay: false,
          description: null,
          url: null,
          location: null,
          reminders: [],
        ),
      ).called(1);
    });
  });

  // ─── Événements à la frontière minuit ────────────────────────────────────

  group('Événements à la frontière minuit', () {
    test('Événement à minuit UTC : jour précédent dans les fuseaux négatifs', () async {
      // Un événement à 00h00 UTC est encore le dimanche 23 décembre en UTC-1
      final utcMidnight = TZDateTime(getLocation('UTC'), 2025, 12, 24, 0, 0);
      final utcMidnightEnd = TZDateTime(getLocation('UTC'), 2025, 12, 24, 1, 0);

      final azoresTime = TZDateTime.from(utcMidnight, getLocation('Atlantic/Azores')); // UTC-1
      expect(azoresTime.day, 23); // Toujours le 23 décembre aux Açores
      expect(azoresTime.hour, 23);

      final utcStart = utcMidnight.millisecondsSinceEpoch;
      final utcEnd = utcMidnightEnd.millisecondsSinceEpoch;

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
        ),
      ).thenAnswer((_) async => _makeEvent(startDate: utcStart, endDate: utcEnd));

      await eventide.createEvent(title: 'Minuit UTC', startDate: utcMidnight, endDate: utcMidnightEnd, calendarId: '1');

      verify(
        () => mockCalendarApi.createEvent(
          calendarId: '1',
          title: 'Minuit UTC',
          startDate: utcStart,
          endDate: utcEnd,
          isAllDay: false,
          description: null,
          url: null,
          location: null,
          reminders: null,
        ),
      ).called(1);
    });

    test('Événement débutant avant minuit et se terminant après minuit (multi-jours)', () async {
      // Sydney AEDT (UTC+11 en été)
      // Départ : 31 déc 23h00 AEDT = 31 déc 12h00 UTC
      // Fin    :  1 jan 14h00 AEDT =  1 jan 03h00 UTC (franchit minuit UTC)
      final sydneyStart = TZDateTime(getLocation('Australia/Sydney'), 2025, 12, 31, 23, 0);
      final sydneyEnd = TZDateTime(getLocation('Australia/Sydney'), 2026, 1, 1, 14, 0);

      expect(sydneyStart.toUtc().day, 31);
      expect(sydneyStart.toUtc().month, 12);
      expect(sydneyEnd.toUtc().day, 1);
      expect(sydneyEnd.toUtc().month, 1);

      final utcStart = sydneyStart.toUtc().millisecondsSinceEpoch;
      final utcEnd = sydneyEnd.toUtc().millisecondsSinceEpoch;

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
        ),
      ).thenAnswer((_) async => _makeEvent(startDate: utcStart, endDate: utcEnd));

      await eventide.createEvent(
        title: 'Réveillon Sydney',
        startDate: sydneyStart,
        endDate: sydneyEnd,
        calendarId: '1',
      );

      verify(
        () => mockCalendarApi.createEvent(
          calendarId: '1',
          title: 'Réveillon Sydney',
          startDate: utcStart,
          endDate: utcEnd,
          isAllDay: false,
          description: null,
          url: null,
          location: null,
          reminders: null,
        ),
      ).called(1);
    });
  });

  // ─── Conversion round-trip Event ↔ ETEvent ────────────────────────────────

  group('Round-trip UTC ↔ ETEvent', () {
    test('toETEvent préserve le timestamp UTC exact pour un fuseau positif', () {
      final tokyoTime = TZDateTime(getLocation('Asia/Tokyo'), 2025, 6, 15, 9, 0); // UTC+9 → 00h00 UTC
      final utcMs = tokyoTime.toUtc().millisecondsSinceEpoch;

      final event = _makeEvent(startDate: utcMs, endDate: utcMs + 3600000);
      final etEvent = event.toETEvent();

      // Le DateTime résultant doit avoir le même millisecondsSinceEpoch
      expect(etEvent.startDate.millisecondsSinceEpoch, utcMs);
      expect(etEvent.startDate.toUtc().hour, 0);
    });

    test('toETEvent préserve le timestamp UTC exact pour un fuseau négatif', () {
      final nyTime = TZDateTime(getLocation('America/New_York'), 2025, 6, 15, 20, 0); // UTC-4 → 00h00 UTC
      final utcMs = nyTime.toUtc().millisecondsSinceEpoch;

      final event = _makeEvent(startDate: utcMs, endDate: utcMs + 3600000);
      final etEvent = event.toETEvent();

      expect(etEvent.startDate.millisecondsSinceEpoch, utcMs);
      expect(etEvent.startDate.toUtc().hour, 0);
    });

    test('toETEvent préserve le timestamp UTC exact pour un offset demi-heure', () {
      // IST UTC+5:30 : 05h30 IST = 00h00 UTC
      final indiaTime = TZDateTime(getLocation('Asia/Kolkata'), 2025, 6, 15, 5, 30);
      final utcMs = indiaTime.toUtc().millisecondsSinceEpoch;

      final event = _makeEvent(startDate: utcMs, endDate: utcMs + 3600000);
      final etEvent = event.toETEvent();

      expect(etEvent.startDate.millisecondsSinceEpoch, utcMs);
      expect(etEvent.startDate.toUtc().hour, 0);
      expect(etEvent.startDate.toUtc().minute, 0);
    });
  });

  // ─── retrieveEvents avec filtres de dates en TZDateTime ──────────────────

  group('retrieveEvents avec filtres timezone', () {
    test('filtre startDate en heure Tokyo envoyé correctement en UTC', () async {
      // Chercher les événements du 15 juin 2025 à partir de 09h00 JST = 00h00 UTC
      final tokyoStart = TZDateTime(getLocation('Asia/Tokyo'), 2025, 6, 15, 9, 0);
      final tokyoEnd = TZDateTime(getLocation('Asia/Tokyo'), 2025, 6, 15, 18, 0);

      when(
        () => mockCalendarApi.retrieveEvents(
          calendarId: any(named: 'calendarId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => []);

      await eventide.retrieveEvents(calendarId: '1', startDate: tokyoStart, endDate: tokyoEnd);

      verify(
        () => mockCalendarApi.retrieveEvents(
          calendarId: '1',
          startDate: tokyoStart.toUtc().millisecondsSinceEpoch,
          endDate: tokyoEnd.toUtc().millisecondsSinceEpoch,
        ),
      ).called(1);
    });

    test('filtre startDate en heure Los Angeles envoyé correctement en UTC', () async {
      // 08h00 PDT (UTC-7) = 15h00 UTC
      final laStart = TZDateTime(getLocation('America/Los_Angeles'), 2025, 8, 1, 8, 0);
      final laEnd = TZDateTime(getLocation('America/Los_Angeles'), 2025, 8, 1, 18, 0);

      expect(laStart.toUtc().hour, 15);
      expect(laEnd.toUtc().hour, 1); // lendemain
      expect(laEnd.toUtc().day, 2);

      when(
        () => mockCalendarApi.retrieveEvents(
          calendarId: any(named: 'calendarId'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => []);

      await eventide.retrieveEvents(calendarId: '1', startDate: laStart, endDate: laEnd);

      verify(
        () => mockCalendarApi.retrieveEvents(
          calendarId: '1',
          startDate: laStart.toUtc().millisecondsSinceEpoch,
          endDate: laEnd.toUtc().millisecondsSinceEpoch,
        ),
      ).called(1);
    });
  });

  // ─── updateEvent avec fuseaux différents entre start et end ──────────────

  group('updateEvent avec fuseaux horaires mixtes', () {
    test('Mise à jour d\'un événement avec startDate et endDate dans des fuseaux différents', () async {
      final originalEvent = Event(
        id: '99',
        title: 'Conférence internationale',
        isAllDay: false,
        startDate: DateTime(2025, 10, 1, 9, 0).toUtc().millisecondsSinceEpoch,
        endDate: DateTime(2025, 10, 1, 17, 0).toUtc().millisecondsSinceEpoch,
        calendarId: 'cal-1',
        description: null,
        url: null,
        location: null,
        reminders: [],
        attendees: [],
      );

      // Nouveau start en heure de Paris, nouvelle fin en heure de New York
      final newStart = TZDateTime(getLocation('Europe/Paris'), 2025, 11, 5, 10, 0); // CET UTC+1 → 09h00 UTC
      final newEnd = TZDateTime(getLocation('America/New_York'), 2025, 11, 5, 17, 0); // EST UTC-5 → 22h00 UTC

      when(
        () => mockCalendarApi.updateEvent(
          eventId: any(named: 'eventId'),
          calendarId: any(named: 'calendarId'),
          title: any(named: 'title'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          isAllDay: any(named: 'isAllDay'),
          description: any(named: 'description'),
          url: any(named: 'url'),
          location: any(named: 'location'),
          reminders: any(named: 'reminders'),
        ),
      ).thenAnswer((_) async => originalEvent);

      await eventide.updateEvent(originalEvent.toETEvent(), startDate: newStart, endDate: newEnd);

      verify(
        () => mockCalendarApi.updateEvent(
          eventId: '99',
          calendarId: 'cal-1',
          title: 'Conférence internationale',
          startDate: newStart.toUtc().millisecondsSinceEpoch,
          endDate: newEnd.toUtc().millisecondsSinceEpoch,
          isAllDay: false,
          description: null,
          url: null,
          location: null,
          reminders: [],
        ),
      ).called(1);
    });
  });
}
