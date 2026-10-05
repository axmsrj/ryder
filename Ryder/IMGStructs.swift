//
//  IMGStructs.swift
//  Ryder
//
//  Created by Alex Marcelle on 04/10/26.
//

struct IMGEntry: Identifiable {
    let id: Int
    let name: String
    let sectorOffset: UInt32
    let sectorCount: UInt16
    let reserved: UInt16
}

struct IMGArchive {
    let entries: [IMGEntry]
}
