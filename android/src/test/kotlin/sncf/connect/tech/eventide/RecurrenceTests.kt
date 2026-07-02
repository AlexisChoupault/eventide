package sncf.connect.tech.eventide

import android.accounts.AccountManager
import android.content.ContentResolver
import android.content.Context
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.provider.CalendarContract
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.test.runTest
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import sncf.connect.tech.eventide.Mocks.Companion.mockPermissionGranted
import sncf.connect.tech.eventide.handler.CalendarActivityManager
import sncf.connect.tech.eventide.handler.IcsEventManager
import sncf.connect.tech.eventide.handler.PermissionHandler
import sncf.connect.tech.eventide.handler.RecurrenceHelper
import java.time.Instant
import java.util.concurrent.CountDownLatch

// NOTE: android/build.gradle sets `unitTests.returnDefaultValues = true`, which stubs
// real Android classes (e.g. ContentValues.put/getAsString) to no-ops/defaults in these
// plain JVM unit tests. That means asserting against the *contents* of a captured
// ContentValues instance is unreliable here (see EventTests.kt, which never does this
// either). Instead, we assert on the `Event` object returned through the callback,
// which is a plain Kotlin data class unaffected by the stubbing.
class RecurrenceTests {
    private lateinit var context: Context
    private lateinit var contentResolver: ContentResolver
    private lateinit var permissionHandler: PermissionHandler
    private lateinit var icsEventManager: IcsEventManager
    private lateinit var accountManager: AccountManager
    private lateinit var packageManager: PackageManager
    private lateinit var calendarImplem: CalendarImplem
    private lateinit var calendarActivityManager: CalendarActivityManager
    private lateinit var calendarContentUri: Uri
    private lateinit var eventContentUri: Uri
    private lateinit var remindersContentUri: Uri
    private lateinit var attendeesContentUri: Uri
    private lateinit var instancesContentUri: Uri

    @BeforeEach
    fun setup() {
        context = mockk(relaxed = true)
        contentResolver = mockk(relaxed = true)
        permissionHandler = mockk(relaxed = true)
        icsEventManager = mockk(relaxed = true)
        accountManager = mockk(relaxed = true)
        packageManager = mockk(relaxed = true)
        calendarActivityManager = mockk(relaxed = true)
        calendarContentUri = mockk(relaxed = true)
        eventContentUri = mockk(relaxed = true)
        remindersContentUri = mockk(relaxed = true)
        attendeesContentUri = mockk(relaxed = true)
        instancesContentUri = mockk(relaxed = true)

        calendarImplem = CalendarImplem(
            context,
            permissionHandler,
            calendarActivityManager,
            icsEventManager,
            accountManager,
            packageManager,
            contentResolver,
            calendarContentUri,
            eventContentUri,
            remindersContentUri,
            attendeesContentUri,
            instancesContentUri
        )
    }

    /**
     * The real `retrieveEvents` implementation builds the query URI via
     * `instancesContentUri.buildUpon().appendPath(...).appendPath(...).build()`.
     * Since `instancesContentUri` is a relaxed mockk, `buildUpon()` returns a relaxed
     * `Uri.Builder` mock by default, whose chained calls also return relaxed mocks -
     * so no extra stubbing of the builder chain is required for the resulting URI
     * itself; we only need to stub `contentResolver.query` to match by URI matcher.
     */
    private fun mockWritableCalendar() {
        val cursor = mockk<Cursor>(relaxed = true)
        every { contentResolver.query(calendarContentUri, any(), any(), any(), any()) } returns cursor
        every { cursor.moveToNext() } returns true
        every { cursor.getInt(any()) } returns CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR
    }

    /**
     * Mocks the `getCalendarId(eventId)` lookup (a broad `contentResolver.query(eventContentUri, ...)`
     * matcher). Mirrors `mockCalendarIdFound()` in EventTests.kt. Individual tests that also need to
     * stub more specific `eventContentUri` queries (e.g. RRULE, DTSTART/DTEND) should define those
     * `every {}` blocks *after* calling this helper, since MockK resolves the most-recently-declared
     * matching stub first.
     */
    private fun mockCalendarIdFound() {
        val cursor = mockk<Cursor>(relaxed = true)
        every { contentResolver.query(eventContentUri, any(), any(), any(), any()) } returns cursor
        every { cursor.moveToNext() } returns true
        every { cursor.getString(any()) } returns "1"
    }

    @Test
    fun `createEvent returns the RRULE in the resulting Event when recurrenceRule is provided`() = runTest {
        mockPermissionGranted(permissionHandler)
        mockWritableCalendar()

        val uri = mockk<Uri>(relaxed = true)
        every { contentResolver.insert(any(), any()) } returns uri
        every { uri.lastPathSegment } returns "42"

        val startMilli = Instant.now().toEpochMilli()
        val endMilli = Instant.now().toEpochMilli()

        var result: Result<Event>? = null
        val latch = CountDownLatch(1)
        calendarImplem.createEvent(
            calendarId = "1",
            title = "Standup",
            startDate = startMilli,
            endDate = endMilli,
            isAllDay = false,
            description = null,
            url = null,
            location = null,
            reminders = null,
            recurrenceRule = "FREQ=WEEKLY;BYDAY=MO",
        ) {
            result = it
            latch.countDown()
        }

        latch.await()

        assertTrue(result!!.isSuccess)
        assertEquals("FREQ=WEEKLY;BYDAY=MO", result.getOrNull()!!.recurrenceRule)
    }

    @Test
    fun `createEvent returns a null recurrenceRule in the resulting Event when none is provided`() = runTest {
        mockPermissionGranted(permissionHandler)
        mockWritableCalendar()

        val uri = mockk<Uri>(relaxed = true)
        every { contentResolver.insert(any(), any()) } returns uri
        every { uri.lastPathSegment } returns "43"

        val startMilli = Instant.now().toEpochMilli()
        val endMilli = Instant.now().toEpochMilli()

        var result: Result<Event>? = null
        val latch = CountDownLatch(1)
        calendarImplem.createEvent(
            calendarId = "1",
            title = "Standup",
            startDate = startMilli,
            endDate = endMilli,
            isAllDay = false,
            description = null,
            url = null,
            location = null,
            reminders = null,
            recurrenceRule = null,
        ) {
            result = it
            latch.countDown()
        }

        latch.await()

        assertTrue(result!!.isSuccess)
        assertNull(result.getOrNull()!!.recurrenceRule)
    }

    @Test
    fun `retrieveEvents returns recurrenceRule and originalInstanceTime from Instances BEGIN`() = runTest {
        mockPermissionGranted(permissionHandler)

        val instanceStart = 1751880000000L
        val instanceEnd = 1751883600000L

        // The master event Instances cursor: retrieveEvents now queries
        // CalendarContract.Instances (expanded occurrences), not CalendarContract.Events.
        val instancesCursor = mockk<Cursor>(relaxed = true)
        every { contentResolver.query(any(), any(), any(), any(), any()) } returns instancesCursor
        every { instancesCursor.moveToNext() } returnsMany listOf(true, false)

        every { instancesCursor.getColumnIndexOrThrow(CalendarContract.Instances.EVENT_ID) } returns 0
        every { instancesCursor.getColumnIndexOrThrow(CalendarContract.Instances.TITLE) } returns 1
        every { instancesCursor.getColumnIndexOrThrow(CalendarContract.Instances.DESCRIPTION) } returns 2
        every { instancesCursor.getColumnIndexOrThrow(CalendarContract.Instances.EVENT_LOCATION) } returns 3
        every { instancesCursor.getColumnIndexOrThrow(CalendarContract.Instances.BEGIN) } returns 4
        every { instancesCursor.getColumnIndexOrThrow(CalendarContract.Instances.END) } returns 5
        every { instancesCursor.getColumnIndexOrThrow(CalendarContract.Instances.RRULE) } returns 6
        every { instancesCursor.getColumnIndexOrThrow(CalendarContract.Instances.ALL_DAY) } returns 7

        every { instancesCursor.getString(0) } returns "42" // EVENT_ID -> master event id
        every { instancesCursor.getString(1) } returns "Standup"
        every { instancesCursor.getString(2) } returns null
        every { instancesCursor.getString(3) } returns null
        every { instancesCursor.getLong(4) } returns instanceStart // BEGIN
        every { instancesCursor.getLong(5) } returns instanceEnd // END
        every { instancesCursor.getString(6) } returns "FREQ=WEEKLY;BYDAY=MO" // RRULE
        every { instancesCursor.getInt(7) } returns 0

        // Reminders/attendees are still looked up by the master EVENT_ID, unchanged.
        val emptyCursor = mockk<Cursor>(relaxed = true)
        every { emptyCursor.moveToNext() } returns false
        every { contentResolver.query(attendeesContentUri, any(), any(), any(), any()) } returns emptyCursor
        every { contentResolver.query(remindersContentUri, any(), any(), any(), any()) } returns emptyCursor

        var result: Result<List<Event>>? = null
        val latch = CountDownLatch(1)
        calendarImplem.retrieveEvents(
            calendarId = "1",
            startDate = instanceStart,
            endDate = instanceEnd,
        ) {
            result = it
            latch.countDown()
        }

        latch.await()

        assertTrue(result!!.isSuccess)
        val event = result.getOrNull()?.firstOrNull()
        assertEquals("42", event?.id)
        assertEquals("FREQ=WEEKLY;BYDAY=MO", event?.recurrenceRule)
        assertEquals(instanceStart, event?.originalInstanceTime)
        assertEquals(instanceStart, event?.startDate)
    }

    // ------------------------------------------------------------------
    // RecurrenceHelper.patchWithUntil - pure function, no mocking needed
    // ------------------------------------------------------------------

    @Test
    fun `patchWithUntil appends UNTIL to a rrule with no COUNT or UNTIL`() {
        val patched = RecurrenceHelper.patchWithUntil("FREQ=WEEKLY;BYDAY=MO", 1751880000000L)

        assertEquals("FREQ=WEEKLY;BYDAY=MO;UNTIL=20250707T091959Z", patched)
    }

    @Test
    fun `patchWithUntil replaces an existing UNTIL`() {
        val patched = RecurrenceHelper.patchWithUntil(
            "FREQ=DAILY;UNTIL=20200101T000000Z",
            1751880000000L,
        )

        assertEquals("FREQ=DAILY;UNTIL=20250707T091959Z", patched)
    }

    @Test
    fun `patchWithUntil replaces an existing COUNT since COUNT and UNTIL are mutually exclusive`() {
        val patched = RecurrenceHelper.patchWithUntil("FREQ=DAILY;COUNT=10", 1751880000000L)

        assertTrue(!patched.contains("COUNT="))
        assertEquals("FREQ=DAILY;UNTIL=20250707T091959Z", patched)
    }

    // ------------------------------------------------------------------
    // RecurrenceHelper.getMasterRrule / getMasterEventDurationMs
    // ------------------------------------------------------------------

    @Test
    fun `getMasterRrule returns the RRULE column value when the master event is found`() {
        val cursor = mockk<Cursor>(relaxed = true)
        every {
            contentResolver.query(eventContentUri, arrayOf(CalendarContract.Events.RRULE), "_id = ?", arrayOf("42"), null)
        } returns cursor
        every { cursor.moveToFirst() } returns true
        every { cursor.getString(0) } returns "FREQ=WEEKLY;BYDAY=MO"

        val rrule = RecurrenceHelper.getMasterRrule(contentResolver, eventContentUri, "42")

        assertEquals("FREQ=WEEKLY;BYDAY=MO", rrule)
    }

    @Test
    fun `getMasterRrule returns null when the master event is not found`() {
        val cursor = mockk<Cursor>(relaxed = true)
        every {
            contentResolver.query(eventContentUri, arrayOf(CalendarContract.Events.RRULE), "_id = ?", arrayOf("42"), null)
        } returns cursor
        every { cursor.moveToFirst() } returns false

        val rrule = RecurrenceHelper.getMasterRrule(contentResolver, eventContentUri, "42")

        assertNull(rrule)
    }

    @Test
    fun `getMasterEventDurationMs returns DTEND minus DTSTART when the master event is found`() {
        val cursor = mockk<Cursor>(relaxed = true)
        every {
            contentResolver.query(
                eventContentUri,
                arrayOf(CalendarContract.Events.DTSTART, CalendarContract.Events.DTEND),
                "_id = ?",
                arrayOf("42"),
                null,
            )
        } returns cursor
        every { cursor.moveToFirst() } returns true
        every { cursor.getLong(0) } returns 1751880000000L // DTSTART
        every { cursor.getLong(1) } returns 1751883600000L // DTEND

        val durationMs = RecurrenceHelper.getMasterEventDurationMs(contentResolver, eventContentUri, "42")

        assertEquals(3_600_000L, durationMs)
    }

    @Test
    fun `getMasterEventDurationMs defaults to one hour when the master event is not found`() {
        val cursor = mockk<Cursor>(relaxed = true)
        every {
            contentResolver.query(
                eventContentUri,
                arrayOf(CalendarContract.Events.DTSTART, CalendarContract.Events.DTEND),
                "_id = ?",
                arrayOf("42"),
                null,
            )
        } returns cursor
        every { cursor.moveToFirst() } returns false

        val durationMs = RecurrenceHelper.getMasterEventDurationMs(contentResolver, eventContentUri, "42")

        assertEquals(3_600_000L, durationMs)
    }

    // ------------------------------------------------------------------
    // deleteEvent - span-aware behavior
    // ------------------------------------------------------------------

    @Test
    fun `deleteEvent with allEvents span deletes the master event row`() = runTest {
        mockPermissionGranted(permissionHandler)
        mockCalendarIdFound()
        mockWritableCalendar()

        every { contentResolver.delete(eventContentUri, "_id = ?", arrayOf("42")) } returns 1

        var result: Result<Unit>? = null
        val latch = CountDownLatch(1)
        calendarImplem.deleteEvent(
            eventId = "42",
            span = "allEvents",
            originalInstanceTime = null,
        ) {
            result = it
            latch.countDown()
        }

        latch.await()

        assertTrue(result!!.isSuccess)
        verify { contentResolver.delete(eventContentUri, "_id = ?", arrayOf("42")) }
    }

    @Test
    fun `deleteEvent with an unrecognized span falls back to deleting the master event row`() = runTest {
        mockPermissionGranted(permissionHandler)
        mockCalendarIdFound()
        mockWritableCalendar()

        every { contentResolver.delete(eventContentUri, "_id = ?", arrayOf("42")) } returns 1

        var result: Result<Unit>? = null
        val latch = CountDownLatch(1)
        calendarImplem.deleteEvent(
            eventId = "42",
            span = "somethingUnexpected",
            originalInstanceTime = null,
        ) {
            result = it
            latch.countDown()
        }

        latch.await()

        assertTrue(result!!.isSuccess)
        verify { contentResolver.delete(eventContentUri, "_id = ?", arrayOf("42")) }
    }

    @Test
    fun `deleteEvent with thisEvent span inserts a STATUS_CANCELED exception row instead of deleting`() = runTest {
        mockPermissionGranted(permissionHandler)
        mockCalendarIdFound()
        mockWritableCalendar()

        // getMasterEventDurationMs query
        val durationCursor = mockk<Cursor>(relaxed = true)
        every {
            contentResolver.query(
                eventContentUri,
                arrayOf(CalendarContract.Events.DTSTART, CalendarContract.Events.DTEND),
                "_id = ?",
                arrayOf("42"),
                null,
            )
        } returns durationCursor
        every { durationCursor.moveToFirst() } returns true
        every { durationCursor.getLong(0) } returns 1751880000000L // DTSTART
        every { durationCursor.getLong(1) } returns 1751883600000L // DTEND

        every { contentResolver.insert(eventContentUri, any()) } returns
            mockk<Uri>(relaxed = true)

        var result: Result<Unit>? = null
        val latch = CountDownLatch(1)
        calendarImplem.deleteEvent(
            eventId = "42",
            span = "thisEvent",
            originalInstanceTime = 1751880000000L,
        ) {
            result = it
            latch.countDown()
        }

        latch.await()

        assertTrue(result!!.isSuccess)
        verify { contentResolver.insert(eventContentUri, any()) }
        verify(exactly = 0) { contentResolver.delete(any(), any(), any()) }
    }

    @Test
    fun `deleteEvent with thisAndFuture span patches the master RRULE with UNTIL when the event recurs`() = runTest {
        mockPermissionGranted(permissionHandler)
        mockCalendarIdFound()
        mockWritableCalendar()

        val rruleCursor = mockk<Cursor>(relaxed = true)
        every {
            contentResolver.query(eventContentUri, arrayOf(CalendarContract.Events.RRULE), "_id = ?", arrayOf("42"), null)
        } returns rruleCursor
        every { rruleCursor.moveToFirst() } returns true
        every { rruleCursor.getString(0) } returns "FREQ=WEEKLY;BYDAY=MO"

        every { contentResolver.update(eventContentUri, any(), "_id = ?", arrayOf("42")) } returns 1

        var result: Result<Unit>? = null
        val latch = CountDownLatch(1)
        calendarImplem.deleteEvent(
            eventId = "42",
            span = "thisAndFuture",
            originalInstanceTime = 1751880000000L,
        ) {
            result = it
            latch.countDown()
        }

        latch.await()

        assertTrue(result!!.isSuccess)
        verify { contentResolver.update(eventContentUri, any(), "_id = ?", arrayOf("42")) }
        verify(exactly = 0) { contentResolver.delete(any(), any(), any()) }
    }

    @Test
    fun `deleteEvent with thisAndFuture span falls back to deleting the master row when the event is not recurring`() = runTest {
        mockPermissionGranted(permissionHandler)
        mockCalendarIdFound()
        mockWritableCalendar()

        val rruleCursor = mockk<Cursor>(relaxed = true)
        every {
            contentResolver.query(eventContentUri, arrayOf(CalendarContract.Events.RRULE), "_id = ?", arrayOf("42"), null)
        } returns rruleCursor
        every { rruleCursor.moveToFirst() } returns false // no RRULE -> non-recurring master

        every { contentResolver.delete(eventContentUri, "_id = ?", arrayOf("42")) } returns 1

        var result: Result<Unit>? = null
        val latch = CountDownLatch(1)
        calendarImplem.deleteEvent(
            eventId = "42",
            span = "thisAndFuture",
            originalInstanceTime = 1751880000000L,
        ) {
            result = it
            latch.countDown()
        }

        latch.await()

        assertTrue(result!!.isSuccess)
        verify { contentResolver.delete(eventContentUri, "_id = ?", arrayOf("42")) }
        verify(exactly = 0) { contentResolver.update(any(), any(), any(), any()) }
    }
}
