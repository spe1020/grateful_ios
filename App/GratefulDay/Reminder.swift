import SwiftUI
import UserNotifications

/// The opt-in daily reminder (M4 criterion 5): one local notification at a
/// time the person picks, off until they opt in, no server push.
///
/// Settings live in UserDefaults (non-sensitive flags; storage
/// recommendation §2). The "offered once" flag lives in the journal store,
/// because it reveals that two reflections exist.
protocol NotificationScheduling: Sendable {
    func requestAuthorization() async -> Bool
    func isAuthorized() async -> Bool
    func scheduleDaily(hour: Int, minute: Int, title: String, body: String) async throws
    func cancelDaily() async
}

struct SystemNotificationScheduler: NotificationScheduling {
    static let identifier = "app.gratefulday.daily-reminder"

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func isAuthorized() async -> Bool {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    func scheduleDaily(hour: Int, minute: Int, title: String, body: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: hour, minute: minute), repeats: true)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        try await center.add(UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger))
    }

    func cancelDaily() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.identifier])
    }
}

@MainActor
@Observable
final class ReminderModel {
    /// Notification copy (Prep, approved): never includes reflection text.
    static let title = "Grateful Day"
    static let body = "A quiet minute of gratitude."
    static let deniedMessage = "Notifications for Grateful Day are turned off in Settings."

    private(set) var isOn: Bool
    private(set) var hour: Int
    private(set) var minute: Int
    private(set) var permissionDenied = false

    private let defaults: UserDefaults
    private let scheduler: NotificationScheduling

    init(defaults: UserDefaults = .standard, scheduler: NotificationScheduling = SystemNotificationScheduler()) {
        self.defaults = defaults
        self.scheduler = scheduler
        isOn = defaults.bool(forKey: Keys.on)
        hour = defaults.object(forKey: Keys.hour) as? Int ?? 20
        minute = defaults.object(forKey: Keys.minute) as? Int ?? 0
    }

    enum Keys {
        static let on = "reminder.on"
        static let hour = "reminder.hour"
        static let minute = "reminder.minute"
    }

    var time: Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
    }

    /// Turn the reminder on at `time`. Permission is asked only now, after
    /// the person picked a time.
    func turnOn(at time: Date) async {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        hour = parts.hour ?? 20
        minute = parts.minute ?? 0
        defaults.set(hour, forKey: Keys.hour)
        defaults.set(minute, forKey: Keys.minute)
        let granted = await scheduler.requestAuthorization()
        guard granted else {
            permissionDenied = true
            setOn(false)
            return
        }
        permissionDenied = false
        do {
            try await scheduler.scheduleDaily(hour: hour, minute: minute, title: Self.title, body: Self.body)
            setOn(true)
        } catch {
            setOn(false)
        }
    }

    /// Change the time of an active reminder; takes effect immediately.
    func change(to time: Date) async {
        guard isOn else { return }
        await turnOn(at: time)
    }

    private var pendingChange: Task<Void, Never>?

    /// From the time picker: changes run one at a time, and a newer pick
    /// cancels an older one that hasn't started, so the reminder that ends
    /// up scheduled is always the last time picked (Audit M4 L1).
    @discardableResult
    func requestChange(to time: Date) -> Task<Void, Never> {
        let previous = pendingChange
        previous?.cancel()
        let task = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled, let self else { return }
            await self.change(to: time)
        }
        pendingChange = task
        return task
    }

    func turnOff() async {
        await scheduler.cancelDaily()
        setOn(false)
    }

    /// If permission was revoked in Settings, show the reminder as off.
    func refreshAuthorization() async {
        guard isOn else { return }
        if !(await scheduler.isAuthorized()) {
            permissionDenied = true
            setOn(false)
        }
    }

    private func setOn(_ on: Bool) {
        isOn = on
        defaults.set(on, forKey: Keys.on)
    }
}

/// Settings → Daily reminder, also opened from the one-time offer on Today.
struct ReminderView: View {
    @Bindable var model: ReminderModel
    @State private var picked: Date = .now
    @State private var working = false

    var body: some View {
        Form {
            Section {
                DatePicker("Time", selection: $picked, displayedComponents: .hourAndMinute)
                    .accessibilityIdentifier("reminder.time")
                    .onChange(of: picked) { _, newValue in
                        if model.isOn { model.requestChange(to: newValue) }
                    }
                if model.isOn {
                    Button("Turn off reminder", role: .destructive) {
                        Task { await model.turnOff() }
                    }
                    .accessibilityIdentifier("reminder.off")
                } else {
                    Button("Remind me at \(picked.formatted(date: .omitted, time: .shortened))") {
                        working = true
                        Task {
                            await model.turnOn(at: picked)
                            working = false
                        }
                    }
                    .disabled(working)
                    .accessibilityIdentifier("reminder.on")
                }
            } footer: {
                Text("One gentle reminder a day, sent by this iPhone. Nothing is sent from a server.")
            }
            if model.permissionDenied {
                Section {
                    Text(ReminderModel.deniedMessage)
                        .accessibilityIdentifier("reminder.denied")
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        Link("Open Settings", destination: url)
                    }
                }
            }
        }
        .navigationTitle("Daily reminder")
        .onAppear { picked = model.time }
        .task { await model.refreshAuthorization() }
    }
}

/// The one-time offer on Today after the 2nd saved reflection.
struct ReminderOffer: View {
    let onChoose: () -> Void
    let onDismiss: () -> Void
    static let question = "Want a gentle reminder each day?"

    var body: some View {
        VStack(alignment: .leading, spacing: GDSpacing.small) {
            Text(Self.question)
                .font(GDFont.body)
                .foregroundStyle(GDColor.foreground)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: GDSpacing.medium) {
                Button(action: onChoose) {
                    Text("Choose a time").frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityIdentifier("reminderOffer.choose")
                Button(action: onDismiss) {
                    Text("Not now").frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityIdentifier("reminderOffer.dismiss")
            }
            .font(GDFont.sectionLabel)
        }
        .padding(GDSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: GDRadius.card, style: .continuous).strokeBorder(GDColor.border))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reminderOffer")
    }
}
