//
//  FileHandler.swift
//  Ryder
//
//  Created by Alex Marcelle on 04/10/26.
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

final class IMGFileHandler: ObservableObject {
    func handleSelectFile(_ url: URL) throws -> IMGOpenResult {
        guard url.pathExtension.lowercased() == "img" else {
            throw IMGOpenError.invalidFileExtension
        }
        
        let hasAccess = url.startAccessingSecurityScopedResource()
        
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        print("Now opening: ", url.path)
        
        return try open(url)
    }
    
    func open(_ url: URL) throws -> IMGOpenResult {
        let file = try FileHandle(forReadingFrom: url)
            
        defer {
            try? file.close()
        }
            
        try file.seek(toOffset: 0)
            
        guard let data = try file.read(upToCount: 4), data.count == 4 else {
            throw IMGOpenError.fileTooSmall
        }

        let version2Signature = Data([0x56, 0x45, 0x52, 0x32])
            
        if data == version2Signature {
            let archive = try openAsV2(file)
            return .version2(archive)
        }
        
        let dirURL = url.deletingPathExtension()
            .appendingPathExtension("dir")
        
        if(FileManager.default.fileExists(atPath: dirURL.path)) {
            return .version1(dirURL: dirURL)
        }
        return .needsDIR
    }
    
    func openAsV2(_ file: FileHandle) throws -> IMGArchive {
        try file.seek(toOffset: 4)
        
        guard let countData = try file.read(upToCount: 4), countData.count == 4 else {
            throw IMGOpenError.invalidV2Header
        }
        
        let bytes = Array(countData)
        
        let entryCount =
        UInt32(bytes[0]) |
        UInt32(bytes[1]) << 8 |
        UInt32(bytes[2]) << 16 |
        UInt32(bytes[3]) << 24
        
        let fileSize = try file.seekToEnd()
        let tableSize = UInt64(entryCount) * 32
        
        guard tableSize <= fileSize - 8 else {
            throw IMGOpenError.invalidEntryTable
        }
        
        try file.seek(toOffset: 8)
        
        var entries: [IMGEntry] = []
        entries.reserveCapacity(Int(entryCount))
        
        for index in 0..<Int(entryCount) {
            guard let entryData = try file.read(upToCount: 32), entryData.count == 32 else {
                throw IMGOpenError.invalidEntryTable
            }
            
            let bytes = Array(entryData)
            
            let sectorOffset =
            UInt32(bytes[0]) |
            UInt32(bytes[1]) << 8 |
            UInt32(bytes[2]) << 16 |
            UInt32(bytes[3]) << 24
            
            let sectorCount =
            UInt16(bytes[4]) |
            UInt16(bytes[5]) << 8
            
            let reserved =
            UInt16(bytes[6]) |
            UInt16(bytes[7]) << 8
            
            let rawName = bytes[8..<32]
            let rawNameFirstIndex = rawName.firstIndex(of: 0)
            let nameBytes: ArraySlice<UInt8>
            
            if let rawNameFirstIndex {
                nameBytes = rawName[..<rawNameFirstIndex]
            }
            else {
                nameBytes = rawName[...]
            }
            
            let name = String(decoding: nameBytes, as: UTF8.self)
            
            let entry = IMGEntry(
                id: index,
                name: name,
                sectorOffset: sectorOffset,
                sectorCount: sectorCount,
                reserved: reserved
            )
            
            entries.append(entry)
        }
        
        return IMGArchive(entries: entries)
    }
}
