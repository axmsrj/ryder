//
//  FocusedValues.swift
//  Ryder
//
//  Created by Alex Marcelle on 04/10/26.
//

import SwiftUI

struct OpenIMGActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var openIMG: (() -> Void)? {
        get { self[OpenIMGActionKey.self] }
        set { self[OpenIMGActionKey.self] = newValue }
    }
}
