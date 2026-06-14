import SwiftUI
import UIKit

/// The reading surface. Chrome-light like Safari's reader: the article fills the
/// screen (under the notch and home indicator) and a floating bar at the bottom
/// carries back, the page title, and reader controls.
///
/// The floating bar uses true Liquid Glass (`.glassEffect`) when built with the
/// iOS 26 SDK (Xcode 26); on older SDKs it falls back to `.ultraThinMaterial`.
struct ReaderScreen: View {
    let item: BookmarkItem

    @AppStorage("readerFontChoice") private var fontChoiceRaw = ReaderFontChoice.serif.rawValue
    @AppStorage("readerFontScale") private var fontScale = 1.0
    @AppStorage("readerArticleSize") private var articleSize = 18.0

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var showingNotes = false
    @State private var showingReaderOptions = false
    @State private var barHidden = false
    @State private var scrollTracker = ReaderScrollTracker()

    // Real device safe-area insets (seeded from the key window, refined on appear).
    @State private var topInset: CGFloat = ReaderScreen.windowInsets.top
    @State private var bottomInset: CGFloat = ReaderScreen.windowInsets.bottom

    private var preferences: ReaderFontPreferences {
        ReaderFontPreferences(
            choice: ReaderFontChoice(rawValue: fontChoiceRaw) ?? .serif,
            articleSize: articleSize,
            scale: fontScale
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemBackground).ignoresSafeArea()
            reader.ignoresSafeArea()
            if showingReaderOptions {
                readerOptionsPanel
                    .padding(.horizontal, 12)
                    .padding(.bottom, bottomInset + 64)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
            floatingBar.padding(.bottom, 8)
        }
        .background(
            GeometryReader { proxy in
                Color.clear.onAppear {
                    let i = proxy.safeAreaInsets
                    if i.top > 0 { topInset = i.top }
                    if i.bottom > 0 { bottomInset = i.bottom }
                }
            }
            .ignoresSafeArea()
        )
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingNotes) {
            NotesSheet(note: item.note ?? "", preferences: preferences)
        }
    }

    static var windowInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.safeAreaInsets ?? .zero
    }

    // MARK: Reader content — fills the screen, content inset by the safe area so
    // the article opens below the status bar and scrolls under it.

    @ViewBuilder
    private var reader: some View {
        if item.hasReaderHTML, let html = item.readerHTML {
            ReaderHTMLView(title: item.title, html: html, baseURL: item.url,
                           preferences: preferences,
                           topInset: topInset, bottomInset: bottomInset + 64,
                           onScroll: handleScroll)
        } else {
            ReaderTextView(text: readableText, preferences: preferences,
                           topInset: topInset + 16, bottomInset: bottomInset + 88,
                           onScroll: handleScroll)
        }
    }

    private var readableText: String {
        let trimmed = item.contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return item.contentText }
        if let summary = item.summary, !summary.isEmpty { return summary }
        return ""
    }

    /// Hide the bar on scroll-down, reveal on scroll-up (and always near the top).
    private func handleScroll(_ offset: CGFloat) {
        if showingReaderOptions {
            scrollTracker.reset(to: offset)
            return
        }
        if offset < 40 {
            scrollTracker.reset(to: offset)
            setBarHidden(false)
            return
        }
        guard let hidden = scrollTracker.hiddenState(for: offset) else { return }
        setBarHidden(hidden)
    }

    private func setBarHidden(_ hidden: Bool) {
        guard hidden != barHidden else { return }
        withAnimation(.easeInOut(duration: 0.22)) { barHidden = hidden }
    }

    // MARK: Floating bar

    private var floatingBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .glassCircle()
            .accessibilityLabel("Back")

            Text(item.title)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .frame(height: 44)
                .glassCapsule()

            Button {
                setBarHidden(false)
                withAnimation(.easeInOut(duration: 0.18)) {
                    showingReaderOptions.toggle()
                }
            } label: {
                Image(systemName: showingReaderOptions ? "xmark" : "textformat.size")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .glassCircle()
            .accessibilityLabel(showingReaderOptions ? "Hide reader options" : "Reader options")
        }
        .tint(.accentColor)
        .padding(.horizontal, 12)
        .offset(y: barHidden && !showingReaderOptions ? 150 : 0)
        .opacity(barHidden && !showingReaderOptions ? 0 : 1)
        .allowsHitTesting(!barHidden || showingReaderOptions)
    }

    private var readerOptionsPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                fontScaleButton(systemImage: "textformat.size.smaller", accessibilityLabel: "Make reader text smaller") {
                    adjustScale(-ReaderFontPreferences.scaleStep)
                }

                Button {
                    fontScale = 1.0
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset reader size")

                fontScaleButton(systemImage: "textformat.size.larger", accessibilityLabel: "Make reader text larger") {
                    adjustScale(+ReaderFontPreferences.scaleStep)
                }

                Text("\(Int((fontScale * 100).rounded()))%")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 52, alignment: .trailing)
            }

            Picker("Typeface", selection: $fontChoiceRaw) {
                ForEach(ReaderFontChoice.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)

            if item.canOpenInBrowser || hasNote {
                HStack(spacing: 8) {
                    if let url = item.url, item.canOpenInBrowser {
                        Button {
                            openURL(url)
                        } label: {
                            Image(systemName: "safari")
                                .frame(width: 44, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open in Browser")

                        Button {
                            UIPasteboard.general.url = url
                        } label: {
                            Image(systemName: "link")
                                .frame(width: 44, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Copy Link")
                    }

                    if hasNote {
                        Button {
                            showingReaderOptions = false
                            showingNotes = true
                        } label: {
                            Image(systemName: "note.text")
                                .frame(width: 44, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("View Notes")
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 360)
        .glassPanel()
    }

    private func fontScaleButton(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 48, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var hasNote: Bool {
        !(item.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func adjustScale(_ delta: Double) {
        fontScale = preferences.bumpedScale(by: delta)
    }
}

private final class ReaderScrollTracker {
    private var lastOffset: CGFloat = 0

    func reset(to offset: CGFloat) {
        lastOffset = offset
    }

    func hiddenState(for offset: CGFloat) -> Bool? {
        defer { lastOffset = offset }
        let dy = offset - lastOffset
        guard abs(dy) > 6 else { return nil }
        return dy > 0
    }
}

// MARK: - Glass styling (Liquid Glass on iOS 26 SDK, material fallback otherwise)

private struct GlassBar: ViewModifier {
    var interactive: Bool = false

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: Capsule())
        } else {
            content.modifier(MaterialBar())
        }
        #else
        content.modifier(MaterialBar())
        #endif
    }
}

private struct MaterialBar: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.14), radius: 14, y: 5)
    }
}

private struct GlassPanel: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            content.modifier(MaterialPanel())
        }
        #else
        content.modifier(MaterialPanel())
        #endif
    }
}

private struct MaterialPanel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
    }
}

private extension View {
    func glassCapsule() -> some View { modifier(GlassBar(interactive: false)) }
    func glassCircle() -> some View { modifier(GlassBar(interactive: true)) }
    func glassPanel() -> some View { modifier(GlassPanel()) }
}

// MARK: - Notes

private struct NotesSheet: View {
    let note: String
    let preferences: ReaderFontPreferences
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ReaderTextView(text: note, preferences: preferences, emptyMessage: "No notes.")
                .navigationTitle("Notes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
