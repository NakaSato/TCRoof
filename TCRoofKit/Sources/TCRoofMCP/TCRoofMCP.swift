import Foundation
// The Model Context Protocol SDK (https://github.com/modelcontextprotocol/swift-sdk), re-exported so the app reaches
// `Server`, `Client`, `Tool` … through `import TCRoofMCP` alone. Only this target depends on it; TCRoofCore and the
// survey modules don't.
@_exported import MCP

/// TCRoof's MCP integration. Nothing is served or called yet.
public enum TCRoofMCP {
    /// The name an MCP server or client of the app announces.
    public static let name = "TCRoof"
}
