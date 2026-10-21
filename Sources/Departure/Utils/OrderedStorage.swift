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

struct OrderedStorage<Key: Hashable, Value> {
    private var orderedKeys: [Key] = []
    private var valuesByKey: [Key: Value] = [:]

    var keys: [Key] {
        orderedKeys
    }

    var values: [Value] {
        orderedKeys.compactMap { valuesByKey[$0] }
    }

    subscript(key: Key) -> Value? {
        get {
            valuesByKey[key]
        }

        set {
            if let newValue {
                if valuesByKey[key] == nil {
                    orderedKeys.append(key)
                }

                valuesByKey[key] = newValue
            } else {
                valuesByKey[key] = nil
                orderedKeys.removeAll { $0 == key }
            }
        }
    }

    mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
        orderedKeys.removeAll(keepingCapacity: keepCapacity)
        valuesByKey.removeAll(keepingCapacity: keepCapacity)
    }
}
