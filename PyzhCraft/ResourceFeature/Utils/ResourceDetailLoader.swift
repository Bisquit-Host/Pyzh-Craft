import Foundation

/// Resource details loader
/// Responsible for loading project details and compatible game information before opening the sheet
enum ResourceDetailLoader {
    /// Load details of common resources and list of compatible games
    /// - Parameters:
    ///   - projectId: project ID
    ///   - gameRepository: game repository
    ///   - resourceType: resource type
    /// - Returns: tuple of project details and list of compatible games, or nil if loading fails
    static func loadProjectDetail(
        projectId: String,
        gameRepository: GameRepository,
        resourceType: String
    ) async -> (detail: ModrinthProjectDetail, compatibleGames: [GameVersionInfo])? {
        guard let detail = await ModrinthService.fetchProjectDetails(id: projectId) else {
            GlobalErrorHandler.shared.handle(GlobalError.resource(
                chineseMessage: "无法获取项目详情",
                i18nKey: "Project Details Not Found",
                level: .notification
            ))
            return nil
        }

        // Detect compatible games
        let compatibleGames = await filterCompatibleGames(
            detail: detail,
            gameRepository: gameRepository,
            resourceType: resourceType,
            projectId: projectId
        )

        return (detail, compatibleGames)
    }

    /// Load integration package details
    /// - Parameter projectId: project ID
    /// - Returns: project details, returns nil if loading fails
    static func loadModPackDetail(projectId: String) async -> ModrinthProjectDetail? {
        guard let detail = await ModrinthService.fetchProjectDetails(id: projectId) else {
            GlobalErrorHandler.shared.handle(GlobalError.resource(
                chineseMessage: "无法获取整合包项目详情",
                i18nKey: "Project Details Not Found",
                level: .notification
            ))
            return nil
        }

        return detail
    }
}
