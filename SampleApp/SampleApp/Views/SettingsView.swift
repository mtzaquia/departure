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

struct SettingsView: View {
    @Environment(Router.self) private var router

    var body: some View {
        List {
            Button("Appearance") {
                Task {
                    await router.present(AppearanceSettingsRoute())
                }
            }

            Button("Authentication") {
                Task {
                    await router.present(AuthenticationSettingsRoute())
                }
            }

            Button("Profile") {
                Task {
                    await router.present(ProfileRoute())
                }
            }

            Section("Actions") {
                Button("Save appearance") {
                    Task {
                        await router.perform(SaveAppearanceSettingsAction())
                    }
                }

                Button("New emoji") {
                    Task {
                        await router.perform(RandomizeEmojiAction())
                    }
                }
            }
        }
        .navigationTitle("Settings")
    }
}
