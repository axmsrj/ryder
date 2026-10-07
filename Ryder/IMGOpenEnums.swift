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

enum IMGOpenError: LocalizedError {
    case fileTooSmall
    case invalidFileExtension
    case invalidV2Header
    case invalidEntryTable
    case entryOutsideArchive
    case incompleteEntryData
    case invalidTXDFileExtension

    var errorDescription: String? {
        switch self {
        case .fileTooSmall:
            "The IMG file is too small to contain a valid header."
        case .invalidFileExtension:
            "The selected file is not an IMG archive."
        case .invalidV2Header:
            "The IMG V2 header is incomplete."
        case .invalidEntryTable:
            "The IMG V2 entry table is invalid."
        case .entryOutsideArchive:
            "The selected entry points outside the IMG archive."
        case .incompleteEntryData:
            "The selected entry could not be read completely."
        case .invalidTXDFileExtension:
            "The selected file is not a TXD texture dictionary."
        }
    }
}
