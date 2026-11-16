import Foundation

public enum HostPaths {
    public static var supportDir: String {
        FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Application Support/Atolye"
    }

    public static var socket: String { supportDir + "/host.sock" }
}
