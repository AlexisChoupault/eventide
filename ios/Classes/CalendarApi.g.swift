// Autogenerated from Pigeon (v22.7.0), do not edit directly.
// See also: https://pub.dev/packages/pigeon

import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#else
  #error("Unsupported platform.")
#endif

/// Error class for passing custom error details to Dart side.
final class PigeonError: Error {
  let code: String
  let message: String?
  let details: Any?

  init(code: String, message: String?, details: Any?) {
    self.code = code
    self.message = message
    self.details = details
  }

  var localizedDescription: String {
    return
      "PigeonError(code: \(code), message: \(message ?? "<nil>"), details: \(details ?? "<nil>")"
      }
}

private func wrapResult(_ result: Any?) -> [Any?] {
  return [result]
}

private func wrapError(_ error: Any) -> [Any?] {
  if let pigeonError = error as? PigeonError {
    return [
      pigeonError.code,
      pigeonError.message,
      pigeonError.details,
    ]
  }
  if let flutterError = error as? FlutterError {
    return [
      flutterError.code,
      flutterError.message,
      flutterError.details,
    ]
  }
  return [
    "\(error)",
    "\(type(of: error))",
    "Stacktrace: \(Thread.callStackSymbols)",
  ]
}

private func isNullish(_ value: Any?) -> Bool {
  return value is NSNull || value == nil
}

private func nilOrValue<T>(_ value: Any?) -> T? {
  if value is NSNull { return nil }
  return value as! T?
}

/// Native data struct to represent a calendar.
/// 
/// [id] is a unique identifier for the calendar.
/// 
/// [title] is the title of the calendar.
/// 
/// [color] is the color of the calendar.
/// 
/// [isWritable] is a boolean to indicate if the calendar is writable.
/// 
/// [sourceName] is the name of the source of the calendar.
///
/// Generated class from Pigeon that represents data sent in messages.
struct Calendar {
  var id: String
  var title: String
  var color: Int64
  var isWritable: Bool
  var sourceName: String


  // swift-format-ignore: AlwaysUseLowerCamelCase
  static func fromList(_ pigeonVar_list: [Any?]) -> Calendar? {
    let id = pigeonVar_list[0] as! String
    let title = pigeonVar_list[1] as! String
    let color = pigeonVar_list[2] as! Int64
    let isWritable = pigeonVar_list[3] as! Bool
    let sourceName = pigeonVar_list[4] as! String

    return Calendar(
      id: id,
      title: title,
      color: color,
      isWritable: isWritable,
      sourceName: sourceName
    )
  }
  func toList() -> [Any?] {
    return [
      id,
      title,
      color,
      isWritable,
      sourceName,
    ]
  }
}

/// Native data struct to represent an event.
/// 
/// [id] is a unique identifier for the event.
/// 
/// [title] is the title of the event.
/// 
/// [isAllDay] is whether or not the event is an all day.
/// 
/// [startDate] is the start date of the event in milliseconds since epoch.
/// 
/// [endDate] is the end date of the event in milliseconds since epoch.
/// 
/// [calendarId] is the id of the calendar that the event belongs to.
/// 
/// [description] is the description of the event.
/// 
/// [url] is the url of the event.  
/// 
/// [reminders] is a list of minutes before the event to remind the user.
///
/// Generated class from Pigeon that represents data sent in messages.
struct Event {
  var id: String
  var title: String
  var isAllDay: Bool
  var startDate: Int64
  var endDate: Int64
  var calendarId: String
  var description: String? = nil
  var url: String? = nil
  var reminders: [Int64]? = nil


  // swift-format-ignore: AlwaysUseLowerCamelCase
  static func fromList(_ pigeonVar_list: [Any?]) -> Event? {
    let id = pigeonVar_list[0] as! String
    let title = pigeonVar_list[1] as! String
    let isAllDay = pigeonVar_list[2] as! Bool
    let startDate = pigeonVar_list[3] as! Int64
    let endDate = pigeonVar_list[4] as! Int64
    let calendarId = pigeonVar_list[5] as! String
    let description: String? = nilOrValue(pigeonVar_list[6])
    let url: String? = nilOrValue(pigeonVar_list[7])
    let reminders: [Int64]? = nilOrValue(pigeonVar_list[8])

    return Event(
      id: id,
      title: title,
      isAllDay: isAllDay,
      startDate: startDate,
      endDate: endDate,
      calendarId: calendarId,
      description: description,
      url: url,
      reminders: reminders
    )
  }
  func toList() -> [Any?] {
    return [
      id,
      title,
      isAllDay,
      startDate,
      endDate,
      calendarId,
      description,
      url,
      reminders,
    ]
  }
}

private class CalendarApiPigeonCodecReader: FlutterStandardReader {
  override func readValue(ofType type: UInt8) -> Any? {
    switch type {
    case 129:
      return Calendar.fromList(self.readValue() as! [Any?])
    case 130:
      return Event.fromList(self.readValue() as! [Any?])
    default:
      return super.readValue(ofType: type)
    }
  }
}

private class CalendarApiPigeonCodecWriter: FlutterStandardWriter {
  override func writeValue(_ value: Any) {
    if let value = value as? Calendar {
      super.writeByte(129)
      super.writeValue(value.toList())
    } else if let value = value as? Event {
      super.writeByte(130)
      super.writeValue(value.toList())
    } else {
      super.writeValue(value)
    }
  }
}

private class CalendarApiPigeonCodecReaderWriter: FlutterStandardReaderWriter {
  override func reader(with data: Data) -> FlutterStandardReader {
    return CalendarApiPigeonCodecReader(data: data)
  }

  override func writer(with data: NSMutableData) -> FlutterStandardWriter {
    return CalendarApiPigeonCodecWriter(data: data)
  }
}

class CalendarApiPigeonCodec: FlutterStandardMessageCodec, @unchecked Sendable {
  static let shared = CalendarApiPigeonCodec(readerWriter: CalendarApiPigeonCodecReaderWriter())
}


/// Generated protocol from Pigeon that represents a handler of messages from Flutter.
protocol CalendarApi {
  func requestCalendarPermission(completion: @escaping (Result<Bool, Error>) -> Void)
  func createCalendar(title: String, color: Int64, completion: @escaping (Result<Calendar, Error>) -> Void)
  func retrieveCalendars(onlyWritableCalendars: Bool, completion: @escaping (Result<[Calendar], Error>) -> Void)
  func deleteCalendar(_ calendarId: String, completion: @escaping (Result<Void, Error>) -> Void)
  func createEvent(title: String, startDate: Int64, endDate: Int64, calendarId: String, isAllDay: Bool, description: String?, url: String?, completion: @escaping (Result<Event, Error>) -> Void)
  func retrieveEvents(calendarId: String, startDate: Int64, endDate: Int64, completion: @escaping (Result<[Event], Error>) -> Void)
  func deleteEvent(withId eventId: String, _ calendarId: String, completion: @escaping (Result<Void, Error>) -> Void)
  func createReminder(_ reminder: Int64, forEventId eventId: String, completion: @escaping (Result<Event, Error>) -> Void)
  func deleteReminder(_ reminder: Int64, withEventId eventId: String, completion: @escaping (Result<Event, Error>) -> Void)
}

/// Generated setup class from Pigeon to handle messages through the `binaryMessenger`.
class CalendarApiSetup {
  static var codec: FlutterStandardMessageCodec { CalendarApiPigeonCodec.shared }
  /// Sets up an instance of `CalendarApi` to handle messages through the `binaryMessenger`.
  static func setUp(binaryMessenger: FlutterBinaryMessenger, api: CalendarApi?, messageChannelSuffix: String = "") {
    let channelSuffix = messageChannelSuffix.count > 0 ? ".\(messageChannelSuffix)" : ""
    let requestCalendarPermissionChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.easy_calendar.CalendarApi.requestCalendarPermission\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      requestCalendarPermissionChannel.setMessageHandler { _, reply in
        api.requestCalendarPermission { result in
          switch result {
          case .success(let res):
            reply(wrapResult(res))
          case .failure(let error):
            reply(wrapError(error))
          }
        }
      }
    } else {
      requestCalendarPermissionChannel.setMessageHandler(nil)
    }
    let createCalendarChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.easy_calendar.CalendarApi.createCalendar\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      createCalendarChannel.setMessageHandler { message, reply in
        let args = message as! [Any?]
        let titleArg = args[0] as! String
        let colorArg = args[1] as! Int64
        api.createCalendar(title: titleArg, color: colorArg) { result in
          switch result {
          case .success(let res):
            reply(wrapResult(res))
          case .failure(let error):
            reply(wrapError(error))
          }
        }
      }
    } else {
      createCalendarChannel.setMessageHandler(nil)
    }
    let retrieveCalendarsChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.easy_calendar.CalendarApi.retrieveCalendars\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      retrieveCalendarsChannel.setMessageHandler { message, reply in
        let args = message as! [Any?]
        let onlyWritableCalendarsArg = args[0] as! Bool
        api.retrieveCalendars(onlyWritableCalendars: onlyWritableCalendarsArg) { result in
          switch result {
          case .success(let res):
            reply(wrapResult(res))
          case .failure(let error):
            reply(wrapError(error))
          }
        }
      }
    } else {
      retrieveCalendarsChannel.setMessageHandler(nil)
    }
    let deleteCalendarChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.easy_calendar.CalendarApi.deleteCalendar\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      deleteCalendarChannel.setMessageHandler { message, reply in
        let args = message as! [Any?]
        let calendarIdArg = args[0] as! String
        api.deleteCalendar(calendarIdArg) { result in
          switch result {
          case .success:
            reply(wrapResult(nil))
          case .failure(let error):
            reply(wrapError(error))
          }
        }
      }
    } else {
      deleteCalendarChannel.setMessageHandler(nil)
    }
    let createEventChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.easy_calendar.CalendarApi.createEvent\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      createEventChannel.setMessageHandler { message, reply in
        let args = message as! [Any?]
        let titleArg = args[0] as! String
        let startDateArg = args[1] as! Int64
        let endDateArg = args[2] as! Int64
        let calendarIdArg = args[3] as! String
        let isAllDayArg = args[4] as! Bool
        let descriptionArg: String? = nilOrValue(args[5])
        let urlArg: String? = nilOrValue(args[6])
        api.createEvent(title: titleArg, startDate: startDateArg, endDate: endDateArg, calendarId: calendarIdArg, isAllDay: isAllDayArg, description: descriptionArg, url: urlArg) { result in
          switch result {
          case .success(let res):
            reply(wrapResult(res))
          case .failure(let error):
            reply(wrapError(error))
          }
        }
      }
    } else {
      createEventChannel.setMessageHandler(nil)
    }
    let retrieveEventsChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.easy_calendar.CalendarApi.retrieveEvents\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      retrieveEventsChannel.setMessageHandler { message, reply in
        let args = message as! [Any?]
        let calendarIdArg = args[0] as! String
        let startDateArg = args[1] as! Int64
        let endDateArg = args[2] as! Int64
        api.retrieveEvents(calendarId: calendarIdArg, startDate: startDateArg, endDate: endDateArg) { result in
          switch result {
          case .success(let res):
            reply(wrapResult(res))
          case .failure(let error):
            reply(wrapError(error))
          }
        }
      }
    } else {
      retrieveEventsChannel.setMessageHandler(nil)
    }
    let deleteEventChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.easy_calendar.CalendarApi.deleteEvent\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      deleteEventChannel.setMessageHandler { message, reply in
        let args = message as! [Any?]
        let eventIdArg = args[0] as! String
        let calendarIdArg = args[1] as! String
        api.deleteEvent(withId: eventIdArg, calendarIdArg) { result in
          switch result {
          case .success:
            reply(wrapResult(nil))
          case .failure(let error):
            reply(wrapError(error))
          }
        }
      }
    } else {
      deleteEventChannel.setMessageHandler(nil)
    }
    let createReminderChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.easy_calendar.CalendarApi.createReminder\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      createReminderChannel.setMessageHandler { message, reply in
        let args = message as! [Any?]
        let reminderArg = args[0] as! Int64
        let eventIdArg = args[1] as! String
        api.createReminder(reminderArg, forEventId: eventIdArg) { result in
          switch result {
          case .success(let res):
            reply(wrapResult(res))
          case .failure(let error):
            reply(wrapError(error))
          }
        }
      }
    } else {
      createReminderChannel.setMessageHandler(nil)
    }
    let deleteReminderChannel = FlutterBasicMessageChannel(name: "dev.flutter.pigeon.easy_calendar.CalendarApi.deleteReminder\(channelSuffix)", binaryMessenger: binaryMessenger, codec: codec)
    if let api = api {
      deleteReminderChannel.setMessageHandler { message, reply in
        let args = message as! [Any?]
        let reminderArg = args[0] as! Int64
        let eventIdArg = args[1] as! String
        api.deleteReminder(reminderArg, withEventId: eventIdArg) { result in
          switch result {
          case .success(let res):
            reply(wrapResult(res))
          case .failure(let error):
            reply(wrapError(error))
          }
        }
      }
    } else {
      deleteReminderChannel.setMessageHandler(nil)
    }
  }
}
