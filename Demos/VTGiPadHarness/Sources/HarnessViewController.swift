import UIKit
import SwiftTerm

/// Shows a `VectorTerminalView` and feeds it the scenes in `HarnessScenes`.
///
/// Everything the terminal shows arrives through `feed(byteArray:)` — the same
/// path a socket, an SSH channel or a recorded stream would use. That is the
/// whole point of the harness: on iOS there is no process to attach to, so the
/// view has to be good enough to drive from bytes alone.
final class HarnessViewController: UIViewController {
    private let terminalView = VectorTerminalView(frame: .zero, font: nil)
    private let picker = UISegmentedControl(items: HarnessScenes.all.map(\.name))

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        terminalView.translatesAutoresizingMaskIntoConstraints = false
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.selectedSegmentIndex = 0
        picker.addTarget(self, action: #selector(sceneChanged), for: .valueChanged)

        view.addSubview(terminalView)
        view.addSubview(picker)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            picker.centerXAnchor.constraint(equalTo: guide.centerXAnchor),

            terminalView.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 8),
            terminalView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: guide.bottomAnchor)
        ])

        // No process, so VTG replies have nowhere to go by default. Print them:
        // a query that answers here is a query that would answer over SSH.
        terminalView.vtgResponseHandler = { response in
            print("VTG reply: \(response.replacingOccurrences(of: "\u{1b}", with: "^["))")
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let terminal = terminalView.getTerminal()
        print("harness: view \(terminalView.bounds.size), grid \(terminal.cols)x\(terminal.rows), "
              + "cell \(terminalView.currentVTGCellSize().map { "\($0.width)x\($0.height)" } ?? "unknown")")
        play(HarnessScenes.all[0])
    }

    @objc private func sceneChanged() {
        play(HarnessScenes.all[picker.selectedSegmentIndex])
    }

    /// What the terminal buffer holds, so "the text is missing" can be told
    /// apart from "the text was never parsed".
    private func dumpFirstLines(_ label: String) {
        let terminal = terminalView.getTerminal()
        let text = terminal.getText(
            start: Position(col: 0, row: 0),
            end: Position(col: terminal.cols - 1, row: 4)
        )
        print("harness \(label): buffer rows 0-4 = \(text.debugDescription)")
    }

    private func play(_ scene: HarnessScene) {
        // Leave page mode and clear the scene before each run, so switching
        // back and forth cannot accumulate state.
        feed(HarnessScenes.reset)
        feed(scene.bytes)
        dumpFirstLines(scene.name)
    }

    private func feed(_ text: String) {
        terminalView.feed(byteArray: Array(text.utf8)[...])
    }
}
