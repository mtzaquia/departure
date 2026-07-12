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

import SwiftUI

enum LabPalette {
    static let indigo = Color(red: 0.28, green: 0.25, blue: 0.78)
    static let blue = Color(red: 0.10, green: 0.49, blue: 0.86)
    static let mint = Color(red: 0.08, green: 0.65, blue: 0.55)
    static let coral = Color(red: 0.93, green: 0.35, blue: 0.39)
    static let amber = Color(red: 0.93, green: 0.59, blue: 0.12)
}

struct LabBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(uiColor: .systemBackground),
                LabPalette.indigo.opacity(0.08),
                LabPalette.blue.opacity(0.05)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct LabScreen<Content: View>: View {
    let title: String
    let eyebrow: String
    let symbol: String
    @ViewBuilder let content: Content

    init(
        _ title: String,
        eyebrow: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.eyebrow = eyebrow
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        ZStack {
            LabBackground()

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(LabPalette.indigo.gradient, in: RoundedRectangle(cornerRadius: 13))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(eyebrow.uppercased())
                            .font(.caption2.weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(LabPalette.indigo)
                        Text(title)
                            .font(.title2.weight(.bold))
                    }

                    Spacer(minLength: 0)
                }

                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
    }
}

struct LabPanel<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let title {
                Text(title.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.6), lineWidth: 1)
        }
    }
}

struct LabStatus: View {
    let label: String
    let value: String
    var color: Color = LabPalette.mint
    var symbol: String = "circle.fill"

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(height: 42)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
        .accessibilityElement(children: .combine)
    }
}

struct LabAction: View {
    let title: String
    let symbol: String
    var color: Color = LabPalette.indigo
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.caption.weight(.bold))
                    .frame(width: 22, height: 22)
                    .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 7))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(role == .destructive ? LabPalette.coral : .primary)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.14), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

struct LabModalCard<Content: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    var color: Color = LabPalette.indigo
    @ViewBuilder let content: Content

    init(
        _ title: String,
        subtitle: String,
        symbol: String,
        color: Color = LabPalette.indigo,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.color = color
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: color.opacity(0.25), radius: 12, y: 6)

            VStack(spacing: 4) {
                Text(title)
                    .font(.title3.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            content
        }
        .frame(maxWidth: 420)
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.7), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 30, y: 14)
        .padding(18)
    }
}

extension View {
    func labPrimaryButton(color: Color = LabPalette.indigo) -> some View {
        buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .tint(color)
    }
}
