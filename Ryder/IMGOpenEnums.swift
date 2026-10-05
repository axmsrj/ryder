//
//  IMGResult.swift
//  Ryder
//
//  Created by Alex Marcelle on 04/10/26.
//

import Foundation

enum IMGOpenResult {
    case version2(IMGArchive)
    case version1(dirURL: URL)
    case needsDIR
}

enum IMGOpenError: Error {
    case fileTooSmall
    case invalidFileExtension
    case invalidV2Header
    case invalidEntryTable
}
