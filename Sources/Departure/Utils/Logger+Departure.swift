//
//  Copyright (c) 2026 @mtzaquia
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import os

/// Global Departure configuration.
public enum Departure {
    private nonisolated static let debugLock = OSAllocatedUnfairLock(initialState: false)

    /// Enables Departure engine logs in debug builds.
    ///
    /// ```swift
    /// Departure.debug = true
    /// ```
    public nonisolated static var debug: Bool {
        get { debugLock.withLock { $0 } }
        set { debugLock.withLock { $0 = newValue } }
    }
}

nonisolated let log = Logger(subsystem: "eu.lelfe.departure", category: "Departure")

enum DepartureLogEvent {
    case actionCompleted(action: any Action)
    case actionDirectInvocationEnded(action: any Action, error: any Error)
    case actionFailed(action: any Action, error: any Error)
    case actionIntercepted(action: any Action, scope: RouteScope)
    case actionInterceptorFinished(action: any Action)
    case actionNoInterceptor(action: any Action, scope: RouteScope)
    case actionRequested(action: any Action)
    case actionRerouteDropped(action: any Action)
    case actionRerouteRequested(action: any Action, route: any Route)
    case actionRunning(action: any Action, currentRoute: (any Route.Type)?)
    case branchActivated(from: AnyHashable, to: AnyHashable, scope: RouteScope)
    case branchActivationFailed(pathIndex: [RouteScope].Index?)
    case branchActivationRejected(from: AnyHashable, to: AnyHashable, scope: RouteScope)
    case branchActivationSkipped(branch: AnyHashable, scope: RouteScope)
    case branchRegistered(branch: AnyHashable, parent: RouteScope, scope: RouteScope)
    case branchUnregistered(branch: AnyHashable, scope: RouteScope)
    case branchUnregisterSkipped(branch: AnyHashable, scope: RouteScope)
    case highPriorityReplacePreparing(route: any Route, match: Router.DeclarationMatch)
    case highContextCleared
    case highContextStarted(pathIndex: [RouteScope].Index)
    case hookDeclarationsUninstalled(scope: RouteScope)
    case hookDeclarationsInstalled(scope: RouteScope, hookCount: Int)
    case pathCleared(removedCount: Int)
    case pathRemovalRequested(pathIndex: [RouteScope].Index, scope: RouteScope)
    case pathRemovalSkipped(scope: RouteScope)
    case pathTrimmed(keepThrough: [RouteScope].Index, removedCount: Int)
    case pathUnchanged(keepThrough: [RouteScope].Index)
    case pendingResumeCheck(branch: AnyHashable, declaringScope: RouteScope)
    case pendingResumeSkipped
    case pendingRouteResuming(route: any Route)
    case routeAcceptedAppend(route: any Route)
    case routeAcceptedReplaceHighPriority(route: any Route)
    case routeAppendSuperseded(route: any Route)
    case routeAppendPreparing(route: any Route, match: Router.DeclarationMatch)
    case routeAppendWaitingReplacingScopes(removedScopes: Int)
    case routeAppended(route: any Route, pathCount: Int)
    case routeBlockedByHighContext(route: any Route)
    case routeCanPresentActiveLocalScope(branch: AnyHashable)
    case routeCanPresentDeclarationDrivesPresentation
    case routeCannotPresentDiscoveryBranchInactive(branch: AnyHashable)
    case routeCannotPresentNoActiveLocalScope(branch: AnyHashable)
    case routeDroppedBranchActivationFailed(branch: AnyHashable)
    case routeDroppedNoDeclaration(routeType: any Route.Type)
    case routeDroppedResolution
    case routeMatched(route: any Route, match: Router.DeclarationMatch, highContextStart: [RouteScope].Index?)
    case routePendingWaitingForActivatedBranchHost(route: any Route, branch: AnyHashable)
    case routePendingWaitingForLocalPresentationScope(route: any Route, branch: AnyHashable)
    case routeRequested(route: any Route)
    case routeRerouted(from: any Route, to: any Route)
    case routeDeclarationsUninstalled(scope: RouteScope)
    case routeDeclarationsInstalled(scope: RouteScope, declarationCount: Int)
    case scopeInstalledInView(scope: RouteScope)
    case scopeUninstalledFromView(scope: RouteScope)
    case viewExitWaitProgress(remaining: Int)
    case viewExitWaitSkipped
    case viewExitWaitStarted(installed: Int)
    case unwindAccepted(keepThrough: [RouteScope].Index?, removing: Int)
    case unwindAcceptedAncestorTarget(keepThrough: [RouteScope].Index?, removing: Int)
    case unwindCompleted
    case unwindDroppedTargetNotFound(target: Router.UnwindTarget?)
    case unwindRequested(target: Router.UnwindTarget?)
    case unwindSkippedNoRoute
    case unwindSkippedNotInsideBranch
}

extension Logger {
    func departureDebug(_ event: @autoclosure () -> DepartureLogEvent) {
#if DEBUG
        guard Departure.debug else { return }
        let message = event().message
        debug("\(message, privacy: .public)")
#endif
    }

    func departureWarning(_ message: @autoclosure () -> String) {
        let message = message()
        warning("\(message, privacy: .public)")
    }
}

#if DEBUG
extension DepartureLogEvent {
    var message: String {
        switch self {
        case let .actionCompleted(action):
            "Action completed: \(action.departureDebugDescription)."
        case let .actionDirectInvocationEnded(action, error):
            "Action direct invocation ended without delivery: \(action.departureDebugDescription), error: \(String(describing: error))."
        case let .actionFailed(action, error):
            "Action failed: \(action.departureDebugDescription) error: \(String(describing: error))."
        case let .actionIntercepted(action, scope):
            "Action intercepted: \(action.departureDebugDescription) by \(scope.departureDebugDescription)."
        case let .actionInterceptorFinished(action):
            "Action interceptor finished: \(action.departureDebugDescription)."
        case let .actionNoInterceptor(action, scope):
            "Action has no interceptor: \(action.departureDebugDescription). Running directly from \(scope.departureDebugDescription)."
        case let .actionRequested(action):
            "Action requested: \(action.departureDebugDescription)."
        case let .actionRerouteDropped(action):
            "Action reroute dropped: \(action.departureDebugDescription) already rerouted once."
        case let .actionRerouteRequested(action, route):
            "Action reroute requested: \(action.departureDebugDescription) -> \(route.departureDebugDescription)."
        case let .actionRunning(action, currentRoute):
            "Action running: \(action.departureDebugDescription) in currentRoute: \(currentRoute.map { String(reflecting: $0) } ?? "nil")."
        case let .branchActivated(previousBranch, branch, scope):
            "branch activated | from=\(previousBranch.departureDebugDescription) | to=\(branch.departureDebugDescription) | scope=\(scope.departureDebugDescription)"
        case let .branchActivationFailed(pathIndex):
            "branch activation failed | reason=no scope | pathIndex=\(String(describing: pathIndex))"
        case let .branchActivationRejected(previousBranch, branch, scope):
            "branch activation rejected | from=\(previousBranch.departureDebugDescription) | to=\(branch.departureDebugDescription) | scope=\(scope.departureDebugDescription)"
        case let .branchActivationSkipped(branch, scope):
            "branch activation skipped | branch=\(branch.departureDebugDescription) | reason=already active | scope=\(scope.departureDebugDescription)"
        case let .branchRegistered(branch, parent, scope):
            "branch registered | branch=\(branch.departureDebugDescription) | parent=\(parent.departureDebugDescription) | scope=\(scope.departureDebugDescription)"
        case let .branchUnregistered(branch, scope):
            "branch unregistered | branch=\(branch.departureDebugDescription) | scope=\(scope.departureDebugDescription)"
        case let .branchUnregisterSkipped(branch, scope):
            "branch unregister skipped | branch=\(branch.departureDebugDescription) | reason=scope mismatch | scope=\(scope.departureDebugDescription)"
        case let .highPriorityReplacePreparing(route, match):
            "high-priority replace preparing | route=\(route.departureDebugDescription) | \(match.departureDebugDescription)"
        case .highContextCleared:
            "high-priority context cleared"
        case let .highContextStarted(pathIndex):
            "high-priority context started | pathIndex=\(pathIndex)"
        case let .hookDeclarationsUninstalled(scope):
            "hook declarations uninstalled | scope=\(scope.departureDebugDescription)"
        case let .hookDeclarationsInstalled(scope, hookCount):
            "hook declarations installed | scope=\(scope.departureDebugDescription) | hooks=\(hookCount)"
        case let .pathCleared(removedCount):
            "path cleared | removed=\(removedCount)"
        case let .pathRemovalRequested(pathIndex, scope):
            "path removal requested | pathIndex=\(pathIndex) | scope=\(scope.departureDebugDescription)"
        case let .pathRemovalSkipped(scope):
            "path removal skipped | reason=scope not in path | scope=\(scope.departureDebugDescription)"
        case let .pathTrimmed(keepThrough, removedCount):
            "path trimmed | keepThrough=\(keepThrough) | removed=\(removedCount)"
        case let .pathUnchanged(keepThrough):
            "path unchanged | keepThrough=\(keepThrough)"
        case let .pendingResumeCheck(branch, declaringScope):
            "pending resume check | branch=\(branch.departureDebugDescription) | declaringScope=\(declaringScope.departureDebugDescription)"
        case .pendingResumeSkipped:
            "pending resume skipped | reason=no matching pending route"
        case let .pendingRouteResuming(route):
            "pending route resuming | route=\(route.departureDebugDescription)"
        case let .routeAcceptedAppend(route):
            "route accepted | action=append | route=\(route.departureDebugDescription)"
        case let .routeAcceptedReplaceHighPriority(route):
            "route accepted | action=replace high-priority context | route=\(route.departureDebugDescription)"
        case let .routeAppendSuperseded(route):
            "route append dropped | reason=superseded while waiting for replaced scopes | route=\(route.departureDebugDescription)"
        case let .routeAppendPreparing(route, match):
            "route append preparing | route=\(route.departureDebugDescription) | \(match.departureDebugDescription)"
        case let .routeAppendWaitingReplacingScopes(removedScopes):
            "route append waiting | reason=replacing scopes | removedScopes=\(removedScopes)"
        case let .routeAppended(route, pathCount):
            "route appended | route=\(route.departureDebugDescription) | pathCount=\(pathCount)"
        case let .routeBlockedByHighContext(route):
            "route blocked | route=\(route.departureDebugDescription) | reason=normal priority before active high-priority context"
        case let .routeCanPresentActiveLocalScope(branch):
            "route can present | branch=\(branch.departureDebugDescription) | reason=active local scope"
        case .routeCanPresentDeclarationDrivesPresentation:
            "route can present | reason=declaration drives presentation"
        case let .routeCannotPresentDiscoveryBranchInactive(branch):
            "route cannot present | branch=\(branch.departureDebugDescription) | reason=discovery branch inactive"
        case let .routeCannotPresentNoActiveLocalScope(branch):
            "route cannot present | branch=\(branch.departureDebugDescription) | reason=no active local scope"
        case let .routeDroppedBranchActivationFailed(branch):
            "route dropped | reason=branch activation failed | branch=\(branch.departureDebugDescription)"
        case let .routeDroppedNoDeclaration(routeType):
            "route dropped | reason=no declaration | type=\(String(reflecting: routeType))"
        case .routeDroppedResolution:
            "route dropped | reason=resolution"
        case let .routeMatched(route, match, highContextStart):
            "route matched | route=\(route.departureDebugDescription) | \(match.departureDebugDescription) | highContextStart=\(String(describing: highContextStart))"
        case let .routePendingWaitingForActivatedBranchHost(route, branch):
            "route pending | route=\(route.departureDebugDescription) | branch=\(branch.departureDebugDescription) | reason=waiting for activated branch host"
        case let .routePendingWaitingForLocalPresentationScope(route, branch):
            "route pending | route=\(route.departureDebugDescription) | branch=\(branch.departureDebugDescription) | reason=waiting for local presentation scope"
        case let .routeRequested(route):
            "route requested | route=\(route.departureDebugDescription)"
        case let .routeRerouted(route, newRoute):
            "route rerouted | from=\(route.departureDebugDescription) | to=\(newRoute.departureDebugDescription)"
        case let .routeDeclarationsUninstalled(scope):
            "route declarations uninstalled | scope=\(scope.departureDebugDescription)"
        case let .routeDeclarationsInstalled(scope, declarationCount):
            "route declarations installed | scope=\(scope.departureDebugDescription) | declarations=\(declarationCount)\(scope.branchDebugDescription.map { ", branches: \($0)" } ?? "")"
        case let .scopeInstalledInView(scope):
            "scope installed in view | scope=\(scope.departureDebugDescription)"
        case let .scopeUninstalledFromView(scope):
            "scope uninstalled from view | scope=\(scope.departureDebugDescription)"
        case let .viewExitWaitProgress(remaining):
            "view exit wait progress | remaining=\(remaining)"
        case .viewExitWaitSkipped:
            "view exit wait skipped | reason=no installed scopes"
        case let .viewExitWaitStarted(installed):
            "view exit wait started | installed=\(installed)"
        case let .unwindAccepted(keepThrough, removing):
            "unwind accepted | keepThrough=\(String(describing: keepThrough)) | removing=\(removing)"
        case let .unwindAcceptedAncestorTarget(keepThrough, removing):
            "unwind accepted | reason=ancestor target | keepThrough=\(String(describing: keepThrough)) | removing=\(removing)"
        case .unwindCompleted:
            "unwind completed | removed scopes left view"
        case let .unwindDroppedTargetNotFound(target):
            "unwind dropped | reason=target not found | target=\(String(describing: target))"
        case let .unwindRequested(target):
            "unwind requested | target=\(String(describing: target))"
        case .unwindSkippedNoRoute:
            "unwind skipped | reason=no route"
        case .unwindSkippedNotInsideBranch:
            "unwind skipped | reason=not inside a branch"
        }
    }
}

extension Router.DeclarationMatch {
    var departureDebugDescription: String {
        let placementDescription = branchID.map {
            "branch=\($0.departureDebugDescription)"
        } ?? "scope"

        return "match=declaration | pathIndex=\(String(describing: pathIndex)) | declaringPathIndex=\(String(describing: declaringPathIndex)) | \(placementDescription) | declaration=\(declaration.departureDebugDescription)"
    }
}
#endif
