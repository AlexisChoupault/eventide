package sncf.connect.tech.eventide.handler

import android.content.ContentResolver
import android.net.Uri
import android.provider.CalendarContract
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * Helpers to translate Eventide's span-based recurrence editing/deletion model
 * (thisEvent / thisAndFuture / allEvents) into `CalendarContract` operations.
 */
object RecurrenceHelper {
    /**
     * Appends or replaces UNTIL in an RRULE string. Removes any existing COUNT
     * or UNTIL first, since COUNT and UNTIL are mutually exclusive per
     * https://datatracker.ietf.org/doc/html/rfc5545#section-3.3.10.
     *
     * [untilMs] is treated as the exclusive upper bound (typically the start
     * time of the first excluded occurrence) in epoch milliseconds — the
     * UNTIL value is set to [untilMs] - 1ms so that occurrence is excluded
     * from the recurring series.
     */
    fun patchWithUntil(rrule: String, untilMs: Long): String {
        val untilFormat = SimpleDateFormat("yyyyMMdd'T'HHmmss'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        val untilStr = untilFormat.format(Date(untilMs - 1))
        val parts = rrule
            .split(";")
            .filter { !it.startsWith("UNTIL=") && !it.startsWith("COUNT=") }
        return (parts + "UNTIL=$untilStr").joinToString(";")
    }

    /**
     * Fetches the RRULE string of a master event from `CalendarContract.Events`.
     * Returns null if the event has no RRULE (non-recurring) or is not found.
     */
    fun getMasterRrule(
        contentResolver: ContentResolver,
        eventContentUri: Uri,
        eventId: String,
    ): String? {
        val projection = arrayOf(CalendarContract.Events.RRULE)
        val selection = CalendarContract.Events._ID + " = ?"
        val selectionArgs = arrayOf(eventId)

        val cursor = contentResolver.query(eventContentUri, projection, selection, selectionArgs, null)
        cursor?.use {
            if (it.moveToFirst()) return it.getString(0)
        }
        return null
    }

    /**
     * Returns the duration (DTEND - DTSTART) of a master event in milliseconds.
     * Defaults to one hour (3_600_000 ms) if the master event cannot be found.
     */
    fun getMasterEventDurationMs(
        contentResolver: ContentResolver,
        eventContentUri: Uri,
        eventId: String,
    ): Long {
        val projection = arrayOf(CalendarContract.Events.DTSTART, CalendarContract.Events.DTEND)
        val selection = CalendarContract.Events._ID + " = ?"
        val selectionArgs = arrayOf(eventId)

        val cursor = contentResolver.query(eventContentUri, projection, selection, selectionArgs, null)
        cursor?.use {
            if (it.moveToFirst()) return it.getLong(1) - it.getLong(0)
        }
        return 3_600_000L
    }
}
