import Foundation

/// The Direct3D -> Metal translation strategy used inside a bottle.
///
/// The chosen backend's `d3d11.dll` / `d3d12.dll` / `dxgi.dll` are installed into
/// the bottle and forced via `WINEDLLOVERRIDES` (native) so the game loads them
/// instead of Wine's built-in `wined3d`.
public enum GraphicsBackend: String, Codable, Sendable, CaseIterable {
    /// Wine's built-in OpenGL-based implementation. Slowest; most compatible.
    case wined3d
    /// D3D 9/10/11 -> Vulkan (reaches Metal via MoltenVK).
    case dxvk
    /// Apple Game Porting Toolkit: D3D11/12 -> Metal directly. Best on Apple Silicon.
    case d3dmetal

    /// The D3D DLLs that this backend overrides inside the bottle.
    public var overriddenDLLs: [String] {
        switch self {
        case .wined3d:  return []
        case .dxvk:     return ["d3d9", "d3d10core", "d3d11", "dxgi"]
        case .d3dmetal: return ["d3d11", "d3d12", "dxgi"]
        }
    }

}
