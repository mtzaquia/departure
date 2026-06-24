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

import Departure
import SwiftUI

struct LandingView: View {
    enum TabItem: nonisolated Hashable {
        case home
        case settings
    }

    @State private var tab: TabItem = .home

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                HomeView()
                    .routeBranch(TabItem.home)
            }
            .tabItem {
                Label("Home", systemImage: "house")
                    .accessibilityIdentifier(SampleAppAccessibility.homeTab)
            }
            .tag(TabItem.home)

            NavigationStack {
                SettingsView()
                    .routeBranch(TabItem.settings)
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
                    .accessibilityIdentifier(SampleAppAccessibility.settingsTab)
            }
            .tag(TabItem.settings)
        }
        .accessibilityIdentifier(SampleAppAccessibility.landing)
        .routes(branch: $tab) {
            Cover(LoginRoute.self, priority: .high)
            Cover(LoginReplacementRoute.self, priority: .high)
            Cover(AlertRoute.self, priority: .high, transition: .fade, providesNavigation: false)
            Cover(CriticalRoute.self, priority: .critical, transition: .fade, providesNavigation: false)
            Cover(CriticalReplacementRoute.self, priority: .critical, transition: .fade, providesNavigation: false)
            Sheet(HighPriorityPassthroughSheetRoute.self, priority: .high, providesNavigation: false)
            Sheet(TopLevelSheetRoute.self, providesNavigation: false)
            Cover(TopLevelCoverRoute.self, providesNavigation: false)
            Cover(TopLevelReplacementCoverRoute.self, providesNavigation: false)

            Branch(.home) {
                Sheet(ProfileRoute.self)
                Sheet(DismissProbeRoute.self, providesNavigation: false)
                Cover(MessageRoute.self, transition: .fade, providesNavigation: false)
            }

            Branch(.settings) {
                Push(AppearanceSettingsRoute.self)
                Push(AuthenticationSettingsRoute.self)
            }
        }
        .hooks {
            UnwindHandler(AuthenticationSettingsRoute.self) {
                guard SampleAppUITesting.isEnabled else {
                    return
                }

                Storage.shared.landingContainerUnwindHookCount += 1
            }
        }
        .environment(\.samplePresentationSource, "top-level branched scope")
    }
}
