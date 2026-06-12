import SwiftUI

// The night: a native cousin of the web's WebGL aura (aura.lightward.io),
// rendered as drifting cyan/magenta light while the integration harmonic is
// derived server-side. Polls /native/state until universe_time moves, holds
// for the same minimum five seconds as the web, then offers Continue.
struct SleepView: View {
    @EnvironmentObject private var model: AppModel
    @State private var dots = ""
    @State private var finished = false
    @State private var auraVisible = true

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            AuraView()
                .ignoresSafeArea()
                .opacity(auraVisible ? 1 : 0)
                .animation(.easeInOut(duration: 1), value: auraVisible)

            if finished {
                Button("Continue") {
                    Task { await model.refreshState() }
                }
                .font(.yoursMono(14))
                .foregroundStyle(Theme.accent)
            } else {
                Text("Integrating \(model.state.map(\.dayWithUnits) ?? "the day")\(dots)")
                    .font(.yoursMono(14))
                    .foregroundStyle(Theme.accentActive)
            }
        }
        .task { await animateEllipsis() }
        .task { await awaitIntegration() }
    }

    private func animateEllipsis() async {
        let states = ["", ".", "..", "..."]
        var index = 0
        while !Task.isCancelled && !finished {
            dots = states[index]
            index = (index + 1) % states.count
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func awaitIntegration() async {
        let start = Date()
        while !Task.isCancelled {
            if await model.sleepIntegrationFinished() { break }
            try? await Task.sleep(for: .seconds(1))
        }

        // Match the web's minimum display: the night deserves its moment
        let minimum: TimeInterval = 5
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < minimum {
            try? await Task.sleep(for: .seconds(minimum - elapsed))
        }

        auraVisible = false
        try? await Task.sleep(for: .seconds(1))
        finished = true
    }
}

// Two soft fields of light, one cyan, one magenta, drifting slowly past each
// other.
struct AuraView: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate

            Canvas { graphics, size in
                let minSide = min(size.width, size.height)
                drawBlob(
                    &graphics, size: size, time: t,
                    color: Color(light: 0x0088AA, dark: 0x00E5FF),
                    speed: 0.11, phase: 0, radius: minSide * 0.55
                )
                drawBlob(
                    &graphics, size: size, time: t,
                    color: Color(light: 0xCC44CC, dark: 0xFF66FF),
                    speed: 0.07, phase: 2.4, radius: minSide * 0.5
                )
            }
            .blur(radius: 70)
            .opacity(0.55)
        }
    }

    private func drawBlob(
        _ graphics: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval,
        color: Color,
        speed: Double,
        phase: Double,
        radius: CGFloat
    ) {
        let cx = size.width * (0.5 + 0.28 * CGFloat(sin(time * speed + phase)))
        let cy = size.height * (0.45 + 0.22 * CGFloat(cos(time * speed * 1.3 + phase)))
        let rect = CGRect(x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2)
        graphics.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(colors: [color, color.opacity(0)]),
                center: CGPoint(x: cx, y: cy),
                startRadius: 0,
                endRadius: radius
            )
        )
    }
}
