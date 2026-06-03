import SwiftUI

/// The little card that slides in bottom-right after a capture. A rounded
/// thumbnail on a frosted glass surround, with a one-time holographic shimmer
/// and a few star particles fluttering up — the first taste of Lightscreen's
/// playful, Pokémon-coded personality.
struct FloatingPreviewView: View {
    let image: NSImage
    /// Whether the shimmer + star flourish plays — driven by the Settings toggle.
    var sparkleEnabled: Bool = true
    var onTap: () -> Void
    var makeProvider: () -> NSItemProvider
    var onDragStart: () -> Void
    var onHover: (Bool) -> Void

    @State private var appeared = false
    @State private var shimmerX: CGFloat = -1.2
    @State private var sparkle = false

    private var particlesOn: Bool { sparkleEnabled }

    var body: some View {
        thumbnail
            .padding(10)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .shadow(color: .black.opacity(0.34), radius: 18, y: 10)
            .scaleEffect(appeared ? 1 : 0.9)
            .opacity(appeared ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .onDrag {
                onDragStart()
                return makeProvider()
            } preview: {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 180)
            }
            .onHover { onHover($0) }
            .onAppear(perform: animateIn)
    }

    private var thumbnail: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 220, maxHeight: 150)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(shimmer)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            )
            .overlay(sparkles)
    }

    // A diagonal band of light that sweeps across once, like tilting a foil card.
    private var shimmer: some View {
        GeometryReader { geo in
            let w = geo.size.width
            LinearGradient(
                colors: [.clear, .white.opacity(0.55), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: w * 0.5)
            .offset(x: shimmerX * w)
            .blendMode(.screen)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .allowsHitTesting(false)
    }

    // Two or three stars drifting up and fading, right after the shot lands.
    private var sparkles: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: "sparkle")
                    .font(.system(size: 11 + CGFloat(i) * 3))
                    .foregroundStyle(.white)
                    .offset(
                        x: [-46, 8, 52][i],
                        y: sparkle ? -38 - CGFloat(i) * 8 : 18
                    )
                    .opacity(sparkle ? 0 : 0.95)
            }
        }
        .allowsHitTesting(false)
    }

    private func animateIn() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
            appeared = true
        }
        guard particlesOn else { return }
        withAnimation(.easeOut(duration: 0.8)) {
            shimmerX = 1.2
        }
        withAnimation(.easeOut(duration: 0.85).delay(0.05)) {
            sparkle = true
        }
    }
}
