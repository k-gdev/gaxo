import Testing
@testable import GaxoCore

@Suite struct StatusMenuModelTests {
    private let phone = ClientInfo(deviceID: "FE:C4:42:6E:68:F7", model: "iPhone18,2", name: "Kevo’s iPhone")

    /// Mockup 1A, plus "Show Gaxo Window" for the menu-bar + window combination.
    @Test func readyMenuMatchesMockup() {
        let items = StatusMenuModel.items(state: .ready, name: "Gaxo", accepting: true)
        #expect(items == [
            .header(title: "Gaxo", status: "Ready · no device connected"),
            .visibleAs("Gaxo"),
            .separator,
            .toggle(title: "Accept connections", isOn: true),
            .separator,
            .action(title: "Show Gaxo Window", key: "1", id: .showWindow),
            .action(title: "Settings…", key: ",", id: .settings),
            .action(title: "Quit Gaxo", key: "q", id: .quit),
        ])
    }

    @Test func mirroringMenuShowsDeviceAndDisconnect() {
        let items = StatusMenuModel.items(state: .mirroring(phone), name: "Gaxo", accepting: true)
        #expect(items.first == .header(title: "Gaxo", status: "Mirroring from Kevo’s iPhone"))
        #expect(items.contains(.action(title: "Show Mirror Window", key: "", id: .showMirrorWindow)))
        #expect(items.contains(.action(title: "Disconnect", key: "", id: .disconnect)))
    }

    @Test func failedMenuShowsError() {
        let items = StatusMenuModel.items(state: .failed(.portInUse(7100)), name: "Gaxo", accepting: true)
        guard case let .header(_, status) = items.first else {
            Issue.record("first item is not the header")
            return
        }
        #expect(status.contains("7100"))
    }

    @Test func pausedMenuSaysNotVisible() {
        let items = StatusMenuModel.items(state: .stopped, name: "Gaxo", accepting: false)
        #expect(items.first == .header(title: "Gaxo", status: "Paused · not visible to iPhones"))
        #expect(items.contains(.toggle(title: "Accept connections", isOn: false)))
    }

    @Test func codeIsShownInHeader() {
        let items = StatusMenuModel.items(state: .awaitingCode("4821"), name: "Gaxo", accepting: true)
        guard case let .header(_, status) = items.first else {
            Issue.record("first item is not the header")
            return
        }
        #expect(status.contains("4821"))
    }
}
