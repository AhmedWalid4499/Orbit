import SwiftUI

/// Settings › Connections › Outlook: Outlook meetings come in through the Calendar app, which already handles
/// work accounts, repeating meetings and time zones. Orbit then reads them like any other calendar, and the
/// assistant and the brief tell you about them.
struct OutlookCalendarRow: View {
    @EnvironmentObject private var apple: AppleSync
    @State private var link = ""
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 28, height: 28).background(RoundedRectangle(cornerRadius: 7).fill(Color(hex: 0x0F6CBD)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Outlook calendar").font(.headline)
                    Text(apple.calendarEnabled ? "Your Outlook meetings show in Joshu once Outlook is in the Calendar app." : "Turn on Apple Calendar first (above); Outlook meetings come in through it.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            DisclosureGroup("Add your Outlook or work account (recommended)") {
                VStack(alignment: .leading, spacing: 6) {
                    #if os(iOS)
                    Text("1. Open Settings › Apps › Calendar › Calendar Accounts › Add Account.")
                    Text("2. Choose Microsoft Exchange (work or school) or Outlook.com, and sign in.")
                    Text("3. Make sure Calendars is switched on. Joshu picks the meetings up by itself.")
                    Button("Open Settings") { Platform.open(URL(string: UIApplication.openSettingsURLString)!) }.padding(.top, 4)
                    #else
                    Text("1. Open System Settings › Internet Accounts › Add Account.")
                    Text("2. Choose Microsoft Exchange or Outlook.com, and sign in.")
                    Text("3. Make sure Calendars is switched on. Joshu picks the meetings up by itself.")
                    Button("Open Internet Accounts") { Platform.open(URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!) }.padding(.top, 4)
                    #endif
                }
                .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
            }
            DisclosureGroup("Or use a calendar link") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("In Outlook on the web: Settings › Calendar › Shared calendars › Publish a calendar › copy the ICS link, and paste it here.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        TextField("https://outlook.office365.com/…/calendar.ics", text: $link).textFieldStyle(.roundedBorder).autocorrectionDisabled()
                        Button("Add") { subscribe() }.disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let note { Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                }
                .padding(.top, 4)
            }
        }
    }

    /// Hands the link to the Calendar app as a subscription (it asks you to confirm once).
    private func subscribe() {
        var s = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.lowercased().contains(".ics") || s.lowercased().contains("calendar") else {
            note = "That doesn't look like a calendar link. It usually ends in .ics."
            return
        }
        for p in ["https://", "http://", "webcals://", "webcal://"] where s.lowercased().hasPrefix(p) { s = String(s.dropFirst(p.count)) }
        guard let url = URL(string: "webcal://" + s) else { note = "Couldn't read that link."; return }
        Platform.open(url)
        note = "Confirm “Subscribe” in Calendar. Your Outlook meetings then show in Joshu within a few minutes."
        link = ""
    }
}
