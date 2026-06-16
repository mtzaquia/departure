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

struct AppearanceSettingsView: View {
    @State private var colorScheme: ColorScheme = .light
    @State private var storage = Storage.shared

    @Environment(\.colorScheme) private var effectiveColorScheme
    @Environment(Router.self) private var router

    var body: some View {
        List {
            Section {
                Picker("Color scheme", selection: $colorScheme) {
                    Text("Light")
                        .tag(ColorScheme.light)
                    Text("Dark")
                        .tag(ColorScheme.dark)
                }
            }

            Section {
                Button("Re-present this") {
                    Task {
                        await router.present(AppearanceSettingsRoute())
                    }
                }

                Button("Present authentication settings") {
                    Task {
                        await router.present(AuthenticationSettingsRoute())
                    }
                }
            }

            Section("Actions") {
                Button("Save appearance") {
                    Task {
                        await router.perform(SaveAppearanceSettingsAction())
                    }
                }

                Text("Saved \(storage.appearanceSaveCount) time(s)")
            }
        }
        .navigationTitle("Appearance")
        .hooks {
            ActionInterceptor(SaveAppearanceSettingsAction.self) { invocation in
                try? await invocation()
            }
        }
        .task {
            colorScheme = effectiveColorScheme
        }
    }
}
