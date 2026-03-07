import Foundation

enum SceneEdgeType: String, Codable {
    case contains, supports, inside, near
    case leftOf, rightOf, inFrontOf, behind, under, occludes
}
