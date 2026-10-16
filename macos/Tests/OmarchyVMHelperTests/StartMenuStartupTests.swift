import AppKit
import Testing
@testable import OmarchyVMHelper

@Suite("Start menu automatic startup", .serialized)
@MainActor
struct StartMenuStartupTests {
    @Test("Enabling automatic startup requires confirmation before saving",
          arguments: [true, false])
    func confirmsAutomaticStartup(confirmed: Bool) throws {
        _ = NSApplication.shared
        var automaticStart = false
        var launchCount = 0
        var confirmationCount = 0
        let menu = makeMenu(
            storageState: { .defaultLocation },
            startAutomatically: { automaticStart },
            setStartAutomatically: { automaticStart = $0; return nil },
            confirmAutomaticStartup: { alert in
                confirmationCount += 1
                #expect(!automaticStart)
                #expect(launchCount == 0)
                #expect(alert.messageText == "Skip the launcher")
                #expect(alert.informativeText.contains("hold Option while opening the app"))
                #expect(alert.informativeText.contains("Setup → Try Omarchy Settings"))
                #expect(alert.buttons.map(\.title) == ["OK", "Cancel"])
                return confirmed ? .alertFirstButtonReturn : .alertSecondButtonReturn
            },
            launch: { launchCount += 1 }
        )
        defer { menu.dismiss() }
        menu.prepareForPresentation(visibleFrame: nil)
        let content = try #require(menu.window.contentView)
        let toggle = try #require(descendant(
            withIdentifier: "automatic-start-toggle", in: content
        ) as? NSButton)
        #expect(toggle.state == .off)
        toggle.performClick(nil)
        #expect(automaticStart == confirmed)
        #expect(toggle.state == (confirmed ? .on : .off))
        #expect(confirmationCount == 1)
        #expect(launchCount == 0)

        menu.launchOmarchy()
        menu.launchOmarchy()
        #expect(launchCount == 1)
        #expect(!menu.window.isVisible)
        let launchingToggle = try #require(descendant(
            withIdentifier: "automatic-start-toggle", in: content
        ) as? NSButton)
        #expect(launchingToggle.state == (confirmed ? .on : .off))
        #expect(!launchingToggle.isEnabled)
    }

    @Test("A failed startup preference write restores the toggle and explains the error",
          arguments: [false, true])
    func failedStartupSave(wasEnabled: Bool) throws {
        _ = NSApplication.shared
        var attempts = 0
        var errorsPresented = 0
        let menu = makeMenu(
            storageState: { .defaultLocation },
            startAutomatically: { wasEnabled },
            setStartAutomatically: { enabled in
                attempts += 1
                #expect(enabled == !wasEnabled)
                return "The workspace is read-only."
            },
            presentStartupSaveError: { alert, _ in
                errorsPresented += 1
                #expect(alert.messageText == "Skip launcher couldn’t be saved")
                #expect(alert.informativeText == "The workspace is read-only.")
            }
        )
        defer { menu.dismiss() }
        menu.prepareForPresentation(visibleFrame: nil)
        let content = try #require(menu.window.contentView)
        let toggle = try #require(descendant(
            withIdentifier: "automatic-start-toggle", in: content
        ) as? NSButton)
        toggle.performClick(nil)
        #expect(attempts == 1)
        #expect(toggle.state == (wasEnabled ? .on : .off))
        #expect(errorsPresented == 1)
    }

    @Test("Running settings can change startup and close without launching or quitting the VM")
    func runningSettings() throws {
        _ = NSApplication.shared
        var automaticStart = true
        var launchCount = 0
        var closeCount = 0
        let menu = makeMenu(
            storageState: { .defaultLocation },
            startAutomatically: { automaticStart },
            setStartAutomatically: { automaticStart = $0; return nil },
            confirmAutomaticStartup: { _ in
                Issue.record("Disabling automatic startup must not ask for confirmation")
                return .alertSecondButtonReturn
            },
            launch: { launchCount += 1 }
        )
        defer { menu.dismiss() }
        menu.launchOmarchy()
        menu.virtualMachineDidStart { closeCount += 1 }
        menu.prepareForPresentation(visibleFrame: nil)
        let content = try #require(menu.window.contentView)
        let toggle = try #require(descendant(
            withIdentifier: "automatic-start-toggle", in: content
        ) as? NSButton)
        #expect(toggle.isEnabled)
        toggle.performClick(nil)
        #expect(!automaticStart)
        for identifier in ["permission-action-folder", "permission-action-network", "permission-action-cpu"] {
            let button = try #require(descendant(withIdentifier: identifier, in: content) as? NSButton)
            #expect(button.isEnabled)
        }
        let immersive = try #require(descendant(withIdentifier: "immersive-toggle", in: content) as? NSButton)
        #expect(immersive.isEnabled)
        for identifier in ["restart-vm-button", "manage-vm-button"] {
            #expect(try #require(descendant(withIdentifier: identifier, in: content) as? NSButton).isEnabled)
        }
        menu.shutdownDidBegin()
        for identifier in ["automatic-start-toggle", "permission-action-folder", "permission-action-network", "permission-action-cpu", "restart-vm-button", "manage-vm-button"] {
            #expect(!(try #require(descendant(withIdentifier: identifier, in: content) as? NSButton)).isEnabled)
        }
        menu.launchOmarchy()
        #expect(launchCount == 1)
        let done = try #require(descendant(withIdentifier: "launch-button", in: content) as? NSButton)
        #expect(done.isEnabled)
        done.performClick(nil)
        #expect(closeCount == 1)
        #expect(menu.windowShouldClose(menu.window) == false)
        #expect(closeCount == 2)
        #expect(launchCount == 1)
    }

    @Test("Send Command-Tab starts off, saves a change and shows the release shortcut")
    func commandTabToggle() throws {
        _ = NSApplication.shared
        var sendsCommandTab = false
        let menu = makeMenu(
            storageState: { .defaultLocation },
            sendsCommandTab: { sendsCommandTab },
            setSendsCommandTab: { sendsCommandTab = $0 }
        )
        defer { menu.dismiss() }
        menu.prepareForPresentation(visibleFrame: nil)
        let content = try #require(menu.window.contentView)
        let toggle = try #require(descendant(
            withIdentifier: "command-tab-toggle", in: content
        ) as? NSButton)
        let caption = try #require(descendant(
            withIdentifier: "command-tab-caption", in: content
        ) as? NSTextField)
        #expect(toggle.state == .off)
        #expect(caption.stringValue == StartMenuPresentation.commandTabDetail(isEnabled: false))

        toggle.performClick(nil)
        #expect(sendsCommandTab)
        #expect(caption.stringValue == StartMenuPresentation.commandTabDetail(isEnabled: true))
        #expect(caption.stringValue.contains(StartMenuPresentation.commandTabReleaseShortcut))
    }

    private func makeMenu(
        storageState: @escaping () -> StorageLocationMenuState,
        startAutomatically: @escaping () -> Bool = { false },
        setStartAutomatically: @escaping (Bool) -> String? = { _ in nil },
        presentStartupSaveError: @escaping (NSAlert, NSWindow) -> Void = { _, _ in },
        confirmAutomaticStartup: @escaping (NSAlert) -> NSApplication.ModalResponse = { _ in .alertFirstButtonReturn },
        sendsCommandTab: @escaping () -> Bool = { false },
        setSendsCommandTab: @escaping (Bool) -> Void = { _ in },
        launch: @escaping () -> Void = {}
    ) -> StartMenuWindow {
        StartMenuWindow(
            accessibilityStatus: { true },
            microphoneStatus: { .authorized },
            cameraStatus: { .authorized },
            requestAccessibility: {},
            requestMicrophone: { completion in completion(true) },
            requestCamera: { completion in completion(true) },
            canResetStorage: true,
            storageLocation: { storageState().displayPath },
            storageLocationURL: {
                storageState().containerPath.map { URL(fileURLWithPath: $0) }
            },
            storageSpaceEstimate: { nil },
            storageLocationStatus: storageState,
            validateStorageLocation: { _ in nil },
            chooseStorageLocation: { _ in nil },
            useDefaultStorageLocation: {},
            resetStorage: {},
            sharedFolderStatus: { .disabled },
            chooseSharedFolder: { _ in nil },
            setSharedFolderEnabled: { _ in },
            portForwardingStatus: { [] },
            offersBridgedNetworking: true,
            immersiveMode: { true },
            setImmersiveMode: { _ in },
            sendsCommandTab: sendsCommandTab,
            setSendsCommandTab: setSendsCommandTab,
            startAutomatically: startAutomatically,
            setStartAutomatically: setStartAutomatically,
            presentStartupSaveError: presentStartupSaveError,
            confirmAutomaticStartup: confirmAutomaticStartup,
            launch: launch
        )
    }

    private func descendant(withIdentifier identifier: String, in view: NSView) -> NSView? {
        if view.identifier?.rawValue == identifier { return view }
        for child in view.subviews {
            if let found = descendant(withIdentifier: identifier, in: child) { return found }
        }
        return nil
    }
}
