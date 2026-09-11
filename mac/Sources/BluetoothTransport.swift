import Foundation
import CoreBluetooth

struct BluetoothNotConnected: Error {}

/// CoreBluetooth callbacks run on their own queue. The controller remains the
/// single serialized writer. A timeout invalidates the session; no uncertain
/// write is retried or allowed to satisfy a later request.
final class BluetoothTransport: NSObject, ReportTransport, CBCentralManagerDelegate, CBPeripheralDelegate {
    let identity: BluetoothKeyboardIdentity
    let connectionName = "Bluetooth"
    let reconnectsWithoutReplug = true
    private let callbackQueue = DispatchQueue(label: "GMK104.Bluetooth")
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var characteristic: CBCharacteristic?
    private var pnpVerified = false
    private var ready = false
    private var closed = false
    private enum Kind { case connect, write, read }
    private final class Pending {
        let kind: Kind
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<[UInt8], Error>?
        init(_ kind: Kind) { self.kind = kind }
    }
    private var pending: Pending?

    init(identity: BluetoothKeyboardIdentity) throws {
        self.identity = identity
        super.init()
        let start = Pending(.connect)
        callbackQueue.sync {
            pending = start
            central = CBCentralManager(delegate: self, queue: callbackQueue,
                                       options: [CBCentralManagerOptionShowPowerAlertKey: false])
        }
        do { _ = try awaitResult(start, seconds: 12) }
        catch { close(); throw error }
    }
    private func finish(_ result: Result<[UInt8], Error>) {
        guard let operation = pending else { return }
        pending = nil; operation.result = result; operation.semaphore.signal()
    }
    private func fail(_ message: String) { finish(.failure(ControllerError.message(message))) }
    private func awaitResult(_ operation: Pending, seconds: Double = 3) throws -> [UInt8] {
        if operation.semaphore.wait(timeout: .now() + seconds) != .success {
            close()
            throw TransportUnavailableError(message: "Bluetooth lighting timed out. Wake the keyboard and keep it in Bluetooth mode.")
        }
        return try operation.result!.get()
    }
    private func perform(_ kind: Kind) throws -> [UInt8] {
        let operation = Pending(kind)
        let valid = callbackQueue.sync { () -> Bool in
            guard !closed, ready, pending == nil, let peripheral, let characteristic, peripheral.state == .connected else { return false }
            pending = operation
            if kind == .read { peripheral.readValue(for: characteristic) }
            return true
        }
        guard valid else { throw TransportUnavailableError(message: "Bluetooth keyboard disconnected.") }
        return try awaitResult(operation)
    }
    private func write(_ bytes: [UInt8]) throws {
        let operation = Pending(.write)
        let valid = callbackQueue.sync { () -> Bool in
            guard !closed, ready, pending == nil, let peripheral, let characteristic, peripheral.state == .connected,
                  bytes.count <= peripheral.maximumWriteValueLength(for: .withResponse) else { return false }
            pending = operation
            peripheral.writeValue(Data(bytes), for: characteristic, type: .withResponse)
            return true
        }
        guard valid else { throw TransportUnavailableError(message: "Bluetooth keyboard is unavailable for lighting.") }
        _ = try awaitResult(operation)
    }
    func exchange(_ payload: [UInt8]) throws -> [UInt8] {
        let packets = try BluetoothPackets.writes(for: payload)
        for packet in packets { try write(packet) }
        if payload[0] == 8 { return try BluetoothPackets.reply(perform(.read)) }
        return payload + Array(repeating: 0, count: 32 - payload.count)
    }
    func checkSingleDevice() throws {
        let identities = BluetoothKeyboardIdentity.candidates()
        try require(identities.count == 1 && identities[0].registryID == identity.registryID,
                    "The Bluetooth keyboard attachment changed. Reconnect in the app.")
        let online = callbackQueue.sync { !closed && ready && peripheral?.state == .connected }
        if !online { throw TransportUnavailableError(message: "The Bluetooth keyboard is asleep or disconnected.") }
    }
    func close() {
        callbackQueue.sync {
            guard !closed else { return }
            closed = true; ready = false
            finish(.failure(TransportUnavailableError(message: "Bluetooth session closed.")))
            if let peripheral { peripheral.delegate = nil; central.cancelPeripheralConnection(peripheral) }
            central?.delegate = nil
        }
    }
    deinit { close() }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !closed, pending?.kind == .connect else { return }
        if central.state == .unknown || central.state == .resetting { return }
        guard central.state == .poweredOn else {
            fail(central.state == .unauthorized ? "Allow Bluetooth access for GMK104 RGB Controller in System Settings." : "Turn on Bluetooth to connect the keyboard.")
            return
        }
        let matches = central.retrieveConnectedPeripherals(withServices: [CBUUID(string: "1812")]).filter { $0.name == identity.name }
        guard matches.count == 1 else { finish(.failure(BluetoothNotConnected())); return }
        peripheral = matches[0]; peripheral?.delegate = self
        central.connect(matches[0])
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard !closed, self.peripheral === peripheral else { return }
        peripheral.discoverServices([CBUUID(string: BluetoothPackets.service), CBUUID(string: "180A")])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        finish(.failure(BluetoothNotConnected()))
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        ready = false
        finish(.failure(TransportUnavailableError(message: "Bluetooth keyboard disconnected. Wake it to reconnect.")))
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard !closed else { return }
        if let error { finish(.failure(error)); return }
        guard let services = peripheral.services,
              let rgb = services.first(where: { $0.uuid == CBUUID(string: BluetoothPackets.service) }) else {
            fail("Bluetooth lighting requires custom firmware v0.3. Connect a USB cable and use the companion firmware installer.")
            return
        }
        guard let information = services.first(where: { $0.uuid == CBUUID(string: "180A") }) else {
            fail("The Bluetooth keyboard did not expose its hardware identity."); return
        }
        peripheral.discoverCharacteristics([CBUUID(string: BluetoothPackets.characteristic)], for: rgb)
        peripheral.discoverCharacteristics([CBUUID(string: "2A50")], for: information)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard !closed else { return }
        if let error { finish(.failure(error)); return }
        if service.uuid == CBUUID(string: "180A") {
            guard let pnp = service.characteristics?.first(where: { $0.uuid == CBUUID(string: "2A50") }), pnp.properties.contains(.read) else {
                fail("The Bluetooth keyboard has no readable PnP identity."); return
            }
            peripheral.readValue(for: pnp)
        } else {
            guard let rgb = service.characteristics?.first(where: { $0.uuid == CBUUID(string: BluetoothPackets.characteristic) }),
                  rgb.properties.contains(.read), rgb.properties.contains(.write) else {
                fail("The Bluetooth lighting service has incompatible properties."); return
            }
            characteristic = rgb; finishConnectionIfReady()
        }
    }
    private func finishConnectionIfReady() {
        if pending?.kind == .connect && pnpVerified && characteristic != nil { ready = true; finish(.success([])) }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard !closed else { return }
        if let error { finish(.failure(error)); return }
        if pending?.kind == .connect && characteristic.uuid == CBUUID(string: "2A50") {
            guard characteristic.value == Data([2,0x5A,0x24,0x76,0x82,1,0]) else {
                fail("The Bluetooth hardware identity does not match this GMK104 firmware."); return
            }
            pnpVerified = true; finishConnectionIfReady()
        } else if pending?.kind == .read && characteristic === self.characteristic {
            finish(.success(Array(characteristic.value ?? Data())))
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard !closed, pending?.kind == .write, characteristic === self.characteristic else { return }
        if let error { finish(.failure(error)) } else { finish(.success([])) }
    }
}

/// Keep the selected Bluetooth identity stable while the unused USB dongle is
/// plugged in. Attaching the keyboard's cable always takes priority.
final class KeyboardConnections {
    private var bluetoothID: UInt64?
    func open() throws -> (transport: ReportTransport, registryID: UInt64?) {
        bluetoothID = nil
        if !HIDTransport.candidates(wiredOnly: true).isEmpty {
            let t = try HIDTransport(wiredOnly: true); return (t, t.registryEntryID)
        }
        let bluetooth = BluetoothKeyboardIdentity.candidates()
        try require(bluetooth.count <= 1, "Connect exactly one GMK104 Bluetooth keyboard.")
        if let identity = bluetooth.first {
            do {
                let t = try BluetoothTransport(identity: identity)
                bluetoothID = identity.registryID; return (t, identity.registryID)
            } catch is BluetoothNotConnected { /* An old HID attachment can outlive its radio link. */ }
        }
        let t = try HIDTransport(); return (t, t.registryEntryID)
    }
    func attachments() -> (count: Int, registryID: UInt64?) {
        let wired = HIDTransport.candidates(wiredOnly: true)
        if !wired.isEmpty { return (wired.count, wired.count == 1 ? try? HIDTransport.registryID(of: wired[0]) : nil) }
        let bluetooth = BluetoothKeyboardIdentity.candidates()
        if let bluetoothID, bluetooth.contains(where: { $0.registryID == bluetoothID }) { return (bluetooth.count, bluetoothID) }
        let usb = HIDTransport.candidates()
        if !usb.isEmpty { return (usb.count, usb.count == 1 ? try? HIDTransport.registryID(of: usb[0]) : nil) }
        return (bluetooth.count, bluetooth.count == 1 ? bluetooth[0].registryID : nil)
    }
}
