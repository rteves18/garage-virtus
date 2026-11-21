import Foundation
import Testing
@testable import GarageVirtusKit

@Test func rememberedFolderIsRestored() throws {
    let space = try TempSpace()
    let folder = try space.makeFolder("catalogue")
    try space.makeAccess().remember(folder)
    let restored = space.makeAccess().restore()
    #expect(restored?.comparablePath == folder.comparablePath)
}

@Test func restoreWithNothingSavedReturnsNil() throws {
    let space = try TempSpace()
    #expect(space.makeAccess().restore() == nil)
}

@Test func restoreReturnsNilAndForgetsWhenFolderIsGone() throws {
    let space = try TempSpace()
    let folder = try space.makeFolder("catalogue")
    try space.makeAccess().remember(folder)
    try FileManager.default.removeItem(at: folder)
    #expect(space.makeAccess().restore() == nil)
    #expect(space.defaults.data(forKey: "catalogueBookmark") == nil)
}

@Test func savingReplacesPreviousFolder() throws {
    let space = try TempSpace()
    let folderA = try space.makeFolder("a")
    let folderB = try space.makeFolder("b")
    let access = space.makeAccess()
    try access.remember(folderA)
    try access.remember(folderB)
    #expect(access.currentFolder?.comparablePath == folderB.comparablePath)
    #expect(space.makeAccess().restore()?.comparablePath == folderB.comparablePath)
}
