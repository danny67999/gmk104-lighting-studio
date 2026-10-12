import Foundation
enum ControllerDiagnostics {
    // A separate CLI path never creates ControllerModel, loads saved profiles,
    // requests permission, reapplies sleep settings or sends lighting writes.
    static func inspect() -> Int32 {
        do {
            let connection = try KeyboardConnections().open()
            defer { connection.transport.close() }
            let state = try RGBClient(connection.transport).read()
            let modes = try OnboardUploader(transport:connection.transport).supportedModes()
            let values: [String:Any] = ["connection":connection.transport.connectionName,
                "inputMonitoring":KeyboardEvents.permission.rawValue,"effect":state.effect,
                "brightness":state.brightness,"nativePlaybackAvailable":modes.volatile,
                "permanentSaveAvailable":modes.persistent,"maximumEffectID":modes.maximumEffectID,
                "activeProfileBytes":modes.activeProfileLength,"lightingWrites":0,"profileWrites":0]
            let data = try JSONSerialization.data(withJSONObject:values,options:[.prettyPrinted,.sortedKeys])
            print(String(data:data,encoding:.utf8)!);print("READ-ONLY INSPECTION PASSED. No lighting or profile was written.")
            return 0
        } catch { print("Inspection failed: \(error.localizedDescription)");return 1 }
    }
}
