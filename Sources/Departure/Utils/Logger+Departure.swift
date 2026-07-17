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

import Foundation
import os

/// Global Departure configuration.
public enum Departure {
    /// The amount of diagnostic detail emitted by Departure in debug builds.
    public enum DebugLogLevel: Sendable {
        /// Disables Departure engine logs.
        case off
        /// Shows requests, routing decisions, outcomes, and resulting route paths.
        case normal
        /// Includes declaration, lifecycle, and waiting details in addition to normal logs.
        case trace
    }

    private nonisolated static let debugLock = OSAllocatedUnfairLock(initialState: DebugLogLevel.off)

    /// Controls the amount of Departure engine logging emitted in debug builds.
    ///
    /// ```swift
    /// Departure.debug = .trace
    /// ```
    public nonisolated static var debug: DebugLogLevel {
        get { debugLock.withLock { $0 } }
        set { debugLock.withLock { $0 = newValue } }
    }
}

nonisolated let log = Logger(subsystem: "eu.lelfe.departure", category: "Departure")

enum DepartureLogTrace {
    @TaskLocal static var id: String?

    static func nextID(prefix: String) -> String {
        "\(prefix):\(UUID().uuidString.prefix(8))"
    }
}

enum DepartureLogEvent {
    case actionCompleted(action: any Action)
    case actionDirectInvocationEnded(action: any Action, error: any Error)
    case actionFailed(action: any Action, error: any Error)
    case actionIntercepted(action: any Action, scope: RouteScope)
    case actionInterceptorFinished(action: any Action)
    case actionNoInterceptor(action: any Action, scope: RouteScope, currentRoute: (any Route.Type)?)
    case actionRequested(action: any Action)
    case actionRerouteDropped(action: any Action)
    case actionRerouteRequested(action: any Action, route: any Route)
    case actionRunning(action: any Action, currentRoute: (any Route.Type)?)
    case branchActivated(from: AnyHashable, to: AnyHashable, scope: RouteScope)
    case branchActivationFailed(position: RoutePath.Position)
    case branchActivationRejected(from: AnyHashable, to: AnyHashable, scope: RouteScope)
    case branchActivationSkipped(branch: AnyHashable, scope: RouteScope)
    case branchRegistered(branch: AnyHashable, parent: RouteScope, scope: RouteScope)
    case branchUnregistered(branch: AnyHashable, scope: RouteScope)
    case branchUnregisterSkipped(branch: AnyHashable, scope: RouteScope)
    case elevatedPriorityReplacePreparing(route: any Route)
    case elevatedTreeCleared
    case elevatedTreeStarted
    case hookDeclarationsUninstalled(scope: RouteScope)
    case hookDeclarationsInstalled(scope: RouteScope, hookCount: Int)
    case pathCleared(removedCount: Int)
    case pathRemovalRequested(scope: RouteScope)
    case pathRemovalSkipped(scope: RouteScope)
    case pathTrimmed(keepThrough: RoutePath.Position, removedCount: Int)
    case pathUnchanged(keepThrough: RoutePath.Position)
    case pendingRouteResuming(route: any Route)
    case ios17PushDismissalDeferred(scope: RouteScope)
    case ios17PushDismissalDropped(scope: RouteScope)
    case ios17PushDismissalResumed(scope: RouteScope)
    case routeAcceptedAppend(route: any Route)
    case routeAcceptedReplaceElevatedPriority(route: any Route)
    case routeAppendSuperseded(route: any Route)
    case routeAppendPreparing(route: any Route, match: Router.DeclarationMatch)
    case routeAppendWaitingReplacingScopes(removedScopes: Int)
    case routeAppended(route: any Route, path: String)
    case routeBlockedByElevatedPriority(route: any Route)
    case routeCanPresentActiveLocalScope(branch: AnyHashable)
    case routeCanPresentDeclarationDrivesPresentation
    case routeCannotPresentDiscoveryBranchInactive(branch: AnyHashable)
    case routeCannotPresentNoActiveLocalScope(branch: AnyHashable)
    case routeDroppedBranchActivationFailed(branch: AnyHashable)
    case routeDroppedNoDeclaration(routeType: any Route.Type)
    case routeDroppedResolution
    case routeNoOpEquivalent(route: any Route, currentRoute: any Route)
    case routeMatched(route: any Route, match: Router.DeclarationMatch)
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
    case ios17ViewExitWaitTimedOut(scope: RouteScope)
    case unwindAccepted(keepThrough: RoutePath.Position, removing: Int)
    case unwindAcceptedAncestorTarget(keepThrough: RoutePath.Position, removing: Int)
    case unwindCompleted(path: String)
    case unwindDroppedTargetNotFound(target: Router.UnwindTarget?)
    case unwindPreviousRequested
    case unwindRequested(target: Router.UnwindTarget?)
    case unwindSkippedNoRoute
    case unwindSkippedNotInsideBranch
}

extension Logger {
    func departureDebug(_ event: @autoclosure () -> DepartureLogEvent) {
#if DEBUG
        let logLevel = Departure.debug
        if case .off = logLevel {
            return
        }

        let event = event()
        guard logLevel.includes(event.logLevel) else { return }

        let message = event.renderedMessage
        debug("\(message, privacy: .public)")
#endif
    }

    func departureWarning(_ message: @autoclosure () -> String) {
        let message = message()
        warning("\(message, privacy: .public)")
    }
}

private extension Departure.DebugLogLevel {
    func includes(_ eventLevel: Departure.DebugLogLevel) -> Bool {
        switch (self, eventLevel) {
        case (.trace, _), (.normal, .normal), (.off, .off):
            true
        default:
            false
        }
    }
}

#if DEBUG
extension DepartureLogEvent {
    var logLevel: Departure.DebugLogLevel {
        switch self {
        case .actionRunning,
             .actionNoInterceptor,
             .branchRegistered,
             .branchUnregistered,
             .branchUnregisterSkipped,
             .hookDeclarationsUninstalled,
             .hookDeclarationsInstalled,
             .pathCleared,
             .pathRemovalRequested,
             .pathRemovalSkipped,
             .pathTrimmed,
             .pathUnchanged,
             .ios17PushDismissalDeferred,
             .ios17PushDismissalDropped,
             .ios17PushDismissalResumed,
             .routeAppendPreparing,
             .routeAppendWaitingReplacingScopes,
             .routeCanPresentActiveLocalScope,
             .routeCanPresentDeclarationDrivesPresentation,
             .routeCannotPresentDiscoveryBranchInactive,
             .routeCannotPresentNoActiveLocalScope,
             .routeDeclarationsUninstalled,
             .routeDeclarationsInstalled,
             .scopeInstalledInView,
             .scopeUninstalledFromView,
             .viewExitWaitProgress,
             .viewExitWaitSkipped,
             .viewExitWaitStarted,
             .ios17ViewExitWaitTimedOut:
            .trace

        default:
            .normal
        }
    }

    var renderedMessage: String {
        let trace = DepartureLogTrace.id.map { "[\($0)]" } ?? ""
        return "[\(category)]\(trace) \(marker) \(message)"
    }

    private var category: String {
        switch self {
        case .actionCompleted,
             .actionDirectInvocationEnded,
             .actionFailed,
             .actionIntercepted,
             .actionInterceptorFinished,
             .actionNoInterceptor,
             .actionRequested,
             .actionRerouteDropped,
             .actionRerouteRequested,
             .actionRunning:
            "action"

        case .branchActivated,
             .branchActivationFailed,
             .branchActivationRejected,
             .branchActivationSkipped,
             .branchRegistered,
             .branchUnregistered,
             .branchUnregisterSkipped:
            "branch"

        case .pathCleared,
             .pathRemovalRequested,
             .pathRemovalSkipped,
             .pathTrimmed,
             .pathUnchanged:
            "path"

        case .unwindAccepted,
             .unwindAcceptedAncestorTarget,
             .unwindCompleted,
             .unwindDroppedTargetNotFound,
             .unwindPreviousRequested,
             .unwindRequested,
             .unwindSkippedNoRoute,
             .unwindSkippedNotInsideBranch,
             .ios17PushDismissalDeferred,
             .ios17PushDismissalDropped,
             .ios17PushDismissalResumed:
            "unwind"

        case .hookDeclarationsUninstalled,
             .hookDeclarationsInstalled,
             .routeDeclarationsUninstalled,
             .routeDeclarationsInstalled,
             .scopeInstalledInView,
             .scopeUninstalledFromView:
            "scope"

        default:
            "route"
        }
    }

    private var marker: String {
        switch self {
        case .actionRequested, .routeRequested, .unwindPreviousRequested, .unwindRequested:
            "⇢"

        case .actionCompleted,
             .actionInterceptorFinished,
             .branchActivated,
             .elevatedTreeStarted,
             .pendingRouteResuming,
             .routeAcceptedAppend,
             .routeAcceptedReplaceElevatedPriority,
             .routeAppended,
             .unwindCompleted:
            "✓"

        case .actionRerouteRequested, .routeRerouted:
            "↪"

        case .routeAppendWaitingReplacingScopes,
             .routePendingWaitingForActivatedBranchHost,
             .routePendingWaitingForLocalPresentationScope,
             .viewExitWaitProgress,
             .viewExitWaitStarted,
             .ios17PushDismissalDeferred:
            "⏳"

        case .actionDirectInvocationEnded,
             .actionFailed,
             .actionRerouteDropped,
             .branchActivationFailed,
             .branchActivationRejected,
             .branchActivationSkipped,
             .branchUnregisterSkipped,
             .pathRemovalSkipped,
             .routeAppendSuperseded,
             .routeBlockedByElevatedPriority,
             .routeDroppedBranchActivationFailed,
             .routeDroppedNoDeclaration,
             .routeDroppedResolution,
             .routeNoOpEquivalent,
             .ios17PushDismissalDropped,
             .unwindDroppedTargetNotFound,
             .unwindSkippedNoRoute,
             .unwindSkippedNotInsideBranch,
             .ios17ViewExitWaitTimedOut:
            "⊘"

        default:
            "•"
        }
    }

    var message: String {
        switch self {
        case let .actionCompleted(action):
            "completed \(action.departureDebugDescription)"
        case let .actionDirectInvocationEnded(action, error):
            "ended without delivery \(action.departureDebugDescription) — \(String(describing: error))"
        case let .actionFailed(action, error):
            "failed \(action.departureDebugDescription) — \(String(describing: error))"
        case let .actionIntercepted(action, scope):
            "intercepted \(action.departureDebugDescription) in \(scope.departureDebugDescription)"
        case let .actionInterceptorFinished(action):
            "interceptor finished \(action.departureDebugDescription)"
        case let .actionNoInterceptor(action, scope, currentRoute):
            "no interceptor in \(scope.departureDebugDescription) — running \(action.departureDebugDescription) from \(currentRoute.map { String(reflecting: $0) } ?? "root")"
        case let .actionRequested(action):
            "requested \(action.departureDebugDescription)"
        case let .actionRerouteDropped(action):
            "reroute dropped — \(action.departureDebugDescription) already rerouted once"
        case let .actionRerouteRequested(action, route):
            "\(action.departureDebugDescription) rerouted to \(route.departureDebugDescription)"
        case let .actionRunning(action, currentRoute):
            "running \(action.departureDebugDescription) from \(currentRoute.map { String(reflecting: $0) } ?? "root")"
        case let .branchActivated(previousBranch, branch, scope):
            "switched from \(previousBranch.departureDebugDescription) to \(branch.departureDebugDescription) in \(scope.departureDebugDescription)"
        case let .branchActivationFailed(position):
            "could not activate branch — no scope at \(position)"
        case let .branchActivationRejected(previousBranch, branch, scope):
            "kept \(previousBranch.departureDebugDescription); \(branch.departureDebugDescription) was rejected by \(scope.departureDebugDescription)"
        case let .branchActivationSkipped(branch, scope):
            "kept \(branch.departureDebugDescription) active in \(scope.departureDebugDescription)"
        case let .branchRegistered(branch, parent, scope):
            "branch registered | branch=\(branch.departureDebugDescription) | parent=\(parent.departureDebugDescription) | scope=\(scope.departureDebugDescription)"
        case let .branchUnregistered(branch, scope):
            "branch unregistered | branch=\(branch.departureDebugDescription) | scope=\(scope.departureDebugDescription)"
        case let .branchUnregisterSkipped(branch, scope):
            "branch unregister skipped | branch=\(branch.departureDebugDescription) | reason=scope mismatch | scope=\(scope.departureDebugDescription)"
        case let .elevatedPriorityReplacePreparing(route):
            "preparing elevated-priority presentation for \(route.departureDebugDescription)"
        case .elevatedTreeCleared:
            "cleared elevated-priority route tree"
        case .elevatedTreeStarted:
            "started elevated-priority route tree"
        case let .hookDeclarationsUninstalled(scope):
            "hook declarations uninstalled | scope=\(scope.departureDebugDescription)"
        case let .hookDeclarationsInstalled(scope, hookCount):
            "hook declarations installed | scope=\(scope.departureDebugDescription) | hooks=\(hookCount)"
        case let .pathCleared(removedCount):
            "path cleared | removed=\(removedCount)"
        case let .pathRemovalRequested(scope):
            "path removal requested | scope=\(scope.departureDebugDescription)"
        case let .pathRemovalSkipped(scope):
            "path removal skipped | reason=scope not in path | scope=\(scope.departureDebugDescription)"
        case let .pathTrimmed(keepThrough, removedCount):
            "path trimmed | keepThrough=\(keepThrough) | removed=\(removedCount)"
        case let .pathUnchanged(keepThrough):
            "path unchanged | keepThrough=\(keepThrough)"
        case let .pendingRouteResuming(route):
            "resuming pending \(route.departureDebugDescription)"
        case let .ios17PushDismissalDeferred(scope):
            "iOS 17 push dismissal deferred until view exit | scope=\(scope.departureDebugDescription)"
        case let .ios17PushDismissalDropped(scope):
            "iOS 17 push dismissal write-back dropped | reason=pending plan invalidated | scope=\(scope.departureDebugDescription)"
        case let .ios17PushDismissalResumed(scope):
            "iOS 17 push dismissal resumed after view exit | scope=\(scope.departureDebugDescription)"
        case let .routeAcceptedAppend(route):
            "will append \(route.departureDebugDescription)"
        case let .routeAcceptedReplaceElevatedPriority(route):
            "will replace the elevated-priority tree with \(route.departureDebugDescription)"
        case let .routeAppendSuperseded(route):
            "dropped \(route.departureDebugDescription) — superseded while waiting for replaced scopes"
        case let .routeAppendPreparing(route, _):
            "preparing append for \(route.departureDebugDescription)"
        case let .routeAppendWaitingReplacingScopes(removedScopes):
            "route append waiting | reason=replacing scopes | removedScopes=\(removedScopes)"
        case let .routeAppended(route, path):
            "presented \(route.departureDebugDescription)\n  path: \(path)"
        case let .routeBlockedByElevatedPriority(route):
            "blocked \(route.departureDebugDescription) — a higher-priority route is active or pending"
        case let .routeCanPresentActiveLocalScope(branch):
            "route can present | branch=\(branch.departureDebugDescription) | reason=active local scope"
        case .routeCanPresentDeclarationDrivesPresentation:
            "route can present | reason=declaration drives presentation"
        case let .routeCannotPresentDiscoveryBranchInactive(branch):
            "route cannot present | branch=\(branch.departureDebugDescription) | reason=discovery branch inactive"
        case let .routeCannotPresentNoActiveLocalScope(branch):
            "route cannot present | branch=\(branch.departureDebugDescription) | reason=no active local scope"
        case let .routeDroppedBranchActivationFailed(branch):
            "dropped route — could not activate branch \(branch.departureDebugDescription)"
        case let .routeDroppedNoDeclaration(routeType):
            "dropped \(String(reflecting: routeType)) — no declaration found"
        case .routeDroppedResolution:
            "dropped by route resolution"
        case let .routeNoOpEquivalent(route, currentRoute):
            "kept \(currentRoute.departureDebugDescription) — already equivalent to \(route.departureDebugDescription)"
        case let .routeMatched(route, match):
            "matched \(route.departureDebugDescription) — \(match.departureDebugDescription)"
        case let .routePendingWaitingForActivatedBranchHost(route, branch):
            "waiting to present \(route.departureDebugDescription) until branch \(branch.departureDebugDescription) mounts"
        case let .routePendingWaitingForLocalPresentationScope(route, branch):
            "waiting to present \(route.departureDebugDescription) for a local scope in branch \(branch.departureDebugDescription)"
        case let .routeRequested(route):
            "requested \(route.departureDebugDescription)"
        case let .routeRerouted(route, newRoute):
            "\(route.departureDebugDescription) rerouted to \(newRoute.departureDebugDescription)"
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
        case let .ios17ViewExitWaitTimedOut(scope):
            "iOS 17 view exit wait timed out — forcing reconciliation | scope=\(scope.departureDebugDescription)"
        case let .unwindAccepted(keepThrough, removing):
            "removing \(removing) route scope\(removing == 1 ? "" : "s") through \(String(describing: keepThrough))"
        case let .unwindAcceptedAncestorTarget(keepThrough, removing):
            "removing \(removing) route scope\(removing == 1 ? "" : "s") to ancestor target \(String(describing: keepThrough))"
        case let .unwindCompleted(path):
            "completed\n  path: \(path)"
        case let .unwindDroppedTargetNotFound(target):
            "could not find unwind target \(String(describing: target))"
        case .unwindPreviousRequested:
            "requested to previous route (scope-anchored)"
        case let .unwindRequested(target):
            "requested to \(target.map { String(describing: $0) } ?? "previous route")"
        case .unwindSkippedNoRoute:
            "skipped — no route to remove"
        case .unwindSkippedNotInsideBranch:
            "skipped — not inside a branch"
        }
    }
}

extension Router.DeclarationMatch {
    var departureDebugDescription: String {
        let placementDescription = branchID.map {
            "branch \($0.departureDebugDescription)"
        } ?? "local scope"

        let description = "\(declaration.departureDebugDescription) • \(placementDescription)"
        guard presentationLocation.path !== declarationLocation.path
            || presentationLocation.position != declarationLocation.position
        else {
            return description
        }

        return "\(description) • declared at \(declarationLocation.position) • presents at \(presentationLocation.position)"
    }
}
#endif
