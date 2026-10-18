import GameController
import UOCore

/// Poll on the world animation timer so all callbacks stay on the main actor.
@MainActor
final class ControllerInput {
    private var controller: GCController?
    private var state = ControllerState()
    private(set) var connected = false
    func suspend() { state.suspend() }
    func poll(enabled: Bool) -> ControllerState.Output {
        let available = GCController.controllers().filter { $0.extendedGamepad != nil }
        let selected = controller.flatMap { current in available.first { $0 === current } } ?? available.first
        if selected !== controller {
            controller = selected; state.suspend()
            connected = selected != nil
            Telemetry.shared.record("controller_connection", ["connected": connected])
        }
        guard let pad = selected?.extendedGamepad else {
            return state.sample(x: 0, y: 0, trigger: 0, buttons: [], enabled: false)
        }
        var buttons = Set<ControllerState.Action>()
        if pad.buttonA.isPressed { buttons.insert(.use) }
        if pad.buttonB.isPressed { buttons.insert(.cancel) }
        if pad.buttonX.isPressed { buttons.insert(.backpack) }
        if pad.buttonY.isPressed { buttons.insert(.character) }
        if pad.leftShoulder.isPressed { buttons.insert(.tool) }
        let stick = pad.leftThumbstick
        let dpad = pad.dpad
        let useDpad = dpad.xAxis.value != 0 || dpad.yAxis.value != 0
        return state.sample(x: Double(useDpad ? dpad.xAxis.value : stick.xAxis.value),
                            y: Double(useDpad ? dpad.yAxis.value : stick.yAxis.value),
                            trigger: Double(pad.rightTrigger.value), buttons: buttons, enabled: enabled)
    }
}
