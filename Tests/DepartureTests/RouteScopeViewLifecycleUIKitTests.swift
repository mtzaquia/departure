#if canImport(UIKit)
import Testing
import UIKit
@testable import Departure

@MainActor
struct RouteScopeLedgerUIKitTests {
    @Test func siblingAndUnrelatedHostingControllersAreNotMistakenForPresentations() {
        let root = UIViewController()
        let managedController = UIViewController()
        let declarationController = UIViewController()

        for child in [managedController, declarationController] {
            root.addChild(child)
            root.view.addSubview(child.view)
            child.didMove(toParent: root)
        }

        let managedView = UIView()
        managedController.view.addSubview(managedView)
        let declarationView = UIView()
        declarationController.view.addSubview(declarationView)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let ledger = RouteScopeLedger(initialID: "root")
        // A descendant may update before the branch's own lifecycle bridge installs.
        #expect(ledger.ownership(of: declarationView) == .pending)
        let managedID = UUID()
        ledger.installManagedView(managedView, id: managedID)
        #expect(ledger.ownership(of: declarationView) == .managed)

        let fragmentedController = UIViewController()
        let fragmentedView = UIView()
        fragmentedController.view.addSubview(fragmentedView)
        root.view.addSubview(fragmentedController.view)
        #expect(ledger.ownership(of: fragmentedView) == .managed)

        ledger.uninstallManagedView(id: managedID)
        #expect(ledger.ownership(of: declarationView) == .pending)
    }

    @Test func presentedControllerIsOutsideTheManagedPresentation() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let managedView = UIView()
        root.view.addSubview(managedView)
        let ledger = RouteScopeLedger(initialID: "root")
        ledger.installManagedView(managedView, id: UUID())

        let presented = UIViewController()
        presented.modalPresentationStyle = .fullScreen
        let declarationView = UIView()
        presented.view.addSubview(declarationView)
        root.present(presented, animated: false)
        defer { root.dismiss(animated: false) }

        #expect(presented.presentingViewController === root)
        #expect(ledger.ownership(of: declarationView) == .unmanaged)
    }

    @Test func pageSheetControllerIsOutsideTheManagedPresentation() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let managedView = UIView()
        root.view.addSubview(managedView)
        let ledger = RouteScopeLedger(initialID: "root")
        ledger.installManagedView(managedView, id: UUID())

        let presented = UIViewController()
        presented.modalPresentationStyle = .pageSheet
        let declarationView = UIView()
        presented.view.addSubview(declarationView)
        root.present(presented, animated: false)
        defer { root.dismiss(animated: false) }

        #expect(presented.presentingViewController === root)
        #expect(ledger.ownership(of: declarationView) == .unmanaged)
    }

    @Test func staleTeardownCannotRemoveTheReplacementManagedView() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let firstView = UIView()
        let replacementView = UIView()
        let declarationView = UIView()
        [firstView, replacementView, declarationView].forEach(root.view.addSubview)

        let ledger = RouteScopeLedger(initialID: "root")
        let firstID = UUID()
        ledger.installManagedView(firstView, id: firstID)
        ledger.installManagedView(replacementView, id: UUID())
        ledger.uninstallManagedView(id: firstID)

        #expect(ledger.ownership(of: declarationView) == .managed)
    }

    @Test func changingTabsDoesNotMakeTheSelectedBranchUnmanaged() {
        let first = UIViewController()
        let second = UIViewController()
        let tabs = UITabBarController()
        tabs.viewControllers = [first, second]
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let managedView = UIView()
        tabs.view.addSubview(managedView)
        let firstDeclaration = UIView()
        first.view.addSubview(firstDeclaration)
        let secondDeclaration = UIView()
        second.view.addSubview(secondDeclaration)
        let ledger = RouteScopeLedger(initialID: "root")
        ledger.installManagedView(managedView, id: UUID())

        #expect(ledger.ownership(of: firstDeclaration) == .managed)
        tabs.selectedIndex = 1
        #expect(ledger.ownership(of: secondDeclaration) == .managed)
        tabs.selectedIndex = 0
        #expect(ledger.ownership(of: firstDeclaration) == .managed)
    }

    @Test func pendingAttachmentInstallsWhenTheManagedViewArrives() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let managedView = UIView()
        let declarationView = UIView()
        root.view.addSubview(managedView)
        root.view.addSubview(declarationView)

        let scope = RouteScope(id: "root", route: nil)
        let attachment = RouteScopeAttachment(kind: .routes)
        var installations = 0
        var removals = 0
        attachment.update(target: scope, view: declarationView,
            apply: { _ in installations += 1 }, remove: { _ in removals += 1 })
        #expect(installations == 0)

        let firstManagedID = UUID()
        scope.ledger.installManagedView(managedView, id: firstManagedID)
        #expect(installations == 1)
        scope.ledger.uninstallManagedView(id: firstManagedID)
        #expect(removals == 0)
        scope.ledger.installManagedView(managedView, id: UUID())
        #expect(installations == 2)
        attachment.detach()
        #expect(removals == 1)
    }

    @Test func attachmentRebindingRemovesTheExactFormerScope() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let firstView = UIView()
        let secondView = UIView()
        let attachmentView = UIView()
        [firstView, secondView, attachmentView].forEach(root.view.addSubview)
        let first = RouteScope(id: "first", route: nil)
        let second = RouteScope(id: "second", route: nil)
        first.ledger.installManagedView(firstView, id: UUID())
        second.ledger.installManagedView(secondView, id: UUID())

        let attachment = RouteScopeAttachment(kind: .hooks)
        var applied: [ObjectIdentifier] = []
        var removed: [ObjectIdentifier] = []
        let apply: (RouteScope) -> Void = { applied.append(ObjectIdentifier($0)) }
        let remove: (RouteScope) -> Void = { removed.append(ObjectIdentifier($0)) }
        attachment.update(target: first, view: attachmentView, apply: apply, remove: remove)
        attachment.update(target: second, view: attachmentView, apply: apply, remove: remove)
        attachment.detach()

        #expect(applied == [ObjectIdentifier(first), ObjectIdentifier(second)])
        #expect(removed == [ObjectIdentifier(first), ObjectIdentifier(second)])
    }

    @Test func branchKeyChangeRemovesTheFormerRegistration() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let hostView = UIView()
        let attachmentView = UIView()
        controller.view.addSubview(hostView)
        controller.view.addSubview(attachmentView)
        let parent = RouteScope(id: "parent", route: nil)
        let branch = RouteScope(id: "first", route: nil)
        parent.ledger.installManagedView(hostView, id: UUID())
        let attachment = RouteScopeAttachment(kind: .branch)

        attachment.update(target: parent, key: "first", view: attachmentView,
            apply: { $0.registerBranchScope(branch, for: "first") },
            remove: { $0.unregisterBranchScope(branch, for: "first") })
        attachment.update(target: parent, key: "second", view: nil,
            apply: { $0.registerBranchScope(branch, for: "second") },
            remove: { $0.unregisterBranchScope(branch, for: "second") })

        #expect(parent.branchScopes["first"] == nil)
        #expect(parent.branchScopes["second"] === branch)
        // Direct registration preserves a scope's explicit ID; the view modifier
        // updates its own generated scope ID when its branch value changes.
        #expect(branch.id == AnyHashable("first"))
        attachment.detach()
        #expect(parent.branchScopes["second"] == nil)
    }
}
#endif
