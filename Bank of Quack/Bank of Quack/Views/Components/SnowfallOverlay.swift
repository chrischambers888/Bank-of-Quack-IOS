import SwiftUI
import Combine

// MARK: - Snowflake Model

struct Snowflake: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    let size: CGFloat
    let opacity: Double
    let speed: CGFloat
    let wobbleAmount: CGFloat
    let wobbleSpeed: Double
    let rotationSpeed: Double
    let symbol: String
    
    static let symbols = ["❄", "❅", "❆", "✻", "✼", "❋"]
    
    static func random(in size: CGSize) -> Snowflake {
        Snowflake(
            x: CGFloat.random(in: 0...size.width),
            y: CGFloat.random(in: -100...size.height),
            size: CGFloat.random(in: 8...22),
            opacity: Double.random(in: 0.4...0.9),
            speed: CGFloat.random(in: 20...60),
            wobbleAmount: CGFloat.random(in: 15...40),
            wobbleSpeed: Double.random(in: 1.5...3.5),
            rotationSpeed: Double.random(in: 0.5...2.0),
            symbol: symbols.randomElement()!
        )
    }
}

// MARK: - Snowfall Overlay View

struct SnowfallOverlay: View {
    @State private var snowflakes: [Snowflake] = []
    @State private var animationTime: Double = 0
    
    private let snowflakeCount = 50
    private let timer = Timer.publish(every: 1/30, on: .main, in: .common).autoconnect()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(snowflakes) { snowflake in
                    SnowflakeView(
                        snowflake: snowflake,
                        animationTime: animationTime,
                        screenHeight: geometry.size.height
                    )
                }
            }
            .onAppear {
                initializeSnowflakes(in: geometry.size)
            }
            .onReceive(timer) { _ in
                animationTime += 1/30
                updateSnowflakes(in: geometry.size)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
    
    private func initializeSnowflakes(in size: CGSize) {
        snowflakes = (0..<snowflakeCount).map { _ in
            Snowflake.random(in: size)
        }
    }
    
    private func updateSnowflakes(in size: CGSize) {
        for i in snowflakes.indices {
            // Move snowflake down
            snowflakes[i].y += snowflakes[i].speed / 30
            
            // Reset if off screen
            if snowflakes[i].y > size.height + 50 {
                snowflakes[i].y = -50
                snowflakes[i].x = CGFloat.random(in: 0...size.width)
            }
        }
    }
}

// MARK: - Individual Snowflake View

struct SnowflakeView: View {
    let snowflake: Snowflake
    let animationTime: Double
    let screenHeight: CGFloat
    
    private var wobbleOffset: CGFloat {
        sin(animationTime * snowflake.wobbleSpeed) * snowflake.wobbleAmount
    }
    
    private var rotation: Double {
        animationTime * snowflake.rotationSpeed * 360
    }
    
    var body: some View {
        Text(snowflake.symbol)
            .font(.system(size: snowflake.size))
            .foregroundStyle(.white)
            .opacity(snowflake.opacity)
            .rotationEffect(.degrees(rotation))
            .position(
                x: snowflake.x + wobbleOffset,
                y: snowflake.y
            )
            .shadow(color: .white.opacity(0.3), radius: 2)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        LinearGradient(
            colors: [Color(hex: "cb0b0a"), Color(hex: "8e0413")],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        
        SnowfallOverlay()
    }
}
