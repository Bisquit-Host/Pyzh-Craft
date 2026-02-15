import SwiftUI

class CacheManager: ObservableObject {
    @Published var cacheInfo: CacheInfo = CacheInfo(fileCount: 0, totalSize: 0)
    private let calculator = CacheCalculator.shared

    /// Compute metadata cache information (silent version)
    func calculateMetaCacheInfo() {
        do {
            self.cacheInfo = try calculator.calculateMetaCacheInfo()
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("计算元数据缓存信息失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            // keep default value
        }
    }

    /// - Throws: GlobalError when the operation fails
    func calculateMetaCacheInfoThrowing() throws {
        do {
            self.cacheInfo = try calculator.calculateMetaCacheInfo()
        } catch {
            throw GlobalError.fileSystem(
                chineseMessage: "计算元数据缓存信息失败: \(error.localizedDescription)",
                i18nKey: "error.filesystem.meta_cache_calculation_failed",
                level: .notification
            )
        }
    }

    /// Calculate data cache information (silent version)
    func calculateDataCacheInfo() {
        do {
            self.cacheInfo = try calculator.calculateCacheInfo()
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("计算数据缓存信息失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            // keep default value
        }
    }

    /// - Throws: GlobalError when the operation fails
    func calculateDataCacheInfoThrowing() throws {
        do {
            self.cacheInfo = try calculator.calculateCacheInfo()
        } catch {
            throw GlobalError.fileSystem(
                chineseMessage: "计算数据缓存信息失败: \(error.localizedDescription)",
                i18nKey: "error.filesystem.data_cache_calculation_failed",
                level: .notification
            )
        }
    }

    /// Calculate game cache information (silent version)
    /// - Parameter game: game name
    func calculateGameCacheInfo(_ game: String) {
        do {
            self.cacheInfo = try calculator.calculateProfileCacheInfo(gameName: game)
        } catch {
            let globalError = GlobalError.from(error)
            Logger.shared.error("计算游戏缓存信息失败: \(globalError.chineseMessage)")
            GlobalErrorHandler.shared.handle(globalError)
            // keep default value
        }
    }

    /// - Parameter game: game name
    /// - Throws: GlobalError when the operation fails
    func calculateGameCacheInfoThrowing(_ game: String) throws {
        do {
            self.cacheInfo = try calculator.calculateProfileCacheInfo(gameName: game)
        } catch {
            throw GlobalError.fileSystem(
                chineseMessage: "计算游戏缓存信息失败: \(error.localizedDescription)",
                i18nKey: "error.filesystem.game_cache_calculation_failed",
                level: .notification
            )
        }
    }
}
