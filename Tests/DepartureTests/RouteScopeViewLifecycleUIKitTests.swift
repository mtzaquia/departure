#if canImport(UIKit)
import Testing
import UIKit
import SwiftUI
@testable import Departure

@MainActor
struct RouteScopeHostUIKitTests {
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

        let scope = RouteScope(id: "root", route: nil)
        // A descendant may update before the branch's own lifecycle bridge installs.
        #expect(scope.ownership(of: declarationView) == .pending)
        let managedID = UUID()
        scope.attachHost(managedView, id: managedID)
        #expect(scope.ownership(of: declarationView) == .managed)

        let fragmentedController = UIViewController()
        let fragmentedView = UIView()
        fragmentedController.view.addSubview(fragmentedView)
        root.view.addSubview(fragmentedController.view)
        #expect(scope.ownership(of: fragmentedView) == .managed)

        scope.detachHost(id: managedID)
        #expect(scope.ownership(of: declarationView) == .pending)
    }

    @Test func presentedControllerIsOutsideTheManagedPresentation() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let managedView = UIView()
        root.view.addSubview(managedView)
        let scope = RouteScope(id: "root", route: nil)
        scope.attachHost(managedView, id: UUID())

        let presented = UIViewController()
        presented.modalPresentationStyle = .fullScreen
        let declarationView = UIView()
        presented.view.addSubview(declarationView)
        root.present(presented, animated: false)
        defer { root.dismiss(animated: false) }

        #expect(presented.presentingViewController === root)
        #expect(scope.ownership(of: declarationView) == .unmanaged)
    }

    @Test func pageSheetControllerIsOutsideTheManagedPresentation() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let managedView = UIView()
        root.view.addSubview(managedView)
        let scope = RouteScope(id: "root", route: nil)
        scope.attachHost(managedView, id: UUID())

        let presented = UIViewController()
        presented.modalPresentationStyle = .pageSheet
        let declarationView = UIView()
        presented.view.addSubview(declarationView)
        root.present(presented, animated: false)
        defer { root.dismiss(animated: false) }

        #expect(presented.presentingViewController === root)
        #expect(scope.ownership(of: declarationView) == .unmanaged)
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

        let scope = RouteScope(id: "root", route: nil)
        let firstID = UUID()
        scope.attachHost(firstView, id: firstID)
        scope.attachHost(replacementView, id: UUID())
        scope.detachHost(id: firstID)

        #expect(scope.ownership(of: declarationView) == .managed)
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
        let scope = RouteScope(id: "root", route: nil)
        scope.attachHost(managedView, id: UUID())

        #expect(scope.ownership(of: firstDeclaration) == .managed)
        tabs.selectedIndex = 1
        #expect(scope.ownership(of: secondDeclaration) == .managed)
        tabs.selectedIndex = 0
        #expect(scope.ownership(of: firstDeclaration) == .managed)
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
        let attachment = RouteScopeAttachment(kind: .hooks)
        var installations = 0
        var removals = 0
        attachment.update(target: scope, view: declarationView,
            apply: { _ in installations += 1 }, remove: { _ in removals += 1 })
        #expect(installations == 0)

        let firstManagedID = UUID()
        scope.attachHost(managedView, id: firstManagedID)
        #expect(installations == 1)
        scope.detachHost(id: firstManagedID)
        #expect(removals == 0)
        #expect(installations == 2)
        scope.attachHost(managedView, id: UUID())
        #expect(installations == 3)
        attachment.detach()
        #expect(removals == 1)
    }

    @Test func destroyedNativeAnchorCannotBecomeAModelOnlyHost() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let scope = RouteScope(id: "root", route: nil)
        do {
            let anchor = UIView()
            controller.view.addSubview(anchor)
            scope.attachHost(anchor, id: UUID())
            #expect(scope.isAvailableForPresentation)
            anchor.removeFromSuperview()
        }
        #expect(scope.isInstalledInView)
        #expect(!scope.isAvailableForPresentation)
    }

    @Test func admittedAttachmentRefreshesWhileUnavailableWithoutAdmittingANewSource() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let managedView = UIView(), declarationView = UIView()
        root.view.addSubview(managedView)
        root.view.addSubview(declarationView)
        let scope = RouteScope(id: "root", route: nil)
        let hostID = UUID()
        scope.attachHost(managedView, id: hostID)
        let existing = RouteScopeAttachment(kind: .hooks)
        var value = ""
        existing.update(target: scope, view: declarationView,
            apply: { _ in value = "initial" }, remove: { _ in })
        #expect(value == "initial")
        managedView.removeFromSuperview()
        declarationView.removeFromSuperview()
        scope.hostAvailabilityDidChange(id: hostID)
        #expect(scope.isInstalledInView)
        #expect(!scope.isAvailableForPresentation)
        existing.handle(.updated(isInstalledInWindow: false), target: scope, view: declarationView,
            apply: { _ in value = "refreshed" }, remove: { _ in })
        #expect(value == "refreshed")
        let pending = RouteScopeAttachment(kind: .hooks)
        pending.update(target: scope, view: declarationView,
            apply: { _ in value = "not authorized" }, remove: { _ in })
        #expect(value == "refreshed")
        existing.detach()
        pending.detach()
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
        first.attachHost(firstView, id: UUID())
        second.attachHost(secondView, id: UUID())

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

    @Test func branchHostRebindingKeepsMappedScopes() throws {
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
        parent.define(RouteMap { Branches { Branch("first") {}; Branch("second") {} } }.declarations)
        let first = try #require(parent.branchScopes["first"])
        let second = try #require(parent.branchScopes["second"])
        first.attachHost(hostView, id: UUID())
        second.attachHost(hostView, id: UUID())
        let attachment = RouteScopeAttachment(kind: .routing)
        let hostID = RoutePresentationHostID()
        let apply: (RouteScope) -> Void = {
            $0.bindRoutingHost(hostID, automatic: false, environment: EnvironmentValues())
        }
        let remove: (RouteScope) -> Void = { $0.unbindRoutingHost(hostID) }
        attachment.update(target: first, view: attachmentView, apply: apply, remove: remove)
        attachment.update(target: second, view: nil, apply: apply, remove: remove)

        #expect(first.presentationHostID == nil)
        #expect(second.presentationHostID == hostID)
        attachment.detach()
        #expect(second.presentationHostID == nil)
        #expect(parent.branchScopes["first"] === first)
        #expect(parent.branchScopes["second"] === second)
    }
}
#endif
