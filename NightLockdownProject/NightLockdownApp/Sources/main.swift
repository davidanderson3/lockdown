import AppKit
import Foundation
import UserNotifications

struct TimeWindow: Codable {
    static let allWeekdays = Array(1...7)

    var weekdays: [Int]
    var startMinutes: Int
    var endMinutes: Int

    enum CodingKeys: String, CodingKey {
        case weekdays
        case startMinutes
        case endMinutes
    }

    init(startMinutes: Int, endMinutes: Int, weekdays: [Int] = TimeWindow.allWeekdays) {
        self.weekdays = Self.sanitizedWeekdays(weekdays)
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedWeekdays = try container.decodeIfPresent([Int].self, forKey: .weekdays) ?? Self.allWeekdays
        weekdays = Self.sanitizedWeekdays(decodedWeekdays)
        startMinutes = try container.decode(Int.self, forKey: .startMinutes)
        endMinutes = try container.decode(Int.self, forKey: .endMinutes)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.sanitizedWeekdays(weekdays), forKey: .weekdays)
        try container.encode(startMinutes, forKey: .startMinutes)
        try container.encode(endMinutes, forKey: .endMinutes)
    }

    static func fromHours(startHour: Int, endHour: Int) -> TimeWindow {
        TimeWindow(startMinutes: startHour * 60, endMinutes: endHour * 60)
    }

    func contains(_ minuteOfDay: Int, weekday: Int) -> Bool {
        let normalizedDays = Self.sanitizedWeekdays(weekdays)
        if startMinutes < endMinutes {
            return normalizedDays.contains(weekday) && minuteOfDay >= startMinutes && minuteOfDay < endMinutes
        }
        if startMinutes > endMinutes {
            let previousWeekday = weekday == 1 ? 7 : weekday - 1
            return (normalizedDays.contains(weekday) && minuteOfDay >= startMinutes)
                || (normalizedDays.contains(previousWeekday) && minuteOfDay < endMinutes)
        }
        return false
    }

    func toDisplayString() -> String {
        "\(daySummary()) \(Self.format(minutes: startMinutes))-\(Self.format(minutes: endMinutes))"
    }

    private func daySummary() -> String {
        let days = Self.sanitizedWeekdays(weekdays)
        if days == Self.allWeekdays {
            return "Every day"
        }
        if days == [2, 3, 4, 5, 6] {
            return "Weekdays"
        }
        if days == [1, 7] {
            return "Weekends"
        }
        return days.map(Self.shortWeekdayName).joined(separator: ", ")
    }

    static func shortWeekdayName(_ weekday: Int) -> String {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        guard (1...7).contains(weekday) else {
            return "?"
        }
        return names[weekday - 1]
    }

    private static func format(minutes: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date(forMinutes: minutes))
    }

    private static func date(forMinutes minutes: Int) -> Date {
        let clampedMinutes = max(0, min(23 * 60 + 59, minutes))
        let hour = clampedMinutes / 60
        let minute = clampedMinutes % 60

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = 2001
        components.month = 1
        components.day = 1
        components.hour = hour
        components.minute = minute
        return components.date ?? Date(timeIntervalSinceReferenceDate: 0)
    }

    private static func sanitizedWeekdays(_ weekdays: [Int]) -> [Int] {
        let filtered = Set(weekdays.filter { (1...7).contains($0) })
        let normalized = filtered.sorted()
        return normalized.isEmpty ? allWeekdays : normalized
    }
}

struct ScheduleEditorValidationError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

struct SettingsEditorValidationError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

struct LockdownConfig: Codable {
    var blockWindows: [TimeWindow]
    var distractingApps: [String]
    var checkIntervalSeconds: TimeInterval

    enum CodingKeys: String, CodingKey {
        case blockWindows
        case blockStartHour
        case blockEndHour
        case distractingApps
        case checkIntervalSeconds
    }

    init(blockWindows: [TimeWindow], distractingApps: [String], checkIntervalSeconds: TimeInterval) {
        self.blockWindows = blockWindows
        self.distractingApps = distractingApps
        self.checkIntervalSeconds = checkIntervalSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let decodedWindows = try container.decodeIfPresent([TimeWindow].self, forKey: .blockWindows), !decodedWindows.isEmpty {
            blockWindows = decodedWindows
        } else {
            let start = try container.decodeIfPresent(Int.self, forKey: .blockStartHour) ?? 21
            let end = try container.decodeIfPresent(Int.self, forKey: .blockEndHour) ?? 8
            blockWindows = [TimeWindow.fromHours(startHour: start, endHour: end)]
        }

        distractingApps = try container.decodeIfPresent([String].self, forKey: .distractingApps) ?? LockdownConfig.default.distractingApps
        checkIntervalSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .checkIntervalSeconds) ?? LockdownConfig.default.checkIntervalSeconds
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(blockWindows, forKey: .blockWindows)
        try container.encode(distractingApps, forKey: .distractingApps)
        try container.encode(checkIntervalSeconds, forKey: .checkIntervalSeconds)
    }

    static let `default` = LockdownConfig(
        blockWindows: [
            TimeWindow.fromHours(startHour: 21, endHour: 8)
        ],
        distractingApps: [
            "Safari",
            "Google Chrome",
            "Firefox",
            "Brave Browser",
            "Arc",
            "Microsoft Edge",
            "Slack",
            "Discord",
            "Messages",
            "Mail",
            "Xcode",
            "Steam",
            "Spotify",
            "Bluestacks"
        ],
        checkIntervalSeconds: 60
    )
}

final class ScheduleRowView: NSView {
    private let startPicker = NSDatePicker()
    private let endPicker = NSDatePicker()
    private let dayButtons: [NSButton]
    let removeButton = NSButton(title: "Remove", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        dayButtons = (1...7).map { day in
            NSButton(checkboxWithTitle: TimeWindow.shortWeekdayName(day), target: nil, action: nil)
        }
        super.init(frame: frameRect)
        buildUI()
        apply(window: TimeWindow.fromHours(startHour: 21, endHour: 8))
    }

    convenience init(window: TimeWindow) {
        self.init(frame: .zero)
        apply(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(window: TimeWindow) {
        let selectedDays = Set(window.weekdays)
        for (index, button) in dayButtons.enumerated() {
            let weekday = index + 1
            button.state = selectedDays.contains(weekday) ? .on : .off
        }
        startPicker.dateValue = Self.date(forMinutes: window.startMinutes)
        endPicker.dateValue = Self.date(forMinutes: window.endMinutes)
    }

    func setCanRemove(_ enabled: Bool) {
        removeButton.isEnabled = enabled
    }

    func selectedWeekdays() -> [Int] {
        dayButtons.enumerated().compactMap { index, button in
            button.state == .on ? index + 1 : nil
        }
    }

    func startMinutesValue() -> Int {
        Self.minutes(from: startPicker.dateValue)
    }

    func endMinutesValue() -> Int {
        Self.minutes(from: endPicker.dateValue)
    }

    func makeWindow() -> TimeWindow {
        return TimeWindow(
            startMinutes: startMinutesValue(),
            endMinutes: endMinutesValue(),
            weekdays: selectedWeekdays()
        )
    }

    private func buildUI() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        let daysLabel = Self.makeLabel("Days")
        let startLabel = Self.makeLabel("Start")
        let endLabel = Self.makeLabel("End")

        let dayStack = NSStackView(views: dayButtons)
        dayStack.orientation = .horizontal
        dayStack.alignment = .centerY
        dayStack.spacing = 8
        dayStack.distribution = .fillEqually

        configureTimePicker(startPicker)
        configureTimePicker(endPicker)

        let timeStack = NSStackView(views: [startLabel, startPicker, endLabel, endPicker, removeButton])
        timeStack.orientation = .horizontal
        timeStack.alignment = .centerY
        timeStack.spacing = 10

        let contentStack = NSStackView(views: [daysLabel, dayStack, timeStack])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            startPicker.widthAnchor.constraint(equalToConstant: 120),
            endPicker.widthAnchor.constraint(equalToConstant: 120)
        ])
    }

    private func configureTimePicker(_ picker: NSDatePicker) {
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.datePickerElements = .hourMinute
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerMode = .single
        picker.locale = Locale(identifier: "en_US_POSIX")
        picker.calendar = Calendar(identifier: .gregorian)
        picker.timeZone = TimeZone(secondsFromGMT: 0)
    }

    private static func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        return label
    }

    private static func minutes(from date: Date) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(secondsFromGMT: 0)!, from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func date(forMinutes minutes: Int) -> Date {
        let clampedMinutes = max(0, min(23 * 60 + 59, minutes))
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2001
        components.month = 1
        components.day = 1
        components.hour = clampedMinutes / 60
        components.minute = clampedMinutes % 60
        return components.date ?? Date(timeIntervalSinceReferenceDate: 0)
    }
}

final class ScheduleEditorView: NSView {
    private let rowsStack = NSStackView()
    private let addButton = NSButton(title: "Add Schedule", target: nil, action: nil)
    private var rowViews: [ScheduleRowView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
        addScheduleRow(window: TimeWindow.fromHours(startHour: 21, endHour: 8))
    }

    convenience init(windows: [TimeWindow]) {
        self.init(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        rowViews.forEach { row in
            rowsStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        rowViews.removeAll()

        let sourceWindows = windows.isEmpty ? [TimeWindow.fromHours(startHour: 21, endHour: 8)] : windows
        for window in sourceWindows {
            addScheduleRow(window: window)
        }
        refreshRemoveButtons()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func validatedWindows() throws -> [TimeWindow] {
        var windows: [TimeWindow] = []

        for (index, row) in rowViews.enumerated() {
            let weekdays = row.selectedWeekdays()
            let startMinutes = row.startMinutesValue()
            let endMinutes = row.endMinutesValue()

            if weekdays.isEmpty {
                throw ScheduleEditorValidationError(message: "Schedule \(index + 1) must include at least one day.")
            }
            if startMinutes == endMinutes {
                throw ScheduleEditorValidationError(message: "Schedule \(index + 1) must have different start and end times.")
            }

            windows.append(TimeWindow(startMinutes: startMinutes, endMinutes: endMinutes, weekdays: weekdays))
        }

        return windows
    }

    @objc private func addScheduleRowAction() {
        addScheduleRow(window: TimeWindow.fromHours(startHour: 21, endHour: 8))
    }

    @objc private func removeScheduleRowAction(_ sender: NSButton) {
        guard rowViews.count > 1 else {
            return
        }
        guard let row = rowViews.first(where: { $0.removeButton === sender }) else {
            return
        }
        rowsStack.removeArrangedSubview(row)
        row.removeFromSuperview()
        rowViews.removeAll { $0 === row }
        refreshRemoveButtons()
    }

    private func buildUI() {
        translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Recurring Lockdown Schedule")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let helpLabel = NSTextField(
            wrappingLabelWithString: "Choose the days and the start and end times for each recurring lockdown window. End times earlier than start times continue into the next day."
        )
        helpLabel.font = NSFont.systemFont(ofSize: 12)
        helpLabel.maximumNumberOfLines = 2

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 12
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        addButton.target = self
        addButton.action = #selector(addScheduleRowAction)
        addButton.bezelStyle = .rounded

        let rootStack = NSStackView(views: [titleLabel, helpLabel, rowsStack, addButton])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 12
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(rootStack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 640),
            heightAnchor.constraint(equalToConstant: 420),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            rowsStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor)
        ])
    }

    private func addScheduleRow(window: TimeWindow) {
        let row = ScheduleRowView(window: window)
        row.removeButton.target = self
        row.removeButton.action = #selector(removeScheduleRowAction(_:))
        rowViews.append(row)
        rowsStack.addArrangedSubview(row)
        refreshRemoveButtons()
    }

    private func refreshRemoveButtons() {
        let canRemove = rowViews.count > 1
        rowViews.forEach { $0.setCanRemove(canRemove) }
    }
}

final class AppListRowView: NSView {
    private let nameField = NSTextField()
    let removeButton = NSButton(title: "Remove", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
    }

    convenience init(appName: String) {
        self.init(frame: .zero)
        nameField.stringValue = appName
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setCanRemove(_ enabled: Bool) {
        removeButton.isEnabled = enabled
    }

    func appName() -> String {
        nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildUI() {
        translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "App")
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)

        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameField.placeholderString = "Safari"

        let rowStack = NSStackView(views: [label, nameField, removeButton])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 10
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(rowStack)

        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            rowStack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 280)
        ])
    }
}

final class AppListEditorView: NSView {
    private let rowsStack = NSStackView()
    private let addButton = NSButton(title: "Add App", target: nil, action: nil)
    private var rowViews: [AppListRowView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildUI()
        addRow(appName: "Safari")
    }

    convenience init(apps: [String]) {
        self.init(frame: .zero)
        rowViews.forEach { row in
            rowsStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        rowViews.removeAll()

        let sourceApps = apps.isEmpty ? ["Safari"] : apps
        for app in sourceApps {
            addRow(appName: app)
        }
        refreshRemoveButtons()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func validatedApps() throws -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        for (index, row) in rowViews.enumerated() {
            let name = row.appName()
            if name.isEmpty {
                throw SettingsEditorValidationError(message: "Blocked app \(index + 1) cannot be blank.")
            }

            let key = name.lowercased()
            if seen.insert(key).inserted {
                result.append(name)
            }
        }

        if result.isEmpty {
            throw SettingsEditorValidationError(message: "Add at least one blocked app.")
        }

        return result
    }

    @objc private func addRowAction() {
        addRow(appName: "")
    }

    @objc private func removeRowAction(_ sender: NSButton) {
        guard rowViews.count > 1 else {
            return
        }
        guard let row = rowViews.first(where: { $0.removeButton === sender }) else {
            return
        }
        rowsStack.removeArrangedSubview(row)
        row.removeFromSuperview()
        rowViews.removeAll { $0 === row }
        refreshRemoveButtons()
    }

    private func buildUI() {
        translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Blocked Apps")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let helpLabel = NSTextField(
            wrappingLabelWithString: "These app names are quit during lockdown and force-killed if needed. Use the visible app names from macOS, like Safari or Google Chrome."
        )
        helpLabel.font = NSFont.systemFont(ofSize: 12)
        helpLabel.maximumNumberOfLines = 3

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 8
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        addButton.target = self
        addButton.action = #selector(addRowAction)
        addButton.bezelStyle = .rounded

        let rootStack = NSStackView(views: [titleLabel, helpLabel, rowsStack, addButton])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 12
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(rootStack)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 640),
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rootStack.topAnchor.constraint(equalTo: topAnchor),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor),
            rowsStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor)
        ])
    }

    private func addRow(appName: String) {
        let row = AppListRowView(appName: appName)
        row.removeButton.target = self
        row.removeButton.action = #selector(removeRowAction(_:))
        rowViews.append(row)
        rowsStack.addArrangedSubview(row)
        refreshRemoveButtons()
    }

    private func refreshRemoveButtons() {
        let canRemove = rowViews.count > 1
        rowViews.forEach { $0.setCanRemove(canRemove) }
    }
}

final class LockdownSettingsEditorView: NSView {
    private let scheduleEditor: ScheduleEditorView
    private let appListEditor: AppListEditorView
    private let intervalField = NSTextField()
    private let intervalStepper = NSStepper()

    init(config: LockdownConfig) {
        scheduleEditor = ScheduleEditorView(windows: config.blockWindows)
        appListEditor = AppListEditorView(apps: config.distractingApps)
        super.init(frame: NSRect(x: 0, y: 0, width: 700, height: 560))
        buildUI(checkIntervalSeconds: config.checkIntervalSeconds)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func validatedConfig() throws -> LockdownConfig {
        let windows = try scheduleEditor.validatedWindows()
        let apps = try appListEditor.validatedApps()
        let rawValue = intervalField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let interval = Int(rawValue) else {
            throw SettingsEditorValidationError(message: "Check interval must be a whole number of seconds.")
        }
        guard interval >= 15 else {
            throw SettingsEditorValidationError(message: "Check interval must be at least 15 seconds.")
        }
        guard interval <= 3600 else {
            throw SettingsEditorValidationError(message: "Check interval must be 3600 seconds or less.")
        }

        return LockdownConfig(
            blockWindows: windows,
            distractingApps: apps,
            checkIntervalSeconds: TimeInterval(interval)
        )
    }

    @objc private func stepInterval(_ sender: NSStepper) {
        intervalField.stringValue = String(Int(sender.integerValue))
    }

    private func buildUI(checkIntervalSeconds: TimeInterval) {
        translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: "Lockdown Settings")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let helpLabel = NSTextField(
            wrappingLabelWithString: "Manage the weekly schedule, blocked apps, and how often the app re-checks whether lockdown should be enforced."
        )
        helpLabel.font = NSFont.systemFont(ofSize: 12)
        helpLabel.maximumNumberOfLines = 2

        let intervalLabel = NSTextField(labelWithString: "Check Interval")
        intervalLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let intervalHelpLabel = NSTextField(
            wrappingLabelWithString: "How often the app re-checks the schedule and re-enforces lockdown if needed."
        )
        intervalHelpLabel.font = NSFont.systemFont(ofSize: 12)
        intervalHelpLabel.maximumNumberOfLines = 2

        intervalField.translatesAutoresizingMaskIntoConstraints = false
        intervalField.alignment = .right
        intervalField.placeholderString = "60"
        intervalField.stringValue = String(Int(checkIntervalSeconds))

        let secondsLabel = NSTextField(labelWithString: "seconds")

        intervalStepper.translatesAutoresizingMaskIntoConstraints = false
        intervalStepper.minValue = 15
        intervalStepper.maxValue = 3600
        intervalStepper.increment = 15
        intervalStepper.integerValue = Int(checkIntervalSeconds)
        intervalStepper.target = self
        intervalStepper.action = #selector(stepInterval(_:))

        let intervalRow = NSStackView(views: [intervalField, secondsLabel, intervalStepper])
        intervalRow.orientation = .horizontal
        intervalRow.alignment = .centerY
        intervalRow.spacing = 10

        let intervalSection = NSStackView(views: [intervalLabel, intervalHelpLabel, intervalRow])
        intervalSection.orientation = .vertical
        intervalSection.alignment = .leading
        intervalSection.spacing = 8

        let contentStack = NSStackView(views: [titleLabel, helpLabel, scheduleEditor, appListEditor, intervalSection])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 18
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(contentStack)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView

        addSubview(scrollView)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 700),
            heightAnchor.constraint(equalToConstant: 560),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 14),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -14),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 14),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -14),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            intervalField.widthAnchor.constraint(equalToConstant: 64)
        ])
    }
}

final class LockdownController: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSWindowDelegate {
    private let appName = "Lockdown Ready"
    private let manualLockDuration: TimeInterval = 30 * 60
    private var timer: Timer?
    private var manualLockUntil: Date?
    private var hasLockedInCurrentWindow = false
    private var mainWindow: NSWindow?
    private var settingsEditor: LockdownSettingsEditorView?
    private var statusItem: NSStatusItem?
    private let stateLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")

    private lazy var configURL: URL = {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("LockdownReady", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let configURL = folder.appendingPathComponent("config.json")
        let legacyURL = appSupport
            .appendingPathComponent("NightLockdown", isDirectory: true)
            .appendingPathComponent("config.json")

        if !fm.fileExists(atPath: configURL.path), fm.fileExists(atPath: legacyURL.path) {
            try? fm.copyItem(at: legacyURL, to: configURL)
        }

        return configURL
    }()

    private var config: LockdownConfig = .default

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermission()
        loadOrCreateConfig()
        configureMainWindow()
        runEnforcementCycle(trigger: "startup")
        startScheduler()
        if isLockdownActive(now: Date()) {
            ensureStatusItem()
            updateStatusItem()
        } else {
            showMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideMainWindowToStatusBar()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func configureMainWindow() {
        let window: NSWindow
        if let existingWindow = mainWindow {
            window = existingWindow
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 860),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 860, height: 760)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.delegate = self
            mainWindow = window
        }

        window.title = appName

        let backgroundView = NSVisualEffectView()
        backgroundView.material = .underWindowBackground
        backgroundView.state = .active
        backgroundView.blendingMode = .behindWindow
        backgroundView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: appName)
        titleLabel.font = NSFont.systemFont(ofSize: 34, weight: .black)

        let subtitleLabel = NSTextField(
            wrappingLabelWithString: "Lock your Mac when you need a real break. Start a quick timeout, or set recurring windows so screen-time boundaries happen automatically."
        )
        subtitleLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        subtitleLabel.textColor = NSColor.secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 3

        stateLabel.font = NSFont.systemFont(ofSize: 24, weight: .black)
        detailLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        detailLabel.textColor = NSColor.secondaryLabelColor
        detailLabel.maximumNumberOfLines = 5

        let startButton = makeActionButton(
            title: "Start Lockdown (30 Minutes)",
            action: #selector(startManualLockdown),
            bezelColor: NSColor.systemRed
        )

        let saveButton = makeActionButton(
            title: "Save Settings",
            action: #selector(saveSettings),
            bezelColor: NSColor.systemBlue
        )

        let reloadButton = makeActionButton(
            title: "Reload From Disk",
            action: #selector(reloadConfig),
            bezelColor: NSColor.systemTeal
        )

        let openConfigButton = makeActionButton(
            title: "Open Raw Config File",
            action: #selector(openConfig),
            bezelColor: NSColor.systemGray
        )

        let quitButton = makeActionButton(
            title: "Quit",
            action: #selector(quitApp),
            bezelColor: NSColor.systemGray
        )

        let heroStack = NSStackView(views: [titleLabel, subtitleLabel, stateLabel, detailLabel])
        heroStack.orientation = .vertical
        heroStack.alignment = .leading
        heroStack.spacing = 12
        heroStack.translatesAutoresizingMaskIntoConstraints = false

        let primaryActions = NSStackView(views: [startButton, saveButton, reloadButton])
        primaryActions.orientation = .horizontal
        primaryActions.alignment = .centerY
        primaryActions.distribution = .fillEqually
        primaryActions.spacing = 12
        primaryActions.translatesAutoresizingMaskIntoConstraints = false

        let secondaryActions = NSStackView(views: [openConfigButton, quitButton])
        secondaryActions.orientation = .horizontal
        secondaryActions.alignment = .centerY
        secondaryActions.distribution = .fillEqually
        secondaryActions.spacing = 12
        secondaryActions.translatesAutoresizingMaskIntoConstraints = false

        let heroCard = makeCard(backgroundColor: NSColor(calibratedRed: 0.95, green: 0.97, blue: 1.0, alpha: 0.95))
        heroCard.addSubview(heroStack)
        heroCard.addSubview(primaryActions)
        heroCard.addSubview(secondaryActions)

        let settingsTitle = NSTextField(labelWithString: "Settings")
        settingsTitle.font = NSFont.systemFont(ofSize: 20, weight: .bold)

        let settingsSubtitle = NSTextField(
            wrappingLabelWithString: "Everything is editable on this first screen: schedule, blocked apps, and enforcement interval."
        )
        settingsSubtitle.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        settingsSubtitle.textColor = NSColor.secondaryLabelColor
        settingsSubtitle.maximumNumberOfLines = 2

        let settingsEditor = LockdownSettingsEditorView(config: config)
        self.settingsEditor = settingsEditor

        let settingsStack = NSStackView(views: [settingsTitle, settingsSubtitle, settingsEditor])
        settingsStack.orientation = .vertical
        settingsStack.alignment = .leading
        settingsStack.spacing = 14
        settingsStack.translatesAutoresizingMaskIntoConstraints = false

        let settingsCard = makeCard(backgroundColor: NSColor.windowBackgroundColor.withAlphaComponent(0.96))
        settingsCard.addSubview(settingsStack)

        let rootStack = NSStackView(views: [heroCard, settingsCard])
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 18
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(rootStack)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView

        backgroundView.addSubview(scrollView)
        window.contentView = backgroundView

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),

            rootStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 22),
            rootStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -22),
            rootStack.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 22),
            rootStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -22),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            heroStack.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 22),
            heroStack.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor, constant: -22),
            heroStack.topAnchor.constraint(equalTo: heroCard.topAnchor, constant: 22),

            primaryActions.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 22),
            primaryActions.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor, constant: -22),
            primaryActions.topAnchor.constraint(equalTo: heroStack.bottomAnchor, constant: 18),

            secondaryActions.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 22),
            secondaryActions.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor, constant: -22),
            secondaryActions.topAnchor.constraint(equalTo: primaryActions.bottomAnchor, constant: 10),
            secondaryActions.bottomAnchor.constraint(equalTo: heroCard.bottomAnchor, constant: -22),

            settingsStack.leadingAnchor.constraint(equalTo: settingsCard.leadingAnchor, constant: 22),
            settingsStack.trailingAnchor.constraint(equalTo: settingsCard.trailingAnchor, constant: -22),
            settingsStack.topAnchor.constraint(equalTo: settingsCard.topAnchor, constant: 22),
            settingsStack.bottomAnchor.constraint(equalTo: settingsCard.bottomAnchor, constant: -22),
            heroCard.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            settingsCard.widthAnchor.constraint(equalTo: rootStack.widthAnchor)
        ])

        rebuildMenu()
    }

    private func showMainWindow() {
        let now = Date()
        if isLockdownActive(now: now) {
            ensureStatusItem()
            updateStatusItem(now: now)
            mainWindow?.orderOut(nil)
            lockScreen()
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
        removeStatusItem()
    }

    private func hideMainWindowToStatusBar() {
        mainWindow?.orderOut(nil)
        ensureStatusItem()
        updateStatusItem()
        notify(title: appName, body: "Window hidden. \(appName) is still running in the menu bar.")
    }

    private func rebuildMenu() {
        let now = Date()
        let title: String
        let detail: String
        let color: NSColor

        if let manualLockUntil, now < manualLockUntil {
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .short
            title = "LOCKED NOW"
            detail = "Manual lockdown ends \(fmt.localizedString(for: manualLockUntil, relativeTo: now)).\n\(scheduleSummary())"
            color = .systemRed
        } else if inBlockWindow(now: now) {
            title = "LOCKDOWN ACTIVE"
            detail = "The current schedule is active.\n\(scheduleSummary())"
            color = .systemRed
        } else {
            title = "LOCKDOWN READY"
            detail = "Window closed does not stop enforcement.\n\(scheduleSummary())"
            color = .systemBlue
        }

        stateLabel.stringValue = title
        stateLabel.textColor = color
        detailLabel.stringValue = detail
        updateStatusItem(now: now)
    }

    private func ensureStatusItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem?.button?.imagePosition = .imageLeading
        }
    }

    private func removeStatusItem() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func updateStatusItem(now: Date = Date()) {
        guard statusItem != nil else {
            return
        }

        let symbolName: String
        let title: String

        let lockdownActive = isLockdownActive(now: now)

        if let manualLockUntil, now < manualLockUntil {
            symbolName = "lock.circle.fill"
            title = "Lockdown Ready: Locked"
        } else if inBlockWindow(now: now) {
            symbolName = "lock.shield.fill"
            title = "Lockdown Ready: Active"
        } else {
            symbolName = "moon.stars.fill"
            title = "Lockdown Ready"
        }

        if let button = statusItem?.button {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold, scale: .medium)
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: appName)?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
            button.title = " \(title)"
            button.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        }

        let menu = NSMenu()
        let stateItem = NSMenuItem(title: stateLine(now: now), action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(NSMenuItem.separator())

        if lockdownActive {
            let lockedItem = NSMenuItem(title: "Lockdown active. Controls unavailable.", action: nil, keyEquivalent: "")
            lockedItem.isEnabled = false
            menu.addItem(lockedItem)
        } else {
            menu.addItem(withTitle: "Show Window", action: #selector(showWindowFromStatusBar), keyEquivalent: "")
            menu.addItem(withTitle: "Start Lockdown (30 Minutes)", action: #selector(startManualLockdown), keyEquivalent: "")
            menu.addItem(withTitle: "Reload From Disk", action: #selector(reloadConfig), keyEquivalent: "")
            menu.addItem(withTitle: "Quit", action: #selector(quitApp), keyEquivalent: "")
        }

        for item in menu.items {
            item.target = self
        }

        statusItem?.menu = menu
    }

    private func makeCard(backgroundColor: NSColor) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.cornerRadius = 24
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = backgroundColor.cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        return view
    }

    private func makeActionButton(title: String, action: Selector, bezelColor: NSColor) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        styleButton(button, bezelColor: bezelColor)
        return button
    }

    private func styleButton(_ button: NSButton, bezelColor: NSColor) {
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        button.isBordered = true
        button.bezelColor = bezelColor
    }

    private func startScheduler() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(15, config.checkIntervalSeconds), repeats: true) { [weak self] _ in
            self?.runEnforcementCycle(trigger: "timer")
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func loadOrCreateConfig() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configURL.path) {
            saveConfig(LockdownConfig.default)
            config = .default
            return
        }

        do {
            let data = try Data(contentsOf: configURL)
            config = try JSONDecoder().decode(LockdownConfig.self, from: data)
        } catch {
            config = .default
            saveConfig(config)
            notify(title: appName, body: "Config was invalid and has been reset to defaults.")
        }
    }

    private func saveConfig(_ newConfig: LockdownConfig) {
        do {
            let data = try JSONEncoder().encode(newConfig)
            try data.write(to: configURL, options: [.atomic])
        } catch {
            NSLog("Failed to save config: \(error.localizedDescription)")
        }
    }

    private func inBlockWindow(now: Date = Date()) -> Bool {
        let comps = Calendar.current.dateComponents([.weekday, .hour, .minute], from: now)
        let minuteOfDay = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let weekday = comps.weekday ?? 1
        return config.blockWindows.contains { $0.contains(minuteOfDay, weekday: weekday) }
    }

    private func isManualLockActive(now: Date = Date()) -> Bool {
        guard let manualLockUntil else {
            return false
        }
        if now < manualLockUntil {
            return true
        }
        self.manualLockUntil = nil
        return false
    }

    private func isLockdownActive(now: Date = Date()) -> Bool {
        inBlockWindow(now: now) || isManualLockActive(now: now)
    }

    private func stateLine(now: Date = Date()) -> String {
        let windows = config.blockWindows.map { $0.toDisplayString() }.joined(separator: ", ")
        let state: String
        if let manualLockUntil, now < manualLockUntil {
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .short
            state = "ACTIVE (manual, ends \(fmt.localizedString(for: manualLockUntil, relativeTo: now)))"
        } else if inBlockWindow(now: now) {
            state = "ACTIVE"
        } else {
            state = "Idle"
        }
        return "\(state) · \(windows)"
    }

    private func scheduleSummary() -> String {
        "Schedule: \(config.blockWindows.map { $0.toDisplayString() }.joined(separator: ", "))"
    }

    private func runEnforcementCycle(trigger: String) {
        let now = Date()
        defer {
            rebuildMenu()
        }

        let scheduledLock = inBlockWindow(now: now)
        let manualLock = isManualLockActive(now: now)

        guard scheduledLock || manualLock else {
            hasLockedInCurrentWindow = false
            enableWiFi()
            return
        }

        disableWiFi()
        quitApps()
        killStubbornProcesses()
        mainWindow?.orderOut(nil)
        ensureStatusItem()
        updateStatusItem(now: now)

        if !hasLockedInCurrentWindow || trigger == "manual-start" {
            lockScreen()
            hasLockedInCurrentWindow = true
            let body = manualLock && !scheduledLock
                ? "Manual lockdown started for 30 minutes."
                : "Lockdown enforced."
            notify(title: appName, body: body)
        }
    }

    @objc private func startManualLockdown() {
        manualLockUntil = Date().addingTimeInterval(manualLockDuration)
        runEnforcementCycle(trigger: "manual-start")
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(configURL)
    }

    @objc private func configureSettings() {
        showMainWindow()
    }

    @objc private func showWindowFromStatusBar() {
        showMainWindow()
    }

    @objc private func saveSettings() {
        guard let settingsEditor else {
            return
        }

        do {
            config = try settingsEditor.validatedConfig()
            saveConfig(config)
            startScheduler()
            runEnforcementCycle(trigger: "config-update")
            notify(title: appName, body: "Lockdown settings updated.")
            rebuildMenu()
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Invalid settings"
            errorAlert.informativeText = error.localizedDescription
            errorAlert.alertStyle = .warning
            errorAlert.runModal()
        }
    }

    @objc private func reloadConfig() {
        loadOrCreateConfig()
        startScheduler()
        configureMainWindow()
        notify(title: appName, body: "Configuration reloaded.")
        rebuildMenu()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func run(_ launchPath: String, _ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            NSLog("Command failed: \(launchPath) \(args.joined(separator: " ")) :: \(error.localizedDescription)")
        }
    }

    private func wifiDevice() -> String? {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-listallhardwareports"]
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else { return nil }

            var sawWiFi = false
            for line in text.components(separatedBy: .newlines) {
                if line.contains("Hardware Port: Wi-Fi") || line.contains("Hardware Port: AirPort") {
                    sawWiFi = true
                    continue
                }
                if sawWiFi, line.trimmingCharacters(in: .whitespaces).hasPrefix("Device:") {
                    return line
                        .replacingOccurrences(of: "Device:", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } catch {
            NSLog("Failed to detect Wi-Fi device: \(error.localizedDescription)")
        }

        return nil
    }

    private func disableWiFi() {
        guard let device = wifiDevice(), !device.isEmpty else { return }
        run("/usr/sbin/networksetup", ["-setairportpower", device, "off"])
    }

    private func enableWiFi() {
        guard let device = wifiDevice(), !device.isEmpty else { return }
        run("/usr/sbin/networksetup", ["-setairportpower", device, "on"])
    }

    private func lockScreen() {
        let cgSession = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
        if FileManager.default.isExecutableFile(atPath: cgSession) {
            run(cgSession, ["-suspend"])
        } else {
            run("/usr/bin/pmset", ["displaysleepnow"])
        }
    }

    private func quitApps() {
        for app in config.distractingApps {
            let escaped = app.replacingOccurrences(of: "\"", with: "\\\"")
            run("/usr/bin/osascript", ["-e", "tell application \"\(escaped)\" to quit"])
        }
    }

    private func killStubbornProcesses() {
        for app in config.distractingApps {
            run("/usr/bin/pkill", ["-x", app])
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

let app = NSApplication.shared
let delegate = LockdownController()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
