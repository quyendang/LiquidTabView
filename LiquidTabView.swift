// iOS 26+. Drop this file into your app; no assets, package or Metal build step required.
import Foundation

#if !LIQUID_MOTION_TEST
import SwiftUI

public struct LiquidTab<ID: Hashable>: Identifiable {
    public let id: ID
    public let title: String
    public let icon: Image
    public init(_ title: String, image: Image, value: ID) {
        self.title = title
        icon = image
        id = value
    }
    public init(_ title: String, systemImage: String, value: ID) {
        self.init(title, image: Image(systemName: systemImage), value: value)
    }
}

public struct LiquidTabAction {
    let title: String
    let label: AnyView
    let perform: () -> Void
    public init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.init(title, action: action) { Image(systemName: systemImage).font(.system(size: 22, weight: .semibold)) }
    }
    public init<Label: View>(_ title: String, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.title = title
        self.perform = action
        self.label = AnyView(label())
    }
}

/// Keeps each tab's view identity/state; selection belongs to the caller.
@available(iOS 26.0, *) public struct LiquidTabView<ID: Hashable, Content: View>: View {
    @Binding var selection: ID
    let tabs: [LiquidTab<ID>]
    let tint: Color
    let iconTint: Color?
    let action: LiquidTabAction?
    let reduceMotion: Bool
    let content: (ID) -> Content

    public init(
        selection: Binding<ID>, tabs: [LiquidTab<ID>], tint: Color = Color(red: 1, green: 138 / 255, blue: 112 / 255),
        iconTint: Color? = nil, action: LiquidTabAction? = nil, reduceMotion: Bool = false,
        @ViewBuilder content: @escaping (ID) -> Content
    ) {
        _selection = selection
        self.tabs = tabs
        self.tint = tint
        self.iconTint = iconTint
        self.action = action
        self.reduceMotion = reduceMotion
        self.content = content
    }

    public var body: some View {
        ZStack {
            ForEach(tabs) { tab in
                content(tab.id).opacity(selection == tab.id ? 1 : 0).allowsHitTesting(selection == tab.id)
                    .accessibilityHidden(selection != tab.id)
            }
        }.safeAreaInset(edge: .bottom, spacing: 0) {
            LiquidTabBar(
                selection: $selection, tabs: tabs, tint: tint, iconTint: iconTint, action: action,
                reduceMotion: reduceMotion
            ).padding(.horizontal, 16).padding(.vertical, 12)
        }
    }
}

/// Use alone in an overlay, or use LiquidTabView to manage pages and the safe area.
@available(iOS 26.0, *) public struct LiquidTabBar<ID: Hashable>: View {
    @Binding var selection: ID
    let tabs: [LiquidTab<ID>]
    let tint: Color
    let iconTint: Color?
    let action: LiquidTabAction?
    let reduceMotion: Bool

    public init(
        selection: Binding<ID>, tabs: [LiquidTab<ID>], tint: Color = Color(red: 1, green: 138 / 255, blue: 112 / 255),
        iconTint: Color? = nil, action: LiquidTabAction? = nil, reduceMotion: Bool = false
    ) {
        precondition(
            (2...5).contains(tabs.count) && Set(tabs.map(\.id)).count == tabs.count,
            "LiquidTabBar requires 2–5 unique tab IDs")
        precondition(tabs.contains { $0.id == selection.wrappedValue }, "selection must belong to tabs")
        _selection = selection
        self.tabs = tabs
        self.tint = tint
        self.iconTint = iconTint
        self.action = action
        self.reduceMotion = reduceMotion
    }

    public var body: some View {
        LiquidBarContent(
            selection: $selection, tabs: tabs, tint: tint, iconTint: iconTint, reduceMotion: reduceMotion,
            action: action
        ).id(tabs.map(\.id))
    }
}

@available(iOS 26.0, *) private struct LiquidBarContent<ID: Hashable>: View {
    @Binding var selection: ID
    var reduceMotion = false
    let tabs: [LiquidTab<ID>]
    let tint: Color
    let iconTint: Color?
    var action: LiquidTabAction?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var drag: LiquidDragState?
    @GestureState private var touching = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var motion: LiquidPresentation

    init(
        selection: Binding<ID>, tabs: [LiquidTab<ID>], tint: Color, iconTint: Color?, reduceMotion: Bool,
        action: LiquidTabAction?
    ) {
        self.tabs = tabs
        _selection = selection
        self.reduceMotion = reduceMotion
        self.action = action
        self.tint = tint
        self.iconTint = iconTint
        _motion = State(
            initialValue: LiquidPresentation(
                position: Double(tabs.firstIndex { $0.id == selection.wrappedValue } ?? 0), tabCount: tabs.count))
    }

    private var reduced: Bool { reduceMotion || systemReduceMotion }

    var body: some View {
        GeometryReader { available in
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 8) {
                    GeometryReader { geometry in
                        let cellWidth = (geometry.size.width - 16) / Double(tabs.count)
                        TimelineView(.animation(paused: !motion.isAnimating)) { context in
                            let sample = motion.sample(at: context.date.timeIntervalSinceReferenceDate)
                            ZStack(alignment: .leading) {
                                HStack(spacing: 0) {
                                    ForEach(tabs) { tab in
                                        Button {
                                            select(tab.id)
                                        } label: {
                                            tab.icon.resizable().scaledToFit().font(.system(size: 20, weight: .semibold)).frame(
                                                width: 22, height: 22
                                            ).foregroundStyle(Color.secondary.opacity(0.75)).frame(
                                                maxWidth: .infinity, minHeight: 64
                                            ).contentShape(.rect)
                                        }.buttonStyle(.plain).accessibilityLabel(tab.title).accessibilityAddTraits(
                                            selection == tab.id ? .isSelected : []
                                        ).accessibilityIdentifier("tab.\(tab.id)")
                                    }
                                }.padding(.horizontal, 8).mask {
                                    let optics = LiquidOptics(
                                        pressure: reduced ? 0 : sample.pressure,
                                        energy: reduced ? 0 : sample.motion.energy)
                                    Canvas { context, size in
                                        let w = cellWidth * optics.widthScale
                                        let h = 48 * optics.heightScale
                                        var cutout = Path(CGRect(origin: .zero, size: size))
                                        cutout.addRoundedRect(
                                            in: CGRect(
                                                x: 8 + cellWidth * sample.motion.position - (w - cellWidth) / 2,
                                                y: (64 - h) / 2, width: w, height: h),
                                            cornerSize: CGSize(width: h / 2, height: h / 2))
                                        context.fill(cutout, with: .color(.white), style: FillStyle(eoFill: true))
                                    }
                                }
                                LiquidSelectionLens(
                                    tabs: tabs, position: sample.motion.position,
                                    energy: reduced ? 0 : sample.motion.energy,

                                    press: reduced ? 0 : sample.pressure, cellWidth: cellWidth, tint: tint,
                                    iconTint: iconTint, dark: colorScheme == .dark)
                            }  // These are presentation samples, not new animation targets.
                            .transaction { transaction in
                                transaction.animation = nil
                                transaction.disablesAnimations = true
                            }
                        }.frame(height: 64).contentShape(.rect).highPriorityGesture(scrubGesture(cellWidth: cellWidth))
                    }.frame(height: 64).modifier(LiquidGlassSurface())

                    if let action {
                        Button(action: action.perform) {
                            action.label.frame(width: 76, height: 64).contentShape(.capsule)
                        }.buttonStyle(LiquidPressStyle(reduceMotion: reduceMotion || systemReduceMotion)).modifier(
                            LiquidGlassSurface()
                        ).accessibilityLabel(action.title).accessibilityIdentifier("liquidTabAction")
                    }
                }
            }.frame(
                width: min(available.size.width, Double(tabs.count) * 80 + 16 + (action == nil ? 0 : 84)), height: 64
            ).frame(maxWidth: .infinity)
        }.frame(height: 64).environment(\.layoutDirection, .leftToRight).onChange(of: selection) { _, new in
            if drag != nil { finishDrag(destination: new) } else { retarget(to: new) }
        }.onChange(of: touching) { _, active in
            // GestureState resets for system cancellation, even without onEnded.
            if !active, drag != nil { finishDrag(destination: selection) }
        }.onChange(of: reduced) { _, value in
            if value { motion.snap(to: Double(tabs.firstIndex { $0.id == selection } ?? 0)) }
        }.task(id: motion.deadline) {
            guard let deadline = motion.deadline else { return }
            do { try await Task.sleep(for: .seconds(max(deadline - Date.now.timeIntervalSinceReferenceDate, 0))) } catch
            { return }
            motion.finish(at: max(deadline, Date.now.timeIntervalSinceReferenceDate))
        }.onDisappear {
            motion.snap(to: Double(tabs.firstIndex { $0.id == selection } ?? 0))
            drag = nil
        }
    }

    private func scrubGesture(cellWidth: Double) -> some Gesture {
        DragGesture(minimumDistance: 0).updating($touching) { _, active, _ in active = true }.onChanged { value in
            let now = Date.now.timeIntervalSinceReferenceDate
            if drag == nil {
                let current = motion.sample(at: now).motion
                drag = LiquidDragState(
                    x: value.startLocation.x - 8, cellWidth: cellWidth, tabCount: tabs.count,
                    presentation: current.position, time: now)
                motion.track(.init(position: current.position, velocity: 0), at: now, reduced: reduced)
                motion.setPressed(true, at: now, reduced: reduced)
            }
            drag?.update(x: value.location.x - 8, at: now)
            if let drag, drag.moved { motion.track(drag.sample, at: now, reduced: reduced) }
        }.onEnded { value in
            guard var session = drag else { return }
            session.update(x: value.location.x - 8, at: Date.now.timeIntervalSinceReferenceDate)
            if session.moved {
                motion.track(session.sample, at: Date.now.timeIntervalSinceReferenceDate, reduced: reduced)
            }
            let inside =
                (-48...112).contains(value.location.y)
                && (-24...(cellWidth * Double(tabs.count) + 40)).contains(value.location.x)
            let index = session.moved ? session.destination : session.tappedIndex
            finishDrag(destination: inside ? tabs[index].id : selection)
        }
    }

    private func finishDrag(destination: ID) {
        let now = Date.now.timeIntervalSinceReferenceDate
        motion.release(
            to: Double(tabs.firstIndex { $0.id == destination } ?? 0), at: now, reduced: reduced,
            response: drag?.moved == true ? 0.26 : nil)
        drag = nil
        selection = destination
    }

    private func select(_ tab: ID) {
        guard tab != selection else { return }
        // Prepare presentation BEFORE publishing navigation's new selection.
        retarget(to: tab)
        selection = tab
    }

    private func retarget(to tab: ID) {
        motion.retarget(
            to: Double(tabs.firstIndex { $0.id == tab } ?? 0), at: Date.now.timeIntervalSinceReferenceDate,
            reduced: reduced)
    }
}

@available(iOS 26.0, *) private struct LiquidSelectionLens<ID: Hashable>: View {
    @Environment(\.self) private var environment
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let tabs: [LiquidTab<ID>]
    let position: Double
    let energy: Double
    let press: Double
    let cellWidth: Double
    let tint: Color
    let iconTint: Color?
    let dark: Bool

    var body: some View {
        let active = iconTint ?? tint.mix(with: .black, by: 0.72)
        let rgb = tint.resolve(in: environment)
        let lift = max(0, 0.7 - Double(max(rgb.red, rgb.green, rgb.blue))) / 0.7
        let held = dark ? tint.mix(with: .white, by: lift) : tint.mix(with: .black, by: 0.45)
        let gradient = [tint.mix(with: .white, by: 0.33), tint, tint.mix(with: .white, by: 0.20)]
        let optics = LiquidOptics(pressure: press, energy: energy)
        let glass = reduceTransparency ? 0 : optics.glassMix
        let width = cellWidth * optics.widthScale
        let height = 48 * optics.heightScale
        ZStack {
            // Isolated from the rail's glass container: the lens is a separate
            // optical surface, not another shape to union with the entire rail.
            GlassEffectContainer(spacing: 0) {
                Color.clear.frame(width: width, height: height).glassEffect(.clear, in: .capsule)
            }.opacity(glass)
            Capsule().fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(reduceTransparency ? 1 : optics.tintOpacity(dark: dark))
            Capsule().fill(
                LinearGradient(
                    colors: [.white.opacity(0.17 * glass), .clear, .black.opacity(0.055 * glass)], startPoint: .top,
                    endPoint: .bottom))
            ZStack {
                iconStrip(color: active, width: width, height: height).opacity(1 - glass)
                iconStrip(color: held, width: width, height: height).opacity(glass)
            }.compositingGroup().layerEffect(
                LiquidLensShader.library.liquidLens(
                    .float2(width / 2, height / 2), .float2(width / 2, height / 2),
                    .float(reduceTransparency ? 0 : optics.refraction)), maxSampleOffset: CGSize(width: 24, height: 24)
            ).clipShape(.capsule)
            Capsule().strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.12 + 0.65 * glass), location: 0),
                        .init(color: .white.opacity(0.04), location: 0.4),
                        .init(color: .black.opacity(0.08 + 0.17 * glass), location: 0.72),
                        .init(color: .white.opacity(0.28 * glass), location: 1),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8 + 0.5 * glass)
            Capsule().inset(by: 1.8).strokeBorder(
                LinearGradient(
                    colors: [.black.opacity(0.11 * glass), .clear, .white.opacity(0.30 * glass)], startPoint: .top,
                    endPoint: .bottom), lineWidth: 1.3)
            Capsule().strokeBorder(.white.opacity(dark ? 0 : 0.35), lineWidth: 1).opacity(1 - glass)
        }.frame(width: width, height: height).shadow(
            color: .black.opacity((dark ? 0.22 : 0.08) * glass), radius: 3 + 3 * glass, y: 2 + 3 * glass
        ).shadow(color: tint.mix(with: .black, by: 0.75).opacity((dark ? 0.20 : 0.12) * (1 - glass)), radius: 5, y: 3)
            .offset(x: 8 + cellWidth * position - (width - cellWidth) / 2).allowsHitTesting(false).accessibilityElement(
                children: .ignore
            ).accessibilityHidden(true)
    }

    private func iconStrip(color: Color, width: Double, height: Double) -> some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                tab.icon.resizable().scaledToFit().font(.system(size: 20, weight: .semibold)).frame(width: 22, height: 22).foregroundStyle(color)
                    .frame(width: cellWidth, height: height)
            }
        }.frame(width: cellWidth * Double(tabs.count), alignment: .leading).offset(
            x: -cellWidth * position + (width - cellWidth) / 2
        ).frame(width: width, height: height, alignment: .leading)
    }
}

@available(iOS 26.0, *) private struct LiquidGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        Group {
            if opaque {
                content.background(scheme == .dark ? Color(white: 0.11) : .white, in: .capsule)
            } else {
                content.glassEffect(.regular, in: .capsule)
            }
        }.overlay {
            Capsule().strokeBorder(
                LinearGradient(
                    colors: scheme == .dark
                        ? [.white.opacity(0.08), .white.opacity(0.1), .black.opacity(0.08), .white.opacity(0.03)]
                        : [.gray.opacity(0.35), .white.opacity(0.94), .white.opacity(0.42), .gray.opacity(0.45)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: scheme == .dark ? 0.5 : 0.8
            ).allowsHitTesting(false)
        }.shadow(color: .black.opacity(scheme == .dark ? 0.28 : 0.06), radius: 12, y: 6)
    }
}

private struct LiquidPressStyle: ButtonStyle {
    var reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1).animation(
            reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// Precompiled from the approved 24pt-bounded liquidLens shader. Two targets are required
// by Metal; embedding them preserves refraction without a second .metal/resource file.
@available(iOS 26.0, *) private enum LiquidLensShader {
    static let library: ShaderLibrary = {
        #if targetEnvironment(simulator)
        let encoded = """
            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
            9JAP8FAOMx5qHsphHOghHd7BHX4BHuShHMwhHfBhBlSFgzjMwzuwQz3QQzn8wjzkQzuIwzuww4zFCod5mId3GId0CAd6KAdymIFc4xAO7MAO5VAO8zAjwdJB
            HuThF9jhHd4BHmZIGTuwgz20gxuEwziMQznMwzy4wTnIwzvUAzzMSLRxCAd2YAdxCIdxWIcZ28YO7GAP7eAG8CAP5TAP5SAP9lAObhAO4zAO5TAP8+AG6eAO
            5FAO+DAj4uxhHMKBHdjhF+whHeYhHcQhHdghHeghH2YgnTu8Qz24AzmUgznMWLxwcAd3eAd6CAd6SId3cIcZzocO5RAO8BAO7MAO7zAO85AO9FAOMygwCId0
            kAc3MId6cIdxoId0eAd3+IVzkId3qAd4mAcAAAAAeSAAAH4BAAByHkggQ4gMGQlyMkggI4GMkZHRRKAQKGQ8MTJCjpAho8gGZLBaAAAAi9JY2AZt0BwUG0cG
            UlREBhNcA2EUBSJJT2M5jwNNhlNEzwMAU0RLIFZlcnNpb253Y2hhcl9zaXplZnJhbWUtcG9pbnRlcmFpci5tYXhfZGV2aWNlX2J1ZmZlcnNhaXIubWF4X2Nv
            bnN0YW50X2J1ZmZlcnNhaXIubWF4X3RocmVhZGdyb3VwX2J1ZmZlcnNhaXIubWF4X3RleHR1cmVzYWlyLm1heF9yZWFkX3dyaXRlX3RleHR1cmVzYWlyLm1h
            eF9zYW1wbGVyc0FwcGxlIG1ldGFsIHZlcnNpb24gMzIwMjMuOTIxIChtZXRhbGZlLTMyMDIzLjkyMS42KU1ldGFsYWlyLmNvbXBpbGUuZGVub3Jtc19kaXNh
            YmxlYWlyLmNvbXBpbGUuZmFzdF9tYXRoX2VuYWJsZWFpci5jb21waWxlLmZyYW1lYnVmZmVyX2ZldGNoX2VuYWJsZWFpci52aXNpYmxlX291dHB1dGFpci5h
            cmdfdHlwZV9uYW1laGFsZjRhaXIudmlzaWJsZV9pbnB1dGZsb2F0MmFpci5hcmdfbmFtZXB0ZXh0dXJlMmQ8aGFsZiwgc2FtcGxlPnRleGluZm9jZW50ZXJy
            YWRpaWZsb2F0c3RyZW5ndGhhaXIuc3RpdGNoaW5nX2luZm9haXIuc3RpdGNoaW5nX3R5cGVhaXIudmVjdG9yX3R5cGVhaXIuaGFsZl90eXBlYWlyLnN0aXRj
            aGluZ19hcmd1bWVudGFpci5mbG9hdF90eXBlYWlyLnN0cnVjdF90eXBlU3dpZnRVSTo6TGF5ZXJhaXIucmVjb3JkX2ZpZWxkYWlyLnRleHR1cmVfMmRfdHlw
            ZXNhbXBsZWFpci5hcnJheV90eXBlbGF5ZXJhaXIuc2FtcGxlcl9zdGF0ZW9tbmlwb3RlbnQgY2hhclNpbXBsZSBDKysgVEJBQQBG9QAAAAAAADCCYAdgMIJQ
            Cn8wgmAHYTCCYAdiMIJgB2MwgmAHZDCCYAdlMIJgB2YwgmAHZzCCYAdoMIKgBtMIgh2kwQiCHajBCIJljCBgyAiClIwgOMcIgiKMIEDECIJUjCA4wwiCHazB
            CIIdsMEIwqeMIJBBM4IgOSMIzjKCYAbPCAIaRCMIkjSC4EAjCAIwggB8MwxtELjBDMMbCHAwwxAHQxvMMMQBIQczDHFQyMEMQxwYcjDDEAfHHMwwxAFCBzMM
            cZDUwQyBMsPQBnRgBzMQCxzYgR3MEDAzBM0MgTPD8EDRDEEvzGDYgQRNVDWD8QYSZFHXDEYbSNBEYTMYeCBBE5XNYMCBBE2UNoORBxK0UdwMxi+AQziIwziQ
            wwwEGLRBGwAzGB8d0AFgDnAwg+Gdgx7sAR/0wQyEGMABHAAzGB8d0AGQDm0wg+Gpgx/8ASiEwgxDGKxDNYNhBnRAB4A5nMEMRhnYAR20wwXMYKDBKNABoA55
            MINRBnRAB++AATMI7gAPMxhjIAp0AJBBPMxgePJACqVgCqcwwxAG85AGMwxhsA7ZDEMYrIM2g+GlAyqkgiqswgxDGNwDN8PRoQM70EM92AM+zEDcgS+UQz7M
            IKgBK8wQsMEMwxrwQyvMMPRDP7TCDMPWD60ww/AP/9AKRwsAGqABGqABGqABGqABGqCBGKABGnAcx3Ecx6EBGnBiwHFiIAYcx3Fu4AZu4AZu4AZu4AZuYNGB
            HliWJQacHuiBHuiBHugBLugBK8iCHrCCLLiBLLCCLLACGsiCLNCBG7iBLLiBL4ACGnB0QAduICOBCcqIjc2uzaXtjayOrczFjC3sbG6UpBVc4RVgIRZkYRZo
            oRZSYWOza3NJIytzoxslsIVcwtLkXOzK5ObS3txGCW4hqbA0ORe2MLezurCzsi+7Mrm5tDe3UQJcyCksTc5l7K0NLo2t7OsNji7tzW1ulCEXdGEXcglLk3Ox
            S5tLE2MrGyXIh5TC0uRc5sLa4NjK5L7m6MLoyuZGCfQBAAAAqRgAACUAAAALCnIoh3eAB3pYcJhDPbjDOLBDOdDDguYcxqEN6EEewsEd5iEd6CEd3sEdFjTj
            YA7nUA/hIA/kQA/hIA/nUA70sICBB3koh3BgB3Z4h3EIB3ooB3JYcJzDOLQBO6SDPZTDAmsc2CEc3OEc3CAc5GEc3CAc6IEewmEc0KEcyGEcwoEd2GHBAQ/0
            IA/hUA/0gA4AAAAA0RAAAAYAAAAHzDykgzucAzuUAz2ggzyUQziQwwEAAABhIAAABwAAABMEQQbGpQBBNgiIAQIAAABbhiDoBwAAAAAAAABhIAAACgAAABME
            QQrGTeG4FCDIsAExBASgATEAAwAAAFsGIeiHLcMQ9AMAAAAAAABhIAAACAAAABMEQQrGHTYgAoEANCAGAAACAAAAW4Yg6AcAAAAAAAAAYSAAAAEAAAATBIEC
            YSAAAAcAAAATBEEGyKWAQjYIiAECAAAAW4Yg6AcAAAAAAAAAYSAAAAoAAAATBEEKyE0huRRQyLABMQQEoAExAAMAAABbBiHohy3DEPQDAAAAAAAAYSAAAAgA
            AAATBEEKyB02IAKBADQgBgAAAgAAAFuGIOgHAAAAAAAAAGEgAAABAAAAEwSBAmEgAAAcAAAAEwRBLBAAAAAEAAAABCiIAimYAioo6owGAAAAAHkolwIN6QMh
            QTIwLgUI0gcCo2RgXAoQpA+Eh8nAuBQgSB8IkpOBcSlAkD4QKigD41KAILMREgQAsxGBEwCzEQETBLMRgRIIsxEBEgyzEYEREBsAAGEgAAAJAAAAEwRBLBAA
            AAACAAAABCgwAo0AAAAjBogSgmAQBnhADEKgAAAAYSAAAB0AAAATBEEsEAAAAAMAAAAEKIgCKZgCKigAAACjCQcwmnAAowlIMJqQCKMJyjCasBDpKHfYgAgO
            AugD4WEyMO6wAREgBNAHQtRkYNxhAyJICKAPhMnJwLjDBkSgEEAfCNWTgXGHDYhgIYA+EC4oA+MOGxABQwAKAGEgAAABAAAAEwSBAmEgAAAHAAAAEwRBBsul
            4DA2CIgBAgAAAFuGIPgHAAAAAAAAAGEgAAAKAAAAEwRBCstNgbkUHMawATEEA6ABMQADAAAAWwYh+IctwxD8AwAAAAAAAGEgAAAIAAAAEwRBCssdNiACYQA0
            IAYAAAIAAABbhiD4BwAAAAAAAABhIAAAAQAAABMEgQJhIAAAsAAAABMEQSwQAAAAJwAAAAQogxIogkIg2wwA3UYAqDkCQM45CDQIAzBQBTqMEYAgCOLfCMAY
            AQiCIAgGYwQgCIIkGIwRmHPOur8wRsCXZwmCwRgBquL1/QtjBGAejysYjBGwLw2P3xjBS8Pr740RzDlrzh8hRgPGEkAQBPEPBEEQ/8YSQBAEd3AAQRDcwWEs
            AQRBcAcDEATBHQzGEt6ZNNHunUkT7Wg1GjADADMRnR2EASmMJoAB0DuEMAp6oAfDBkQgEMBoQhgAvUMQpTAKpTBsQAQCAYwmjEHQO4RxCqXwDRsQgUAAowll
            IPQOgaTCKYDBsAERCAQwmnAGQ+8QyiqkAhkMGxCBQACjCWlA9A7BtMIqjMGwAREIBIBtoAbhP2JwLCEIFv4hCrCgBhQKAfmPGBxLCIKFf/hBLQTBiIGxhCBY
            +Acf0EKAARiAPwZgIP4jBsgSgmDhH6CAC0EZmAEGgfijYAbij2YQhD8OgfgjUgbgj0EZiP+IAbKEIFj4Byj8QsAGbYBBIP4otIH4YxsE4Y9DIP4oB0H4Y7IG
            4o/BGoC/WeA/x7AGQjkMMgRsoAdzDG0QCucwyBC4AR/MMbwBkg6DDAEc+AEOh/hjYIg/BoP4jxggSwiChX/oQT0EchAHGAZxAP4jBscSgmDhH35AD0EwYmAs
            IQgW/sEH9hDMMeBBIA+DDEEenAIGhfjjK/CB+GPQiT8GlvjPMfhBgA+DDMEftAIagfhjowvgP2JwMDAIFv4RByWxBwEOAviPGBwMDIKFf8TBSfRBgEQR/iMG
            BwODYOEfcZASfxCMIRS6MIZA7MIYwsALIwbHAoJg4R9u4BJCMGJwLCAIFv7hBi9BBGMIiEnMMZxCcBJjCAw4zDEIQTiMISjhMMcgBOIwx9AKB0sMMgSuAA4j
            BscCgmDhH2yQE0MwyBDAQjjMMQRLOmwAYSAAAFgAAAATBEEsEAAAAAkAAAAEKIEiKINCIFANjADQbQRgLCEI6DACQIjRgBkAqtkKAAAAAADxMAAAHwAAACJH
            yJBRCoQuAAAAAKJAAQBfWlRTTjVtZXRhbDl0ZXh0dXJlMmRJRGhMTlNfNmFjY2Vzc0UwRUxOU18xNm1lbW9yeV9jb2hlcmVuY2VFMEV2RUVfX21ldGFsX3Rl
            eHR1cmVfMmRfdAAAGwaR6IdW2DCExEi0woaBJEaiFQCDDM1g9A7xwIEbwAEFCDLIABVI7xDSHMQBRAGC9A5B1cEcRBQgyIgBsoQgWPiHHvRBMQQjBsgSgmDh
            H3rgB8kR9A6B5cEdUBQgSO8Q2h7kQUUBgowYIEsIgoV/6AEpFEPQO0TnB3VQBxRoyIhB04QgGOABKgTSkF1YVd3BaEIAbBAQAwAIAAAAWwYh6IctQxH0w5bh
            CPphy7AE/bBlaIJ+2DJAAUkAAAAAAAAAcSAAABEAAAAyDhAihAK9CjhgrIAE0gpYwK2ABt8KeICugAj0Cpjgr4AKgQu48LmADaoL6JC8gA/MCwhRvYAR4Qso
            sb6AE+4LaAHaAAAAAABlDAAA2QAAABIDlLgGAAAAAwAAACQFAAALAAAATAAAAAEAAABYAAAAAAAAAFgAAAAfAAAAQAMAAAEAAAAvBQAAIwAAAFAEAAAKAAAA
            EwAAAAAAAABYAwAAAAAAAAAAAAAfAAAAAAAAACUAAAA6AAAAJQAAADoAAAD/////gCAAAF8AAABOAAAAXwAAAE4AAAD/////gCAAAK0AAABCAAAArQAAAEIA
            AAD/////gCAAAO8AAAAzAAAA7wAAADMAAAD/////gCAAACIBAAA7AAAAIgEAADsAAAD/////gCAAAF0BAABPAAAAXQEAAE8AAAD/////gCAAAKwBAABDAAAA
            rAEAAEMAAAD/////gCAAAO8BAAA0AAAA7wEAADQAAAD/////gCAAACMCAABFAAAAIwIAAEUAAAD/////gCAAAGgCAABZAAAAaAIAAFkAAAD/////gCAAAMEC
            AAAZAAAAwQIAABkAAAD/////CCwAANoCAABNAAAA2gIAAE0AAAD/////gCAAACcDAAA+AAAAJwMAAD4AAAD/////gCAAAGUDAAA2AAAAZQMAADYAAAD/////
            gCAAAJsDAABKAAAAmwMAAEoAAAD/////gCAAAOUDAAA8AAAA5QMAADwAAAD/////gCAAACEEAAAvAAAAIQQAAC8AAAD/////gCAAAFAEAAAKAAAAUAQAAAoA
            AAD/////ACQAAFoEAAAOAAAAWgQAAA4AAAD/////CCQAAGgEAAAMAAAAaAQAAAwAAAD/////CCQAAHQEAAAfAAAAdAQAAB8AAAD/////ADAAAJMEAAAbAAAA
            kwQAABsAAAD/////CCQAAK4EAAAUAAAArgQAABQAAAD/////CCQAAMIEAAANAAAAwgQAAA0AAAD/////CCQAAM8EAAASAAAAzwQAABIAAAD/////CCQAAOEE
            AAANAAAA4QQAAA0AAAD/////CCQAAO4EAAASAAAA7gQAABIAAAD/////CCQAAAAFAAARAAAAAAUAABEAAAD/////CCQAABEFAAATAAAAEQUAABMAAAD/////
            CCQAAAAAAAATAAAAAAAAABMAAAD/////AAAAABMAAAASAAAAEwAAABIAAAD/////BAwAAAAAAAAAAAAAEwAAAAAAAABSBQAADQAAAAAAAABdDAAAWwEAABID
            lL8aAAAAX19haXJfc2FtcGxlcl9zdGF0ZWxsdm0uY29tcGlsZXIudXNlZF9aTjVtZXRhbDIyX3N0aXRjaGluZ190cmFpdHNfaW1wbElEdjJfZkUxM2xvYWRf
            YXJndW1lbnRFUHZfWk41bWV0YWwyMl9zdGl0Y2hpbmdfdHJhaXRzX2ltcGxJRHYyX2ZFMTZjb3B5X2Zyb21fYnVmZmVyRVB2UFUxMU1UTGNvbnN0YW50S3Zf
            Wk41bWV0YWwyMl9zdGl0Y2hpbmdfdHJhaXRzX2ltcGxJRHYyX2ZFMThzdG9yZV9yZXR1cm5fdmFsdWVFUHZTMV9fWk41bWV0YWwyMl9zdGl0Y2hpbmdfdHJh
            aXRzX2ltcGxJRHYyX2ZFN2Rlc3Ryb3lFUHZfWk41bWV0YWwyMl9zdGl0Y2hpbmdfdHJhaXRzX2ltcGxJRHY0X0RoRTEzbG9hZF9hcmd1bWVudEVQdl9aTjVt
            ZXRhbDIyX3N0aXRjaGluZ190cmFpdHNfaW1wbElEdjRfRGhFMTZjb3B5X2Zyb21fYnVmZmVyRVB2UFUxMU1UTGNvbnN0YW50S3ZfWk41bWV0YWwyMl9zdGl0
            Y2hpbmdfdHJhaXRzX2ltcGxJRHY0X0RoRTE4c3RvcmVfcmV0dXJuX3ZhbHVlRVB2UzFfX1pONW1ldGFsMjJfc3RpdGNoaW5nX3RyYWl0c19pbXBsSUR2NF9E
            aEU3ZGVzdHJveUVQdl9aTjVtZXRhbDIyX3N0aXRjaGluZ190cmFpdHNfaW1wbElON1N3aWZ0VUk1TGF5ZXJFRTEzbG9hZF9hcmd1bWVudEVQdl9aTjVtZXRh
            bDIyX3N0aXRjaGluZ190cmFpdHNfaW1wbElON1N3aWZ0VUk1TGF5ZXJFRTE2Y29weV9mcm9tX2J1ZmZlckVQdlBVMTFNVExjb25zdGFudEt2bGx2bS5tZW1j
            cHkucDBpOC5wMmk4Lmk2NF9aTjVtZXRhbDIyX3N0aXRjaGluZ190cmFpdHNfaW1wbElON1N3aWZ0VUk1TGF5ZXJFRTE4c3RvcmVfcmV0dXJuX3ZhbHVlRVB2
            UzJfX1pONW1ldGFsMjJfc3RpdGNoaW5nX3RyYWl0c19pbXBsSU43U3dpZnRVSTVMYXllckVFN2Rlc3Ryb3lFUHZfWk41bWV0YWwyMl9zdGl0Y2hpbmdfdHJh
            aXRzX2ltcGxJZkUxM2xvYWRfYXJndW1lbnRFUHZfWk41bWV0YWwyMl9zdGl0Y2hpbmdfdHJhaXRzX2ltcGxJZkUxNmNvcHlfZnJvbV9idWZmZXJFUHZQVTEx
            TVRMY29uc3RhbnRLdl9aTjVtZXRhbDIyX3N0aXRjaGluZ190cmFpdHNfaW1wbElmRTE4c3RvcmVfcmV0dXJuX3ZhbHVlRVB2Zl9aTjVtZXRhbDIyX3N0aXRj
            aGluZ190cmFpdHNfaW1wbElmRTdkZXN0cm95RVB2bGlxdWlkTGVuc2Fpci5mbWluLnYzZjE2YWlyLmZtYXguZjE2X1pOSzdTd2lmdFVJNUxheWVyNnNhbXBs
            ZUVEdjJfZmFpci5zYW1wbGVfdGV4dHVyZV8yZC52NGYxNmFpci5mYXN0X2NsYW1wLnYyZjMyYWlyLmZtYS52MmYzMmFpci5mYXN0X3JzcXJ0LmYzMmFpci5k
            b3QudjJmMzJhaXIuZmFzdF9jbGFtcC5mMzJhaXIuZmFzdF9zcXJ0LmYzMmFpci5mYXN0X2ZtYXgudjJmMzIzMjAyMy45MjEuNmFpcjY0X3YyOC1hcHBsZS1p
            b3MyNi4wLjAtc2ltdWxhdG9ybGx2bS5tZXRhZGF0YQAAAAAAAAAAAA==
            """
        #else
        let encoded = """
            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
            3sEdfgEe5KEczCEd8GEGVIWDOMzDO7BDPdBDOfzCPORDO4jDO7DDjMUKh3mYh3cYh3QIB3ooB3KYgVzjEA7swA7lUA7zMCPB0kEe5OEX2OEd3gEeZkgZO7CD
            PbSDG4TDOIxDOczDPLjBOcjDO9QDPMxItHEIB3ZgB3EIh3FYhxnbxg7sYA/t4AbwIA/lMA/lIA/2UA5uEA7jMA7lMA/z4Abp4A7kUA74MCPi7GEcwoEd2OEX
            7CEd5iEdxCEd2CEd6CEfZiCdO7xDPbgDOZSDOcxYvHBwB3d4B3oIB3pIh3dwhxnOhw7lEA7wEA7swA7vMA7zkA70UA4zKDAIh3SQBzcwh3pwh3Ggh3R4B3f4
            hXOQh3eoB3iYBwAAAAB5IAAAfgEAAHIeSCBDiAwZCXIySCAjgYyRkdFEoBAoZDwxMkKOkCGjyAZksFoAAACL0ljYBm3QHBQbRwZSVEQGE1wDYRQFIklPYzmP
            A02GU0TPAwBTREsgVmVyc2lvbndjaGFyX3NpemVmcmFtZS1wb2ludGVyYWlyLm1heF9kZXZpY2VfYnVmZmVyc2Fpci5tYXhfY29uc3RhbnRfYnVmZmVyc2Fp
            ci5tYXhfdGhyZWFkZ3JvdXBfYnVmZmVyc2Fpci5tYXhfdGV4dHVyZXNhaXIubWF4X3JlYWRfd3JpdGVfdGV4dHVyZXNhaXIubWF4X3NhbXBsZXJzQXBwbGUg
            bWV0YWwgdmVyc2lvbiAzMjAyMy45MjEgKG1ldGFsZmUtMzIwMjMuOTIxLjYpTWV0YWxhaXIuY29tcGlsZS5kZW5vcm1zX2Rpc2FibGVhaXIuY29tcGlsZS5m
            YXN0X21hdGhfZW5hYmxlYWlyLmNvbXBpbGUuZnJhbWVidWZmZXJfZmV0Y2hfZW5hYmxlYWlyLnZpc2libGVfb3V0cHV0YWlyLmFyZ190eXBlX25hbWVoYWxm
            NGFpci52aXNpYmxlX2lucHV0ZmxvYXQyYWlyLmFyZ19uYW1lcHRleHR1cmUyZDxoYWxmLCBzYW1wbGU+dGV4aW5mb2NlbnRlcnJhZGlpZmxvYXRzdHJlbmd0
            aGFpci5zdGl0Y2hpbmdfaW5mb2Fpci5zdGl0Y2hpbmdfdHlwZWFpci52ZWN0b3JfdHlwZWFpci5oYWxmX3R5cGVhaXIuc3RpdGNoaW5nX2FyZ3VtZW50YWly
            LmZsb2F0X3R5cGVhaXIuc3RydWN0X3R5cGVTd2lmdFVJOjpMYXllcmFpci5yZWNvcmRfZmllbGRhaXIudGV4dHVyZV8yZF90eXBlc2FtcGxlYWlyLmFycmF5
            X3R5cGVsYXllcmFpci5zYW1wbGVyX3N0YXRlb21uaXBvdGVudCBjaGFyU2ltcGxlIEMrKyBUQkFBAEb1AAAAAAAAMIJgB2AwglAKfzCCYAdhMIJgB2IwgmAH
            YzCCYAdkMIJgB2UwgmAHZjCCYAdnMIJgB2gwgqAG0wiCHaTBCIIdqMEIgmWMIGDICIKUjCA4xwiCIowgQMQIglSMIDjDCIIdrMEIgh2wwQjCp4wgkEEzgiA5
            IwjOMoJgBs8IAhpEIwiSNILgQCMIAjCCAHwzDG0QuMEMwxsIcDDDEAdDG8wwxAEhBzMMcVDIwQxDHBhyMMMQB8cczDDEAUIHMwxxkNTBDIEyw9AGdGAHMxAL
            HNiBHcwQMDMEzQyBM8PwQNEMQS/MYNiBBE1UNYPxBhJkUdcMRhtI0ERhMxh4IEETlc1gwIEETZQ2g5EHErRR3AzGL4BDOIjDOJDDDAQYtEEbADMYHx3QAWAO
            cDCD4Z2DHuwBH/TBDIQYwAEcADMYHx3QAZAObTCD4amDH/wBKITCDEMYrEM1g2EGdEAHgDmcwQxGGdgBHbTDBcxgoMEo0AGgDnkwg1EGdEAH74ABMwjuAA8z
            GGMgCnQAkEE8zGB48kAKpWAKpzDDEAbzkAYzDGGwDtkMQxisgzaD4aUDKqSCKqzCDEMY3AM3w9GhAzvQQz3YAz7MQNyBL5RDPswgqAErzBCwwQzDGvBDK8ww
            9EM/tMIMw9YPrTDD8A//0ApHCwAaoAEaoAEaoAEaoAEaoIEYoAEacBzHcRzHoQEacGLAcWIgBhzHcW7gBm7gBm7gBm7gBm5g0YEeWJYlBpwe6IEe6IEe6AEu
            6AEryIIesIIsuIEssIIssAIayIIs0IEbuIEsuIEvgAIacHRAB24gI4EJyoiNza7Npe2NrI6tzMWMLexsbpSkFVzhFWAhFmRhFmihFlJhY7Nrc0kjK3OjGyWw
            hVzC0uRc7Mrk5tLe3EYJbiGpsDQ5F7Ywt7O6sLOyL7syubm0N7dRAlzIKSxNzmXsrQ0uja3s6w2OLu3NbW6UIRd0YRdyCUuTc7FLm0sTYysbJciHlMLS5Fzm
            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
            h1bYMITESLTChoEkRqIVAIMMzWD0DvHAgRvAAQUIMsgAFUjvENIcxAFEAYL0DkHVwRxEFCDIiAGyhCBY+Ice9EExBCMGyBKCYOEfeuAHyRH0DoHlwR1QFCBI
            7xDaHuRBRQGCjBggSwiChX/oASkUQ9A7ROcHdVAHFGjIiEHThCAY4AEqBNKQXVhV3cFoQgBsEBADAAgAAABbBiHohy1DEfTDluEI+mHLsAT9sGVogn7YMkAB
            SQAAAAAAAABxIAAAEQAAADIOECKEArkKOCCsgATOCliArYAG2wp4QK6ACPAKmKCvgAr9CriwuYANpgvoULyAD8gLCBG9gBHdCyhxvoAT6gtowdkAAAAAAGUM
            AADZAAAAEgOUuAYAAAADAAAAJAUAAAsAAABMAAAAAQAAAFgAAAAAAAAAWAAAAB8AAABAAwAAAQAAAC8FAAAZAAAAUAQAAAoAAAATAAAAAAAAAFgDAAAAAAAA
            AAAAAB8AAAAAAAAAJQAAADoAAAAlAAAAOgAAAP////+AIAAAXwAAAE4AAABfAAAATgAAAP////+AIAAArQAAAEIAAACtAAAAQgAAAP////+AIAAA7wAAADMA
            AADvAAAAMwAAAP////+AIAAAIgEAADsAAAAiAQAAOwAAAP////+AIAAAXQEAAE8AAABdAQAATwAAAP////+AIAAArAEAAEMAAACsAQAAQwAAAP////+AIAAA
            7wEAADQAAADvAQAANAAAAP////+AIAAAIwIAAEUAAAAjAgAARQAAAP////+AIAAAaAIAAFkAAABoAgAAWQAAAP////+AIAAAwQIAABkAAADBAgAAGQAAAP//
            //8ILAAA2gIAAE0AAADaAgAATQAAAP////+AIAAAJwMAAD4AAAAnAwAAPgAAAP////+AIAAAZQMAADYAAABlAwAANgAAAP////+AIAAAmwMAAEoAAACbAwAA
            SgAAAP////+AIAAA5QMAADwAAADlAwAAPAAAAP////+AIAAAIQQAAC8AAAAhBAAALwAAAP////+AIAAAUAQAAAoAAABQBAAACgAAAP////8AJAAAWgQAAA4A
            AABaBAAADgAAAP////8IJAAAaAQAAAwAAABoBAAADAAAAP////8IJAAAdAQAAB8AAAB0BAAAHwAAAP////8AMAAAkwQAABsAAACTBAAAGwAAAP////8IJAAA
            rgQAABQAAACuBAAAFAAAAP////8IJAAAwgQAAA0AAADCBAAADQAAAP////8IJAAAzwQAABIAAADPBAAAEgAAAP////8IJAAA4QQAAA0AAADhBAAADQAAAP//
            //8IJAAA7gQAABIAAADuBAAAEgAAAP////8IJAAAAAUAABEAAAAABQAAEQAAAP////8IJAAAEQUAABMAAAARBQAAEwAAAP////8IJAAAAAAAABMAAAAAAAAA
            EwAAAP////8AAAAAEwAAABIAAAATAAAAEgAAAP////8EDAAAAAAAAAAAAAATAAAAAAAAAEgFAAANAAAAAAAAAF0MAABZAQAAEgOUtRoAAABfX2Fpcl9zYW1w
            bGVyX3N0YXRlbGx2bS5jb21waWxlci51c2VkX1pONW1ldGFsMjJfc3RpdGNoaW5nX3RyYWl0c19pbXBsSUR2Ml9mRTEzbG9hZF9hcmd1bWVudEVQdl9aTjVt
            ZXRhbDIyX3N0aXRjaGluZ190cmFpdHNfaW1wbElEdjJfZkUxNmNvcHlfZnJvbV9idWZmZXJFUHZQVTExTVRMY29uc3RhbnRLdl9aTjVtZXRhbDIyX3N0aXRj
            aGluZ190cmFpdHNfaW1wbElEdjJfZkUxOHN0b3JlX3JldHVybl92YWx1ZUVQdlMxX19aTjVtZXRhbDIyX3N0aXRjaGluZ190cmFpdHNfaW1wbElEdjJfZkU3
            ZGVzdHJveUVQdl9aTjVtZXRhbDIyX3N0aXRjaGluZ190cmFpdHNfaW1wbElEdjRfRGhFMTNsb2FkX2FyZ3VtZW50RVB2X1pONW1ldGFsMjJfc3RpdGNoaW5n
            X3RyYWl0c19pbXBsSUR2NF9EaEUxNmNvcHlfZnJvbV9idWZmZXJFUHZQVTExTVRMY29uc3RhbnRLdl9aTjVtZXRhbDIyX3N0aXRjaGluZ190cmFpdHNfaW1w
            bElEdjRfRGhFMThzdG9yZV9yZXR1cm5fdmFsdWVFUHZTMV9fWk41bWV0YWwyMl9zdGl0Y2hpbmdfdHJhaXRzX2ltcGxJRHY0X0RoRTdkZXN0cm95RVB2X1pO
            NW1ldGFsMjJfc3RpdGNoaW5nX3RyYWl0c19pbXBsSU43U3dpZnRVSTVMYXllckVFMTNsb2FkX2FyZ3VtZW50RVB2X1pONW1ldGFsMjJfc3RpdGNoaW5nX3Ry
            YWl0c19pbXBsSU43U3dpZnRVSTVMYXllckVFMTZjb3B5X2Zyb21fYnVmZmVyRVB2UFUxMU1UTGNvbnN0YW50S3ZsbHZtLm1lbWNweS5wMGk4LnAyaTguaTY0
            X1pONW1ldGFsMjJfc3RpdGNoaW5nX3RyYWl0c19pbXBsSU43U3dpZnRVSTVMYXllckVFMThzdG9yZV9yZXR1cm5fdmFsdWVFUHZTMl9fWk41bWV0YWwyMl9z
            dGl0Y2hpbmdfdHJhaXRzX2ltcGxJTjdTd2lmdFVJNUxheWVyRUU3ZGVzdHJveUVQdl9aTjVtZXRhbDIyX3N0aXRjaGluZ190cmFpdHNfaW1wbElmRTEzbG9h
            ZF9hcmd1bWVudEVQdl9aTjVtZXRhbDIyX3N0aXRjaGluZ190cmFpdHNfaW1wbElmRTE2Y29weV9mcm9tX2J1ZmZlckVQdlBVMTFNVExjb25zdGFudEt2X1pO
            NW1ldGFsMjJfc3RpdGNoaW5nX3RyYWl0c19pbXBsSWZFMThzdG9yZV9yZXR1cm5fdmFsdWVFUHZmX1pONW1ldGFsMjJfc3RpdGNoaW5nX3RyYWl0c19pbXBs
            SWZFN2Rlc3Ryb3lFUHZsaXF1aWRMZW5zYWlyLmZtaW4udjNmMTZhaXIuZm1heC5mMTZfWk5LN1N3aWZ0VUk1TGF5ZXI2c2FtcGxlRUR2Ml9mYWlyLnNhbXBs
            ZV90ZXh0dXJlXzJkLnY0ZjE2YWlyLmZhc3RfY2xhbXAudjJmMzJhaXIuZm1hLnYyZjMyYWlyLmZhc3RfcnNxcnQuZjMyYWlyLmRvdC52MmYzMmFpci5mYXN0
            X2NsYW1wLmYzMmFpci5mYXN0X3NxcnQuZjMyYWlyLmZhc3RfZm1heC52MmYzMjMyMDIzLjkyMS42YWlyNjRfdjI4LWFwcGxlLWlvczI2LjAuMGxsdm0ubWV0
            YWRhdGEAAAAAAAAAAAAAAAAAAAAAAAAA
            """
        #endif
        return ShaderLibrary(data: Data(base64Encoded: encoded, options: .ignoreUnknownCharacters)!)
    }()
}
#endif

struct LiquidMotionSample {
    var position: Double
    var velocity: Double
    var energy: Double { min(abs(velocity) / 8, 1) }
}

/// Pure, critically damped trajectory shared conceptually with the Compose demo.
struct LiquidMotionSegment {
    let start: LiquidMotionSample
    let target: Double
    let startedAt: TimeInterval
    let response: Double
    let bounds: ClosedRange<Double>

    init(
        start: LiquidMotionSample, target: Double, startedAt: TimeInterval, response: Double? = nil,
        bounds: ClosedRange<Double> = 0...3
    ) {
        self.bounds = bounds
        self.start = start
        self.target = target
        self.startedAt = startedAt
        let distance = abs(target - start.position)
        self.response = response ?? (0.32 + 0.13 * max(distance - 1, 0))
    }

    var settlingDuration: Double { response * 1.7 }

    func sample(at time: TimeInterval) -> LiquidMotionSample {
        let t = max(time - startedAt, 0)
        let omega = 2 * Double.pi / response
        let displacement = start.position - target
        let coefficient = start.velocity + omega * displacement
        let decay = exp(-omega * t)
        let position = target + (displacement + coefficient * t) * decay
        let velocity = (start.velocity - omega * coefficient * t) * decay
        return LiquidMotionSample(
            position: min(max(position, bounds.lowerBound), bounds.upperBound),
            velocity: !bounds.contains(position) ? 0 : velocity)
    }
}

/// Owns the displayed position independently of the navigation selection.
/// Position and pressure are sampled once, from the same clock, without a
/// second implicit animation interpolating those already-interpolated values.
struct LiquidPresentation {
    private var restingPosition: Double
    private let bounds: ClosedRange<Double>
    private var restingPressure = 0.0
    private var travel: LiquidMotionSegment?
    private var pressure: LiquidMotionSegment?
    private var tracking: LiquidMotionSegment?

    init(position: Double, tabCount: Int = 4) {
        precondition(tabCount >= 2)
        restingPosition = position
        bounds = 0...Double(tabCount - 1)
    }

    var target: Double { tracking?.target ?? travel?.target ?? restingPosition }
    var isAnimating: Bool { tracking != nil || travel != nil || pressure != nil }
    var deadline: TimeInterval? {
        [travel, pressure].compactMap { segment in segment.map { $0.startedAt + $0.settlingDuration } }.max()
    }

    func sample(at time: TimeInterval) -> (motion: LiquidMotionSample, pressure: Double) {
        let movement =
            tracking?.sample(at: time) ?? travel?.sample(at: time)
            ?? LiquidMotionSample(position: restingPosition, velocity: 0)
        let press = pressure?.sample(at: time).position ?? restingPressure
        return (movement, min(max(press, 0), 1))
    }

    mutating func retarget(to destination: Double, at time: TimeInterval, reduced: Bool) {
        guard tracking == nil else { return }
        if reduced {
            snap(to: destination)
            return
        }
        guard destination != target else { return }
        travel = LiquidMotionSegment(
            start: sample(at: time).motion, target: destination, startedAt: time, bounds: bounds)
    }

    mutating func track(_ sample: LiquidMotionSample, at time: TimeInterval, reduced: Bool = false) {
        if reduced {
            snap(to: sample.position)
            return
        }
        let current = self.sample(at: time).motion
        tracking = LiquidMotionSegment(
            start: current, target: sample.position, startedAt: time, response: 0.105, bounds: bounds)
        travel = nil
    }

    mutating func release(to destination: Double, at time: TimeInterval, reduced: Bool, response: Double? = nil) {
        let current = sample(at: time).motion
        tracking = nil
        if reduced {
            snap(to: destination)
            return
        }
        travel = LiquidMotionSegment(
            start: current, target: destination, startedAt: time, response: response, bounds: bounds)
        setPressed(false, at: time, reduced: reduced)
    }

    mutating func setPressed(_ pressed: Bool, at time: TimeInterval, reduced: Bool) {
        if reduced {
            pressure = nil
            restingPressure = 0
            return
        }
        let destination = pressed ? 1.0 : 0.0
        guard destination != (pressure?.target ?? restingPressure) else { return }
        let current = pressure?.sample(at: time) ?? LiquidMotionSample(position: restingPressure, velocity: 0)
        pressure = LiquidMotionSegment(
            start: current, target: destination, startedAt: time, response: pressed ? 0.18 : 0.27, bounds: 0...1)
    }

    mutating func finish(at time: TimeInterval) {
        if let travel, time >= travel.startedAt + travel.settlingDuration {
            restingPosition = travel.target
            self.travel = nil
        }
        if let pressure, time >= pressure.startedAt + pressure.settlingDuration {
            restingPressure = pressure.target
            self.pressure = nil
        }
    }

    mutating func snap(to destination: Double) {
        restingPosition = destination
        restingPressure = 0
        travel = nil
        pressure = nil
        tracking = nil
    }
}

/// Pointer coordinates are local to the row of tab slots (without shell padding).
struct LiquidDragState {
    let startX: Double
    let cellWidth: Double
    let tabCount: Int
    let origin: Double
    private(set) var sample: LiquidMotionSample
    private(set) var moved = false
    private var lastTime: TimeInterval

    init(x: Double, cellWidth: Double, tabCount: Int, presentation: Double, time: TimeInterval) {
        self.startX = x
        self.cellWidth = max(cellWidth, 1)
        self.tabCount = tabCount
        let finger = x / max(cellWidth, 1) - 0.5
        // Preserve the grab offset when catching a capsule already in flight.
        origin = abs(finger - presentation) <= 0.65 ? presentation : min(max(finger.rounded(), 0), Double(tabCount - 1))
        sample = .init(position: presentation, velocity: 0)
        lastTime = time
    }

    mutating func update(x: Double, at time: TimeInterval) {
        let delta = x - startX
        moved = moved || abs(delta) >= 6
        guard moved else { return }
        let position = min(max(origin + delta / cellWidth, 0), Double(tabCount - 1))
        let dt = max(time - lastTime, 1.0 / 240)
        let velocity = min(max((position - sample.position) / dt, -8), 8)
        sample = .init(position: position, velocity: sample.velocity * exp(-dt * 18) * 0.65 + velocity * 0.35)
        lastTime = time
    }

    var destination: Int { Int(sample.position.rounded()).clamped(to: 0...(tabCount - 1)) }
    var tappedIndex: Int { Int(floor(startX / cellWidth)).clamped(to: 0...(tabCount - 1)) }
}

extension Int {
    fileprivate func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

/// Authored from the native recording, not Apple's private material constants.
struct LiquidOptics {
    let pressure: Double
    let energy: Double
    var widthScale: Double { 1 + 0.22 * pressure + 0.10 * energy * (1 - 0.5 * pressure) }
    var heightScale: Double { 1 + 0.38 * pressure + 0.025 * energy }
    var glassMix: Double { pressure * pressure * (3 - 2 * pressure) }
    var refraction: Double { glassMix * (0.85 + 0.15 * energy) }
    func tintOpacity(dark: Bool) -> Double { (dark ? 0.96 : 1) * (1 - glassMix) + 0.035 * glassMix }
}
