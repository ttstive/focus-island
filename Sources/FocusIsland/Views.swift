import SwiftUI
import Charts
import FocusCore

extension Color {
    static let canvas = Color(red: 0.055, green: 0.065, blue: 0.075)
    static let surface = Color(red: 0.085, green: 0.10, blue: 0.115)
    static let mint = Color(red: 0.64, green: 0.94, blue: 0.69)
    static let muted = Color(red: 0.53, green: 0.58, blue: 0.61)
}

struct Dashboard: View {
    @ObservedObject var model: FocusModel
    @State private var settings = false
    @State private var selection = "Overview"
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 30) {
                HStack(spacing: 10) {
                    BrandMark().frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("focus island").font(.system(size: 17, weight: .bold, design: .rounded))
                        Text("A little more intentional.").font(.system(size: 10)).foregroundStyle(Color.muted)
                    }
                }.padding(.top, 25)
                VStack(spacing: 7) {
                    nav("Overview", icon: "square.grid.2x2")
                    nav("History", icon: "chart.bar.xaxis")
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("YOUR SPACE").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(Color.muted)
                    HStack { Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundStyle(Color.mint); Text("Visual Studio Code").font(.system(size: 12)) }
                    HStack { Circle().fill(model.active ? Color.mint : Color.muted).frame(width: 5, height: 5); Text(model.status).font(.system(size: 10)).foregroundStyle(Color.muted) }
                }.padding(.top, 10)
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "leaf").foregroundStyle(Color.mint)
                    Text("Small steps.\nMeaningful progress.").font(.system(size: 16, weight: .medium, design: .rounded)).lineSpacing(4)
                    Text("Your pace is the right pace.").font(.system(size: 10)).foregroundStyle(Color.muted)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.mint.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                Button { settings = true } label: { Label("Settings & connections", systemImage: "slider.horizontal.3").font(.system(size: 11)).foregroundStyle(Color.muted) }.buttonStyle(.plain)
                HStack { Circle().fill(model.connected ? Color.mint : Color.muted).frame(width: 6, height: 6); Text(model.connected ? "@\(model.login)" : "Local & private").font(.system(size: 11)); Spacer(); Image(systemName: "lock.shield").foregroundStyle(Color.muted) }
            }.padding(22).frame(width: 220).background(Color.black.opacity(0.2))
            Rectangle().fill(.white.opacity(0.055)).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if let editor = model.requestedEditor {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Track this VS Code session?").font(.system(size: 16, weight: .semibold))
                            Text("Focus time and commit updates stay off until you choose.").font(.system(size: 12)).foregroundStyle(Color.muted)
                            HStack { Button("Not now") { model.respondToConsent(editor, allow: false) }; Button("Track this session") { model.respondToConsent(editor, allow: true) }.tint(.mint) }
                        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).card()
                    }
                    if let error = model.error {
                        HStack { Image(systemName: "info.circle"); Text(error).font(.system(size: 11)); Spacer(); Button("Dismiss") { model.error = nil } }.foregroundStyle(.orange).padding(12).background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if selection == "Overview" { overview } else { history }
                    HStack {
                        Image(systemName: "lock").font(.system(size: 9))
                        Text("Activity stays on this Mac. Progress is personal.").font(.system(size: 10))
                        Spacer()
                        Text("FOCUS ISLAND / 01").font(.system(size: 9, design: .monospaced)).tracking(1)
                    }.foregroundStyle(Color.muted).padding(.top, 2)
                }.padding(32)
            }
        }.background(Color.canvas).foregroundStyle(.white).preferredColorScheme(.dark)
        .frame(minWidth: 970, minHeight: 720)
        .sheet(isPresented: $settings) { SettingsView(model: model) }
    }
    func nav(_ title: String, icon: String) -> some View {
        Button { selection = title } label: {
            HStack { Image(systemName: icon).frame(width: 18); Text(title); Spacer(); if selection == title { Circle().fill(Color.mint).frame(width: 5, height: 5) } }
                .font(.system(size: 12, weight: .medium)).padding(12).foregroundStyle(selection == title ? Color.mint : Color.muted)
                .background(selection == title ? Color.mint.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
    var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased()).font(.system(size: 9, weight: .medium)).tracking(2).foregroundStyle(Color.muted)
                Text(selection == "History" ? "Your rhythm, over time." : "Make room for deep work.").font(.system(size: 29, weight: .semibold, design: .rounded))
                Text(selection == "History" ? "A week of showing up, one day at a time." : "A quiet space to see what you’re building, one day at a time.").font(.system(size: 12)).foregroundStyle(Color.muted)
            }
            Spacer()
            Button { model.togglePause() } label: {
                Label(model.hasSessionConsent ? (model.paused ? "Resume" : "Pause") : "Start session", systemImage: model.paused || !model.hasSessionConsent ? "play.fill" : "pause.fill").font(.system(size: 11, weight: .medium)).padding(.horizontal, 13).padding(.vertical, 9)
                    .background(.white.opacity(0.05), in: Capsule())
            }.buttonStyle(.plain)
        }
    }
    var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                metric(title: "FOCUSED TIME", value: Activity.liveDuration(model.today.seconds), subtitle: "of \(Activity.duration(model.focusGoal * 60)) daily goal", icon: "timer", progress: model.focusProgress, color: .mint)
                metric(title: "COMMITS TODAY", value: model.today.commits.map(String.init) ?? "—", subtitle: model.selections.isEmpty ? "Add repositories to track your commits" : "of \(model.commitGoal) commit goal", icon: "point.3.connected.trianglepath.dotted", progress: model.commitProgress, color: Color(red: 0.72, green: 0.69, blue: 1))
            }
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) { Text("The shape of your day").font(.system(size: 14, weight: .semibold)); Text("Active minutes in VS Code, by hour").font(.system(size: 11)).foregroundStyle(Color.muted) }
                    Spacer()
                    HStack(spacing: 5) { Circle().fill(Color.mint).frame(width: 5, height: 5); Text(model.active ? "LIVE" : "TODAY").font(.system(size: 9, weight: .semibold)).tracking(1) }.foregroundStyle(Color.mint)
                }
                Chart(Array(model.today.hours.enumerated()), id: \.offset) { item in
                    BarMark(x: .value("Hour", Double(item.offset)), y: .value("Minutes", item.element / 60), width: .fixed(14))
                        .foregroundStyle(Color.mint).cornerRadius(3)
                }.chartXScale(domain: -0.5...23.5).chartYScale(domain: 0.0...60.0)
                    .chartXAxis { AxisMarks(values: [0, 4, 8, 12, 16, 20, 23]) { value in AxisValueLabel { if let h = value.as(Int.self) { Text(String(format: "%02d", h)).font(.system(size: 9, design: .monospaced)).foregroundStyle(Color.muted) } } } }
                    .chartYAxis { AxisMarks(position: .leading, values: [0, 30, 60]) { _ in AxisGridLine().foregroundStyle(.white.opacity(0.05)); AxisValueLabel().foregroundStyle(Color.muted) } }
                    .frame(height: 155)
            }.padding(22).card()
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text("Built today").font(.system(size: 14, weight: .semibold)); Spacer(); Image(systemName: "arrow.triangle.branch").foregroundStyle(Color.muted) }
                    if model.selections.isEmpty {
                        Text("Give your focus a little context.").font(.system(size: 12)).foregroundStyle(Color.muted)
                        Button { settings = true } label: { Label("Set up repositories", systemImage: "folder.badge.plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.canvas).padding(.horizontal, 14).padding(.vertical, 9).background(Color.mint, in: Capsule()) }.buttonStyle(.plain)
                    } else if model.repositories.isEmpty {
                        Text("No matching commits yet. Good work takes many forms.").font(.system(size: 12)).foregroundStyle(Color.muted)
                    } else {
                        ForEach(model.repositories.prefix(3)) { repo in HStack { Text(URL(fileURLWithPath: repo.id).lastPathComponent).font(.system(size: 11)).lineLimit(1); Spacer(); Text("\(repo.count)").font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Color.mint) } }
                    }
                    Text(model.syncDate.map { "Updated \($0.formatted(date: .omitted, time: .shortened)) · local Git · live" } ?? "Local commits, including unpushed work.").font(.system(size: 9)).foregroundStyle(Color.muted)
                }.padding(20).frame(maxWidth: .infinity, minHeight: 155, alignment: .topLeading).card()
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("Today’s reflection").font(.system(size: 14, weight: .semibold)); Spacer(); Image(systemName: "sparkle").foregroundStyle(Color.mint) }
                    Text(model.focusProgress >= 1 ? "You made space.\nYou moved things forward." : "Every focused minute\nis a small investment.").font(.system(size: 18, weight: .medium, design: .rounded)).lineSpacing(4)
                    Text("An evening recap appears after 8 pm.\nCommit counts are a signal, never a score.").font(.system(size: 10)).foregroundStyle(Color.muted).lineSpacing(3)
                }.padding(20).frame(maxWidth: .infinity, minHeight: 155, alignment: .topLeading).background(Color.mint.opacity(0.05), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.mint.opacity(0.1)))
            }
        }
    }
    func metric(title: String, value: String, subtitle: String, icon: String, progress: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(title).font(.system(size: 9, weight: .semibold)).tracking(1.7).foregroundStyle(Color.muted); Spacer(); Image(systemName: icon).font(.system(size: 15)).foregroundStyle(color) }
            HStack(alignment: .firstTextBaseline, spacing: 8) { Text(value).font(.system(size: 39, weight: .medium, design: .rounded)).monospacedDigit(); Spacer(); Text("\(Int(progress * 100))%").font(.system(size: 11, design: .monospaced)).foregroundStyle(color) }
            GeometryReader { proxy in ZStack(alignment: .leading) { Capsule().fill(.white.opacity(0.05)); Capsule().fill(color).frame(width: proxy.size.width * progress) } }.frame(height: 4)
            Text(subtitle).font(.system(size: 10)).foregroundStyle(Color.muted)
        }.padding(22).frame(maxWidth: .infinity).card()
    }
    var history: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("LAST 7 DAYS").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(Color.muted)
            Chart(model.week) { day in BarMark(x: .value("Day", String(day.id.suffix(5))), y: .value("Minutes", day.seconds / 60)).foregroundStyle(Color.mint.gradient).cornerRadius(5) }.frame(height: 210).padding(20).card()
            ForEach(model.week.reversed()) { day in
                HStack { Text(day.id).foregroundStyle(Color.muted); Spacer(); Text(Activity.duration(day.seconds)).frame(width: 100, alignment: .trailing); Text(day.commits.map { "\($0) commits" } ?? "Not synced").foregroundStyle(Color.muted).frame(width: 110, alignment: .trailing) }.font(.system(size: 12, design: .monospaced))
                Divider().overlay(.white.opacity(0.04))
            }
            Button("Export activity as JSON") { model.export() }.tint(.mint)
        }
    }
}

extension View {
    func card() -> some View { self.background(Color.surface, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.055))) }
}

struct SettingsView: View {
    @ObservedObject var model: FocusModel
    @Environment(\.dismiss) var dismiss
    @State private var emailDraft = ""
    @State private var emailFeedback: String?
    @State private var emailInvalid = false

    @discardableResult
    private func applyEmails() -> Bool {
        do {
            try model.saveAuthorEmails(emailDraft)
            emailDraft = model.extraEmails
            emailInvalid = false
            emailFeedback = "Emails saved. They’ll be used for commit tracking."
            return true
        } catch {
            emailInvalid = true
            emailFeedback = error.localizedDescription
            return false
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Make it yours").font(.system(size: 23, weight: .semibold, design: .rounded)); Spacer(); Button("Done") { if applyEmails() { dismiss() } } }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("DAILY INTENTIONS").font(.system(size: 10, weight: .medium)).tracking(2).foregroundStyle(Color.muted)
                    HStack { Text("Focused minutes"); Spacer(); Stepper("\(Int(model.focusGoal)) min", value: $model.focusGoal, in: 15...720, step: 15).frame(width: 165) }
                    HStack { Text("Commit goal"); Spacer(); Stepper("\(model.commitGoal) commits", value: $model.commitGoal, in: 1...100).frame(width: 165) }
                    Divider()
                    Text("GITHUB · SSH KEY").font(.system(size: 10, weight: .medium)).tracking(2).foregroundStyle(Color.muted)
                    if model.connected {
                        HStack { Label("@\(model.login)", systemImage: "checkmark.shield.fill").foregroundStyle(Color.mint); Spacer(); Button("Verify again") { model.connectSSH() }.disabled(model.authorizing); Button("Disconnect") { model.disconnect() } }
                    } else {
                        Text("Verify your GitHub identity using your existing SSH key and ssh-agent. No API token, key upload, or private-key storage.").foregroundStyle(Color.muted)
                        Button("Connect with SSH key") { model.connectSSH() }.disabled(model.authorizing)
                    }
                    if let error = model.connectionError { Text(error).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled) }
                    if model.authorizing { HStack { ProgressView().controlSize(.small); Text("Verifying with GitHub…").foregroundStyle(Color.muted) } }
                    Text("GitHub’s server is verified against its published Ed25519 key. Your existing SSH key must be added to GitHub and unlocked in ssh-agent. Focus Island never asks for your passphrase.").font(.system(size: 10)).foregroundStyle(Color.muted).textSelection(.enabled)
                    Divider()
                    HStack { Text("LIVE LOCAL REPOSITORIES").font(.system(size: 10, weight: .medium)).tracking(2).foregroundStyle(Color.muted); Spacer(); Button("Add folders…") { model.addRepository() } }
                    ForEach(model.selections) { repo in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) { Text(repo.name).fontWeight(.medium); Text(repo.email.isEmpty ? (model.extraEmails.isEmpty ? "Add an author email below" : "Using your saved author emails") : repo.email).font(.system(size: 10)).foregroundStyle(Color.muted) }
                            Spacer()
                            Button { model.removeRepository(repo) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).help("Stop monitoring this repository")
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your commit author emails").fontWeight(.medium)
                        HStack {
                            TextField("you@example.com, you@users.noreply.github.com", text: $emailDraft)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { applyEmails() }
                                .onChange(of: emailDraft) { _, value in if value != model.extraEmails { emailFeedback = nil; emailInvalid = false } }
                            Button("Save emails") { applyEmails() }
                        }
                        if let feedback = emailFeedback {
                            Text(feedback).font(.system(size: 10)).foregroundStyle(emailInvalid ? Color.orange : Color.mint)
                        }
                        if !model.extraEmails.isEmpty {
                            Text("Saved: \(model.extraEmails)").font(.system(size: 10)).foregroundStyle(Color.muted).textSelection(.enabled)
                        }
                    }
                    Text("Commits are read from selected repositories, across all refs, using Git’s resolved author email (including a generated local address) plus any emails above. Counts use today’s commit timestamp and deduplicate commit hashes across repositories. Unpushed commits count. SSH verifies your account; it does not prove commit authorship or grant access to GitHub’s metrics API.").font(.system(size: 10)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
                    Text("Git metadata changes trigger an immediate refresh, with a two-second fallback scan. Repository contents and private keys never leave your Mac. Local tracking works even without SSH verification.").font(.system(size: 10)).foregroundStyle(Color.muted)
                    if let error = model.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled) }
                    Divider()
                    Text("Each VS Code launch asks whether to track. After you choose Track this session, app switches update immediately and the clock updates four times a second. Tracking pauses after 60 seconds idle, during sleep/lock, or when another app is in front. No keyboard content is recorded.").font(.system(size: 11)).foregroundStyle(Color.muted)
                }.padding(.trailing, 4)
            }.frame(maxHeight: 520)
            HStack { Button("Export my history") { model.export() }; Spacer(); Button("Quit Focus Island") { NSApplication.shared.terminate(nil) } }
        }.font(.system(size: 12)).padding(28).frame(width: 530).background(Color.canvas).preferredColorScheme(.dark)
        .onAppear { emailDraft = model.extraEmails }
    }
}

struct IslandView: View {
    @ObservedObject var model: FocusModel
    let expanded: Bool
    let toggle: () -> Void
    let dashboard: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                IslandWindowHandle(kind: .move).frame(width: 22, height: 34).padding(.leading, 5)
                Button(action: toggle) {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.path").foregroundStyle(Color.mint)
                    Text(expanded ? "focus island" : (model.active ? "In the flow" : "Focus Island")).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Circle().fill(model.active ? Color.mint : Color.muted).frame(width: 5, height: 5)
                    Text(Activity.liveDuration(model.today.seconds)).font(.system(size: 12, weight: .medium, design: .monospaced))
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 8)).foregroundStyle(Color.muted)
                }.padding(.leading, 3).padding(.trailing, 16).frame(height: 42).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if expanded {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) { Text(Activity.liveDuration(model.today.seconds)).font(.system(size: 30, weight: .medium, design: .rounded)); Text("focused today").font(.system(size: 10)).foregroundStyle(Color.muted) }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) { Text(model.today.commits.map(String.init) ?? "—").font(.system(size: 30, weight: .medium, design: .rounded)).foregroundStyle(Color.mint); Text("local commits").font(.system(size: 10)).foregroundStyle(Color.muted) }
                    }
                    ProgressView(value: model.focusProgress).tint(.mint)
                    HStack { Text(model.status).font(.system(size: 10)).foregroundStyle(Color.muted); Spacer(); Button { model.togglePause() } label: { Image(systemName: model.paused || !model.hasSessionConsent ? "play.fill" : "pause.fill") }.buttonStyle(.plain); Button("Dashboard", action: dashboard).buttonStyle(.plain).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.mint) }
                }.padding(.horizontal, 22).padding(.top, 6).padding(.bottom, 20)
            }
            if expanded { Spacer(minLength: 0) }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .bottomTrailing) { IslandWindowHandle(kind: .resize).frame(width: expanded ? 22 : 16, height: expanded ? 22 : 16).padding(expanded ? 5 : 2) }
        .background(.black).clipShape(RoundedRectangle(cornerRadius: expanded ? 25 : 21)).overlay(RoundedRectangle(cornerRadius: expanded ? 25 : 21).stroke(.white.opacity(0.12))).foregroundStyle(.white).preferredColorScheme(.dark)
    }
}


struct SessionConsentView: View {
    let editor: EditorSession
    let choose: (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 10) {
                Image(systemName: "leaf.fill").font(.system(size: 21)).foregroundStyle(Color.mint)
                Text("A little intention before you begin.").font(.system(size: 11)).foregroundStyle(Color.muted)
            }
            Text("Track this \(editor.name) session?").font(.system(size: 21, weight: .semibold, design: .rounded))
            Text("Count active editor time and refresh today’s commits from your selected repositories. Nothing starts until you choose.")
                .font(.system(size: 12)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Not now") { choose(false) }.buttonStyle(.plain).padding(.horizontal, 17).padding(.vertical, 10).background(.white.opacity(0.06), in: Capsule())
                Spacer()
                Button("Track this session") { choose(true) }.buttonStyle(.plain).fontWeight(.semibold).foregroundStyle(Color.canvas).padding(.horizontal, 17).padding(.vertical, 10).background(Color.mint, in: Capsule())
            }.font(.system(size: 12))
            Text("Only this session. No code or keystroke content is recorded.").font(.system(size: 9)).foregroundStyle(Color.muted)
        }.padding(24).frame(width: 420, height: 255).background(Color.canvas, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.13))).foregroundStyle(.white).preferredColorScheme(.dark)
    }
}


struct BrandMark: View {
    private static let logo: NSImage? = {
        let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png") ?? Bundle.module.url(forResource: "AppIcon", withExtension: "png")
        return url.flatMap { NSImage(contentsOf: $0) }
    }()
    var body: some View {
        if let logo = Self.logo { Image(nsImage: logo).resizable().scaledToFit() }
        else { Image(systemName: "waveform.path").foregroundStyle(Color.mint) }
    }
}
