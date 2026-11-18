import AppKit
import QuartzCore

/// Something that moves the text. Today: a timer at a set words-per-minute.
/// Later: a voice-follow driver that listens to speech and calls
/// `scrollDriver(moveToCharacter:)` with the position of the last word heard.
@MainActor
protocol ScrollDriverDelegate: AnyObject {
    /// Smooth, continuous movement (timer-based).
    func scrollDriver(scrollBy points: CGFloat)
    /// Jump to a known position in the text (e.g. voice matched a word).
    func scrollDriver(moveToCharacter index: Int)
}

@MainActor
protocol ScrollDriver: AnyObject {
    var delegate: ScrollDriverDelegate? { get set }
    func start()
    func stop()
}

/// Scrolls at a constant speed, ~60 updates per second.
@MainActor
final class TimedScrollDriver: ScrollDriver {
    weak var delegate: ScrollDriverDelegate?
    var pointsPerSecond: () -> CGFloat = { 0 }

    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0

    func start() {
        stop()
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let elapsed = min(now - lastTick, 0.1)
        lastTick = now
        delegate?.scrollDriver(scrollBy: pointsPerSecond() * CGFloat(elapsed))
    }
}
