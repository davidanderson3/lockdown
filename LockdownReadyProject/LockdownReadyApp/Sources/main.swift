import AppKit
import Foundation
import UserNotifications

private let uiBackgroundColor = NSColor(calibratedRed: 0.93, green: 0.95, blue: 0.99, alpha: 1.0)
private let uiCardColor = NSColor(calibratedRed: 0.99, green: 0.97, blue: 0.92, alpha: 1.0)
private let uiInputColor = NSColor.white
private let uiButtonColor = NSColor(calibratedRed: 0.86, green: 0.9, blue: 0.97, alpha: 1.0)
private let uiBorderColor = NSColor(calibratedRed: 0.71, green: 0.78, blue: 0.88, alpha: 1.0)
private let uiTextColor = NSColor.black
private let uiStartButtonColor = NSColor(calibratedRed: 0.99, green: 0.8, blue: 0.74, alpha: 1.0)
private let uiSaveButtonColor = NSColor(calibratedRed: 0.8, green: 0.93, blue: 0.84, alpha: 1.0)
private let uiQuitButtonColor = NSColor(calibratedRed: 0.85, green: 0.88, blue: 0.95, alpha: 1.0)
private let uiPanelTintColor = NSColor(calibratedRed: 0.97, green: 0.98, blue: 1.0, alpha: 1.0)
private let uiPreviewBackgroundColor = NSColor(calibratedRed: 0.99, green: 0.98, blue: 0.95, alpha: 1.0)

private func styleNeutralButton(
    _ button: NSButton,
    controlSize: NSControl.ControlSize = .regular,
    fillColor: NSColor = uiButtonColor
) {
    button.bezelStyle = .rounded
    button.controlSize = controlSize
    button.font = NSFont.systemFont(ofSize: controlSize == .large ? 13 : 12, weight: .semibold)
    button.isBordered = true
    button.bezelColor = fillColor
    button.contentTintColor = uiTextColor
}

private func styleCheckboxButton(_ button: NSButton) {
    let title = button.title
    button.attributedTitle = NSAttributedString(
        string: title,
        attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: uiTextColor
        ]
    )
    button.contentTintColor = uiTextColor
}

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
    var onChange: (() -> Void)?

    override init(frame frameRect: NSRect) {
        dayButtons = (1...7).map { day in
            let button = NSButton(checkboxWithTitle: TimeWindow.shortWeekdayName(day), target: nil, action: nil)
            styleCheckboxButton(button)
            return button
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
        layer?.backgroundColor = uiPanelTintColor.cgColor
        layer?.borderColor = uiBorderColor.cgColor

        let daysLabel = Self.makeLabel("Days")
        let startLabel = Self.makeLabel("Start")
        let endLabel = Self.makeLabel("End")

        let dayStack = NSStackView(views: dayButtons)
        dayStack.orientation = .horizontal
        dayStack.alignment = .centerY
        dayStack.spacing = 8
        dayStack.distribution = .fillEqually
        for button in dayButtons {
            button.target = self
            button.action = #selector(handleValueChanged)
        }

        configureTimePicker(startPicker)
        configureTimePicker(endPicker)
        styleNeutralButton(removeButton)

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
        picker.target = self
        picker.action = #selector(handleValueChanged)
    }

    @objc private func handleValueChanged() {
        onChange?()
    }

    private static func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = uiTextColor
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

final class WeeklySchedulePreviewView: NSView {
    var windows: [TimeWindow] = [] {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.backgroundColor = uiPreviewBackgroundColor.cgColor
        layer?.borderColor = uiBorderColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        uiPreviewBackgroundColor.setFill()
        dirtyRect.fill()

        let leftLabelWidth: CGFloat = 44
        let topInset: CGFloat = 12
        let rightInset: CGFloat = 12
        let bottomInset: CGFloat = 26
        let chartRect = NSRect(
            x: leftLabelWidth,
            y: topInset,
            width: max(0, bounds.width - leftLabelWidth - rightInset),
            height: max(0, bounds.height - topInset - bottomInset)
        )

        guard chartRect.width > 0, chartRect.height > 0 else {
            return
        }

        let rowHeight = chartRect.height / 7
        let columnWidth = chartRect.width / 24
        let gridBorder = NSColor(calibratedRed: 0.79, green: 0.82, blue: 0.88, alpha: 1.0)
        let blockedFill = NSColor(calibratedRed: 0.37, green: 0.58, blue: 0.9, alpha: 0.88)
        let openFill = NSColor(calibratedRed: 0.97, green: 0.93, blue: 0.86, alpha: 1.0)
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: uiTextColor
        ]

        for day in 1...7 {
            let y = chartRect.minY + CGFloat(day - 1) * rowHeight
            let label = TimeWindow.shortWeekdayName(day)
            let labelSize = label.size(withAttributes: textAttributes)
            label.draw(
                at: NSPoint(x: 6, y: y + (rowHeight - labelSize.height) / 2),
                withAttributes: textAttributes
            )

            for hour in 0..<24 {
                let rect = NSRect(
                    x: chartRect.minX + CGFloat(hour) * columnWidth,
                    y: y,
                    width: columnWidth,
                    height: rowHeight
                )
                let blocked = windows.contains { window in
                    Self.hourIntersects(window: window, weekday: day, hour: hour)
                }
                (blocked ? blockedFill : openFill).setFill()
                rect.fill()
                gridBorder.setStroke()
                NSBezierPath(rect: rect).stroke()
            }
        }

        let hourLabels: [(Int, String)] = [(0, "12a"), (6, "6a"), (12, "12p"), (18, "6p"), (24, "12a")]
        for (hour, label) in hourLabels {
            let x = chartRect.minX + CGFloat(hour) * columnWidth
            let size = label.size(withAttributes: textAttributes)
            let drawX = min(max(chartRect.minX, x - size.width / 2), chartRect.maxX - size.width)
            label.draw(
                at: NSPoint(x: drawX, y: chartRect.maxY + 4),
                withAttributes: textAttributes
            )
        }
    }

    private static func hourIntersects(window: TimeWindow, weekday: Int, hour: Int) -> Bool {
        let startMinute = hour * 60
        return [0, 15, 30, 45].contains { offset in
            window.contains(startMinute + offset, weekday: weekday)
        }
    }
}

final class ScheduleEditorView: NSView {
    private let summaryLabel = NSTextField(labelWithString: "")
    private let previewView = WeeklySchedulePreviewView()
    private let rowsStack = NSStackView()
    private let addButton = NSButton(title: "Add Lock Window", target: nil, action: nil)
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
        titleLabel.textColor = uiTextColor

        let helpLabel = NSTextField(
            wrappingLabelWithString: "Choose the days and the start and end times for each recurring lockdown window. End times earlier than start times continue into the next day."
        )
        helpLabel.font = NSFont.systemFont(ofSize: 12)
        helpLabel.textColor = uiTextColor
        helpLabel.maximumNumberOfLines = 2

        summaryLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        summaryLabel.textColor = uiTextColor
        summaryLabel.maximumNumberOfLines = 3

        let previewLabel = NSTextField(labelWithString: "Blocked Time Preview")
        previewLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        previewLabel.textColor = uiTextColor

        previewView.translatesAutoresizingMaskIntoConstraints = false

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 12
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        addButton.target = self
        addButton.action = #selector(addScheduleRowAction)
        styleNeutralButton(addButton, fillColor: uiSaveButtonColor)

        let rootStack = NSStackView(views: [titleLabel, helpLabel, summaryLabel, previewLabel, previewView, rowsStack, addButton])
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
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
            rowsStack.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            previewView.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            previewView.heightAnchor.constraint(equalToConstant: 210)
        ])
    }

    private func addScheduleRow(window: TimeWindow) {
        let row = ScheduleRowView(window: window)
        row.onChange = { [weak self] in
            self?.updatePreview()
        }
        row.removeButton.target = self
        row.removeButton.action = #selector(removeScheduleRowAction(_:))
        rowViews.append(row)
        rowsStack.addArrangedSubview(row)
        refreshRemoveButtons()
        updatePreview()
    }

    private func refreshRemoveButtons() {
        let canRemove = rowViews.count > 1
        rowViews.forEach { $0.setCanRemove(canRemove) }
    }

    private func updatePreview() {
        let windows: [TimeWindow] = rowViews.compactMap { row in
            let weekdays = row.selectedWeekdays()
            let startMinutes = row.startMinutesValue()
            let endMinutes = row.endMinutesValue()
            guard !weekdays.isEmpty, startMinutes != endMinutes else {
                return nil
            }
            return TimeWindow(startMinutes: startMinutes, endMinutes: endMinutes, weekdays: weekdays)
        }
        previewView.windows = windows
        summaryLabel.stringValue = windows.isEmpty
            ? "Schedule: None"
            : "Schedule: " + windows.map { $0.toDisplayString() }.joined(separator: ", ")
    }
}

final class LockdownSettingsEditorView: NSView {
    private let scheduleEditor: ScheduleEditorView
    private let distractingApps: [String]
    private let checkIntervalSeconds: TimeInterval

    init(config: LockdownConfig) {
        scheduleEditor = ScheduleEditorView(windows: config.blockWindows)
        distractingApps = config.distractingApps
        checkIntervalSeconds = config.checkIntervalSeconds
        super.init(frame: NSRect(x: 0, y: 0, width: 700, height: 640))
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func validatedConfig() throws -> LockdownConfig {
        let windows = try scheduleEditor.validatedWindows()

        return LockdownConfig(
            blockWindows: windows,
            distractingApps: distractingApps,
            checkIntervalSeconds: checkIntervalSeconds
        )
    }

    private func buildUI() {
        translatesAutoresizingMaskIntoConstraints = false

        let contentStack = NSStackView(views: [scheduleEditor])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 18
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(contentStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 640),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor)
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
        return folder.appendingPathComponent("config.json")
    }()

    private var config: LockdownConfig = .default

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
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
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = uiBackgroundColor

        let backgroundView = NSView()
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = uiBackgroundColor.cgColor
        backgroundView.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: appName)
        titleLabel.font = NSFont.systemFont(ofSize: 34, weight: .black)
        titleLabel.textColor = uiTextColor

        let subtitleLabel = NSTextField(
            wrappingLabelWithString: "Lock your Mac when you need a real break. Start a quick timeout, or set recurring windows so screen-time boundaries happen automatically."
        )
        subtitleLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        subtitleLabel.textColor = uiTextColor
        subtitleLabel.maximumNumberOfLines = 3

        stateLabel.font = NSFont.systemFont(ofSize: 24, weight: .black)
        stateLabel.textColor = uiTextColor
        detailLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        detailLabel.textColor = uiTextColor
        detailLabel.maximumNumberOfLines = 5

        let startButton = makeActionButton(
            title: "Start Lockdown (30 Minutes)",
            action: #selector(startManualLockdown),
            fillColor: uiStartButtonColor
        )

        let saveButton = makeActionButton(
            title: "Save Settings",
            action: #selector(saveSettings),
            fillColor: uiSaveButtonColor
        )

        let quitButton = makeActionButton(
            title: "Quit",
            action: #selector(quitApp),
            fillColor: uiQuitButtonColor
        )

        let heroStack = NSStackView(views: [titleLabel, subtitleLabel, stateLabel, detailLabel])
        heroStack.orientation = .vertical
        heroStack.alignment = .leading
        heroStack.spacing = 12
        heroStack.translatesAutoresizingMaskIntoConstraints = false

        let primaryActions = NSStackView(views: [startButton, saveButton, quitButton])
        primaryActions.orientation = .horizontal
        primaryActions.alignment = .centerY
        primaryActions.distribution = .fillEqually
        primaryActions.spacing = 12
        primaryActions.translatesAutoresizingMaskIntoConstraints = false

        let heroCard = makeCard(backgroundColor: uiCardColor)
        heroCard.addSubview(heroStack)
        heroCard.addSubview(primaryActions)

        let settingsEditor = LockdownSettingsEditorView(config: config)
        self.settingsEditor = settingsEditor
        settingsEditor.translatesAutoresizingMaskIntoConstraints = false
        heroCard.addSubview(settingsEditor)

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(heroCard)

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

            heroCard.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 22),
            heroCard.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -22),
            heroCard.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 22),
            heroCard.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -22),
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            heroStack.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 22),
            heroStack.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor, constant: -22),
            heroStack.topAnchor.constraint(equalTo: heroCard.topAnchor, constant: 22),

            primaryActions.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 22),
            primaryActions.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor, constant: -22),
            primaryActions.topAnchor.constraint(equalTo: heroStack.bottomAnchor, constant: 18),
            settingsEditor.leadingAnchor.constraint(equalTo: heroCard.leadingAnchor, constant: 22),
            settingsEditor.trailingAnchor.constraint(equalTo: heroCard.trailingAnchor, constant: -22),
            settingsEditor.topAnchor.constraint(equalTo: primaryActions.bottomAnchor, constant: 18),
            settingsEditor.bottomAnchor.constraint(equalTo: heroCard.bottomAnchor, constant: -22)
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
        let showsStateHeading: Bool
        if let manualLockUntil, now < manualLockUntil {
            let fmt = RelativeDateTimeFormatter()
            fmt.unitsStyle = .short
            title = "LOCKED NOW"
            detail = "Manual lockdown ends \(fmt.localizedString(for: manualLockUntil, relativeTo: now))."
            showsStateHeading = true
        } else if inBlockWindow(now: now) {
            title = "LOCKDOWN ACTIVE"
            detail = "The current schedule is active."
            showsStateHeading = true
        } else {
            title = ""
            detail = "Closing this window does not stop enforcement."
            showsStateHeading = false
        }

        stateLabel.stringValue = title
        stateLabel.isHidden = !showsStateHeading
        stateLabel.textColor = uiTextColor
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
        view.layer?.borderColor = uiBorderColor.cgColor
        return view
    }

    private func makeActionButton(
        title: String,
        action: Selector,
        fillColor: NSColor = uiButtonColor
    ) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        styleButton(button, fillColor: fillColor)
        return button
    }

    private func styleButton(_ button: NSButton, fillColor: NSColor) {
        styleNeutralButton(button, controlSize: .large, fillColor: fillColor)
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
        let alert = NSAlert()
        alert.messageText = "Start Lockdown?"
        alert.informativeText = "This will start lockdown immediately for 30 minutes, turn off Wi-Fi, and lock the Mac."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Start Lockdown")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

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
