import Foundation

public enum HostPaths {
    public static var supportDir: String {
        FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Application Support/Atolye"
    }

    public static var socket: String { supportDir + "/host.sock" }
    /// Claude Code hook'larının (`atolye-hook`) bağlandığı, Atölye'nin dinlediği soket.
    public static var hookSocket: String { supportDir + "/hooks.sock" }
    /// Hook'un ayarlara yazılan sabit yolu (uygulama nereden açılırsa açılsın aynı kalır).
    public static var hookBinary: String { supportDir + "/bin/atolye-hook" }
}
