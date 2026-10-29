import XCTest
import UIKit
@testable import BankingLab

final class BootstrapTests: XCTestCase {
    @MainActor
    func testApplicationAcceptsLaunchWithoutOptions() {
        let delegate = AppDelegate()

        XCTAssertTrue(delegate.application(UIApplication.shared, didFinishLaunchingWithOptions: nil))
    }

    @MainActor
    func testLaunchScreenLoadsWithoutStoryboard() {
        let controller = LaunchViewController()
        let navigation = UINavigationController(rootViewController: controller)

        controller.loadViewIfNeeded()

        XCTAssertEqual(controller.title, "BankingLab")
        XCTAssertNil(controller.storyboard)
        XCTAssertNil(controller.nibName)
        XCTAssertTrue(navigation.viewControllers.first === controller)
    }

    @MainActor
    func testApplicationDeclaresProgrammaticScene() throws {
        let bundle = Bundle(for: AppDelegate.self)
        let manifest = try XCTUnwrap(bundle.object(forInfoDictionaryKey: "UIApplicationSceneManifest") as? [String: Any])
        let configurations = try XCTUnwrap(manifest["UISceneConfigurations"] as? [String: Any])
        let scenes = try XCTUnwrap(configurations["UIWindowSceneSessionRoleApplication"] as? [[String: Any]])
        let scene = try XCTUnwrap(scenes.first)

        XCTAssertEqual(scenes.count, 1)
        XCTAssertEqual(scene["UISceneDelegateClassName"] as? String, NSStringFromClass(SceneDelegate.self))
        XCTAssertEqual(manifest["UIApplicationSupportsMultipleScenes"] as? Bool, false)
        XCTAssertNil(scene["UISceneStoryboardFile"])
        XCTAssertNil(bundle.object(forInfoDictionaryKey: "UIMainStoryboardFile"))
    }
}
